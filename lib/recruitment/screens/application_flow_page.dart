import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../../api/user_facing_api_error.dart';
import '../../data/recruitment_application.dart';
import '../../data/rsp_screening_scores.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../login/screens/login_page.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../widgets/rsp_application_status_timeline.dart';
import '../widgets/rsp_applicant_exam_ui.dart';

/// Default BEI questions when DB has none (admin can edit and save from RSP).
const _defaultBeiQuestions = [
  'Tell me about a time when you had to collaborate with a co-worker that you had a hard time getting along with?',
  'Describe for me a time when you were under a significant amount of pressure at work. How did you deal with it?',
  'Tell me about a time when you were asked to work on a task that you had never done before.',
  'Tell me about a time when you had to cultivate a relationship with a new client. What did you do?',
  'Describe a time when you disagreed with your boss. What did you do?',
  'Describe your greatest challenge.',
  'What was your greatest accomplishment?',
  'Tell me about a time you failed.',
];

/// Answer keys (option text) used to auto-check the 3 MCQ exams.
///
/// The scoring matches each answer text against the question's `options`.
/// If a match is not found, it falls back to the backend `correct` index.
const _answerKeyGeneral = <String>[
  'Design or Blueprint',
  'Bud',
  'Was',
  'After',
  'Screen',
  'Scene',
  '3, 2, 5, 4, 1',
  'Temperature',
  'Forget the past Quarrel',
  'VY',
];

const _answerKeyMathematics = <String>[
  '27 inches',
  '20',
  '6',
  '292',
  '144',
  '1.25',
  '6.00',
  '28',
  '22 seconds',
];

const _answerKeyGeneralInfo = <String>[
  'Fair remuneration for equal work',
  'Equitably diffuse property ownership and right',
  'Bill of Rights',
  'Constitution of Universality',
  'No ex post facto law or bill of attainder shall not be enacted.',
];

const _kRspStep1DraftKey = 'rsp_application_step1_draft_v1';

/// Recruitment flow. **Job application** (no [selectedPositionHeadline]) opens tracking only;
/// **Apply now** on a vacancy includes Step 1 (basic info + documents).
class ApplicationFlowPage extends StatefulWidget {
  const ApplicationFlowPage({super.key, this.selectedPositionHeadline});

  /// Set when the applicant taps **Apply now** on a specific vacancy (job title for Step 1 + DB).
  final String? selectedPositionHeadline;

  @override
  State<ApplicationFlowPage> createState() => _ApplicationFlowPageState();
}

class _ApplicationFlowPageState extends State<ApplicationFlowPage> {
  int _step = 1;
  String? _applicationId;

  /// Set when applicant uses "Continue" so the app bar shows DB position for later steps.
  String? _applicationPositionAppliedFor;

  /// When loaded via "Continue application" or after Step 1: submitted | document_approved | document_declined
  String? _applicationStatus;
  bool _examPassed = false;
  double _examScore = 0;
  bool _examSubmitting = false;

  /// From HR via admin “Final interview” scheduler (shown to passed applicants).
  DateTime? _finalInterviewAt;

  /// HR-recorded in-person final interview outcome (null = not set yet).
  bool? _finalInterviewPassed;

  /// Set when HR links Create Account to this application (`registered` + FK).
  String? _hiredUserId;

  /// HR monitoring flag for Step 8 (independent of employee user link).
  bool _hrAccountSetupDone = false;

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _continueEmailController = TextEditingController();
  final Map<RspApplicationDocKind, PlatformFile> _pickedDocs = {};
  List<String>? _beiQuestionsLoaded;
  List<TextEditingController> _beiControllers = [];
  bool _submitting = false;
  bool _continueLoading = false;
  bool _beiLoading = false;

  /// Step 1: same “track status” preview as [TrackApplicationPage], before Continue.
  RecruitmentApplication? _step1StatusApp;
  RecruitmentExamResult? _step1StatusExam;
  String? _step1StatusError;
  bool _step1StatusLoading = false;
  String? _statusPreviewEmail;
  Timer? _step1StatusTimer;

  Timer? _draftDebounce;
  bool _hasLocalDraft = false;

  /// From [GET /api/rsp/email-verification/config]. `null` before first fetch.
  bool? _serverRequiresEmailOtp;
  int _emailOtpTtlMs = 600000;
  bool _emailOtpSending = false;
  bool _emailOtpVerifying = false;
  String? _emailVerificationToken;
  String? _verifiedEmailNorm;
  final _emailOtpController = TextEditingController();
  String? _suffixValue;
  String? _sexValue;

  static const List<String> _suffixOptions = [
    'Jr.',
    'Sr.',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];

  /// Opens from **Apply now** on a vacancy (Step 1 form is shown). Otherwise = track-only entry.
  bool get _isVacancyApplication {
    final h = widget.selectedPositionHeadline?.trim();
    return h != null && h.isNotEmpty;
  }

  /// Per-exam countdown limits from API (keys: general, math, general_info).
  Map<String, int> _examTimeLimitSeconds = {};

  Timer? _examCountdownTimer;
  int? _examCountdownRemaining;

  /// True until HR enters all BEI scores (Step 7 shows waiting, not pass/fail).
  bool _examBeiGradingPending = false;
  Timer? _beiGradingPollTimer;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_scheduleDraftSave);
    _middleNameController.addListener(_scheduleDraftSave);
    _lastNameController.addListener(_scheduleDraftSave);
    _emailController.addListener(_scheduleDraftSave);
    _emailController.addListener(_onEmailMaybeInvalidateOtp);
    _phoneController.addListener(_scheduleDraftSave);
    _continueEmailController.addListener(_scheduleDraftSave);
    _continueEmailController.addListener(_onContinueEmailChangedForPreview);
    _continueEmailController.addListener(_rebuildForContinueButtonEligibility);
    if (_isVacancyApplication) _checkLocalDraft();
    if (_isVacancyApplication) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadEmailOtpConfig(),
      );
    }
  }

  Future<void> _loadEmailOtpConfig() async {
    if (!_isVacancyApplication) return;
    try {
      final cfg = await RecruitmentRepo.instance
          .fetchRspEmailVerificationConfig();
      if (!mounted) return;
      setState(() {
        _serverRequiresEmailOtp = cfg.requiresOtpForNewApplication;
        _emailOtpTtlMs = cfg.otpTtlMs;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _serverRequiresEmailOtp = false);
    }
  }

  void _onEmailMaybeInvalidateOtp() {
    if (!_isVacancyApplication) return;
    final e = _emailController.text.trim().toLowerCase();
    if (_verifiedEmailNorm == null) return;
    if (e == _verifiedEmailNorm) return;
    setState(() {
      _emailVerificationToken = null;
      _verifiedEmailNorm = null;
    });
  }

  bool get _step1EmailOtpVerified {
    final tok = _emailVerificationToken?.trim();
    if (tok == null || tok.isEmpty) return false;
    final addr = _emailController.text.trim().toLowerCase();
    final v = _verifiedEmailNorm?.trim().toLowerCase();
    return v != null && v.isNotEmpty && addr == v;
  }

  int get _emailOtpTtlMinutes =>
      ((_emailOtpTtlMs / 60000).round()).clamp(1, 120);

  Future<void> _sendApplicantEmailOtp() async {
    final email = _emailController.text.trim();
    if (!_isValidEmailFormat(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address first.')),
      );
      return;
    }
    setState(() {
      _emailOtpSending = true;
      if (_verifiedEmailNorm != email.toLowerCase()) {
        _emailVerificationToken = null;
        _verifiedEmailNorm = null;
      }
    });
    try {
      await RecruitmentRepo.instance.sendRspApplicantEmailOtp(
        email,
        fullName: (() {
          final first = _firstNameController.text.trim();
          final middle = _middleNameController.text.trim();
          final last = _lastNameController.text.trim();
          final parts = <String>[
            first,
            if (middle.isNotEmpty) middle,
            last,
          ].where((s) => s.trim().isNotEmpty).toList();
          final base = parts.join(' ').trim();
          if (base.isEmpty) return null;
          return _suffixValue != null ? '$base ${_suffixValue!}' : base;
        })(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Check your inbox for a 6-digit verification code (check spam folder too).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    } finally {
      if (mounted) setState(() => _emailOtpSending = false);
    }
  }

  Future<void> _verifyApplicantEmailOtp() async {
    final email = _emailController.text.trim();
    final code = _emailOtpController.text.replaceAll(RegExp(r'\s'), '');
    if (!_isValidEmailFormat(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address first.')),
      );
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the 6-digit code from your email.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _emailOtpVerifying = true);
    try {
      final token = await RecruitmentRepo.instance.verifyRspApplicantEmailOtp(
        email,
        code,
      );
      if (!mounted) return;
      setState(() {
        _emailVerificationToken = token;
        _verifiedEmailNorm = email.toLowerCase();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email verified. You can continue and submit your application.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    } finally {
      if (mounted) setState(() => _emailOtpVerifying = false);
    }
  }

  Widget _buildStep1EmailOtpSection() {
    if (!_isVacancyApplication) return const SizedBox.shrink();
    if (_serverRequiresEmailOtp == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryNavy.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Checking email verification…',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_serverRequiresEmailOtp != true) return const SizedBox.shrink();

    final verified = _step1EmailOtpVerified;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your email',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We will send a one-time code to this address so we know it is yours and messages from HR '
            'can reach you. The code expires in about $_emailOtpTtlMinutes minutes.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          if (verified)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.shade700.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Colors.green.shade800,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Email verified for this application.',
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: (_submitting || _emailOtpSending)
                      ? null
                      : _sendApplicantEmailOtp,
                  icon: _emailOtpSending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                          ),
                        )
                      : const Icon(Icons.mark_email_read_outlined, size: 20),
                  label: Text(_emailOtpSending ? 'Sending…' : 'Send code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: BorderSide(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 400;
                final otpField = TextField(
                  controller: _emailOtpController,
                  decoration: _step1FieldDecoration(
                    '6-digit code',
                    hintText: '000000',
                    prefixIcon: Icons.pin_outlined,
                  ).copyWith(counterText: ''),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _verifyApplicantEmailOtp(),
                  enabled: !_submitting,
                );
                final verifyBtn = FilledButton(
                  onPressed:
                      (_submitting || _emailOtpVerifying || _emailOtpSending)
                      ? null
                      : _verifyApplicantEmailOtp,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 18,
                    ),
                  ),
                  child: _emailOtpVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify'),
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [otpField, const SizedBox(height: 10), verifyBtn],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: otpField),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: verifyBtn,
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _rebuildForContinueButtonEligibility() {
    if (!mounted || _step != 1) return;
    setState(() {});
  }

  void _onContinueEmailChangedForPreview() {
    final e = _continueEmailController.text.trim().toLowerCase();
    if (_statusPreviewEmail == null) return;
    if (e == _statusPreviewEmail!.trim().toLowerCase()) return;
    _stopStep1StatusTimer();
    if (mounted) {
      setState(() {
        _statusPreviewEmail = null;
        _step1StatusApp = null;
        _step1StatusExam = null;
        _step1StatusError = null;
        _step1StatusLoading = false;
      });
    }
  }

  void _stopStep1StatusTimer() {
    _step1StatusTimer?.cancel();
    _step1StatusTimer = null;
  }

  void _startStep1StatusTimer() {
    _stopStep1StatusTimer();
    _step1StatusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _step == 1) _silentRefreshStep1Status();
    });
  }

  Future<void> _silentRefreshStep1Status() async {
    final email = _continueEmailController.text.trim();
    if (email.isEmpty || _statusPreviewEmail == null) return;
    if (email.toLowerCase() != _statusPreviewEmail!.trim().toLowerCase()) {
      return;
    }
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted || lookup == null) return;
      setState(() {
        _step1StatusApp = lookup.application;
        _step1StatusExam = lookup.examResult;
      });
    } catch (_) {}
  }

  Future<void> _checkStep1StatusOnly() async {
    final email = _continueEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email to check status.')),
      );
      return;
    }
    setState(() {
      _step1StatusLoading = true;
      _step1StatusError = null;
      _step1StatusApp = null;
      _step1StatusExam = null;
    });
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted) return;
      _stopStep1StatusTimer();
      if (lookup == null) {
        setState(() {
          _step1StatusLoading = false;
          _step1StatusError = !_isVacancyApplication
              ? 'No application found for this email. To apply, go to the home page, open Job Vacancies, and tap Apply now on a position.'
              : 'No application found for this email.';
          _statusPreviewEmail = email;
        });
        return;
      }
      setState(() {
        _step1StatusLoading = false;
        _step1StatusError = null;
        _step1StatusApp = lookup.application;
        _step1StatusExam = lookup.examResult;
        _statusPreviewEmail = email;
      });
      _startStep1StatusTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _step1StatusLoading = false;
          _step1StatusError = 'Could not load status. Please try again.';
          _step1StatusApp = null;
          _step1StatusExam = null;
        });
      }
    }
  }

  void _scheduleDraftSave() {
    if (!_isVacancyApplication || _step != 1) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(
      const Duration(milliseconds: 600),
      _persistStep1Draft,
    );
  }

  Future<void> _persistStep1Draft() async {
    if (!_isVacancyApplication || _step != 1) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final first = _firstNameController.text.trim();
      final middle = _middleNameController.text.trim();
      final last = _lastNameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final cont = _continueEmailController.text.trim();
      final hasAnyName =
          first.isNotEmpty || middle.isNotEmpty || last.isNotEmpty;
      if (!hasAnyName && email.isEmpty && phone.isEmpty && cont.isEmpty) {
        await prefs.remove(_kRspStep1DraftKey);
        if (mounted) setState(() => _hasLocalDraft = false);
        return;
      }
      await prefs.setString(
        _kRspStep1DraftKey,
        jsonEncode({
          'firstName': _firstNameController.text,
          'middleName': _middleNameController.text,
          'lastName': _lastNameController.text,
          'suffix': _suffixValue,
          'sex': _sexValue,
          'email': _emailController.text,
          'phone': _phoneController.text,
          'continueEmail': _continueEmailController.text,
        }),
      );
    } catch (_) {}
  }

  Future<void> _checkLocalDraft() async {
    if (!_isVacancyApplication) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRspStep1DraftKey);
      if (!mounted || raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final m = Map<String, dynamic>.from(decoded);
      final hasText = [
        m['firstName']?.toString().trim(),
        m['middleName']?.toString().trim(),
        m['lastName']?.toString().trim(),
        m['email']?.toString().trim(),
        m['phone']?.toString().trim(),
        m['continueEmail']?.toString().trim(),
      ].any((s) => s != null && s.isNotEmpty);
      if (hasText && mounted) setState(() => _hasLocalDraft = true);
    } catch (_) {}
  }

  Future<void> _loadLocalDraftToFields() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRspStep1DraftKey);
      if (!mounted || raw == null) return;
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      setState(() {
        _firstNameController.text = m['firstName']?.toString() ?? '';
        _middleNameController.text = m['middleName']?.toString() ?? '';
        _lastNameController.text = m['lastName']?.toString() ?? '';
        _suffixValue = m['suffix']?.toString().trim().isEmpty == true
            ? null
            : m['suffix']?.toString();
        _sexValue = m['sex']?.toString().trim().isEmpty == true
            ? null
            : m['sex']?.toString();
        _emailController.text = m['email']?.toString() ?? '';
        _phoneController.text = m['phone']?.toString() ?? '';
        _continueEmailController.text = m['continueEmail']?.toString() ?? '';
        _hasLocalDraft = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft loaded into the form.')),
        );
      }
    } catch (_) {}
  }

  Future<void> _clearLocalDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRspStep1DraftKey);
    if (mounted) setState(() => _hasLocalDraft = false);
  }

  @override
  void dispose() {
    _examCountdownTimer?.cancel();
    _step1StatusTimer?.cancel();
    _beiGradingPollTimer?.cancel();
    _draftDebounce?.cancel();
    _firstNameController.removeListener(_scheduleDraftSave);
    _middleNameController.removeListener(_scheduleDraftSave);
    _lastNameController.removeListener(_scheduleDraftSave);
    _emailController.removeListener(_scheduleDraftSave);
    _emailController.removeListener(_onEmailMaybeInvalidateOtp);
    _phoneController.removeListener(_scheduleDraftSave);
    _continueEmailController.removeListener(_scheduleDraftSave);
    _continueEmailController.removeListener(_onContinueEmailChangedForPreview);
    _continueEmailController.removeListener(
      _rebuildForContinueButtonEligibility,
    );
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailOtpController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _continueEmailController.dispose();
    for (final c in _beiControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBeiQuestions() async {
    if (_beiLoading || _beiQuestionsLoaded != null) return;
    _beiLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestions('bei');
      final questions = list.isNotEmpty ? list : _defaultBeiQuestions;
      if (mounted) {
        for (final c in _beiControllers) {
          c.dispose();
        }
        _beiControllers = questions
            .map((_) => TextEditingController())
            .toList();
        _beiQuestionsLoaded = questions;
        _beiLoading = false;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        for (final c in _beiControllers) {
          c.dispose();
        }
        _beiControllers = _defaultBeiQuestions
            .map((_) => TextEditingController())
            .toList();
        _beiQuestionsLoaded = _defaultBeiQuestions;
        _beiLoading = false;
        setState(() {});
      }
    }
  }

  static bool _isPdfFileName(String name) {
    final lower = name.trim().toLowerCase();
    return lower.endsWith('.pdf');
  }

  Future<void> _pickDoc(RspApplicationDocKind kind) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    if (f.name.isEmpty || f.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read that file. Try another format or smaller file.',
            ),
          ),
        );
      }
      return;
    }
    if (!_isPdfFileName(f.name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Only PDF files are accepted. Please save or export your document as PDF (.pdf), not Word.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _pickedDocs[kind] = f);
  }

  void _removeDoc(RspApplicationDocKind kind) {
    setState(() => _pickedDocs.remove(kind));
  }

  static bool _isValidEmailFormat(String email) {
    final e = email.trim();
    if (e.isEmpty) return false;
    // Practical check: local@domain.tld
    return RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(e);
  }

  /// Accepts typical PH and international formats after stripping non-digits.
  static bool _isValidPhoneDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 && digits.length <= 15;
  }

  static String _docKindLabel(RspApplicationDocKind kind) {
    switch (kind) {
      case RspApplicationDocKind.applicationLetter:
        return 'Application letter';
      case RspApplicationDocKind.resume:
        return 'Resume';
      case RspApplicationDocKind.tor:
        return 'TOR';
      case RspApplicationDocKind.eligibilityTrainings:
        return 'Eligibility and trainings for preliminary requirements';
    }
  }

  Future<void> _submitStep1() async {
    final first = _firstNameController.text.trim();
    final middle = _middleNameController.text.trim();
    final last = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    if (first.isEmpty ||
        last.isEmpty ||
        _sexValue == null ||
        email.isEmpty ||
        phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your first name, last name, gender, email, and phone number.',
          ),
        ),
      );
      return;
    }
    if (!_isValidEmailFormat(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }
    if (_serverRequiresEmailOtp == true && !_step1EmailOtpVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verify your email first: tap Send code, enter the 6-digit code from your inbox, then Verify.',
          ),
        ),
      );
      return;
    }
    if (!_isValidPhoneDigits(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid phone number (at least 10 digits, including area or country code).',
          ),
        ),
      );
      return;
    }
    for (final kind in RspApplicationDocKind.values) {
      final f = _pickedDocs[kind];
      if (f == null || f.bytes == null || f.name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please attach: ${_docKindLabel(kind)}.')),
        );
        return;
      }
      if (!_isPdfFileName(f.name)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_docKindLabel(kind)} must be a PDF file (.pdf), not Word or other formats.',
            ),
          ),
        );
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final pos = widget.selectedPositionHeadline?.trim();
      final id = await RecruitmentRepo.instance.insertApplication(
        RecruitmentApplication(
          id: '',
          fullName:
              '$first${middle.isNotEmpty ? ' $middle' : ''} $last${_suffixValue != null ? ' ${_suffixValue!}' : ''}'
                  .trim(),
          firstName: first,
          middleName: middle.isNotEmpty ? middle : null,
          lastName: last,
          suffix: _suffixValue,
          sex: _sexValue,
          email: email,
          phone: phone,
          resumeNotes: null,
          positionAppliedFor: (pos != null && pos.isNotEmpty) ? pos : null,
          status: 'submitted',
        ),
        emailVerificationToken:
            (_serverRequiresEmailOtp == true && _step1EmailOtpVerified)
            ? _emailVerificationToken
            : null,
      );
      if (mounted) {
        try {
          for (final kind in RspApplicationDocKind.values) {
            final f = _pickedDocs[kind]!;
            await RecruitmentRepo.instance.uploadTypedDocument(
              id,
              kind,
              f.bytes!,
              f.name,
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Application saved but a file upload failed: $e'),
              ),
            );
          }
        }
      }
      if (mounted) {
        await SharedPreferences.getInstance().then(
          (p) => p.remove(_kRspStep1DraftKey),
        );
        setState(() {
          _applicationId = id;
          _applicationStatus = 'submitted';
          _step = 2;
          _submitting = false;
          _hasLocalDraft = false;
          _pickedDocs.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
      }
    }
  }

  void _cancelExamCountdown() {
    _examCountdownTimer?.cancel();
    _examCountdownTimer = null;
    _examCountdownRemaining = null;
  }

  String _formatMmSs(int seconds) {
    final s = seconds.clamp(0, 86400);
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  String _examLabelForType(String examType) {
    switch (examType) {
      case 'general':
        return 'General Exam';
      case 'math':
        return 'Mathematics Exam';
      case 'general_info':
        return 'General Information Exam';
      default:
        return 'Exam';
    }
  }

  void _startExamCountdown(String examType) {
    _cancelExamCountdown();
    final limit =
        _examTimeLimitSeconds[examType] ??
        RecruitmentRepo.kDefaultRspExamTimeLimitSeconds[examType] ??
        0;
    if (limit <= 0) return;
    _examCountdownRemaining = limit;
    _examCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final r = _examCountdownRemaining;
      if (r == null) {
        t.cancel();
        return;
      }
      if (r <= 1) {
        t.cancel();
        setState(() => _examCountdownRemaining = 0);
        _onExamTimeExpired(examType);
        return;
      }
      setState(() => _examCountdownRemaining = r - 1);
    });
    setState(() {});
  }

  void _onExamTimeExpired(String examType) {
    _cancelExamCountdown();
    if (!mounted) return;
    final label = _examLabelForType(examType);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Time limit reached for $label.')));
    switch (examType) {
      case 'general':
        setState(() => _step = 5);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadMathQuestions(),
        );
        return;
      case 'math':
        setState(() => _step = 6);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadGeneralInfoQuestions(),
        );
        return;
      case 'general_info':
        unawaited(_submitGeneralInfoExam(dueToTimeLimit: true));
        return;
    }
  }

  String _mcqInstructionTimeNote(String examType) {
    final sec =
        _examTimeLimitSeconds[examType] ??
        RecruitmentRepo.kDefaultRspExamTimeLimitSeconds[examType] ??
        0;
    if (sec <= 0) return '';
    final mins = (sec + 59) ~/ 60;
    return ' A timer applies to this section (about $mins minute${mins == 1 ? '' : 's'}).';
  }

  Widget _buildExamTimerBanner() {
    final r = _examCountdownRemaining;
    if (r == null || r <= 0) return const SizedBox.shrink();
    return RspApplicantExamTimerBanner(
      timeLabel: _formatMmSs(r),
      urgent: r <= 60,
    );
  }

  int _beiAnsweredCount() {
    var n = 0;
    for (final c in _beiControllers) {
      if (c.text.trim().isNotEmpty) n++;
    }
    return n;
  }

  int _mcqAnsweredCount(List<int> selected) {
    var n = 0;
    for (final v in selected) {
      if (v >= 0) n++;
    }
    return n;
  }

  Widget _buildMcqQuestionList({
    required List<Map<String, dynamic>> questions,
    required List<int> selected,
    required void Function(int questionIndex, int optionIndex) onSelect,
    required bool useLetterPrefix,
  }) {
    return Column(
      children: List.generate(questions.length, (i) {
        final q = questions[i];
        final options = q['options'] as List<dynamic>? ?? [];
        return RspApplicantMcqQuestionCard(
          index: i,
          questionText: q['question_text']?.toString() ?? '',
          options: options,
          selectedIndex: i < selected.length ? selected[i] : -1,
          useLetterPrefix: useLetterPrefix,
          onSelect: (j) => onSelect(i, j),
        );
      }),
    );
  }

  Future<void> _submitBeiExam() async {
    if (_beiQuestionsLoaded == null || _beiControllers.isEmpty) return;
    final answers = _beiControllers.map((c) => c.text.trim()).toList();
    final allFilled = answers.every((a) => a.isNotEmpty);
    if (!allFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide an answer for each question.'),
        ),
      );
      return;
    }
    _beiAnswersForSubmit = answers;
    try {
      _examTimeLimitSeconds = await RecruitmentRepo.instance
          .getExamTimeLimits();
    } catch (_) {
      _examTimeLimitSeconds = Map<String, int>.from(
        RecruitmentRepo.kDefaultRspExamTimeLimitSeconds,
      );
    }
    if (!mounted) return;
    setState(() => _step = 4);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadGeneralQuestions(),
    );
  }

  List<String>? _beiAnswersForSubmit;

  List<Map<String, dynamic>>? _generalQuestionsLoaded;
  List<int> _generalSelected = [];
  bool _generalLoading = false;

  Future<void> _loadGeneralQuestions() async {
    if (_generalLoading || _generalQuestionsLoaded != null) return;
    _generalLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        'general',
      );
      if (mounted) {
        _generalQuestionsLoaded = list;
        _generalSelected = List.filled(list.length, -1);
        _generalLoading = false;
        setState(() {});
        if (list.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _step != 4) return;
            _startExamCountdown('general');
          });
        }
      }
    } catch (_) {
      if (mounted) {
        _generalQuestionsLoaded = [];
        _generalSelected = [];
        _generalLoading = false;
        setState(() {});
      }
    }
  }

  void _submitGeneralExam() {
    _cancelExamCountdown();
    if (_generalQuestionsLoaded == null || _generalQuestionsLoaded!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No General Exam questions loaded.')),
      );
      return;
    }
    if (_generalSelected.any((s) => s < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions.')),
      );
      return;
    }
    setState(() => _step = 5);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMathQuestions());
  }

  List<Map<String, dynamic>>? _mathQuestionsLoaded;
  List<int> _mathSelected = [];
  bool _mathLoading = false;
  List<Map<String, dynamic>>? _generalInfoQuestionsLoaded;
  List<int> _generalInfoSelected = [];
  bool _generalInfoLoading = false;

  Future<void> _loadMathQuestions() async {
    if (_mathLoading || _mathQuestionsLoaded != null) return;
    _mathLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        'math',
      );
      if (mounted) {
        _mathQuestionsLoaded = list;
        _mathSelected = List.filled(list.length, -1);
        _mathLoading = false;
        setState(() {});
        if (list.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _step != 5) return;
            _startExamCountdown('math');
          });
        }
      }
    } catch (_) {
      if (mounted) {
        _mathQuestionsLoaded = [];
        _mathSelected = [];
        _mathLoading = false;
        setState(() {});
      }
    }
  }

  Future<void> _loadGeneralInfoQuestions() async {
    if (_generalInfoLoading || _generalInfoQuestionsLoaded != null) return;
    _generalInfoLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        'general_info',
      );
      if (mounted) {
        _generalInfoQuestionsLoaded = list;
        _generalInfoSelected = List.filled(list.length, -1);
        _generalInfoLoading = false;
        setState(() {});
        if (list.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _step != 6) return;
            _startExamCountdown('general_info');
          });
        }
      }
    } catch (_) {
      if (mounted) {
        _generalInfoQuestionsLoaded = [];
        _generalInfoSelected = [];
        _generalInfoLoading = false;
        setState(() {});
      }
    }
  }

  void _submitMathExam() {
    _cancelExamCountdown();
    if (_mathQuestionsLoaded == null || _mathQuestionsLoaded!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Mathematics Exam questions loaded.')),
      );
      return;
    }
    if (_mathSelected.any((s) => s < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions.')),
      );
      return;
    }
    setState(() => _step = 6);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadGeneralInfoQuestions(),
    );
  }

  List<double> _numbersInString(String s) {
    final matches = RegExp(r'[+-]?\d+(?:\.\d+)?').allMatches(s);
    return matches
        .map((m) => double.tryParse(m.group(0) ?? '') ?? double.nan)
        .where((v) => !v.isNaN)
        .toList();
  }

  bool _answersMatch(String expectedOptionText, String actualOptionText) {
    final expNorm = expectedOptionText.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final actNorm = actualOptionText.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    if (expNorm.isEmpty || actNorm.isEmpty) return false;
    if (expNorm == actNorm) return true;

    // Numeric match: only when both strings contain exactly one number token.
    // This avoids false positives for values like "3, 2, 5, 4, 1" (multiple numbers).
    final expNums = _numbersInString(expNorm);
    final actNums = _numbersInString(actNorm);
    if (expNums.length == 1 && actNums.length == 1) {
      final diff = (expNums.first - actNums.first).abs();
      return diff < 1e-9;
    }

    return false;
  }

  List<int> _computeCorrectIndicesFromAnswerKey({
    required List<Map<String, dynamic>> questionsLoaded,
    required List<String> answerKey,
  }) {
    final out = <int>[];
    for (int i = 0; i < questionsLoaded.length; i++) {
      final q = questionsLoaded[i];
      final options =
          (q['options'] as List<dynamic>?)?.map((x) => x.toString()).toList() ??
          <String>[];
      final backendCorrect = (q['correct'] as num?)?.toInt() ?? 0;

      if (i < answerKey.length) {
        final expected = answerKey[i];
        for (int j = 0; j < options.length; j++) {
          if (_answersMatch(expected, options[j])) {
            out.add(j);
            break;
          }
        }
        if (out.length <= i) out.add(backendCorrect);
      } else {
        out.add(backendCorrect);
      }
    }
    return out;
  }

  double _computeScorePercent({
    required List<int> selected,
    required List<int> correct,
  }) {
    final total = correct.length;
    if (total == 0) return 0;
    int correctCount = 0;
    for (int i = 0; i < total; i++) {
      if (i < selected.length && selected[i] == correct[i]) correctCount++;
    }
    return (correctCount / total) * 100.0;
  }

  Future<void> _submitGeneralInfoExam({bool dueToTimeLimit = false}) async {
    _cancelExamCountdown();
    if (_generalInfoQuestionsLoaded == null ||
        _generalInfoQuestionsLoaded!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No General Information Exam questions loaded.'),
        ),
      );
      return;
    }
    if (!dueToTimeLimit && _generalInfoSelected.any((s) => s < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions.')),
      );
      return;
    }
    if (_applicationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Application not found. Please restart the application flow.',
          ),
        ),
      );
      return;
    }

    setState(() => _examSubmitting = true);

    final generalQuestions =
        _generalQuestionsLoaded ?? <Map<String, dynamic>>[];
    final mathQuestions = _mathQuestionsLoaded ?? <Map<String, dynamic>>[];
    final generalInfoQuestions = _generalInfoQuestionsLoaded!;

    final generalCorrect = generalQuestions.isEmpty
        ? <int>[]
        : _computeCorrectIndicesFromAnswerKey(
            questionsLoaded: generalQuestions,
            answerKey: _answerKeyGeneral,
          );
    final mathCorrect = mathQuestions.isEmpty
        ? <int>[]
        : _computeCorrectIndicesFromAnswerKey(
            questionsLoaded: mathQuestions,
            answerKey: _answerKeyMathematics,
          );
    final generalInfoCorrect = _computeCorrectIndicesFromAnswerKey(
      questionsLoaded: generalInfoQuestions,
      answerKey: _answerKeyGeneralInfo,
    );

    final generalScore = _computeScorePercent(
      selected: _generalSelected,
      correct: generalCorrect,
    );
    final mathScore = _computeScorePercent(
      selected: _mathSelected,
      correct: mathCorrect,
    );
    final infoScore = _computeScorePercent(
      selected: _generalInfoSelected,
      correct: generalInfoCorrect,
    );

    final sectionPercents = <double>[];
    if (generalQuestions.isNotEmpty) sectionPercents.add(generalScore);
    if (mathQuestions.isNotEmpty) sectionPercents.add(mathScore);
    sectionPercents.add(infoScore);
    final overallScore = sectionPercents.isEmpty
        ? infoScore
        : sectionPercents.reduce((a, b) => a + b) / sectionPercents.length;

    final answersJson = <String, dynamic>{
      if (generalQuestions.isNotEmpty)
        'general': {
          'questions': generalQuestions.map((q) => q['question_text']).toList(),
          'options': generalQuestions.map((q) => q['options']).toList(),
          'correct': generalCorrect,
          'selected': _generalSelected,
          'score': generalScore,
          'passed': generalScore >= 60,
        },
      if (mathQuestions.isNotEmpty)
        'math': {
          'questions': mathQuestions.map((q) => q['question_text']).toList(),
          'options': mathQuestions.map((q) => q['options']).toList(),
          'correct': mathCorrect,
          'selected': _mathSelected,
          'score': mathScore,
          'passed': mathScore >= 60,
        },
      'general_info': {
        'questions': generalInfoQuestions
            .map((q) => q['question_text'])
            .toList(),
        'options': generalInfoQuestions.map((q) => q['options']).toList(),
        'correct': generalInfoCorrect,
        'selected': _generalInfoSelected,
        'score': infoScore,
        'passed': infoScore >= 60,
      },
    };

    if (_beiAnswersForSubmit != null && _beiQuestionsLoaded != null) {
      answersJson['bei'] = {
        'questions': _beiQuestionsLoaded,
        'answers': _beiAnswersForSubmit,
      };
    }

    final combinedOverall =
        RspScreeningScores.overallPercent(answersJson) ?? overallScore;
    final roundedOverall = RspScreeningScores.roundOverall(combinedOverall);
    final beiFullyGraded = RspScreeningScores.isBeiFullyGraded(answersJson);
    final storedPassed = beiFullyGraded && combinedOverall >= 60;

    try {
      await RecruitmentRepo.instance.submitExamResult(
        applicationId: _applicationId!,
        scorePercent: roundedOverall,
        passed: storedPassed,
        answersJson: answersJson,
      );

      if (!mounted) return;
      setState(() {
        _examBeiGradingPending = !beiFullyGraded;
        _examScore = roundedOverall;
        _examPassed = storedPassed;
        _step = 7;
        _examSubmitting = false;
      });
      if (!beiFullyGraded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startBeiGradingPoll();
        });
      } else {
        _beiGradingPollTimer?.cancel();
      }
      await _syncInterviewFromEmail();
    } catch (e) {
      if (!mounted) return;
      setState(() => _examSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit exam result: $e')),
      );
    }
  }

  Future<void> _syncInterviewFromEmail() async {
    final email = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim().toLowerCase()
        : _continueEmailController.text.trim().toLowerCase();
    if (email.isEmpty || _applicationId == null) return;
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted || lookup == null) return;
      final app = lookup.application;
      if (app.id == _applicationId) {
        setState(() {
          _finalInterviewAt = app.finalInterviewAt;
          _finalInterviewPassed = app.finalInterviewPassed;
          _applicationStatus = app.status;
          _hiredUserId = app.hiredUserId;
          _hrAccountSetupDone = app.hrAccountSetupDone;
        });
      }
    } catch (_) {
      // Non-fatal: interview banner simply won’t update
    }
  }

  String _emailForExamStatusLookup() {
    final a = _emailController.text.trim().toLowerCase();
    if (a.isNotEmpty) return a;
    return _continueEmailController.text.trim().toLowerCase();
  }

  void _startBeiGradingPoll() {
    _beiGradingPollTimer?.cancel();
    if (!_examBeiGradingPending) return;
    _beiGradingPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshBeiGradingFromServer(),
    );
  }

  Future<void> _refreshBeiGradingFromServer() async {
    if (!_examBeiGradingPending || _applicationId == null) return;
    final email = _emailForExamStatusLookup();
    if (email.isEmpty) return;
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted || lookup == null) return;
      final exam = lookup.examResult;
      if (exam == null || !exam.beiGradingComplete) return;
      _beiGradingPollTimer?.cancel();
      setState(() {
        _examBeiGradingPending = false;
        _examScore = exam.scorePercent;
        _examPassed = exam.passed;
        _applicationStatus = lookup.application.status;
      });
      await _syncInterviewFromEmail();
    } catch (_) {}
  }

  /// Picks the correct step after "Continue to exam" using DB status + optional exam row.
  /// Previously only `document_approved` advanced past step 2; after the exam, status is
  /// `passed`/`failed`, so applicants were stuck on "Under review".
  int _resumeStepFor(RecruitmentApplication app, RecruitmentExamResult? exam) {
    if (app.status == 'document_declined') return 2;
    if (app.status == 'submitted') return 2;

    if (exam != null) {
      if (!exam.passed) return 7;
      final hired =
          app.hiredUserId != null && app.hiredUserId!.trim().isNotEmpty;
      if (app.status == 'registered' || hired) return 8;
      // Passed exam: always resume on the result step so score + HR updates
      // (final interview date / outcome) are visible — not stuck on document review.
      return 7;
    }

    if (app.status == 'document_approved') return 3;
    if (app.status == 'failed') return 7;
    if (app.status == 'passed') return 7;
    if (app.status == 'registered') return 8;

    return 2;
  }

  /// Track-only entry: stay on Step 1 for document review; open exams/results only when allowed.
  /// Failed screening exam stays on tracking (no forward steps). Passed → result / hiring steps.
  int _resumeStepForTrackingOnlyEntry(
    RecruitmentApplication app,
    RecruitmentExamResult? exam,
  ) {
    if (app.status == 'failed') return 1;
    if (exam != null && !exam.passed) {
      if (!exam.beiGradingComplete) return 7;
      return 1;
    }
    if (exam != null) {
      final hired =
          app.hiredUserId != null && app.hiredUserId!.trim().isNotEmpty;
      if (app.status == 'registered' || hired) return 8;
      return 7;
    }
    if (app.status == 'document_approved' || app.status == 'exam_taken') {
      return 3;
    }
    if (app.status == 'passed') return 7;
    if (app.status == 'registered') return 8;
    return 1;
  }

  /// Whether Continue may leave the track screen (docs approved for exams, or post-exam forward path).
  bool _canProceedTrackingContinue(
    RecruitmentApplication app,
    RecruitmentExamResult? exam,
  ) {
    return _resumeStepForTrackingOnlyEntry(app, exam) > 1;
  }

  String _trackingContinueBlockedHint(
    RecruitmentApplication app,
    RecruitmentExamResult? exam,
  ) {
    if (exam != null && !exam.passed && !exam.beiGradingComplete) {
      return 'HR is still grading your BEI. When grading is done, Continue will open your final screening result.';
    }
    if (exam != null && !exam.passed) {
      return 'You did not pass the screening exam. You cannot continue to the next steps in this process.';
    }
    if (app.status == 'failed') {
      return 'The screening exam was not passed. You cannot continue to the next steps in this process.';
    }
    if (app.status == 'submitted') {
      return 'Continue will be available after HR approves your documents.';
    }
    if (app.status == 'document_declined') {
      return 'Your documents were not approved. Contact HR for assistance.';
    }
    return 'You cannot proceed at this time. Check your status above.';
  }

  String _trackingOnlyContinueStayMessage(String status) {
    switch (status) {
      case 'submitted':
        return 'HR is still reviewing your documents. You can start the screening exams only after approval. Check back here for updates.';
      case 'document_declined':
        return 'Your documents were not approved. See the status below or contact HR for next steps.';
      default:
        return 'You can continue to forms and exams when HR approves your documents.';
    }
  }

  Future<void> _continueApplication() async {
    final email = _continueEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email to continue.')),
      );
      return;
    }
    if (!_isVacancyApplication) {
      if (_step1StatusApp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tap Check status first to load your application.'),
          ),
        );
        return;
      }
      if (!_canProceedTrackingContinue(_step1StatusApp!, _step1StatusExam)) {
        return;
      }
    }
    setState(() => _continueLoading = true);
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted) return;
      if (lookup == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !_isVacancyApplication
                  ? 'No application for this email. To apply, use Job Vacancies on the home page and tap Apply on a position.'
                  : 'No application found for this email.',
            ),
          ),
        );
        setState(() => _continueLoading = false);
        return;
      }
      final app = lookup.application;
      final exam = lookup.examResult;
      final trackingOnly = !_isVacancyApplication;
      final nextStep = trackingOnly
          ? _resumeStepForTrackingOnlyEntry(app, exam)
          : _resumeStepFor(app, exam);

      _stopStep1StatusTimer();
      setState(() {
        if (nextStep == 1 && trackingOnly) {
          _step1StatusApp = app;
          _step1StatusExam = exam;
          _statusPreviewEmail = email.trim().toLowerCase();
          _step1StatusError = null;
          _startStep1StatusTimer();
        } else {
          _statusPreviewEmail = null;
          _step1StatusApp = null;
          _step1StatusExam = null;
          _step1StatusError = null;
        }
        _applicationId = app.id;
        _applicationStatus = app.status;
        _finalInterviewAt = app.finalInterviewAt;
        _finalInterviewPassed = app.finalInterviewPassed;
        _hiredUserId = app.hiredUserId;
        _hrAccountSetupDone = app.hrAccountSetupDone;
        final p = app.positionAppliedFor?.trim();
        _applicationPositionAppliedFor = (p != null && p.isNotEmpty) ? p : null;
        if (exam != null) {
          _examScore = exam.scorePercent;
          _examPassed = exam.passed;
        } else {
          _examScore = 0;
          _examPassed = false;
        }
        _examBeiGradingPending =
            nextStep == 7 && exam != null && !exam.beiGradingComplete;
        if (!_examBeiGradingPending) {
          _beiGradingPollTimer?.cancel();
        }
        _step = nextStep;
        _continueLoading = false;
      });

      if (nextStep == 7 && _examBeiGradingPending && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startBeiGradingPoll();
        });
      }

      if (nextStep == 1 && trackingOnly && mounted) {
        final hint =
            (exam != null && !exam.passed && exam.beiGradingComplete) ||
                app.status == 'failed'
            ? _trackingContinueBlockedHint(app, exam)
            : _trackingOnlyContinueStayMessage(app.status);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(hint)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
        setState(() => _continueLoading = false);
      }
    }
  }

  String? _displayPositionTitle() {
    final w = widget.selectedPositionHeadline?.trim();
    if (w != null && w.isNotEmpty) return w;
    final loaded = _applicationPositionAppliedFor?.trim();
    if (loaded != null && loaded.isNotEmpty) return loaded;
    final preview = _step1StatusApp?.positionAppliedFor?.trim();
    if (preview != null && preview.isNotEmpty) return preview;
    return null;
  }

  String _appBarTitle() {
    if (!_isVacancyApplication && _step == 1) {
      return 'Track your application';
    }
    final pos = _displayPositionTitle();
    if (pos != null && pos.isNotEmpty) {
      return 'Apply for $pos';
    }
    return 'Recruitment Application';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: Text(
          _appBarTitle(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        ),
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_step == 1 && _step1StatusApp != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh status preview',
              onPressed: _step1StatusLoading ? null : _silentRefreshStep1Status,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          kIsWeb ? 32 : 24,
          kIsWeb ? 28 : 24,
          kIsWeb ? 32 : 24,
          kIsWeb ? 48 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: kIsWeb ? 720 : 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isVacancyApplication || _step != 1) ...[
                  _buildStepIndicator(),
                  const SizedBox(height: 32),
                ],
                if (_step == 1) _buildStep1BasicInfo(),
                if (_step == 2) _buildStep2PendingReview(),
                if (_step == 3) _buildStep3BeiExam(),
                if (_step == 4) _buildStep4GeneralExam(),
                if (_step == 5) _buildStep5MathExam(),
                if (_step == 6) _buildStep6GeneralInfoExam(),
                if (_step == 7) _buildStep7Result(),
                if (_step == 8) _buildStep8FinalHiring(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final w = MediaQuery.sizeOf(context).width;
    final scrollSteps = kIsWeb && w < 560;
    final dot = kIsWeb && !scrollSteps ? 30.0 : 26.0;
    final font = kIsWeb && !scrollSteps ? 11.0 : 10.0;
    final arrowPad = kIsWeb && !scrollSteps ? 4.0 : 2.0;
    final row = Row(
      mainAxisAlignment: scrollSteps
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: List.generate(8, (i) {
        final n = i + 1;
        final active = n == _step;
        final done = n < _step;
        return Row(
          children: [
            Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.primaryNavy
                    : (done
                          ? AppTheme.primaryNavy.withOpacity(0.5)
                          : AppTheme.lightGray),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$n',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: font,
                ),
              ),
            ),
            if (n < 8)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: arrowPad),
                child: Icon(
                  Icons.arrow_forward,
                  size: kIsWeb ? 14 : 12,
                  color: AppTheme.textSecondary,
                ),
              ),
          ],
        );
      }),
    );
    if (!scrollSteps) return row;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      ),
    );
  }

  Widget _buildStep1BasicInfo() {
    if (!_isVacancyApplication) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _recruitmentWebPanel(
            tinted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: kIsWeb ? 52 : 48,
                      height: kIsWeb ? 52 : 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryNavy.withValues(alpha: 0.16),
                            AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                          ],
                        ),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        Icons.manage_search_rounded,
                        color: AppTheme.primaryNavy,
                        size: kIsWeb ? 28 : 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Track your application',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: kIsWeb ? 26 : 22,
                              height: 1.15,
                              letterSpacing: -0.35,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Look up your record by email, then continue when the process allows it.',
                            style: TextStyle(
                              fontSize: kIsWeb ? 14.5 : 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.92,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: kIsWeb ? 22 : 18),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(kIsWeb ? 16 : 14),
                  decoration: BoxDecoration(
                    color: AppTheme.sectionAlt.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.lightGray.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: AppTheme.primaryNavy.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'To start a new application, go back to the home page, open Job Vacancies, and tap Apply now on the position you want.',
                              style: TextStyle(
                                fontSize: kIsWeb ? 14.5 : 14,
                                height: 1.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.mail_outline_rounded,
                            size: 18,
                            color: AppTheme.primaryNavy.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Enter the email you used when you applied, then tap Check status. Continue stays off until your application is loaded and you are allowed to proceed (for example, after HR approves your documents).',
                              style: TextStyle(
                                fontSize: kIsWeb ? 14.5 : 14,
                                height: 1.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: kIsWeb ? 22 : 18),
                _buildContinueEmailRow(),
                _buildStep1StatusPreviewSection(),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasLocalDraft)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: AppTheme.primaryNavy.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.save_outlined,
                      color: AppTheme.primaryNavy,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'May naka-save na draft sa device na ito mula sa dating pagbisita (Step 1). Pwede mong i-load o alisin.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadLocalDraftToFields,
                      child: const Text('I-load'),
                    ),
                    TextButton(
                      onPressed: _clearLocalDraft,
                      child: const Text('Alisin'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (kIsWeb)
          _recruitmentWebPanel(tinted: false, child: _buildStep1FormFields())
        else
          _buildStep1FormFields(),
      ],
    );
  }

  Widget _recruitmentWebPanel({required bool tinted, required Widget child}) {
    final radius = BorderRadius.circular(20);
    final hairline = AppTheme.lightGray.withValues(alpha: 0.75);
    final borderSide = Border.all(color: hairline);
    final panelShadow = [
      BoxShadow(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        blurRadius: 28,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
    if (tinted) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: radius,
          border: borderSide,
          boxShadow: panelShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppTheme.primaryNavyDark,
                    AppTheme.primaryNavy,
                    AppTheme.primaryNavyLight,
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                kIsWeb ? 28 : 22,
                kIsWeb ? 26 : 20,
                kIsWeb ? 28 : 22,
                kIsWeb ? 28 : 24,
              ),
              child: child,
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: radius,
        border: borderSide,
        boxShadow: panelShadow,
      ),
      padding: EdgeInsets.all(kIsWeb ? 28 : 22),
      child: child,
    );
  }

  bool get _isContinueEmailRowActionEnabled {
    if (_continueLoading || _step1StatusLoading) return false;
    final email = _continueEmailController.text.trim();
    if (email.isEmpty) return false;
    final app = _step1StatusApp;
    if (app == null) return false;
    return _canProceedTrackingContinue(app, _step1StatusExam);
  }

  Widget _buildContinueEmailRow() {
    final navy = AppTheme.primaryNavy;
    final continueBtn = FilledButton(
      onPressed: _isContinueEmailRowActionEnabled ? _continueApplication : null,
      style: FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        disabledBackgroundColor: AppTheme.lightGray.withValues(alpha: 0.85),
        disabledForegroundColor: AppTheme.textSecondary.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        minimumSize: const Size(128, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _continueLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
    );
    final checkBtn = OutlinedButton.icon(
      onPressed: (_step1StatusLoading || _continueLoading)
          ? null
          : _checkStep1StatusOnly,
      icon: _step1StatusLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: navy),
            )
          : const Icon(Icons.search_rounded, size: 20),
      label: Text(
        _step1StatusLoading ? 'Checking…' : 'Check status',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        side: BorderSide(color: navy.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final emailField = TextField(
      controller: _continueEmailController,
      decoration: _trackEmailDecoration('Email to continue'),
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
    );
    final app = _step1StatusApp;
    final emailNonEmpty = _continueEmailController.text.trim().isNotEmpty;
    final showCheckStatusFirstHint =
        emailNonEmpty &&
        app == null &&
        !_step1StatusLoading &&
        !_continueLoading &&
        _step1StatusError == null;
    final showBlockedHint =
        app != null &&
        emailNonEmpty &&
        !_canProceedTrackingContinue(app, _step1StatusExam);

    Widget hintBox(String text) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryNavy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              size: 18,
              color: AppTheme.primaryNavy.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppTheme.textSecondary.withValues(alpha: 0.95),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final narrowActions = MediaQuery.sizeOf(context).width < 480;

    return Container(
      padding: EdgeInsets.all(kIsWeb ? 16 : 14),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.lightGray.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          emailField,
          const SizedBox(height: 14),
          if (narrowActions) ...[
            checkBtn,
            const SizedBox(height: 10),
            continueBtn,
          ] else
            Row(
              children: [
                const Spacer(),
                checkBtn,
                const SizedBox(width: 10),
                continueBtn,
              ],
            ),
          if (showCheckStatusFirstHint) ...[
            const SizedBox(height: 14),
            hintBox(
              'Tap Check status first so we can load your application. Continue stays off until we confirm your record and you are allowed to move forward (for example, after HR approves your documents).',
            ),
          ],
          if (showBlockedHint) ...[
            const SizedBox(height: 14),
            hintBox(_trackingContinueBlockedHint(app, _step1StatusExam)),
          ],
        ],
      ),
    );
  }

  Widget _buildStep1StatusPreviewSection() {
    if (_step1StatusLoading &&
        _step1StatusApp == null &&
        _step1StatusError == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryNavy),
        ),
      );
    }
    if (_step1StatusError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _step1StatusError!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_step1StatusApp == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        RspApplicationStatusTimeline(
          application: _step1StatusApp!,
          examResult: _step1StatusExam,
          sameAsRecruitmentFlowNote: true,
          statusFooterNote:
              'Status refreshes every 30 seconds while you stay on this page. Use Refresh in the app bar for an immediate update.',
        ),
        const SizedBox(height: 12),
        Text(
          _isVacancyApplication
              ? 'When you are ready to fill forms or take exams, tap Continue above to open your application at the correct step.'
              : 'Tap Check status first to load your application. After HR approves your documents, Continue unlocks for exams. If you do not pass the exam, Continue stays off.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _step1FormSectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.textSecondary.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _step1GuidelineExpansion({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.primaryNavy.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.16),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            iconColor: AppTheme.primaryNavy,
            collapsedIconColor: AppTheme.primaryNavy,
            leading: Icon(
              icon,
              size: 22,
              color: AppTheme.primaryNavy.withValues(alpha: 0.85),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.textSecondary.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _step1FieldDecoration(
    String plainLabel, {
    bool requiredMark = false,
    IconData? prefixIcon,
    String? hintText,
  }) {
    final radius = BorderRadius.circular(14);
    return InputDecoration(
      label: Text.rich(
        TextSpan(
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(text: plainLabel),
            if (requiredMark)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Color(0xFFC62828),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelStyle: const TextStyle(
        color: AppTheme.primaryNavy,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      hintText: hintText,
      hintStyle: TextStyle(
        color: AppTheme.textSecondary.withValues(alpha: 0.45),
        fontSize: 15,
      ),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(
              prefixIcon,
              color: AppTheme.primaryNavy.withValues(alpha: 0.55),
              size: 22,
            ),
      filled: true,
      fillColor: AppTheme.white,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: AppTheme.lightGray.withValues(alpha: 0.95),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: prefixIcon == null ? 16 : 12,
        vertical: 18,
      ),
    );
  }

  Widget _buildStep1FormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STEP 1',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.85,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submit Basic Information',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: kIsWeb ? 24 : 21,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Provide your details. HR will review your documents before you can take the exam.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 15 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        _step1FormSectionHeader(
          'Personal information',
          subtitle:
              'Provide your name and gender exactly as it appears on your records.',
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: _firstNameController,
            decoration: _step1FieldDecoration(
              'First Name',
              requiredMark: true,
              hintText: 'First name',
              prefixIcon: Icons.person_outline_rounded,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: _middleNameController,
            decoration: _step1FieldDecoration(
              'Middle Name',
              hintText: 'Middle name (optional)',
              prefixIcon: Icons.person_outline_rounded,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: _lastNameController,
            decoration: _step1FieldDecoration(
              'Last Name',
              requiredMark: true,
              hintText: 'Last name',
              prefixIcon: Icons.person_outline_rounded,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DropdownButtonFormField<String>(
            initialValue: _suffixValue,
            items: _suffixOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _suffixValue = v),
            decoration: _step1FieldDecoration(
              'Suffix',
              hintText: 'Select suffix (optional)',
              prefixIcon: Icons.text_fields_rounded,
            ),
            isExpanded: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: DropdownButtonFormField<String>(
            initialValue: _sexValue,
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
            ],
            onChanged: (v) => setState(() => _sexValue = v),
            decoration: _step1FieldDecoration(
              'Gender',
              requiredMark: true,
              hintText: 'Select gender',
              prefixIcon: Icons.wc_rounded,
            ),
            isExpanded: true,
          ),
        ),
        _step1FormSectionHeader(
          'Contact details',
          subtitle:
              'Email and phone number are required. HR uses these to reach you about your application.',
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: TextField(
            controller: _emailController,
            decoration: _step1FieldDecoration(
              'Email',
              requiredMark: _serverRequiresEmailOtp == true,
              hintText: 'you@example.com',
              prefixIcon: Icons.alternate_email_rounded,
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
        ),
        _buildStep1EmailOtpSection(),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _phoneController,
            decoration: _step1FieldDecoration(
              'Phone number',
              requiredMark: true,
              hintText: 'Mobile you answer regularly',
              prefixIcon: Icons.phone_outlined,
            ),
            keyboardType: TextInputType.phone,
          ),
        ),
        _step1GuidelineExpansion(
          icon: Icons.contact_mail_outlined,
          title: 'Valid contact information',
          body:
              'Use only a real, active email address and mobile number that you check regularly. '
              'Do not use fake, dummy, burner, or disposable accounts or numbers. '
              'Providing false contact information may delay or void your application.',
        ),
        const SizedBox(height: 18),
        _step1FormSectionHeader(
          'Required documents',
          subtitle:
              'Application letter, resume, TOR, and eligibility/trainings documents are all required to submit.',
        ),
        const SizedBox(height: 12),
        _step1GuidelineExpansion(
          icon: Icons.picture_as_pdf_outlined,
          title: 'PDF files only',
          body:
              'Each attachment must be a PDF file (.pdf). '
              'Microsoft Word (.doc, .docx) and other formats are not accepted—save or export as PDF before uploading.',
        ),
        const SizedBox(height: 6),
        ...RspApplicationDocKind.values.map((kind) {
          final f = _pickedDocs[kind];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.lightGray.withValues(alpha: 0.95),
                ),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 20,
                          color: AppTheme.primaryNavy.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _docKindLabel(kind),
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (f == null)
                      FilledButton.tonalIcon(
                        onPressed: _submitting ? null : () => _pickDoc(kind),
                        icon: const Icon(Icons.upload_file_rounded, size: 22),
                        label: const Text('Choose PDF file'),
                        style: FilledButton.styleFrom(
                          foregroundColor: AppTheme.primaryNavy,
                          backgroundColor: AppTheme.primaryNavy.withValues(
                            alpha: 0.12,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : () => _pickDoc(kind),
                        icon: const Icon(Icons.upload_rounded, size: 20),
                        label: const Text('Replace file'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryNavy,
                          side: const BorderSide(
                            color: AppTheme.primaryNavy,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 14,
                          ),
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () => _removeDoc(kind),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submitStep1,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, size: 22),
                      SizedBox(width: 10),
                      Text('Submit application'),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2PendingReview() {
    final isDeclined = _applicationStatus == 'document_declined';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 2: Document review',
          style: TextStyle(
            color: AppTheme.primaryNavy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        if (!isDeclined) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _continueEmailController,
                    decoration: _dec('Your email to take the exam'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _continueLoading ? null : _continueApplication,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  child: _continueLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continue to exam'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDeclined
                ? Colors.red.shade50
                : AppTheme.primaryNavy.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDeclined
                  ? Colors.red.shade200
                  : AppTheme.primaryNavy.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Icon(
                isDeclined ? Icons.cancel : Icons.hourglass_top_rounded,
                size: 56,
                color: isDeclined ? Colors.red.shade700 : AppTheme.primaryNavy,
              ),
              const SizedBox(height: 16),
              Text(
                isDeclined ? 'Application not approved' : 'Under review',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isDeclined
                    ? 'Your application was not approved. You cannot proceed to the exam. If you have questions, please contact HR.'
                    : 'HR is reviewing your documents. Once approved, you can take the screening exam. Use "Continue application" above and enter your email to take the exam when ready.',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (!isDeclined)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Return to this page later and click "Continue" with your email to take the exam.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStep3BeiExam() {
    const stepTitle = '8 Behavioral Event Interview (BEI)';
    const stepSubtitle =
        'For new applicants and promotions. Answer each question in the space provided.';

    if (_beiQuestionsLoaded == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBeiQuestions());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 3,
            title: stepTitle,
            subtitle: stepSubtitle,
            icon: Icons.psychology_rounded,
          ),
          const RspApplicantExamLoading(),
        ],
      );
    }
    final questions = _beiQuestionsLoaded!;
    if (questions.isEmpty || _beiControllers.length != questions.length) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantStepHeader(
          stepNumber: 3,
          title: stepTitle,
          subtitle: stepSubtitle,
          icon: Icons.psychology_rounded,
        ),
        RspApplicantExamProgress(
          answeredCount: _beiAnsweredCount(),
          totalCount: questions.length,
          label: 'Questions answered',
        ),
        const SizedBox(height: 20),
        ...List.generate(questions.length, (i) {
          return RspApplicantBeiQuestionCard(
            index: i,
            question: questions[i],
            controller: _beiControllers[i],
            onChanged: () => setState(() {}),
          );
        }),
        const RspApplicantBeiMotivationQuote(),
        const SizedBox(height: 8),
        RspApplicantSubmitButton(
          label: 'Submit BEI answers',
          onPressed: _submitBeiExam,
        ),
      ],
    );
  }

  Widget _buildStep4GeneralExam() {
    const stepTitle = 'General Exam for LGU-Plaridel Applicants';
    final timeNote = _mcqInstructionTimeNote('general');
    final subtitle =
        'Answer each question. You need 60% or higher to pass.$timeNote';

    if (_generalQuestionsLoaded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 4,
            title: stepTitle,
            subtitle: subtitle,
            icon: Icons.quiz_rounded,
          ),
          const RspApplicantExamLoading(),
        ],
      );
    }
    final questions = _generalQuestionsLoaded!;
    if (questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 4,
            title: stepTitle,
            subtitle: subtitle,
            icon: Icons.quiz_rounded,
          ),
          const SizedBox(height: 16),
          const RspApplicantExamEmpty(
            message: 'No questions configured. Please try again later.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantStepHeader(
          stepNumber: 4,
          title: stepTitle,
          subtitle: subtitle,
          icon: Icons.quiz_rounded,
        ),
        RspApplicantExamProgress(
          answeredCount: _mcqAnsweredCount(_generalSelected),
          totalCount: questions.length,
          label: 'Questions answered',
        ),
        _buildExamTimerBanner(),
        const SizedBox(height: 16),
        _buildMcqQuestionList(
          questions: questions,
          selected: _generalSelected,
          onSelect: (i, j) => setState(() => _generalSelected[i] = j),
          useLetterPrefix: false,
        ),
        const SizedBox(height: 8),
        RspApplicantSubmitButton(
          label: 'Submit General Exam',
          onPressed: _submitGeneralExam,
        ),
      ],
    );
  }

  Widget _buildStep5MathExam() {
    const stepTitle = 'Mathematics Exam';
    final timeNote = _mcqInstructionTimeNote('math');
    final subtitle =
        'Choose the best answer (a–d). You need 60% or higher to pass.$timeNote';

    if (_mathQuestionsLoaded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 5,
            title: stepTitle,
            subtitle: subtitle,
            icon: Icons.calculate_rounded,
          ),
          const RspApplicantExamLoading(),
        ],
      );
    }
    final questions = _mathQuestionsLoaded!;
    if (questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 5,
            title: stepTitle,
            subtitle: subtitle,
            icon: Icons.calculate_rounded,
          ),
          const SizedBox(height: 16),
          const RspApplicantExamEmpty(
            message: 'No questions configured. Please try again later.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantStepHeader(
          stepNumber: 5,
          title: stepTitle,
          subtitle: subtitle,
          icon: Icons.calculate_rounded,
        ),
        RspApplicantExamProgress(
          answeredCount: _mcqAnsweredCount(_mathSelected),
          totalCount: questions.length,
          label: 'Questions answered',
        ),
        _buildExamTimerBanner(),
        const SizedBox(height: 16),
        _buildMcqQuestionList(
          questions: questions,
          selected: _mathSelected,
          onSelect: (i, j) => setState(() => _mathSelected[i] = j),
          useLetterPrefix: true,
        ),
        const SizedBox(height: 8),
        RspApplicantSubmitButton(
          label: 'Submit Mathematics Exam',
          onPressed: _submitMathExam,
        ),
      ],
    );
  }

  Widget _buildStep6GeneralInfoExam() {
    const stepTitle = 'General Information Exam';
    final timeNote = _mcqInstructionTimeNote('general_info');
    final subtitle =
        'Choose the best answer (a–d). You need 60% or higher to pass.$timeNote';

    if (_generalInfoQuestionsLoaded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 6,
            title: stepTitle,
            subtitle: subtitle,
            icon: Icons.menu_book_rounded,
          ),
          const RspApplicantExamLoading(),
        ],
      );
    }
    final questions = _generalInfoQuestionsLoaded!;
    if (questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantStepHeader(
            stepNumber: 6,
            title: stepTitle,
            subtitle: subtitle,
            icon: Icons.menu_book_rounded,
          ),
          const SizedBox(height: 16),
          const RspApplicantExamEmpty(
            message: 'No questions configured. Please try again later.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantStepHeader(
          stepNumber: 6,
          title: stepTitle,
          subtitle: subtitle,
          icon: Icons.menu_book_rounded,
        ),
        RspApplicantExamProgress(
          answeredCount: _mcqAnsweredCount(_generalInfoSelected),
          totalCount: questions.length,
          label: 'Questions answered',
        ),
        _buildExamTimerBanner(),
        const SizedBox(height: 16),
        _buildMcqQuestionList(
          questions: questions,
          selected: _generalInfoSelected,
          onSelect: (i, j) => setState(() => _generalInfoSelected[i] = j),
          useLetterPrefix: true,
        ),
        const SizedBox(height: 8),
        RspApplicantSubmitButton(
          label: 'Submit General Information Exam',
          onPressed: _examSubmitting
              ? null
              : () async => await _submitGeneralInfoExam(),
          enabled: !_examSubmitting,
        ),
      ],
    );
  }

  static const double _step7CardRadius = 16;

  Widget _step7Bullet(String text, {required Color bulletColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: bulletColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep7AwaitingBeiGrading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RspApplicantStepHeader(
          stepNumber: 7,
          title: 'View Exam Result',
          subtitle:
              'Your multiple-choice exams are submitted. HR must grade every BEI answer before your final screening result appears.',
          icon: Icons.fact_check_rounded,
        ),
        const SizedBox(height: 20),
        RspApplicantStatusCard(
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting for BEI grading',
          body:
              'This page checks every 15 seconds. You can also tap Refresh status.',
          accentColor: AppTheme.primaryNavy,
          child: OutlinedButton.icon(
            onPressed: _refreshBeiGradingFromServer,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Refresh status'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              side: const BorderSide(color: AppTheme.primaryNavy, width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Provisional score (MCQ only; BEI not included yet): ${_examScore.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: AppTheme.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildStep7Result() {
    if (_examBeiGradingPending) {
      return _buildStep7AwaitingBeiGrading();
    }
    final examOk = _examPassed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RspApplicantStepHeader(
          stepNumber: 7,
          title: 'View Exam Result',
          subtitle:
              'Review your screening score and any update on your final interview.',
          icon: Icons.fact_check_rounded,
        ),
        const SizedBox(height: 20),
        RspApplicantExamResultHero(
          passed: examOk,
          scorePercent: _examScore,
        ),
        if (_examPassed && _finalInterviewPassed == true) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(_step7CardRadius),
              border: Border.all(
                color: const Color(0xFF43A047).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_rounded,
                  color: Colors.green.shade800,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Final interview: Passed',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.green.shade900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'HR has recorded that you passed the in-person final interview.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade900.withValues(alpha: 0.92),
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _step7Bullet(
                        'Follow HR instructions for onboarding.',
                        bulletColor: Colors.green.shade700,
                      ),
                      _step7Bullet(
                        'Employee accounts are created by HR only—not through this form.',
                        bulletColor: Colors.green.shade700,
                      ),
                      _step7Bullet(
                        'When your account is ready, continue to Step 8 and sign in with the email HR used for you.',
                        bulletColor: Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else if (_examPassed && _finalInterviewPassed == false) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(_step7CardRadius),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.red.shade800,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'HR has recorded the result of your final interview. If you have questions, please contact the HR office.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_examPassed && _finalInterviewAt != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(_step7CardRadius),
              border: Border.all(
                color: const Color(0xFF43A047).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.event_available_rounded,
                  color: Colors.green.shade800,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Final interview scheduled',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.green.shade900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF43A047,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                              color: Colors.green.shade800,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${MaterialLocalizations.of(context).formatFullDate(_finalInterviewAt!.toLocal())} · ${TimeOfDay.fromDateTime(_finalInterviewAt!.toLocal()).format(context)}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade900,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _step7Bullet(
                        'Arrive on time and bring a valid ID.',
                        bulletColor: Colors.green.shade700,
                      ),
                      _step7Bullet(
                        'Contact HR if you need to reschedule.',
                        bulletColor: Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (_examPassed)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await _syncInterviewFromEmail();
                if (mounted) setState(() => _step = 8);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_step7CardRadius),
                ),
              ),
              child: const Text('Continue to final hiring'),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_step7CardRadius),
                ),
              ),
              child: const Text('Back to recruitment'),
            ),
          ),
      ],
    );
  }

  bool get _employeeAccountLinked =>
      _applicationStatus == 'registered' ||
      (_hiredUserId != null && _hiredUserId!.trim().isNotEmpty);

  Future<void> _refreshHiringStatus() async {
    await _syncInterviewFromEmail();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status updated from HR records.')),
    );
  }

  Widget _buildStep8StatusFooter() {
    final interview = _finalInterviewAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (interview != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 20,
                  color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Final interview: '
                    '${MaterialLocalizations.of(context).formatFullDate(interview.toLocal())} · '
                    '${TimeOfDay.fromDateTime(interview.toLocal()).format(context)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _refreshHiringStatus,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('Refresh status'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryNavy,
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: AppTheme.primaryNavy.withValues(alpha: 0.35),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHiringStatusCard({
    required bool linked,
    required bool passedFinal,
    required bool failedFinal,
    required bool hrSetupDone,
  }) {
    late final String title;
    late final String body;
    late final Color accent;
    late final IconData icon;

    if (linked) {
      title = 'Hired — your account is ready';
      body =
          'Your application is linked to an employee account. Sign in below with the same email you used for this application. If login fails, check your inbox (including spam) or contact HR.';
      accent = const Color(0xFF2E7D32);
      icon = Icons.verified_rounded;
    } else if (failedFinal) {
      title = 'Final interview recorded';
      body =
          'HR has recorded your final interview result. For questions, contact the HR office.';
      accent = Colors.red.shade800;
      icon = Icons.info_outline_rounded;
    } else if (passedFinal && hrSetupDone) {
      title = 'Account setup complete';
      body =
          'HR marked your employee account as ready. Check your email, then use Go to login form with this application email.';
      accent = const Color(0xFF1565C0);
      icon = Icons.task_alt_rounded;
    } else if (passedFinal) {
      title = 'Waiting for HR account setup';
      body =
          'You passed the final interview. HR will create your account and email you when you can sign in—applicants cannot self-register. Check your inbox and spam folder, then tap Refresh status for updates.';
      accent = const Color(0xFFE85D04);
      icon = Icons.hourglass_top_rounded;
    } else {
      title = 'Waiting for interview result';
      body =
          'HR has not recorded a final interview outcome yet. After your in-person interview, tap Refresh status here or continue on Step 2 with your email.';
      accent = AppTheme.primaryNavy;
      icon = Icons.pending_outlined;
    }

    return RspApplicantStatusCard(
      icon: icon,
      title: title,
      body: body,
      accentColor: accent,
      child: _buildStep8StatusFooter(),
    );
  }

  Widget _buildStep8FinalHiring() {
    final linked = _employeeAccountLinked;
    final passedFinal = _finalInterviewPassed == true;
    final failedFinal = _finalInterviewPassed == false;

    String headerSubtitle;
    if (failedFinal) {
      headerSubtitle = 'Your current hiring status from HR.';
    } else if (linked) {
      headerSubtitle = 'You can sign in with your employee account.';
    } else if (passedFinal) {
      headerSubtitle =
          'You passed screening and the final interview. HR will set up your account.';
    } else {
      headerSubtitle =
          'Track your final interview result and account setup in one place.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantStepHeader(
          stepNumber: 8,
          title: 'Final hiring & your account',
          subtitle: headerSubtitle,
          icon: Icons.badge_rounded,
        ),
        const SizedBox(height: 20),
        _buildHiringStatusCard(
          linked: linked,
          passedFinal: passedFinal,
          failedFinal: failedFinal,
          hrSetupDone: _hrAccountSetupDone,
        ),
        const SizedBox(height: 24),
        if (linked || (passedFinal && _hrAccountSetupDone))
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              icon: const Icon(Icons.login_rounded, size: 22),
              label: const Text('Go to login form'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String label) => rspUnderlinedField(label);

  InputDecoration _trackEmailDecoration(String label) {
    final radius = BorderRadius.circular(14);
    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(
        color: AppTheme.textSecondary.withValues(alpha: 0.65),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: AppTheme.white,
      prefixIcon: Icon(
        Icons.alternate_email_rounded,
        color: AppTheme.primaryNavy.withValues(alpha: 0.55),
        size: 22,
      ),
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: AppTheme.lightGray.withValues(alpha: 0.85),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }
}
