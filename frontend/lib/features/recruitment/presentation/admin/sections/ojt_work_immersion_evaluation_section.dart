import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

const _kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _kMonthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime? _tryParseDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  final slash = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$');
  final m1 = slash.firstMatch(s);
  if (m1 != null) {
    final a = int.tryParse(m1.group(1)!);
    final b = int.tryParse(m1.group(2)!);
    final y = int.tryParse(m1.group(3)!);
    if (a != null && b != null && y != null) {
      final month = a <= 12 ? a : b;
      final day = a <= 12 ? b : a;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(y, month, day);
      }
    }
  }
  final named = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})$');
  final m2 = named.firstMatch(s);
  if (m2 != null) {
    final monthName = m2.group(1)!.toLowerCase();
    final day = int.tryParse(m2.group(2)!);
    final year = int.tryParse(m2.group(3)!);
    final mi = _kMonths.indexWhere((m) => m.toLowerCase() == monthName);
    if (mi != -1 && day != null && year != null) {
      return DateTime(year, mi + 1, day);
    }
  }
  return null;
}

String _formatDate(DateTime date) {
  final d = date.toLocal();
  return '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';
}

String _formatDateShort(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = _tryParseDate(raw);
  if (parsed == null) return raw.trim();
  final d = parsed.toLocal();
  return '${_kMonthsShort[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
}

class _OjtCriterionDef {
  const _OjtCriterionDef({
    required this.number,
    required this.title,
    required this.prompt,
  });
  final int number;
  final String title;
  final String prompt;
}

const List<_OjtCriterionDef> _kCriteria = [
  _OjtCriterionDef(
    number: 1,
    title: 'Problem Solving and Decision Making',
    prompt:
        'Tell me about a time you had to make a difficult decision quickly with limited information.',
  ),
  _OjtCriterionDef(
    number: 2,
    title: 'Communication and Clarity',
    prompt:
        'How do you explain a complex concept or project update to a non-technical stakeholder?',
  ),
  _OjtCriterionDef(
    number: 3,
    title: 'Teamwork and Collaboration',
    prompt:
        'Describe a time you worked with a difficult team member to reach a shared goal.',
  ),
  _OjtCriterionDef(
    number: 4,
    title: 'Adaptability and Resilience',
    prompt:
        'How do you handle sudden priority shifts or project changes under tight deadlines?',
  ),
];

const List<(int, String, String)> _kRatingScale = [
  (
    1,
    'Unsatisfactory',
    'Fails to meet basic expectations or provide relevant examples.',
  ),
  (2, 'Marginal', 'Partially meets criteria; weak or vague examples.'),
  (3, 'Competent', 'Solidly meets job requirements with clear examples.'),
  (
    4,
    'Above Average',
    'Exceeds standard expectations; strong evidence of skill.',
  ),
  (5, 'Exceptional', 'Outstanding proficiency; deeply relevant expertise.'),
];

class _ApplicantHint {
  const _ApplicantHint({required this.name, this.school});
  final String name;
  final String? school;
}

class _EmployeeHint {
  const _EmployeeHint({required this.fullName});
  final String fullName;
}

Future<List<_ApplicantHint>> _fetchApplicantHints() async {
  try {
    final apps = await RecruitmentRepo.instance.listApplications();
    return apps
        .where((a) => a.fullName.trim().isNotEmpty)
        .map(
          (a) => _ApplicantHint(
            name: a.fullName.trim(),
            school: a.course?.trim().isNotEmpty == true ? a.course!.trim() : null,
          ),
        )
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<List<_EmployeeHint>> _fetchEmployeeHints() async {
  try {
    final res = await ApiClient.instance.get<dynamic>(
      '/api/employees',
      queryParameters: <String, dynamic>{
        'status': 'Active',
        'role': 'All',
        'limit': 4000,
        'offset': 0,
        'sort': 'full_name',
        'order': 'asc',
      },
    );
    final data = res.data;
    final List<dynamic> list;
    if (data is Map && data['employees'] is List) {
      list = data['employees'] as List<dynamic>;
    } else if (data is List) {
      list = data;
    } else {
      list = const [];
    }
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e)['full_name']?.toString() ?? '')
        .where((n) => n.trim().isNotEmpty)
        .map((n) => _EmployeeHint(fullName: n.trim()))
        .toList();
  } catch (_) {
    return const [];
  }
}

String? _opt(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : t;
}

/// RSP: OJT / Work Immersion Evaluation.
///
/// Screen UI is a modern evaluator workflow. Print/PDF (see
/// [FormPdf.buildOjtWorkImmersionEvaluationPdf]) is an independent official
/// template that reads the same [OjtWorkImmersionEvaluation].
class RspOjtWorkImmersionEvaluationSection extends StatefulWidget {
  const RspOjtWorkImmersionEvaluationSection({super.key});

  @override
  State<RspOjtWorkImmersionEvaluationSection> createState() =>
      _RspOjtWorkImmersionEvaluationSectionState();
}

class _RspOjtWorkImmersionEvaluationSectionState
    extends State<RspOjtWorkImmersionEvaluationSection> {
  List<OjtWorkImmersionEvaluation> _entries = [];
  bool _loading = true;
  OjtWorkImmersionEvaluation? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await OjtWorkImmersionEvaluationRepo.instance.list();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
      });
    }
  }

  void _startNew() =>
      setState(() => _editing = const OjtWorkImmersionEvaluation());
  void _edit(OjtWorkImmersionEvaluation e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(OjtWorkImmersionEvaluation entry) async {
    try {
      if (entry.id == null) {
        await OjtWorkImmersionEvaluationRepo.instance.insert(entry);
      } else {
        await OjtWorkImmersionEvaluationRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OJT / Work Immersion Evaluation saved.')),
      );
      setState(() => _editing = null);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
      );
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await OjtWorkImmersionEvaluationRepo.instance.delete(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evaluation deleted.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _print(OjtWorkImmersionEvaluation entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildOjtWorkImmersionEvaluationPdf(entry),
        filename: 'OJT_Work_Immersion_Evaluation.pdf',
        format: FormPdf.pageLetter,
        printModule: 'rsp',
        printFormKey: 'ojt_work_immersion',
      );
    } catch (_) {}
  }

  Future<void> _download(OjtWorkImmersionEvaluation entry) async {
    try {
      final doc = await FormPdf.buildOjtWorkImmersionEvaluationPdf(entry);
      await FormPdf.sharePdf(doc, name: 'OJT_Work_Immersion_Evaluation.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF ready to save or share.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved OJT / Work Immersion Evaluations',
      emptyMessage: 'No evaluations yet.',
      loading: _loading,
      items: _entries.map((e) {
        final name = (e.ojtImmersion?.trim().isNotEmpty ?? false)
            ? e.ojtImmersion!
            : '(No name)';
        final total = e.totalScore;
        return SavedRecordListItem(
          title: name,
          subtitle:
              '${e.school ?? '—'} · ${_formatDateShort(e.interviewDate)} · ${total == null ? '—/20' : '$total/20'}',
          detailDialogTitle: 'OJT / Work Immersion Evaluation — $name',
          previewContentWidth: 900,
          previewBuilder: () => OjtWorkImmersionEvaluationEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _print(e),
        );
      }).toList(),
    );
  }

  Widget _toolbar(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: _loading ? null : _startNew,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('New Evaluation'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.dashTextPrimaryOf(context),
            side: BorderSide(color: AppTheme.dashHairlineOf(context)),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _openSavedRecordsBrowser,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('View Records'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.dashTextPrimaryOf(context),
            side: BorderSide(color: AppTheme.dashHairlineOf(context)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RSP',
              style: TextStyle(
                color: secondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
            Text(
              'OJT Evaluation',
              style: TextStyle(
                color: secondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'OJT Evaluation',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Interview scoring form.',
          style: TextStyle(color: secondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          OjtWorkImmersionEvaluationEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _print,
            onDownloadPdf: _download,
          ),
          const SizedBox(height: 24),
        ],
        _toolbar(context),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          const RspFormEmptyState(
            message:
                'No evaluations yet. Tap "New Evaluation" to add one.',
            icon: Icons.school_outlined,
          )
        else
          _OjtList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _print,
            onDownloadPdf: _download,
          ),
      ],
    );
  }
}

class OjtWorkImmersionEvaluationEditor extends StatefulWidget {
  const OjtWorkImmersionEvaluationEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final OjtWorkImmersionEvaluation entry;
  final bool readOnly;
  final void Function(OjtWorkImmersionEvaluation) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(OjtWorkImmersionEvaluation) onPrint;
  final Future<void> Function(OjtWorkImmersionEvaluation) onDownloadPdf;

  @override
  State<OjtWorkImmersionEvaluationEditor> createState() =>
      _OjtWorkImmersionEvaluationEditorState();
}

class _OjtWorkImmersionEvaluationEditorState
    extends State<OjtWorkImmersionEvaluationEditor> {
  late final TextEditingController _ojt;
  late final TextEditingController _school;
  late final TextEditingController _date;
  late final TextEditingController _psNotes;
  late final TextEditingController _commNotes;
  late final TextEditingController _teamNotes;
  late final TextEditingController _adaptNotes;
  late final TextEditingController _strengths;
  late final TextEditingController _concerns;
  late final TextEditingController _interviewer;

  int? _psScore;
  int? _commScore;
  int? _teamScore;
  int? _adaptScore;
  String? _recommendation;

  final FocusNode _ojtFocus = FocusNode();
  final FocusNode _interviewerFocus = FocusNode();
  List<_ApplicantHint> _applicants = [];
  List<_EmployeeHint> _employees = [];

  String? _ojtError;
  String? _schoolError;
  String? _dateError;
  String? _scoreError;
  String? _interviewerError;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _ojt = TextEditingController(text: e.ojtImmersion ?? '');
    _school = TextEditingController(text: e.school ?? '');
    _date = TextEditingController(text: e.interviewDate ?? '');
    _psNotes = TextEditingController(text: e.problemSolvingNotes ?? '');
    _commNotes = TextEditingController(text: e.communicationNotes ?? '');
    _teamNotes = TextEditingController(text: e.teamworkNotes ?? '');
    _adaptNotes = TextEditingController(text: e.adaptabilityNotes ?? '');
    _strengths = TextEditingController(text: e.keyStrengths ?? '');
    _concerns = TextEditingController(text: e.keyConcerns ?? '');
    _interviewer = TextEditingController(text: e.interviewer ?? '');
    _psScore = e.problemSolvingScore;
    _commScore = e.communicationScore;
    _teamScore = e.teamworkScore;
    _adaptScore = e.adaptabilityScore;
    _recommendation = e.overallRecommendation?.trim().isNotEmpty == true
        ? e.overallRecommendation!.trim()
        : null;
    _ojtFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _interviewerFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (!widget.readOnly) _loadLookups();
  }

  Future<void> _loadLookups() async {
    final applicants = await _fetchApplicantHints();
    final employees = await _fetchEmployeeHints();
    if (!mounted) return;
    setState(() {
      _applicants = applicants;
      _employees = employees;
    });
  }

  @override
  void dispose() {
    _ojtFocus.dispose();
    _interviewerFocus.dispose();
    for (final c in [
      _ojt,
      _school,
      _date,
      _psNotes,
      _commNotes,
      _teamNotes,
      _adaptNotes,
      _strengths,
      _concerns,
      _interviewer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  OjtWorkImmersionEvaluation _buildCurrent() {
    return OjtWorkImmersionEvaluation(
      id: widget.entry.id,
      ojtImmersion: _opt(_ojt),
      school: _opt(_school),
      interviewDate: _opt(_date),
      problemSolvingScore: _psScore,
      problemSolvingNotes: _opt(_psNotes),
      communicationScore: _commScore,
      communicationNotes: _opt(_commNotes),
      teamworkScore: _teamScore,
      teamworkNotes: _opt(_teamNotes),
      adaptabilityScore: _adaptScore,
      adaptabilityNotes: _opt(_adaptNotes),
      overallRecommendation: _recommendation,
      keyStrengths: _opt(_strengths),
      keyConcerns: _opt(_concerns),
      interviewer: _opt(_interviewer),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  int? get _total {
    final scores = [_psScore, _commScore, _teamScore, _adaptScore];
    if (scores.any((s) => !OjtWorkImmersionEvaluation.isValidScore(s))) {
      return null;
    }
    return scores.fold<int>(0, (sum, s) => sum + s!);
  }

  bool _validate() {
    _ojtError = _ojt.text.trim().isEmpty ? 'OJT / Immersion is required.' : null;
    _schoolError = _school.text.trim().isEmpty ? 'School is required.' : null;
    _dateError = _date.text.trim().isEmpty
        ? 'Date of interview is required.'
        : null;
    final missing = [
      _psScore,
      _commScore,
      _teamScore,
      _adaptScore,
    ].where((s) => !OjtWorkImmersionEvaluation.isValidScore(s)).length;
    _scoreError = missing > 0
        ? 'Score every criterion from 1 to 5.'
        : null;
    _interviewerError = _interviewer.text.trim().isEmpty
        ? 'Interviewer is required.'
        : null;
    setState(() {});
    return [
      _ojtError,
      _schoolError,
      _dateError,
      _scoreError,
      _interviewerError,
    ].every((e) => e == null);
  }

  void _save() {
    if (widget.readOnly) return;
    if (!_validate()) return;
    widget.onSave(_buildCurrent());
  }

  Future<void> _pickDate() async {
    if (widget.readOnly) return;
    final now = DateTime.now();
    final parsed = _tryParseDate(_date.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      helpText: 'Date of interview',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date.text = _formatDate(picked);
      _dateError = null;
    });
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
    String? error,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) => AppTheme.dashInputDecoration(
    context,
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
  ).copyWith(errorText: error);

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _applicantField() {
    final q = _ojt.text.trim().toLowerCase();
    final matches =
        (!widget.readOnly &&
            _applicants.isNotEmpty &&
            _ojtFocus.hasFocus &&
            q.isNotEmpty)
        ? _applicants
              .where((a) => a.name.toLowerCase().contains(q))
              .take(6)
              .toList()
        : const <_ApplicantHint>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _ojt,
          focusNode: _ojtFocus,
          readOnly: widget.readOnly,
          onChanged: (_) => setState(() => _ojtError = null),
          decoration: _decoration(
            context,
            label: 'OJT / Immersion',
            hint: _applicants.isNotEmpty
                ? 'Search an existing applicant or type a name'
                : 'Applicant / trainee name',
            error: _ojtError,
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
          ),
        ),
        if (matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final m in matches)
                  ListTile(
                    dense: true,
                    title: Text(
                      m.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: (m.school ?? '').isEmpty
                        ? null
                        : Text(
                            m.school!,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                    onTap: () {
                      setState(() {
                        _ojt.text = m.name;
                        if ((m.school ?? '').isNotEmpty &&
                            _school.text.trim().isEmpty) {
                          _school.text = m.school!;
                        }
                        _ojtError = null;
                      });
                      _ojtFocus.unfocus();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _interviewerField() {
    final q = _interviewer.text.trim().toLowerCase();
    final matches =
        (!widget.readOnly &&
            _employees.isNotEmpty &&
            _interviewerFocus.hasFocus &&
            q.isNotEmpty)
        ? _employees
              .where((e) => e.fullName.toLowerCase().contains(q))
              .take(6)
              .toList()
        : const <_EmployeeHint>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _interviewer,
          focusNode: _interviewerFocus,
          readOnly: widget.readOnly,
          onChanged: (_) => setState(() => _interviewerError = null),
          decoration: _decoration(
            context,
            hint: 'Printed name / over signature',
            error: _interviewerError,
            prefixIcon: const Icon(Icons.badge_outlined, size: 18),
          ),
        ),
        if (matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final m in matches)
                  ListTile(
                    dense: true,
                    title: Text(
                      m.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _interviewer.text = m.fullName;
                        _interviewerError = null;
                      });
                      _interviewerFocus.unfocus();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _infoCard() {
    return _sectionCard(
      title: 'APPLICANT / INTERVIEW INFORMATION',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 640;
          final fields = [
            _applicantField(),
            TextFormField(
              controller: _school,
              readOnly: widget.readOnly,
              onChanged: (_) => setState(() => _schoolError = null),
              decoration: _decoration(
                context,
                label: 'School',
                error: _schoolError,
              ),
            ),
            TextFormField(
              controller: _date,
              readOnly: true,
              onTap: widget.readOnly ? null : _pickDate,
              decoration: _decoration(
                context,
                label: 'Date of Interview',
                hint: widget.readOnly ? null : 'Select date',
                error: _dateError,
                suffixIcon: widget.readOnly
                    ? null
                    : IconButton(
                        tooltip: 'Pick date',
                        icon: const Icon(Icons.calendar_today_rounded, size: 18),
                        onPressed: _pickDate,
                      ),
              ),
            ),
          ];
          if (!wide) {
            return Column(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  fields[i],
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: fields[0]),
              const SizedBox(width: 12),
              Expanded(child: fields[1]),
              const SizedBox(width: 12),
              Expanded(child: fields[2]),
            ],
          );
        },
      ),
    );
  }

  Widget _ratingScalePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RATING SCALE', style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 10),
          for (final item in _kRatingScale)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${item.$1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                        children: [
                          TextSpan(
                            text: '${item.$2}. ',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: item.$3),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _scorePicker({
    required int? selected,
    required ValueChanged<int>? onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var n = 1; n <= 5; n++)
          _OjtScoreChip(
            value: n,
            selected: selected == n,
            enabled: onChanged != null,
            onTap: onChanged == null ? null : () => onChanged(n),
          ),
      ],
    );
  }

  Widget _criterionCard(_OjtCriterionDef def) {
    final ro = widget.readOnly;
    late final int? score;
    late final TextEditingController notes;
    late final ValueChanged<int>? onScore;
    switch (def.number) {
      case 1:
        score = _psScore;
        notes = _psNotes;
        onScore = ro
            ? null
            : (v) => setState(() {
                _psScore = v;
                _scoreError = null;
              });
        break;
      case 2:
        score = _commScore;
        notes = _commNotes;
        onScore = ro
            ? null
            : (v) => setState(() {
                _commScore = v;
                _scoreError = null;
              });
        break;
      case 3:
        score = _teamScore;
        notes = _teamNotes;
        onScore = ro
            ? null
            : (v) => setState(() {
                _teamScore = v;
                _scoreError = null;
              });
        break;
      default:
        score = _adaptScore;
        notes = _adaptNotes;
        onScore = ro
            ? null
            : (v) => setState(() {
                _adaptScore = v;
                _scoreError = null;
              });
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CRITERION ${def.number}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            def.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Question Prompt',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '"${def.prompt}"',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          _scorePicker(selected: score, onChanged: onScore),
          const SizedBox(height: 12),
          TextFormField(
            controller: notes,
            readOnly: ro,
            minLines: 3,
            maxLines: 6,
            decoration: _decoration(context, label: 'Evidence / Notes'),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final total = _total;
    final recItems = <String>{
      ...OjtWorkImmersionEvaluation.recommendationOptions,
      if (_recommendation != null) _recommendation!,
    }.toList();
    return _sectionCard(
      title: 'SUMMARY AND RECOMMENDATIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text(
                  'TOTAL SCORE',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.primaryNavy,
                  ),
                ),
                const Spacer(),
                Text(
                  total == null ? '— / 20' : '$total / 20',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ],
            ),
          ),
          if (_scoreError != null) ...[
            const SizedBox(height: 8),
            Text(
              _scoreError!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 12),
          widget.readOnly
              ? TextFormField(
                  readOnly: true,
                  initialValue: _recommendation ?? '—',
                  decoration: _decoration(
                    context,
                    label: 'Overall Recommendation',
                  ),
                )
              : DropdownButtonFormField<String>(
                  key: ValueKey(_recommendation ?? ''),
                  initialValue: _recommendation,
                  items: [
                    for (final r in recItems)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => _recommendation = v),
                  decoration: _decoration(
                    context,
                    label: 'Overall Recommendation',
                    hint: 'Select recommendation',
                  ),
                ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _strengths,
            readOnly: widget.readOnly,
            minLines: 3,
            maxLines: 5,
            decoration: _decoration(context, label: 'Key Strengths'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _concerns,
            readOnly: widget.readOnly,
            minLines: 3,
            maxLines: 5,
            decoration: _decoration(context, label: 'Key Concerns'),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INTERVIEWER SIGNATURE',
                  style: AppTheme.dashSectionTitle(context),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 30,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.dashHairlineOf(context),
                      ),
                    ),
                  ),
                ),
                _interviewerField(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 12,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Evaluation'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconButton(
              tooltip: 'Print',
              style: rspLdRecordIconButtonStyle(),
              onPressed: () => widget.onPrint(_buildCurrent()),
              icon: const Icon(Icons.print_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'PDF',
              style: rspLdRecordIconButtonStyle(),
              onPressed: () => widget.onDownloadPdf(_buildCurrent()),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    final heading = _ojt.text.trim().isEmpty
        ? 'New OJT / Work Immersion Evaluation'
        : _ojt.text.trim();
    return Container(
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    heading,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
                if (ro) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.blueGrey.withValues(alpha: 0.32),
                      ),
                    ),
                    child: const Text(
                      'Read-only preview',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoCard(),
                const SizedBox(height: 16),
                _ratingScalePanel(),
                const SizedBox(height: 16),
                for (final c in _kCriteria) ...[
                  _criterionCard(c),
                  const SizedBox(height: 12),
                ],
                _summaryCard(),
                if (!ro) ...[
                  const SizedBox(height: 24),
                  _actionBar(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OjtScoreChip extends StatelessWidget {
  const _OjtScoreChip({
    required this.value,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final int value;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final navy = AppTheme.primaryNavy;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Score $value',
      child: Material(
        color: selected
            ? navy.withValues(alpha: 0.14)
            : AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? navy : AppTheme.dashHairlineOf(context),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: selected
                    ? navy
                    : AppTheme.dashTextPrimaryOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OjtList extends StatelessWidget {
  const _OjtList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<OjtWorkImmersionEvaluation> entries;
  final void Function(OjtWorkImmersionEvaluation) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(OjtWorkImmersionEvaluation) onPrint;
  final Future<void> Function(OjtWorkImmersionEvaluation) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Applicant', flex: 2),
      RspRecordsColumn('School', flex: 1.8),
      RspRecordsColumn('Interview Date', flex: 1.4),
      RspRecordsColumn('Total', flex: 0.8),
      RspRecordsColumn('Recommendation', flex: 1.6),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, e.ojtImmersion ?? '', bold: true),
              rspRecordsTextCell(context, e.school ?? ''),
              rspRecordsTextCell(context, _formatDateShort(e.interviewDate)),
              rspRecordsTextCell(
                context,
                e.totalScore == null ? '—' : '${e.totalScore}/20',
              ),
              rspRecordsTextCell(context, e.overallRecommendation ?? ''),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'OJT / Work Immersion Evaluation',
                  subtitle:
                      '${e.ojtImmersion ?? '—'} · ${_formatDateShort(e.interviewDate)}',
                  previewBuilder: () => OjtWorkImmersionEvaluationEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 900,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete evaluation?',
              ),
            ],
          )
          .toList(),
    );
  }
}
