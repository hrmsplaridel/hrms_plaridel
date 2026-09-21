import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/models/rsp_screening_scores.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_form_header_footer.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/applicant_journey.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_app_bar.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_assessment_hub.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_document_upload_card.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_journey_tracker.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_next_action_card.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_status_badge.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_account_details_card.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_waiting_state.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_application_status_timeline.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_exam_ui.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';
import 'package:hrms_plaridel/shared/widgets/login_style_grid_backdrop.dart';

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

const _kRspStep1DraftKey = 'rsp_application_step1_draft_v2';

/// Recruitment flow. **Job application** (no [selectedPositionHeadline]) opens tracking only;
/// **Apply now** on a vacancy includes Step 1 (basic info + documents).
class ApplicationFlowPage extends StatefulWidget {
  const ApplicationFlowPage({
    super.key,
    this.selectedPositionHeadline,
    this.resumeEmail,
  });

  /// Set when the applicant taps **Apply now** on a specific vacancy (job title for Step 1 + DB).
  final String? selectedPositionHeadline;

  /// Set when Track Application Status taps Continue.
  final String? resumeEmail;

  @override
  State<ApplicationFlowPage> createState() => _ApplicationFlowPageState();
}

class _ApplicationFlowPageState extends State<ApplicationFlowPage> {
  int _step = 1;
  String? _applicationId;

  /// Human-readable randomized applicant ID (e.g. PLR-AB12CD34).
  String? _applicantNumber;

  /// Set when applicant uses "Continue" so the app bar shows DB position for later steps.
  String? _applicationPositionAppliedFor;

  /// When loaded via "Continue application" or after Step 1: submitted | document_approved | document_declined
  String? _applicationStatus;
  bool _examPassed = false;
  // ignore: unused_field
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
  DateTime? _hireCredentialsEmailSentAt;

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _courseController = TextEditingController();
  final _ageController = TextEditingController();
  final _streetController = TextEditingController();
  final _continueEmailController = TextEditingController();
  final GlobalKey<StructuredAddressFormState> _addressFormKey =
      GlobalKey<StructuredAddressFormState>();
  final Map<RspApplicationDocKind, PlatformFile> _pickedDocs = {};
  final Map<RspApplicationDocKind, String> _step1DocNames = {};
  final Map<RspFinalRequirementDocKind, PlatformFile> _pickedFinalReqDocs = {};
  bool _resubmittingDocs = false;
  String? _docMedicalCertificatePath;
  String? _docMedicalCertificateName;
  String? _docDrugTestPath;
  String? _docDrugTestName;
  String? _docNbiClearancePath;
  String? _docNbiClearanceName;
  String? _docMedicalCertificateRejectReason;
  String? _docDrugTestRejectReason;
  String? _docNbiClearanceRejectReason;
  bool _finalRequirementsApproved = false;
  DateTime? _orientationAt;
  bool? _orientationAttended;
  bool _finalReqUploading = false;
  bool _hiringStatusRefreshing = false;
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
  Timer? _duplicateCheckDebounce;
  bool _hasLocalDraft = false;
  bool _privacyConsentAccepted = false;
  bool _privacyConsentChecked = false;
  bool _duplicateApplicantExists = false;
  bool _checkingDuplicateApplicant = false;

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
  String? _civilStatusValue;

  static const List<String> _civilStatusOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Legally Separated',
    'Annulled',
    'Divorced',
    'Live-in / Common-law',
  ];

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

  /// Per-exam countdown limits from API (keys: bei, general, math, general_info, custom_*).
  Map<String, int> _examTimeLimitSeconds = {};

  Timer? _examCountdownTimer;
  int? _examCountdownRemaining;

  /// True until HR enters all BEI scores (Step 7 shows waiting, not pass/fail).
  bool _examBeiGradingPending = false;
  Timer? _beiGradingPollTimer;

  /// When set, the Assessment hub shows the exam body. Null = dashboard.
  String? _activeAssessment;
  int _examQuestionIndex = 0;
  bool _examReviewing = false;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_scheduleDraftSave);
    _firstNameController.addListener(_scheduleDuplicateApplicantCheck);
    _middleNameController.addListener(_scheduleDraftSave);
    _middleNameController.addListener(_scheduleDuplicateApplicantCheck);
    _lastNameController.addListener(_scheduleDraftSave);
    _lastNameController.addListener(_scheduleDuplicateApplicantCheck);
    _emailController.addListener(_scheduleDraftSave);
    _emailController.addListener(_onEmailMaybeInvalidateOtp);
    _emailController.addListener(_scheduleDuplicateApplicantCheck);
    _phoneController.addListener(_scheduleDraftSave);
    _courseController.addListener(_scheduleDraftSave);
    _ageController.addListener(_scheduleDraftSave);
    _streetController.addListener(_scheduleDraftSave);
    _continueEmailController.addListener(_scheduleDraftSave);
    _continueEmailController.addListener(_onContinueEmailChangedForPreview);
    _continueEmailController.addListener(_rebuildForContinueButtonEligibility);
    if (_isVacancyApplication) _checkLocalDraft();
    if (_isVacancyApplication) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadEmailOtpConfig(),
      );
    }
    final resumeEmail = widget.resumeEmail?.trim() ?? '';
    if (resumeEmail.isNotEmpty) {
      _continueEmailController.text = resumeEmail;
      _emailController.text = resumeEmail;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_continueApplication());
      });
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
          'course': _courseController.text,
          'age': _ageController.text,
          'civilStatus': _civilStatusValue,
          'address': _addressFormKey.currentState?.composeEncoded() ?? '',
          'street': _streetController.text,
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
        m['course']?.toString().trim(),
        m['age']?.toString().trim(),
        m['civilStatus']?.toString().trim(),
        m['address']?.toString().trim(),
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
        _civilStatusValue = m['civilStatus']?.toString().trim().isEmpty == true
            ? null
            : m['civilStatus']?.toString();
        _courseController.text = m['course']?.toString() ?? '';
        _ageController.text = m['age']?.toString() ?? '';
        _streetController.text = m['street']?.toString() ?? '';
        _emailController.text = m['email']?.toString() ?? '';
        _phoneController.text = m['phone']?.toString() ?? '';
        _continueEmailController.text = m['continueEmail']?.toString() ?? '';
        _hasLocalDraft = false;
      });
      final draftAddress = m['address']?.toString();
      if (draftAddress != null && draftAddress.trim().isNotEmpty) {
        await _addressFormKey.currentState?.applyRawAddress(draftAddress);
      }
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
    _duplicateCheckDebounce?.cancel();
    _firstNameController.removeListener(_scheduleDraftSave);
    _firstNameController.removeListener(_scheduleDuplicateApplicantCheck);
    _middleNameController.removeListener(_scheduleDraftSave);
    _middleNameController.removeListener(_scheduleDuplicateApplicantCheck);
    _lastNameController.removeListener(_scheduleDraftSave);
    _lastNameController.removeListener(_scheduleDuplicateApplicantCheck);
    _emailController.removeListener(_scheduleDraftSave);
    _emailController.removeListener(_onEmailMaybeInvalidateOtp);
    _emailController.removeListener(_scheduleDuplicateApplicantCheck);
    _phoneController.removeListener(_scheduleDraftSave);
    _courseController.removeListener(_scheduleDraftSave);
    _ageController.removeListener(_scheduleDraftSave);
    _streetController.removeListener(_scheduleDraftSave);
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
    _courseController.dispose();
    _ageController.dispose();
    _streetController.dispose();
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
        if (questions.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _activeAssessment != 'bei') return;
            unawaited(
              _ensureExamTimeLimits().then((_) {
                if (!mounted || _activeAssessment != 'bei') return;
                _startExamCountdown('bei');
              }),
            );
          });
        }
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _activeAssessment != 'bei') return;
          unawaited(
            _ensureExamTimeLimits().then((_) {
              if (!mounted || _activeAssessment != 'bei') return;
              _startExamCountdown('bei');
            }),
          );
        });
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

  void _syncPipelineFromApp(RecruitmentApplication app) {
    _applicantNumber = app.applicantNumber;
    _finalInterviewAt = app.finalInterviewAt;
    _finalInterviewPassed = app.finalInterviewPassed;
    _applicationStatus = app.status;
    _hiredUserId = app.hiredUserId;
    _hrAccountSetupDone = app.hrAccountSetupDone;
    _hireCredentialsEmailSentAt = app.hireCredentialsEmailSentAt;
    if (app.email.trim().isNotEmpty) {
      _emailController.text = app.email.trim();
      if (_continueEmailController.text.trim().isEmpty) {
        _continueEmailController.text = app.email.trim();
      }
    }
    _docMedicalCertificatePath = app.docMedicalCertificatePath;
    _docMedicalCertificateName = app.docMedicalCertificateName;
    _docDrugTestPath = app.docDrugTestPath;
    _docDrugTestName = app.docDrugTestName;
    _docNbiClearancePath = app.docNbiClearancePath;
    _docNbiClearanceName = app.docNbiClearanceName;
    _docMedicalCertificateRejectReason = app.docMedicalCertificateRejectReason;
    _docDrugTestRejectReason = app.docDrugTestRejectReason;
    _docNbiClearanceRejectReason = app.docNbiClearanceRejectReason;
    _finalRequirementsApproved = app.finalRequirementsApproved;
    _orientationAt = app.orientationAt;
    _orientationAttended = app.orientationAttended;
    for (final kind in RspApplicationDocKind.values) {
      final name = app.docDisplayName(kind)?.trim();
      if (name != null && name.isNotEmpty) {
        _step1DocNames[kind] = name;
      }
    }
  }

  String? _finalReqStoredPath(RspFinalRequirementDocKind kind) {
    switch (kind) {
      case RspFinalRequirementDocKind.medicalCertificate:
        return _docMedicalCertificatePath;
      case RspFinalRequirementDocKind.drugTestResult:
        return _docDrugTestPath;
      case RspFinalRequirementDocKind.nbiClearance:
        return _docNbiClearancePath;
    }
  }

  String? _finalReqStoredName(RspFinalRequirementDocKind kind) {
    switch (kind) {
      case RspFinalRequirementDocKind.medicalCertificate:
        return _docMedicalCertificateName;
      case RspFinalRequirementDocKind.drugTestResult:
        return _docDrugTestName;
      case RspFinalRequirementDocKind.nbiClearance:
        return _docNbiClearanceName;
    }
  }

  String? _finalReqRejectReason(RspFinalRequirementDocKind kind) {
    switch (kind) {
      case RspFinalRequirementDocKind.medicalCertificate:
        return _docMedicalCertificateRejectReason;
      case RspFinalRequirementDocKind.drugTestResult:
        return _docDrugTestRejectReason;
      case RspFinalRequirementDocKind.nbiClearance:
        return _docNbiClearanceRejectReason;
    }
  }

  bool get _hasAnyFinalReqRejection {
    for (final kind in RspFinalRequirementDocKind.values) {
      final r = _finalReqRejectReason(kind)?.trim();
      if (r != null && r.isNotEmpty) return true;
    }
    return false;
  }

  bool get _allFinalRequirementsUploaded {
    for (final kind in RspFinalRequirementDocKind.values) {
      final path = _finalReqStoredPath(kind);
      if (path == null || path.trim().isEmpty) return false;
    }
    return true;
  }

  bool _finalReqKindNeedsFile(RspFinalRequirementDocKind kind) {
    final path = _finalReqStoredPath(kind);
    return path == null || path.trim().isEmpty;
  }

  bool get _allRequiredFinalReqChosen {
    for (final kind in RspFinalRequirementDocKind.values) {
      if (_finalReqKindNeedsFile(kind) &&
          !_pickedFinalReqDocs.containsKey(kind)) {
        return false;
      }
    }
    return true;
  }

  bool get _canSubmitFinalRequirements {
    if (_finalRequirementsApproved) return false;
    if (_finalReqUploading) return false;
    return _allRequiredFinalReqChosen &&
        (_pickedFinalReqDocs.isNotEmpty || !_allFinalRequirementsUploaded);
  }

  void _applyFinalReqStored(
    RspFinalRequirementDocKind kind,
    String path,
    String name,
  ) {
    switch (kind) {
      case RspFinalRequirementDocKind.medicalCertificate:
        _docMedicalCertificatePath = path;
        _docMedicalCertificateName = name;
        _docMedicalCertificateRejectReason = null;
      case RspFinalRequirementDocKind.drugTestResult:
        _docDrugTestPath = path;
        _docDrugTestName = name;
        _docDrugTestRejectReason = null;
      case RspFinalRequirementDocKind.nbiClearance:
        _docNbiClearancePath = path;
        _docNbiClearanceName = name;
        _docNbiClearanceRejectReason = null;
    }
  }

  Future<void> _ensureApplicantUploadAccess(String appId) async {
    if (RecruitmentRepo.instance.hasApplicantAccessToken(appId)) return;
    final email = _emailForExamStatusLookup();
    if (email.isEmpty) return;
    await RecruitmentRepo.instance.getApplicationByEmail(email);
  }

  Future<void> _pickFinalReqDoc(RspFinalRequirementDocKind kind) async {
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
          const SnackBar(content: Text('Could not read that file.')),
        );
      }
      return;
    }
    if (!_isPdfFileName(f.name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only PDF files (.pdf) are accepted.')),
        );
      }
      return;
    }
    setState(() => _pickedFinalReqDocs[kind] = f);
  }

  void _removeFinalReqDoc(RspFinalRequirementDocKind kind) {
    setState(() => _pickedFinalReqDocs.remove(kind));
  }

  static String _finalReqKindLabel(RspFinalRequirementDocKind kind) {
    switch (kind) {
      case RspFinalRequirementDocKind.medicalCertificate:
        return 'Medical Certificate';
      case RspFinalRequirementDocKind.drugTestResult:
        return 'Drug Test Result';
      case RspFinalRequirementDocKind.nbiClearance:
        return 'NBI Clearance';
    }
  }

  Future<void> _uploadFinalRequirements() async {
    final appId = _applicationId;
    if (appId == null || appId.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Application is not loaded. Enter your email and tap Refresh status, then submit again.',
            ),
          ),
        );
      }
      return;
    }
    if (!_allRequiredFinalReqChosen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a PDF for each required document before submitting.',
          ),
        ),
      );
      return;
    }
    if (_pickedFinalReqDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one PDF to submit.')),
      );
      return;
    }
    setState(() => _finalReqUploading = true);
    try {
      await _ensureApplicantUploadAccess(appId);
      if (!RecruitmentRepo.instance.hasApplicantAccessToken(appId)) {
        throw Exception(
          'Could not verify this application. Tap Refresh status, then submit again.',
        );
      }
      final uploaded =
          <RspFinalRequirementDocKind, ({String path, String fileName})>{};
      for (final entry in _pickedFinalReqDocs.entries) {
        final f = entry.value;
        uploaded[entry.key] = await RecruitmentRepo.instance
            .uploadFinalRequirementDocument(appId, entry.key, f.bytes!, f.name);
      }
      await _syncInterviewFromEmail();
      if (!mounted) return;
      setState(() {
        for (final entry in uploaded.entries) {
          final stored = _finalReqStoredPath(entry.key);
          if (stored == null || stored.trim().isEmpty) {
            _applyFinalReqStored(
              entry.key,
              entry.value.path,
              entry.value.fileName,
            );
          }
        }
        _pickedFinalReqDocs.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Final requirements submitted. HR will review your documents.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed. ${userFacingApiError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _finalReqUploading = false);
    }
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

  static bool _isValidApplicantAge(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null) return false;
    return n >= 18 && n <= 100;
  }

  bool _isStep1AddressComplete() {
    final encoded = _addressFormKey.currentState?.composeEncoded() ?? '';
    final p = parseStoredAddress(encoded);
    return p.isStructured &&
        p.province.isNotEmpty &&
        p.city.isNotEmpty &&
        p.barangay.isNotEmpty &&
        p.street.isNotEmpty;
  }

  void _scheduleDuplicateApplicantCheck() {
    if (!_isVacancyApplication) return;
    _duplicateCheckDebounce?.cancel();
    _duplicateCheckDebounce = Timer(
      const Duration(milliseconds: 350),
      _checkDuplicateApplicantExists,
    );
  }

  Future<void> _checkDuplicateApplicantExists() async {
    if (!_isVacancyApplication) return;
    final first = _firstNameController.text.trim().toLowerCase();
    final middle = _middleNameController.text.trim().toLowerCase();
    final last = _lastNameController.text.trim().toLowerCase();
    final suffix = (_suffixValue ?? '').trim().toLowerCase();
    final email = _emailController.text.trim().toLowerCase();
    final pos = (widget.selectedPositionHeadline ?? '').trim().toLowerCase();

    if (first.isEmpty || last.isEmpty || !_isValidEmailFormat(email)) {
      if (mounted) {
        setState(() {
          _duplicateApplicantExists = false;
          _checkingDuplicateApplicant = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _checkingDuplicateApplicant = true);
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted) return;
      if (lookup == null) {
        setState(() {
          _duplicateApplicantExists = false;
          _checkingDuplicateApplicant = false;
        });
        return;
      }
      final existing = lookup.application;
      final existingFirst = (existing.firstName ?? '').trim().toLowerCase();
      final existingMiddle = (existing.middleName ?? '').trim().toLowerCase();
      final existingLast = (existing.lastName ?? '').trim().toLowerCase();
      final existingSuffix = (existing.suffix ?? '').trim().toLowerCase();
      final existingPos = (existing.positionAppliedFor ?? '')
          .trim()
          .toLowerCase();
      final sameIdentity =
          existingFirst == first &&
          existingMiddle == middle &&
          existingLast == last &&
          existingSuffix == suffix;
      final samePosition = existingPos == pos;

      setState(() {
        _duplicateApplicantExists = sameIdentity && samePosition;
        _checkingDuplicateApplicant = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _duplicateApplicantExists = false;
        _checkingDuplicateApplicant = false;
      });
    }
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
    if (_isVacancyApplication && !_privacyConsentAccepted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please agree to the Data Privacy Act notice and Terms and Conditions before submitting.',
          ),
        ),
      );
      return;
    }
    final first = _firstNameController.text.trim();
    final middle = _middleNameController.text.trim();
    final last = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final course = _courseController.text.trim();
    final age = _ageController.text.trim();
    final encodedAddress = _addressFormKey.currentState?.composeEncoded() ?? '';
    if (first.isEmpty ||
        last.isEmpty ||
        _sexValue == null ||
        course.isEmpty ||
        age.isEmpty ||
        _civilStatusValue == null ||
        !_isStep1AddressComplete() ||
        email.isEmpty ||
        phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete personal information (including course, age, civil status, and address), email, and phone number.',
          ),
        ),
      );
      return;
    }
    if (!_isValidApplicantAge(age)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid age (18–100).')),
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
    final pos = widget.selectedPositionHeadline?.trim();
    if (pos == null || pos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No vacant position is listed. Applications cannot be submitted until HR posts a job title.',
          ),
        ),
      );
      return;
    }
    final existingLookup = await RecruitmentRepo.instance.getApplicationByEmail(
      email,
    );
    if (!mounted) return;
    if (existingLookup != null) {
      final existing = existingLookup.application;
      final normalizedExistingFirst = (existing.firstName ?? '')
          .trim()
          .toLowerCase();
      final normalizedExistingMiddle = (existing.middleName ?? '')
          .trim()
          .toLowerCase();
      final normalizedExistingLast = (existing.lastName ?? '')
          .trim()
          .toLowerCase();
      final normalizedExistingSuffix = (existing.suffix ?? '')
          .trim()
          .toLowerCase();
      final normalizedExistingPos = (existing.positionAppliedFor ?? '')
          .trim()
          .toLowerCase();

      final normalizedFirst = first.toLowerCase();
      final normalizedMiddle = middle.toLowerCase();
      final normalizedLast = last.toLowerCase();
      final normalizedSuffix = (_suffixValue ?? '').trim().toLowerCase();
      final normalizedPos = pos.toLowerCase();

      final sameIdentity =
          normalizedExistingFirst == normalizedFirst &&
          normalizedExistingMiddle == normalizedMiddle &&
          normalizedExistingLast == normalizedLast &&
          normalizedExistingSuffix == normalizedSuffix;
      final samePosition = normalizedExistingPos == normalizedPos;

      if (sameIdentity && samePosition) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Application rejected: this applicant already submitted for this position. Please use Track Application instead of applying again.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An application already exists for this email. Please use Continue/Track Application instead of creating a new one.',
          ),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final created = await RecruitmentRepo.instance.insertApplication(
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
          course: course,
          address: encodedAddress,
          age: age,
          civilStatus: _civilStatusValue,
          email: email,
          phone: phone,
          resumeNotes: null,
          positionAppliedFor: pos,
          status: 'submitted',
        ),
        emailVerificationToken:
            (_serverRequiresEmailOtp == true && _step1EmailOtpVerified)
            ? _emailVerificationToken
            : null,
      );
      final id = created.id;
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
          _applicantNumber = created.applicantNumber;
          _applicationStatus = 'submitted';
          _step = 2;
          _continueEmailController.text = _emailController.text.trim();
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
      case 'bei':
        return 'BEI / Exam Questions';
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

  Future<void> _ensureExamTimeLimits() async {
    if (_examTimeLimitSeconds.isNotEmpty) return;
    try {
      _examTimeLimitSeconds = await RecruitmentRepo.instance
          .getExamTimeLimits();
    } catch (_) {
      _examTimeLimitSeconds = Map<String, int>.from(
        RecruitmentRepo.kDefaultRspExamTimeLimitSeconds,
      );
    }
  }

  Future<void> _startCountdownWhenReady(String examType) async {
    if (_activeAssessment != examType) return;
    await _ensureExamTimeLimits();
    if (!mounted || _activeAssessment != examType) return;
    if (_examCountdownTimer != null &&
        _examCountdownRemaining != null &&
        _examCountdownRemaining! > 0) {
      return;
    }
    _startExamCountdown(examType);
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
      case 'bei':
        unawaited(_submitBeiExam(dueToTimeLimit: true));
        return;
      case 'general':
        setState(() {
          _step = 5;
          _leaveAssessmentToHub();
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadMathQuestions(),
        );
        return;
      case 'math':
        setState(() {
          _step = 6;
          _leaveAssessmentToHub();
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadGeneralInfoQuestions(),
        );
        return;
      case 'general_info':
        unawaited(_submitGeneralInfoExam(dueToTimeLimit: true));
        return;
    }
  }

  void _leaveAssessmentToHub() {
    _activeAssessment = null;
    _examQuestionIndex = 0;
    _examReviewing = false;
  }

  void _startAssessment(String id) {
    setState(() {
      _activeAssessment = id;
      _examQuestionIndex = 0;
      _examReviewing = false;
      switch (id) {
        case 'bei':
          _step = 3;
        case 'general':
          _step = 4;
        case 'math':
          _step = 5;
        case 'general_info':
          _step = 6;
      }
    });
    switch (id) {
      case 'bei':
        unawaited(_loadBeiQuestions());
      case 'general':
        unawaited(_loadGeneralQuestions());
      case 'math':
        unawaited(_loadMathQuestions());
      case 'general_info':
        unawaited(_loadGeneralInfoQuestions());
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

  // ignore: unused_element
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

  Widget _buildPagedMcq({
    required String title,
    required List<Map<String, dynamic>> questions,
    required List<int> selected,
    required bool useLetterPrefix,
    required VoidCallback onSubmit,
  }) {
    final total = questions.length;
    if (_examQuestionIndex >= total) _examQuestionIndex = total - 1;
    if (_examQuestionIndex < 0) _examQuestionIndex = 0;
    final i = _examQuestionIndex;
    final q = questions[i];
    final options = q['options'] as List<dynamic>? ?? [];
    final timer = _examCountdownRemaining;
    final answered = _mcqAnsweredCount(selected);

    if (_examReviewing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantExamSessionHeader(
            title: title,
            questionIndex: total,
            total: total,
            timeLabel: timer != null && timer > 0 ? _formatMmSs(timer) : null,
            urgent: timer != null && timer <= 60,
          ),
          _buildExamTimerBanner(),
          const SizedBox(height: 16),
          Text(
            'Review answers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text('Answered $answered of $total. Unanswered ${total - answered}.'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() => _examReviewing = false),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Return to questions'),
          ),
          const SizedBox(height: 10),
          RspApplicantSubmitButton(
            label: 'Submit $title',
            enabled: !_examSubmitting,
            onPressed: _examSubmitting
                ? null
                : () async {
                    final ok = await showRspApplicantExamSubmitDialog(
                      context: context,
                      examTitle: title,
                      answered: answered,
                      total: total,
                    );
                    if (ok) onSubmit();
                  },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantExamSessionHeader(
          title: title,
          questionIndex: i + 1,
          total: total,
          timeLabel: timer != null && timer > 0 ? _formatMmSs(timer) : null,
          urgent: timer != null && timer <= 60,
        ),
        _buildExamTimerBanner(),
        const SizedBox(height: 16),
        RspApplicantMcqQuestionCard(
          index: i,
          questionText: q['question_text']?.toString() ?? '',
          options: options,
          selectedIndex: i < selected.length ? selected[i] : -1,
          useLetterPrefix: useLetterPrefix,
          onSelect: (j) => setState(() => selected[i] = j),
        ),
        const SizedBox(height: 16),
        RspApplicantExamPagerNav(
          canGoBack: i > 0,
          isLast: i >= total - 1,
          onBack: () => setState(() => _examQuestionIndex = i - 1),
          onForward: () {
            if (i >= total - 1) {
              setState(() => _examReviewing = true);
            } else {
              setState(() => _examQuestionIndex = i + 1);
            }
          },
        ),
      ],
    );
  }

  Future<void> _submitBeiExam({bool dueToTimeLimit = false}) async {
    if (_beiQuestionsLoaded == null || _beiControllers.isEmpty) return;
    final answers = _beiControllers.map((c) => c.text.trim()).toList();
    final allFilled = answers.every((a) => a.isNotEmpty);
    if (!dueToTimeLimit && !allFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide an answer for each question.'),
        ),
      );
      return;
    }
    _cancelExamCountdown();
    _beiAnswersForSubmit = answers;
    await _ensureExamTimeLimits();
    if (!mounted) return;
    setState(() {
      _step = 4;
      _leaveAssessmentToHub();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadGeneralQuestions(),
    );
  }

  List<String>? _beiAnswersForSubmit;

  List<Map<String, dynamic>>? _generalQuestionsLoaded;
  List<int> _generalSelected = [];
  bool _generalLoading = false;

  Future<void> _loadGeneralQuestions() async {
    if (_generalLoading) return;
    if (_generalQuestionsLoaded != null) {
      unawaited(_startCountdownWhenReady('general'));
      return;
    }
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
            unawaited(_startCountdownWhenReady('general'));
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
    setState(() {
      _step = 5;
      _leaveAssessmentToHub();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMathQuestions());
  }

  List<Map<String, dynamic>>? _mathQuestionsLoaded;
  List<int> _mathSelected = [];
  bool _mathLoading = false;
  List<Map<String, dynamic>>? _generalInfoQuestionsLoaded;
  List<int> _generalInfoSelected = [];
  bool _generalInfoLoading = false;

  Future<void> _loadMathQuestions() async {
    if (_mathLoading) return;
    if (_mathQuestionsLoaded != null) {
      unawaited(_startCountdownWhenReady('math'));
      return;
    }
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
            unawaited(_startCountdownWhenReady('math'));
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
    if (_generalInfoLoading) return;
    if (_generalInfoQuestionsLoaded != null) {
      unawaited(_startCountdownWhenReady('general_info'));
      return;
    }
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
            unawaited(_startCountdownWhenReady('general_info'));
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
    setState(() {
      _step = 6;
      _leaveAssessmentToHub();
    });
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
        _leaveAssessmentToHub();
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
        setState(() => _syncPipelineFromApp(app));
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
      if (app.finalInterviewPassed == true) return 8;
      return 7;
    }

    if (app.status == 'document_approved') return 3;
    if (app.status == 'failed') return 7;
    if (app.status == 'passed') {
      if (app.finalInterviewPassed == true) return 8;
      return 7;
    }
    if (app.status == 'registered') return 8;

    return 2;
  }

  /// Track-only entry: stay on Step 1 while documents are under review; declined docs open Step 2 to resubmit.
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
      if (app.finalInterviewPassed == true) return 8;
      return 7;
    }
    if (app.status == 'document_declined') return 2;
    if (app.status == 'document_approved' || app.status == 'exam_taken') {
      return 3;
    }
    if (app.status == 'passed') {
      if (app.finalInterviewPassed == true) return 8;
      return 7;
    }
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
      return 'Your documents were not approved. Continue to replace them and resubmit for HR review.';
    }
    return 'You cannot proceed at this time. Check your status above.';
  }

  String _trackingOnlyContinueStayMessage(String status) {
    switch (status) {
      case 'submitted':
        return 'HR is still reviewing your documents. You can start the screening exams only after approval. Check back here for updates.';
      case 'document_declined':
        return 'Your documents were not approved. Continue to replace them and resubmit for HR review.';
      default:
        return 'You can continue to forms and exams when HR approves your documents.';
    }
  }

  Future<void> _continueApplication() async {
    if (_continueEmailController.text.trim().isEmpty &&
        _emailController.text.trim().isNotEmpty) {
      _continueEmailController.text = _emailController.text.trim();
    }
    final email = _continueEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email to continue.')),
      );
      return;
    }
    final resumingFromTrack = (widget.resumeEmail ?? '').trim().isNotEmpty;
    if (!_isVacancyApplication && !resumingFromTrack) {
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
        _syncPipelineFromApp(app);
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
      return 'Track Application Status';
    }
    final pos = _displayPositionTitle();
    if (pos != null && pos.isNotEmpty) {
      return 'Apply for $pos';
    }
    return 'Recruitment Application';
  }

  String? _appBarSubtitle() {
    if (!_isVacancyApplication && _step == 1) {
      return 'Look up your application by email';
    }
    if (_showJourneyTracker) {
      return 'Current stage: ${_journeyStage.label}';
    }
    if (_isVacancyApplication && !_privacyConsentAccepted) {
      return 'Municipality of Plaridel · Human Resource';
    }
    return 'Municipality of Plaridel · Human Resource';
  }

  ApplicantJourneyStage get _journeyStage => journeyStageForStep(_step);

  Map<ApplicantJourneyStage, ApplicantJourneyTone> get _journeyTones {
    final current = _journeyStage;
    return {
      for (final stage in ApplicantJourneyStage.values)
        stage: journeyToneForStage(
          stage: stage,
          current: current,
          applicationStatus: _applicationStatus,
          examPassed: _examPassed,
          examBeiGradingPending: _examBeiGradingPending,
          finalInterviewPassed: _finalInterviewPassed,
        ),
    };
  }

  bool get _showJourneyTracker {
    if (_isVacancyApplication) {
      return _privacyConsentAccepted || _step != 1;
    }
    return _step != 1;
  }

  Widget _buildJourneyHeaderMeta() {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    if (!wide) return const SizedBox.shrink();
    final id = (_applicantNumber ?? '').trim();
    if (id.isEmpty && _step <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (id.isNotEmpty)
            Expanded(
              child: Text(
                'Applicant ID: $id',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ),
          Text(
            'Current stage: ${_journeyStage.label}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStage() {
    if (_step == 1) return _buildStep1BasicInfo();
    if (_step == 2) return _buildStep2PendingReview();
    if (_step >= 3 && _step <= 6) {
      if (_activeAssessment == null) return _buildAssessmentHub();
      switch (_activeAssessment) {
        case 'bei':
          return _buildStep3BeiExam();
        case 'general':
          return _buildStep4GeneralExam();
        case 'math':
          return _buildStep5MathExam();
        case 'general_info':
          return _buildStep6GeneralInfoExam();
      }
    }
    if (_step == 7) return _buildStep7Result();
    if (_step == 8) return _buildStep8FinalHiring();
    return const SizedBox.shrink();
  }

  Widget _buildAssessmentHub() {
    return RspApplicantAssessmentHub(
      items: [
        RspAssessmentItem(
          id: 'bei',
          title: 'Behavioral Event Interview',
          detail: '8 written questions',
          status: _step > 3
              ? RspAssessmentItemStatus.waitingForEvaluation
              : RspAssessmentItemStatus.ready,
        ),
        RspAssessmentItem(
          id: 'general',
          title: 'General Exam',
          detail: 'Multiple choice',
          status: _step > 4
              ? RspAssessmentItemStatus.completed
              : (_step == 4
                    ? RspAssessmentItemStatus.ready
                    : RspAssessmentItemStatus.locked),
        ),
        RspAssessmentItem(
          id: 'math',
          title: 'Mathematics Exam',
          detail: 'Multiple choice',
          status: _step > 5
              ? RspAssessmentItemStatus.completed
              : (_step == 5
                    ? RspAssessmentItemStatus.ready
                    : RspAssessmentItemStatus.locked),
        ),
        RspAssessmentItem(
          id: 'general_info',
          title: 'General Information Exam',
          detail: 'Multiple choice',
          status: _step == 6
              ? RspAssessmentItemStatus.ready
              : RspAssessmentItemStatus.locked,
        ),
      ],
      onStart: _startAssessment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: RspApplicantAppBar(
        title: _appBarTitle(),
        subtitle: _appBarSubtitle(),
        icon: (!_isVacancyApplication && _step == 1)
            ? Icons.manage_search_rounded
            : Icons.assignment_rounded,
        actions: [
          if (_step == 1 && _step1StatusApp != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              tooltip: 'Refresh status preview',
              onPressed: _step1StatusLoading ? null : _silentRefreshStep1Status,
            ),
          if (_step == 7)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _hiringStatusRefreshing
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Refresh status',
                      onPressed: _refreshHiringStatus,
                    ),
            ),
        ],
      ),
      body: LoginStyleGridBackdrop(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 20, wide ? 28 : 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showJourneyTracker) ...[
                    _buildJourneyHeaderMeta(),
                    RspApplicantJourneyTracker(
                      current: _journeyStage,
                      tones: _journeyTones,
                    ),
                    const SizedBox(height: 24),
                  ],
                  _buildActiveStage(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1BasicInfo() {
    if (!_isVacancyApplication) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _buildTrackApplicationLookup(),
        ),
      );
    }

    if (!_privacyConsentAccepted) {
      return _buildDataPrivacyConsent();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasLocalDraft)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
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

  Widget _buildTrackApplicationLookup() {
    Widget tipTile({
      required IconData icon,
      required String title,
      required String body,
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primaryNavy),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.textSecondary.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      );
    }

    Widget stepChip(String number, String label) {
      return Expanded(
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final wideTips = MediaQuery.sizeOf(context).width >= 560;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.lightGray.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.1),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              kIsWeb ? 26 : 20,
              kIsWeb ? 24 : 20,
              kIsWeb ? 26 : 20,
              20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFBF360C),
                  Color(0xFFE85D04),
                  Color(0xFFFF8A1F),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.manage_search_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Track Application Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Look up your record with the email you used when you applied.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      stepChip('1', 'Enter email'),
                      stepChip('2', 'Check status'),
                      stepChip('3', 'Continue'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              kIsWeb ? 24 : 18,
              20,
              kIsWeb ? 24 : 18,
              kIsWeb ? 24 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wideTips)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: tipTile(
                          icon: Icons.work_outline_rounded,
                          title: 'New applicant?',
                          body:
                              'Go to Job Vacancies on the home page and tap Apply now.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: tipTile(
                          icon: Icons.mail_outline_rounded,
                          title: 'Already applied?',
                          body:
                              'Use the same email, tap Check status, then Continue when eligible.',
                        ),
                      ),
                    ],
                  )
                else ...[
                  tipTile(
                    icon: Icons.work_outline_rounded,
                    title: 'New applicant?',
                    body:
                        'Go to Job Vacancies on the home page and tap Apply now.',
                  ),
                  const SizedBox(height: 10),
                  tipTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Already applied?',
                    body:
                        'Use the same email, tap Check status, then Continue when eligible.',
                  ),
                ],
                const SizedBox(height: 18),
                _buildContinueEmailRow(),
                _buildStep1StatusPreviewSection(),
              ],
            ),
          ),
        ],
      ),
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

  static final _trackEmailReady = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _isCheckStatusEmailReady {
    final email = _continueEmailController.text.trim();
    return _trackEmailReady.hasMatch(email);
  }

  bool get _isCheckStatusActionEnabled {
    if (_step1StatusLoading || _continueLoading) return false;
    return _isCheckStatusEmailReady;
  }

  bool get _isContinueEmailRowActionEnabled {
    if (_continueLoading || _step1StatusLoading) return false;
    if (!_isCheckStatusEmailReady) return false;
    final app = _step1StatusApp;
    if (app == null) return false;
    return _canProceedTrackingContinue(app, _step1StatusExam);
  }

  Widget _buildContinueEmailRow() {
    final navy = AppTheme.primaryNavy;
    final canContinue = _isContinueEmailRowActionEnabled;
    final continueBtn = FilledButton.icon(
      onPressed: canContinue ? _continueApplication : null,
      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
      label: _continueLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _step1StatusApp?.status == 'document_declined'
                  ? 'Replace documents'
                  : 'Continue',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
      style: FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        disabledBackgroundColor: AppTheme.lightGray.withValues(alpha: 0.85),
        disabledForegroundColor: AppTheme.textSecondary.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final checkBtn = FilledButton.icon(
      onPressed: _isCheckStatusActionEnabled ? _checkStep1StatusOnly : null,
      icon: _step1StatusLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.search_rounded, size: 20),
      label: Text(
        _step1StatusLoading ? 'Checking…' : 'Check status',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.lightGray.withValues(alpha: 0.85),
        disabledForegroundColor: AppTheme.textSecondary.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final emailField = TextField(
      controller: _continueEmailController,
      decoration: _trackEmailDecoration('Email to continue'),
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        if (_isCheckStatusActionEnabled) _checkStep1StatusOnly();
      },
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
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Application email',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          emailField,
          const SizedBox(height: 14),
          if (narrowActions) ...[
            checkBtn,
            const SizedBox(height: 10),
            continueBtn,
          ] else
            Row(
              children: [
                Expanded(child: checkBtn),
                const SizedBox(width: 10),
                Expanded(child: continueBtn),
              ],
            ),
          if (showCheckStatusFirstHint) ...[
            const SizedBox(height: 14),
            hintBox(
              'Tap Check status first. Continue unlocks when your status allows it.',
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
              ? 'Tap Continue to resume your application.'
              : 'Tap Check status first. Continue unlocks when you are eligible.',
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

  Widget _step1ResponsivePair(Widget a, Widget b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 768) {
            return Column(children: [a, const SizedBox(height: 14), b]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 14),
              Expanded(child: b),
            ],
          );
        },
      ),
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

  Widget _step1GuidelineNote({
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primaryNavy.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: AppTheme.primaryNavy.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppTheme.textSecondary.withValues(alpha: 0.95),
                ),
              ),
            ),
          ],
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

  Widget _buildDataPrivacyConsent() {
    final body = Column(
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
                    'BEFORE YOU APPLY',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.85,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Data Privacy & Terms',
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
          'Please read and accept the Data Privacy Act notice and Terms and Conditions before filling out the application form.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 15 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '1. Data Privacy Act Notice',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Republic Act No. 10173 (Data Privacy Act of 2012)',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The Municipality of Plaridel, through the Human Resource Management Office, '
          'will collect and process the personal information you provide in this application '
          '(including your name, contact details, address, education, and uploaded documents) '
          'to evaluate your application and carry out related recruitment activities.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 14.5 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your data will be used only for recruitment, screening, and hiring. It will be '
          'stored securely and accessed only by authorized HR personnel. Records may be '
          'retained as required for government recruitment and audit purposes.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 14.5 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'You may request access to, correction of, or withdrawal of your personal data '
          'by contacting the HRMO, subject to applicable laws and any ongoing recruitment process.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 14.5 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '2. Terms and Conditions',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'By applying through this HRMS, you agree that:',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 14.5 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '• All information and documents you submit are true, complete, and authentic.\n'
          '• Providing false, misleading, or falsified documents may result in '
          'disqualification or withdrawal of any offer.\n'
          '• Submitting an application does not guarantee examination, interview, or employment.\n'
          '• The Municipality of Plaridel / HRMO may contact you using the details you provided.\n'
          '• You will follow the official recruitment process, including document review, '
          'examinations, and interviews as required for the position.\n'
          '• Application records may be used for recruitment evaluation and official HR documentation.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 14.5 : 14,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () =>
              setState(() => _privacyConsentChecked = !_privacyConsentChecked),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _privacyConsentChecked,
                  activeColor: AppTheme.primaryNavy,
                  onChanged: (v) =>
                      setState(() => _privacyConsentChecked = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'I have read and agree to the Data Privacy Act notice (RA 10173) '
                      'and the Terms and Conditions of this job application.',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _privacyConsentChecked
                ? () => setState(() => _privacyConsentAccepted = true)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.lightGray,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'I agree and continue',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ],
    );

    if (kIsWeb) {
      return _buildDataPrivacyConsentWeb();
    }
    return body;
  }

  Widget _buildDataPrivacyConsentWeb() {
    Widget sectionCard({
      required String number,
      required String title,
      required String kicker,
      required List<Widget> children,
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightGray.withValues(alpha: 0.9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (kicker.isNotEmpty)
                        Text(
                          kicker,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
    }

    Widget termRow(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    const noticeStyle = TextStyle(
      fontSize: 14.5,
      height: 1.5,
      color: AppTheme.textSecondary,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.lightGray.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFBF360C),
                      Color(0xFFE85D04),
                      Color(0xFFFF8A1F),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Icon(
                            Icons.privacy_tip_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BEFORE YOU APPLY',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Data Privacy & Terms',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Please read and accept the Data Privacy Act notice and Terms and Conditions before filling out the application form.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionCard(
                      number: '1',
                      title: 'Data Privacy Act Notice',
                      kicker:
                          'Republic Act No. 10173 (Data Privacy Act of 2012)',
                      children: const [
                        Text(
                          'The Municipality of Plaridel, through the Human Resource Management Office, '
                          'will collect and process the personal information you provide in this application '
                          '(including your name, contact details, address, education, and uploaded documents) '
                          'to evaluate your application and carry out related recruitment activities.',
                          style: noticeStyle,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Your data will be used only for recruitment, screening, and hiring. It will be '
                          'stored securely and accessed only by authorized HR personnel. Records may be '
                          'retained as required for government recruitment and audit purposes.',
                          style: noticeStyle,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'You may request access to, correction of, or withdrawal of your personal data '
                          'by contacting the HRMO, subject to applicable laws and any ongoing recruitment process.',
                          style: noticeStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      number: '2',
                      title: 'Terms and Conditions',
                      kicker: 'By applying through this HRMS, you agree that:',
                      children: [
                        termRow(
                          'All information and documents you submit are true, complete, and authentic.',
                        ),
                        termRow(
                          'Providing false, misleading, or falsified documents may result in disqualification or withdrawal of any offer.',
                        ),
                        termRow(
                          'Submitting an application does not guarantee examination, interview, or employment.',
                        ),
                        termRow(
                          'The Municipality of Plaridel / HRMO may contact you using the details you provided.',
                        ),
                        termRow(
                          'You will follow the official recruitment process, including document review, examinations, and interviews as required for the position.',
                        ),
                        termRow(
                          'Application records may be used for recruitment evaluation and official HR documentation.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Material(
                      color: _privacyConsentChecked
                          ? AppTheme.primaryNavy.withValues(alpha: 0.07)
                          : const Color(0xFFFFF8F2),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => setState(
                          () =>
                              _privacyConsentChecked = !_privacyConsentChecked,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primaryNavy.withValues(
                                alpha: _privacyConsentChecked ? 0.35 : 0.18,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: _privacyConsentChecked,
                                activeColor: AppTheme.primaryNavy,
                                onChanged: (v) => setState(
                                  () => _privacyConsentChecked = v ?? false,
                                ),
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                    'I have read and agree to the Data Privacy Act notice (RA 10173) '
                                    'and the Terms and Conditions of this job application.',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14,
                                      height: 1.45,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _privacyConsentChecked
                            ? () =>
                                  setState(() => _privacyConsentAccepted = true)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.lightGray
                              .withValues(alpha: 0.85),
                          disabledForegroundColor: AppTheme.textSecondary
                              .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'I agree and continue',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                    'APPLICATION',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.85,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Personal information and documents',
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
          'Fill in your details and upload the required documents.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: kIsWeb ? 15 : 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        _step1FormSectionHeader(
          'Personal information',
          subtitle: 'Use your legal name.',
        ),
        const SizedBox(height: 14),
        _step1ResponsivePair(
          TextField(
            controller: _firstNameController,
            decoration: _step1FieldDecoration(
              'First Name',
              requiredMark: true,
              hintText: 'First name',
              prefixIcon: Icons.person_outline_rounded,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          TextField(
            controller: _middleNameController,
            decoration: _step1FieldDecoration(
              'Middle Name',
              hintText: 'Middle name (optional)',
              prefixIcon: Icons.person_outline_rounded,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        _step1ResponsivePair(
          TextField(
            controller: _lastNameController,
            decoration: _step1FieldDecoration(
              'Last Name',
              requiredMark: true,
              hintText: 'Last name',
              prefixIcon: Icons.person_outline_rounded,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          DropdownButtonFormField<String>(
            initialValue: _suffixValue,
            items: _suffixOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) {
              setState(() => _suffixValue = v);
              _scheduleDuplicateApplicantCheck();
            },
            decoration: _step1FieldDecoration(
              'Suffix',
              hintText: 'Select suffix (optional)',
              prefixIcon: Icons.text_fields_rounded,
            ),
            isExpanded: true,
          ),
        ),
        _step1ResponsivePair(
          DropdownButtonFormField<String>(
            key: ValueKey('sex_$_sexValue'),
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
          DropdownButtonFormField<String>(
            key: ValueKey('civil_$_civilStatusValue'),
            initialValue: _civilStatusValue,
            items: _civilStatusOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) {
              setState(() => _civilStatusValue = v);
              _scheduleDraftSave();
            },
            decoration: _step1FieldDecoration(
              'Civil status',
              requiredMark: true,
              hintText: 'Select civil status',
              prefixIcon: Icons.family_restroom_outlined,
            ),
            isExpanded: true,
          ),
        ),
        _step1ResponsivePair(
          TextField(
            controller: _courseController,
            decoration: _step1FieldDecoration(
              'Course',
              requiredMark: true,
              hintText: 'e.g. BS Public Administration',
              prefixIcon: Icons.school_outlined,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          TextField(
            controller: _ageController,
            decoration: _step1FieldDecoration(
              'Age',
              requiredMark: true,
              hintText: 'Your age in years',
              prefixIcon: Icons.cake_outlined,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        _step1FormSectionHeader('Address'),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: LayoutBuilder(
            builder: (context, c) {
              return StructuredAddressForm(
                key: _addressFormKey,
                streetController: _streetController,
                initialRawAddress: null,
                inputDecoration: _step1FieldDecoration,
                twoColumn: c.maxWidth >= 768,
              );
            },
          ),
        ),
        _step1FormSectionHeader(
          'Contact details',
          subtitle: 'Email and phone are required.',
        ),
        const SizedBox(height: 14),
        _step1ResponsivePair(
          TextField(
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
          TextField(
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
        _buildStep1EmailOtpSection(),
        _step1GuidelineNote(
          icon: Icons.contact_mail_outlined,
          text: 'Use a real email and phone number that you check regularly.',
        ),
        const SizedBox(height: 18),
        _step1FormSectionHeader(
          'Required documents',
          subtitle: 'All four documents are required.',
        ),
        const SizedBox(height: 12),
        _step1GuidelineNote(
          icon: Icons.picture_as_pdf_outlined,
          text: 'Upload PDF files only.',
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, c) {
            final cards = RspApplicationDocKind.values.map((kind) {
              final f = _pickedDocs[kind];
              return RspApplicantDocumentUploadCard(
                title: _docKindLabel(kind),
                status: f == null
                    ? RspApplicantDocCardStatus.notUploaded
                    : RspApplicantDocCardStatus.uploaded,
                fileName: f?.name,
                onChoose: _submitting ? null : () => _pickDoc(kind),
                onRemove: _submitting ? null : () => _removeDoc(kind),
                busy: _submitting,
              );
            }).toList();
            if (c.maxWidth < 768) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    cards[i],
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (_duplicateApplicantExists)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'You already submitted an application for this position. Use Track/Continue Application instead.',
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                (_submitting ||
                    _checkingDuplicateApplicant ||
                    _duplicateApplicantExists)
                ? null
                : _submitStep1,
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
                      Text('Submit Application'),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  String _sessionEmail() {
    final a = _emailController.text.trim();
    if (a.isNotEmpty) return a;
    return _continueEmailController.text.trim();
  }

  bool get _hasSessionEmail => _sessionEmail().isNotEmpty;

  Future<void> _refreshDocumentReview() async {
    final email = _sessionEmail();
    if (email.isEmpty) return;
    setState(() => _continueLoading = true);
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(
        email,
      );
      if (!mounted || lookup == null) return;
      setState(() {
        _applicationStatus = lookup.application.status;
        _applicantNumber =
            lookup.application.applicantNumber ?? _applicantNumber;
        _applicationId = lookup.application.id;
        _syncPipelineFromApp(lookup.application);
      });
    } finally {
      if (mounted) setState(() => _continueLoading = false);
    }
  }

  bool get _hasAllDeclinedDocsReplaced {
    for (final kind in RspApplicationDocKind.values) {
      final f = _pickedDocs[kind];
      if (f == null || f.bytes == null || f.name.isEmpty) return false;
    }
    return true;
  }

  Future<void> _resubmitDeclinedDocuments() async {
    final id = _applicationId;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not find this application. Check status with your email, then try again.',
          ),
        ),
      );
      return;
    }
    if (!_hasAllDeclinedDocsReplaced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Replace all four documents with new PDF files before resubmitting.',
          ),
        ),
      );
      return;
    }
    setState(() => _resubmittingDocs = true);
    try {
      if (!RecruitmentRepo.instance.hasApplicantAccessToken(id)) {
        final email = _sessionEmail();
        if (email.isNotEmpty) {
          await RecruitmentRepo.instance.getApplicationByEmail(email);
        }
      }
      for (final kind in RspApplicationDocKind.values) {
        final f = _pickedDocs[kind]!;
        await RecruitmentRepo.instance.uploadTypedDocument(
          id,
          kind,
          f.bytes!,
          f.name,
        );
      }
      await RecruitmentRepo.instance.resubmitDeclinedDocuments(id);
      if (!mounted) return;
      setState(() {
        for (final kind in RspApplicationDocKind.values) {
          _step1DocNames[kind] = _pickedDocs[kind]!.name;
        }
        _pickedDocs.clear();
        _applicationStatus = 'submitted';
        _resubmittingDocs = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Documents resubmitted. HR will review them again.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _resubmittingDocs = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
      }
    }
  }

  Widget _buildStep2PendingReview() {
    final isDeclined = _applicationStatus == 'document_declined';
    final approved = _applicationStatus == 'document_approved';
    final applicantId = (_applicantNumber ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Document Review',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (applicantId.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE85D04).withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFFE85D04),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Applicant ID',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        applicantId,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Color(0xFFE85D04),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Keep this ID. HR can use it to search and verify your application details.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (approved) ...[
          RspApplicantStatusBadge(kind: RspApplicantBadgeKind.approved),
          const SizedBox(height: 12),
          const Text(
            'Your application has been approved. You can proceed to Assessment.',
          ),
          const SizedBox(height: 16),
          if (!_hasSessionEmail)
            TextField(
              controller: _continueEmailController,
              decoration: _dec('Email used on your application'),
              keyboardType: TextInputType.emailAddress,
            ),
          if (!_hasSessionEmail) const SizedBox(height: 12),
          RspApplicantNextActionCard(
            title: 'Assessment',
            body:
                'Complete the Behavioral Event Interview and screening exams.',
            actionLabel: 'Proceed to Assessment',
            onPressed: _continueApplication,
            busy: _continueLoading,
            busyLabel: 'Opening assessment…',
          ),
        ] else if (isDeclined) ...[
          RspApplicantWaitingState(
            title: 'Documents not approved',
            body:
                'HR did not approve your documents. Replace each PDF below with a new file, then resubmit for review.',
            icon: Icons.upload_file_rounded,
            onRefresh: _refreshDocumentReview,
            refreshBusy: _continueLoading,
          ),
        ] else ...[
          RspApplicantWaitingState(
            title: 'Waiting for HR review',
            body:
                'Your application has been submitted. HR is reviewing your documents. No action is required right now.',
            onRefresh: _refreshDocumentReview,
            refreshBusy: _continueLoading,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          isDeclined ? 'Replace rejected documents' : 'Submitted documents',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        ...RspApplicationDocKind.values.map((kind) {
          final picked = _pickedDocs[kind];
          final fileName = picked?.name ?? _step1DocNames[kind];
          final replaced = picked != null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RspApplicantDocumentUploadCard(
              title: _docKindLabel(kind),
              fileName: fileName,
              status: isDeclined
                  ? (replaced
                        ? RspApplicantDocCardStatus.uploaded
                        : RspApplicantDocCardStatus.rejected)
                  : (approved
                        ? RspApplicantDocCardStatus.approved
                        : RspApplicantDocCardStatus.submitted),
              rejectReason: isDeclined && !replaced
                  ? 'Replace this PDF with a new file.'
                  : null,
              readOnly: !isDeclined,
              busy: _resubmittingDocs,
              onChoose: isDeclined && !_resubmittingDocs
                  ? () => _pickDoc(kind)
                  : null,
            ),
          );
        }),
        if (isDeclined) ...[
          const SizedBox(height: 8),
          RspApplicantNextActionCard(
            title: 'Resubmit for HR review',
            body: _hasAllDeclinedDocsReplaced
                ? 'All four documents have new PDFs. Send them to HR for another review.'
                : 'Replace all four documents above, then tap Resubmit.',
            actionLabel: 'Resubmit documents',
            onPressed: _resubmitDeclinedDocuments,
            enabled: _hasAllDeclinedDocsReplaced,
            busy: _resubmittingDocs,
            busyLabel: 'Uploading…',
          ),
        ],
      ],
    );
  }

  Widget _buildStep3BeiExam() {
    const stepTitle = '8 Behavioral Event Interview (BEI)';
    final timeNote = _mcqInstructionTimeNote('bei');
    final stepSubtitle =
        'For new applicants and promotions. Answer each question in the space provided.$timeNote';

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
    final total = questions.length;
    if (_examQuestionIndex >= total) _examQuestionIndex = total - 1;
    if (_examQuestionIndex < 0) _examQuestionIndex = 0;
    final i = _examQuestionIndex;
    final timer = _examCountdownRemaining;
    final answered = _beiAnsweredCount();
    if (_examReviewing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RspApplicantExamSessionHeader(
            title: 'Behavioral Event Interview',
            questionIndex: total,
            total: total,
            timeLabel: timer != null && timer > 0 ? _formatMmSs(timer) : null,
          ),
          const SizedBox(height: 16),
          Text('Answered $answered of $total.'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _examReviewing = false),
            child: const Text('Return to questions'),
          ),
          const SizedBox(height: 10),
          RspApplicantSubmitButton(
            label: 'Submit Behavioral Event Interview',
            onPressed: () async {
              final ok = await showRspApplicantExamSubmitDialog(
                context: context,
                examTitle: 'Behavioral Event Interview',
                answered: answered,
                total: total,
              );
              if (ok) await _submitBeiExam();
            },
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspApplicantExamSessionHeader(
          title: 'Behavioral Event Interview',
          questionIndex: i + 1,
          total: total,
          timeLabel: timer != null && timer > 0 ? _formatMmSs(timer) : null,
        ),
        const SizedBox(height: 16),
        RspApplicantBeiQuestionCard(
          index: i,
          question: questions[i],
          controller: _beiControllers[i],
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        RspApplicantExamPagerNav(
          canGoBack: i > 0,
          isLast: i >= total - 1,
          onBack: () => setState(() => _examQuestionIndex = i - 1),
          onForward: () {
            if (i >= total - 1) {
              setState(() => _examReviewing = true);
            } else {
              setState(() => _examQuestionIndex = i + 1);
            }
          },
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
    return _buildPagedMcq(
      title: 'General Exam',
      questions: questions,
      selected: _generalSelected,
      useLetterPrefix: false,
      onSubmit: _submitGeneralExam,
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
    return _buildPagedMcq(
      title: 'Mathematics Exam',
      questions: questions,
      selected: _mathSelected,
      useLetterPrefix: true,
      onSubmit: _submitMathExam,
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
    return _buildPagedMcq(
      title: 'General Information Exam',
      questions: questions,
      selected: _generalInfoSelected,
      useLetterPrefix: true,
      onSubmit: () => unawaited(_submitGeneralInfoExam()),
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
        Text(
          'Deliberation',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        _buildDeliberationTimeline(phase: 1),
        const SizedBox(height: 16),
        RspApplicantWaitingState(
          title: 'Waiting for BEI evaluation',
          body:
              'Your assessments are complete. HR is reviewing your Behavioral Event Interview responses. No action is required.',
          onRefresh: _refreshHiringStatus,
          refreshBusy: _hiringStatusRefreshing,
        ),
      ],
    );
  }

  Widget _buildDeliberationTimeline({required int phase}) {
    Widget row(String label, bool done, bool active) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : (active
                        ? Icons.radio_button_checked_rounded
                        : Icons.circle_outlined),
              size: 18,
              color: done
                  ? const Color(0xFF2E7D32)
                  : (active ? AppTheme.primaryNavy : const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Assessment completed', phase >= 1, phase == 0),
        row('HR evaluation', phase >= 2, phase == 1),
        row('Final decision', phase >= 3, phase == 2),
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
        Text(
          'Deliberation',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        _buildDeliberationTimeline(
          phase: examOk && _finalInterviewPassed == true ? 3 : (examOk ? 2 : 1),
        ),
        const SizedBox(height: 16),
        RspApplicantExamResultHero(passed: examOk),
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
                        'Deliberation: Passed',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.green.shade900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'HR has recorded that you passed deliberation.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade900.withValues(alpha: 0.92),
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _step7Bullet(
                        'Continue to Final Hiring to upload your medical certificate, drug test result, and NBI clearance.',
                        bulletColor: Colors.green.shade700,
                      ),
                      _step7Bullet(
                        'After HR approves your documents, they will schedule your orientation.',
                        bulletColor: Colors.green.shade700,
                      ),
                      _step7Bullet(
                        'Employee accounts are created by HR only—sign in on Step 8 when HR marks your account ready.',
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
                    'HR has recorded your deliberation result. If you have questions, please contact the HR office.',
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
                        'Deliberation scheduled',
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
        if (_examPassed && _finalInterviewPassed == true)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await _syncInterviewFromEmail();
                if (!mounted) return;
                if (_finalInterviewPassed != true) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'You can continue to Final Hiring only after HR records that you passed deliberation.',
                      ),
                    ),
                  );
                  return;
                }
                setState(() => _step = 8);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_step7CardRadius),
                ),
              ),
              child: const Text('Continue to Final Hiring'),
            ),
          )
        else if (_examPassed && _finalInterviewPassed == false)
          RspApplicantWaitingState(
            title: 'Deliberation not passed',
            body:
                'You cannot continue to Final Hiring. Contact the HR office if you have questions.',
            icon: Icons.cancel_rounded,
            onRefresh: _refreshHiringStatus,
            refreshBusy: _hiringStatusRefreshing,
          )
        else if (_examPassed)
          RspApplicantWaitingState(
            title: 'Waiting for deliberation result',
            body:
                'You can continue to Final Hiring only after HR records that you passed deliberation.',
            icon: Icons.hourglass_top_rounded,
            onRefresh: _refreshHiringStatus,
            refreshBusy: _hiringStatusRefreshing,
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

  bool get _employeeAccountReady =>
      _employeeAccountLinked || _hrAccountSetupDone;

  Future<void> _refreshHiringStatus() async {
    if (_hiringStatusRefreshing) return;
    setState(() => _hiringStatusRefreshing = true);
    try {
      await _refreshBeiGradingFromServer();
      await _syncInterviewFromEmail();
    } finally {
      if (mounted) setState(() => _hiringStatusRefreshing = false);
    }
    if (!mounted) return;
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
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'Refresh status',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryNavy,
            padding: const EdgeInsets.symmetric(vertical: 11),
            side: BorderSide(
              color: AppTheme.primaryNavy.withValues(alpha: 0.22),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildHiringStatusCard({
    required bool linked,
    required bool passedFinal,
    required bool failedFinal,
    required bool hrSetupDone,
    required bool finalReqApproved,
    required bool allFinalReqUploaded,
  }) {
    late final String title;
    late final String body;
    late final Color accent;
    late final IconData icon;

    if (linked) {
      title = 'Hired — account ready';
      body =
          'Your application is linked to an employee account. Sign in with the same email used for this application. Check spam or contact HR if login fails.';
      accent = const Color(0xFF2E7D32);
      icon = Icons.verified_rounded;
    } else if (failedFinal) {
      title = 'Final interview recorded';
      body =
          'HR has recorded your final interview result. Contact the HR office for questions.';
      accent = Colors.red.shade800;
      icon = Icons.info_outline_rounded;
    } else if (passedFinal && finalReqApproved && hrSetupDone) {
      title = 'Account setup complete';
      body =
          'HR marked your employee account as ready. Check your email (and spam folder) for sign-in details.';
      accent = const Color(0xFF1565C0);
      icon = Icons.task_alt_rounded;
    } else if (passedFinal && finalReqApproved) {
      title = 'Waiting for HR account setup';
      body =
          'Final requirements are approved. HR will create your account and email you when you can sign in. Tap Refresh status for updates.';
      accent = const Color(0xFFE85D04);
      icon = Icons.hourglass_top_rounded;
    } else if (passedFinal && allFinalReqUploaded) {
      title = 'Final requirements submitted';
      body =
          'HR is reviewing your medical certificate, drug test, and NBI clearance.';
      accent = const Color(0xFF1565C0);
      icon = Icons.fact_check_rounded;
    } else if (passedFinal && _hasAnyFinalReqRejection) {
      title = 'Resubmit final requirements';
      body =
          'HR rejected one or more documents. Review the notes, upload corrected PDFs, then tap Submit documents.';
      accent = const Color(0xFFC62828);
      icon = Icons.replay_circle_filled_rounded;
    } else if (passedFinal) {
      title = 'Submit final requirements';
      body =
          'After you submit the three PDFs above, HR will review them here. Tap Refresh status for updates.';
      accent = const Color(0xFFE85D04);
      icon = Icons.health_and_safety_rounded;
    } else {
      title = 'Waiting for interview result';
      body =
          'HR has not recorded a final interview outcome yet. Refresh here after your interview.';
      accent = AppTheme.primaryNavy;
      icon = Icons.pending_outlined;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: AppTheme.dashTextPrimaryOf(context),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStep8StatusFooter(),
        ],
      ),
    );
  }

  Widget _buildSubmitFinalRequirementsButton() {
    final busy = _finalReqUploading;
    final enabled = _canSubmitFinalRequirements;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? _uploadFinalRequirements : null,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded, size: 20),
        label: Text(busy ? 'Submitting…' : 'Submit documents'),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryNavy,
          disabledBackgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildFinalRequirementsSection() {
    final approved = _finalRequirementsApproved;
    final allUploaded = _allFinalRequirementsUploaded;
    final pendingUpload = _pickedFinalReqDocs.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 20,
                color: AppTheme.primaryNavy.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Final requirements',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
              if (approved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3FAF4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'Approved',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (_hasAnyFinalReqRejection)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6F6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFC62828).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'Resubmit',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (allUploaded)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F9FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Text(
                    'Under review',
                    style: TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Refresh status',
                visualDensity: VisualDensity.compact,
                onPressed: _hiringStatusRefreshing
                    ? null
                    : _refreshHiringStatus,
                icon: _hiringStatusRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Upload PDF copies of your medical certificate, drug test result, and NBI clearance.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withValues(alpha: 0.95),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 480;
              final kinds = RspFinalRequirementDocKind.values;
              final cards = kinds
                  .map(
                    (kind) => _buildFinalRequirementDocCard(
                      kind: kind,
                      approved: approved,
                    ),
                  )
                  .toList();
              if (sideBySide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              );
            },
          ),
          if (!approved && (!allUploaded || pendingUpload)) ...[
            const SizedBox(height: 12),
            if (!_allRequiredFinalReqChosen)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Choose a PDF for each requirement, then tap Submit documents.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textSecondary.withValues(alpha: 0.95),
                  ),
                ),
              ),
            _buildSubmitFinalRequirementsButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildFinalRequirementDocCard({
    required RspFinalRequirementDocKind kind,
    required bool approved,
  }) {
    final storedPath = _finalReqStoredPath(kind);
    final storedName = _finalReqStoredName(kind);
    final hasStored = storedPath != null && storedPath.trim().isNotEmpty;
    final rejectReason = _finalReqRejectReason(kind)?.trim();
    final wasRejected = rejectReason != null && rejectReason.isNotEmpty;
    final picked = _pickedFinalReqDocs[kind];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: wasRejected && !hasStored
              ? const Color(0xFFC62828).withValues(alpha: 0.45)
              : AppTheme.lightGray.withValues(alpha: 0.9),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _finalReqKindLabel(kind),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            if (wasRejected && !hasStored) ...[
              const SizedBox(height: 8),
              Text(
                'Rejected by HR — please upload again',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                rejectReason,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.textSecondary.withValues(alpha: 0.95),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (hasStored)
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      storedName ?? 'Uploaded',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              )
            else if (picked != null)
              Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      picked.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    onPressed: _finalReqUploading
                        ? null
                        : () => _removeFinalReqDoc(kind),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              )
            else
              FilledButton.tonalIcon(
                onPressed: _finalReqUploading || approved
                    ? null
                    : () => _pickFinalReqDoc(kind),
                icon: const Icon(Icons.upload_file_rounded, size: 20),
                label: Text(wasRejected ? 'Re-upload PDF' : 'Choose PDF'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrientationScheduleCard() {
    final at = _orientationAt!.toLocal();
    final attended = _orientationAttended;
    final dateLine =
        '${MaterialLocalizations.of(context).formatFullDate(at)} · ${TimeOfDay.fromDateTime(at).format(context)}';

    late final Color accent;
    late final Color surface;
    late final IconData icon;
    late final String title;
    late final String body;

    if (attended == true) {
      accent = const Color(0xFF2E7D32);
      surface = const Color(0xFFF3FAF4);
      icon = Icons.check_circle_outline_rounded;
      title = 'Orientation attended';
      body = 'HR confirmed attendance. Account setup is next.';
    } else if (attended == false) {
      accent = const Color(0xFFC62828);
      surface = const Color(0xFFFFF6F6);
      icon = Icons.cancel_outlined;
      title = 'Orientation not attended';
      body = 'Contact HR for next steps.';
    } else {
      accent = const Color(0xFF1565C0);
      surface = const Color(0xFFF5F9FF);
      icon = Icons.event_available_outlined;
      title = 'Orientation scheduled';
      body = 'Attend as instructed by HR. Account setup follows this step.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    letterSpacing: -0.15,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLine,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh status',
            visualDensity: VisualDensity.compact,
            onPressed: _hiringStatusRefreshing ? null : _refreshHiringStatus,
            icon: _hiringStatusRefreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildStep8MilestoneRow({
    required bool passedFinal,
    required bool finalReqApproved,
    required bool linked,
  }) {
    final orientationDone = _orientationAttended == true;
    final accountReady = linked || _hrAccountSetupDone;

    Widget chip({
      required String label,
      required bool done,
      required bool active,
    }) {
      final color = done
          ? const Color(0xFF2E7D32)
          : (active ? const Color(0xFFE85D04) : AppTheme.textSecondary);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFF3FAF4)
                : (active ? const Color(0xFFFFF7F0) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : (active
                          ? Icons.radio_button_checked_rounded
                          : Icons.circle_outlined),
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final reqDone =
        passedFinal && (finalReqApproved || _allFinalRequirementsUploaded);
    final reqActive = passedFinal && !finalReqApproved;
    final orientActive =
        passedFinal && finalReqApproved && !orientationDone && !accountReady;
    final accountActive =
        passedFinal &&
        finalReqApproved &&
        (orientationDone || _orientationAt == null) &&
        !accountReady;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final items = [
          chip(
            label: 'Requirements',
            done: finalReqApproved,
            active: reqActive || (passedFinal && !reqDone),
          ),
          chip(
            label: 'Orientation',
            done: orientationDone,
            active: orientActive,
          ),
          chip(label: 'Account', done: accountReady, active: accountActive),
        ];
        if (stacked) {
          return Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                items[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              items[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildStep8FinalHiring() {
    final linked = _employeeAccountLinked;
    final accountReady = _employeeAccountReady;
    final passedFinal = _finalInterviewPassed == true;
    final failedFinal = _finalInterviewPassed == false;
    final finalReqApproved = _finalRequirementsApproved;
    String headerSubtitle;
    if (failedFinal) {
      headerSubtitle = 'Current hiring status from HR.';
    } else if (accountReady) {
      headerSubtitle = 'Your application is successful. You can now start work.';
    } else if (passedFinal &&
        finalReqApproved &&
        _orientationAttended == true) {
      headerSubtitle = 'Orientation done. Account setup in progress.';
    } else if (passedFinal &&
        finalReqApproved &&
        _orientationAttended == false) {
      headerSubtitle = 'Orientation missed. Contact HR for next steps.';
    } else if (passedFinal && finalReqApproved && _orientationAt != null) {
      headerSubtitle = 'Attend orientation, then wait for account setup.';
    } else if (passedFinal && finalReqApproved) {
      headerSubtitle = 'Waiting for orientation schedule and account setup.';
    } else if (passedFinal) {
      headerSubtitle = 'Upload final documents, then wait for HR review.';
    } else {
      headerSubtitle = 'Track your hiring progress here.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Color(0xFFE85D04),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FINAL HIRING',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: const Color(0xFFE85D04).withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Onboarding',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppTheme.dashTextPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headerSubtitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (passedFinal) ...[
          const SizedBox(height: 14),
          _buildStep8MilestoneRow(
            passedFinal: passedFinal,
            finalReqApproved: finalReqApproved,
            linked: linked,
          ),
        ],
        const SizedBox(height: 16),
        if (failedFinal)
          const RspApplicantWaitingState(
            title: 'Application result',
            body:
                'Thank you for completing the recruitment process. Contact HR if you have questions.',
            icon: Icons.info_outline_rounded,
          )
        else if (!passedFinal)
          RspApplicantWaitingState(
            title: 'Waiting for HR',
            body:
                'HR has not recorded a final interview outcome yet. No action is required right now.',
            onRefresh: _refreshHiringStatus,
            refreshBusy: false,
          )
        else if (!finalReqApproved) ...[
          _buildFinalRequirementsSection(),
        ] else if (_orientationAttended != true) ...[
          if (_orientationAt != null)
            _buildOrientationScheduleCard()
          else
            const RspApplicantWaitingState(
              title: 'Orientation',
              body:
                  'Your documents are approved. HR will schedule your orientation. No action is required right now.',
            ),
        ] else if (!accountReady) ...[
          RspApplicantWaitingState(
            title: 'Account setup in progress',
            body:
                'HR is preparing your employee account. Login instructions will be provided when your account is activated.',
            onRefresh: _refreshHiringStatus,
            refreshBusy: _hiringStatusRefreshing,
          ),
        ] else ...[
          RspApplicantAccountDetailsCard(
            gmailAddress: _emailController.text.trim(),
            emailSentAt: _hireCredentialsEmailSentAt,
            onRefresh: _refreshHiringStatus,
            refreshBusy: _hiringStatusRefreshing,
          ),
        ],
        if (_finalInterviewAt != null && (failedFinal || !passedFinal)) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Application history'),
            children: [
              ListTile(
                dense: true,
                title: Text(
                  'Final interview: ${MaterialLocalizations.of(context).formatFullDate(_finalInterviewAt!.toLocal())}',
                ),
              ),
            ],
          ),
        ],
        if (!accountReady) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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
