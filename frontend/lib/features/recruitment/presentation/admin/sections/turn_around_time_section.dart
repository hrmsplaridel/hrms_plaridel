import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_applications_report_export.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/searchable_dropdown_field.dart';
import 'package:hrms_plaridel/shared/widgets/form_document_preview.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_form_header.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_rsp_signature_section.dart';

/// One recruitment milestone tracked per applicant. Keys match the official
/// Turn-Around Time paper form columns / [TurnAroundTimeApplicant] fields —
/// order here drives the on-screen timeline only, not the print/PDF column
/// order (see [FormPdf.buildTurnAroundTimePdf]).
class _TatMilestone {
  const _TatMilestone(this.key, this.label, this.icon, {this.isDate = true});
  final String key;
  final String label;
  final IconData icon;
  final bool isDate;
}

const List<_TatMilestone> _tatMilestones = [
  _TatMilestone('date_initial_assessment', 'Initial Assessment', Icons.fact_check_outlined),
  _TatMilestone('date_contract_exam', 'Exam (Trade/Written)', Icons.edit_note_rounded),
  _TatMilestone('skills_trade_exam_result', 'Exam Result', Icons.grade_outlined, isDate: false),
  _TatMilestone('date_deliberation', 'Deliberation', Icons.groups_outlined),
  _TatMilestone('date_job_offer', 'Job Offer', Icons.mail_outline_rounded),
  _TatMilestone('acceptance_date', 'Offer Accepted', Icons.check_circle_outline_rounded),
  _TatMilestone('date_assumption_to_duty', 'Assumption to Duty', Icons.flag_outlined),
];

/// Order matches [TurnAroundTimeApplicant.toJson] / official form columns.
const List<String> _tatRowKeys = [
  'name',
  'date_initial_assessment',
  'date_contract_exam',
  'skills_trade_exam_result',
  'date_deliberation',
  'date_job_offer',
  'acceptance_date',
  'date_assumption_to_duty',
  'no_of_days_to_fill_up',
  'overall_cost_per_hire',
];

Map<String, String> _emptyTatValues() => {for (final k in _tatRowKeys) k: ''};

Map<String, String> _tatValuesFromApplicant(TurnAroundTimeApplicant a) => {
  'application_id': a.applicationId ?? '',
  'name': a.name ?? '',
  'date_initial_assessment': a.dateInitialAssessment ?? '',
  'date_contract_exam': a.dateContractExam ?? '',
  'skills_trade_exam_result': a.skillsTradeExamResult ?? '',
  'date_deliberation': a.dateDeliberation ?? '',
  'date_job_offer': a.dateJobOffer ?? '',
  'acceptance_date': a.acceptanceDate ?? '',
  'date_assumption_to_duty': a.dateAssumptionToDuty ?? '',
  'no_of_days_to_fill_up': a.noOfDaysToFillUp ?? '',
  'overall_cost_per_hire': a.overallCostPerHire ?? '',
};

TurnAroundTimeApplicant _tatApplicantFromValues(Map<String, String> v) {
  String? opt(String key) {
    final t = (v[key] ?? '').trim();
    return t.isEmpty ? null : t;
  }

  return TurnAroundTimeApplicant(
    applicationId: opt('application_id'),
    name: opt('name'),
    dateInitialAssessment: opt('date_initial_assessment'),
    dateContractExam: opt('date_contract_exam'),
    skillsTradeExamResult: opt('skills_trade_exam_result'),
    dateDeliberation: opt('date_deliberation'),
    dateJobOffer: opt('date_job_offer'),
    acceptanceDate: opt('acceptance_date'),
    dateAssumptionToDuty: opt('date_assumption_to_duty'),
    noOfDaysToFillUp: opt('no_of_days_to_fill_up'),
    overallCostPerHire: opt('overall_cost_per_hire'),
  );
}

/// A named applicant that has any milestone recorded counts as "in progress";
/// reaching Assumption to Duty counts as "completed".
String _tatApplicantStatus(Map<String, String> v) {
  final name = (v['name'] ?? '').trim();
  if (name.isEmpty) return 'Draft';
  if ((v['date_assumption_to_duty'] ?? '').trim().isNotEmpty) return 'Completed';
  final anyMilestone = _tatMilestones.any((m) => (v[m.key] ?? '').trim().isNotEmpty);
  return anyMilestone ? 'In Progress' : 'Draft';
}

Color _tatStatusColor(String status) {
  switch (status) {
    case 'Completed':
      return const Color(0xFF2E7D32);
    case 'In Progress':
      return const Color(0xFF1565C0);
    default:
      return const Color(0xFFB26A00);
  }
}

/// Verified Turn-Around Time rows inserted by the removed October 6, 2026
/// vacancy completion workflow. Hidden from the normal list only; the rows
/// stay in the database and on the saved-entry API.
const Set<String> legacyAutoGeneratedTatRecordIds = {
  '277b88d7-5fb4-4d50-b4e4-3f2e615b29e6',
  '8740109e-dac1-41f6-a5f7-959b6e653792',
  'b208dd40-b419-4373-b63e-f50b56d1c54e',
  'fe3f740a-3c6f-4117-a8a9-5ebe5cb8a6db',
  'cdeebdfa-f0a3-40bd-9585-94c0b2d75643',
  '3c4d87b9-4eed-420c-aec6-fb02b79f66b5',
};

/// Exact-ID check for [legacyAutoGeneratedTatRecordIds]. Blank Position,
/// Office, or applicant fields do not qualify a row.
bool isLegacyAutoGeneratedTatRecord(TurnAroundTimeEntry entry) {
  final id = entry.id?.trim().toLowerCase();
  if (id == null || id.isEmpty) return false;
  return legacyAutoGeneratedTatRecordIds.contains(id);
}

/// Normal Turn-Around Time list. Drops only the six legacy auto-generated IDs.
List<TurnAroundTimeEntry> visibleTurnAroundTimeEntries(
  Iterable<TurnAroundTimeEntry> entries,
) {
  return [
    for (final entry in entries)
      if (!isLegacyAutoGeneratedTatRecord(entry)) entry,
  ];
}

/// Vacancy selection fills Position and the vacancy details already stored on
/// the announcement. It does not insert applicants.
TurnAroundTimeEntry turnAroundTimeEntryFromVacancy({
  required String position,
  String? noOfVacantPosition,
  String? endSearch,
  String? qualificationStandard,
}) {
  String? clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  return TurnAroundTimeEntry(
    position: clean(position),
    noOfVacantPosition: clean(noOfVacantPosition),
    endSearch: clean(endSearch),
    qs: clean(qualificationStandard),
    applicants: const [],
  );
}

/// True when this form already tracks the same recruitment application.
bool tatApplicantIdAlreadyTracked(
  Iterable<Map<String, String>> applicants,
  String? applicationId,
) {
  final id = (applicationId ?? '').trim().toLowerCase();
  if (id.isEmpty) return false;
  return applicants.any(
    (row) => (row['application_id'] ?? '').trim().toLowerCase() == id,
  );
}

/// Listed vacancies have no separate id on this form. Applications are tied
/// to a vacancy by the position title stored in `position_applied_for`.
/// A blank position keeps the full selectable list.
bool tatApplicationMatchesSelectedPosition(
  Map<String, dynamic> row,
  String? position,
) {
  final wanted = (position ?? '').trim().toLowerCase();
  if (wanted.isEmpty) return true;
  return (row['position_applied_for'] ?? '').toString().trim().toLowerCase() ==
      wanted;
}

/// Search text for the Add Applicant field: name, applicant number, and position.
String tatApplicantChoiceSearchText({
  required String name,
  required String applicantNumber,
  required String position,
  required String statusLabel,
}) {
  return [name, applicantNumber, position, statusLabel]
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .join(' ');
}

/// Entry-level status derived from its named applicants — no new DB field.
String tatEntryStatus(TurnAroundTimeEntry e) {
  final named = e.applicants.where((a) => (a.name ?? '').trim().isNotEmpty).toList();
  if (named.isEmpty) return 'Draft';
  final allCompleted = named.every((a) => (a.dateAssumptionToDuty ?? '').trim().isNotEmpty);
  return allCompleted ? 'Completed' : 'In Progress';
}

DateTime? _tryParseTatDate(String raw) {
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
  const months = <String, int>{
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
    'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10,
    'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  };
  final named = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(s);
  if (named != null) {
    final month = months[named.group(1)!.toLowerCase()];
    final day = int.tryParse(named.group(2)!);
    final year = int.tryParse(named.group(3)!);
    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }
  return null;
}

const List<String> _tatMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatTatDate(DateTime date) {
  final d = date.toLocal();
  return '${_tatMonthNames[d.month - 1]} ${d.day}, ${d.year}';
}

/// Days between two form dates, or null if either is missing/unparseable.
int? _tatDaysBetween(String? startRaw, String? endRaw) {
  final start = _tryParseTatDate(startRaw ?? '');
  final end = _tryParseTatDate(endRaw ?? '');
  if (start == null || end == null) return null;
  return end.difference(start).inDays;
}

/// Formats a free-text cost value as Philippine peso when it parses as a
/// number; otherwise the original text is preserved (legacy manual entries).
String _formatTatPeso(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '—';
  final cleaned = t.replaceAll(RegExp(r'[^\d.]'), '');
  final v = double.tryParse(cleaned);
  if (v == null) return t;
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '\u20b1$buf.${parts[1]}';
}

/// Non-blocking chronology warnings for one applicant's dates. The existing
/// process allows unusual sequences, so these are advisory only.
List<String> _tatChronologyWarnings(Map<String, String> v) {
  final warnings = <String>[];
  final ia = _tryParseTatDate(v['date_initial_assessment'] ?? '');
  final ce = _tryParseTatDate(v['date_contract_exam'] ?? '');
  final del = _tryParseTatDate(v['date_deliberation'] ?? '');
  final jo = _tryParseTatDate(v['date_job_offer'] ?? '');
  final acc = _tryParseTatDate(v['acceptance_date'] ?? '');
  final asm = _tryParseTatDate(v['date_assumption_to_duty'] ?? '');
  if (ia != null && ce != null && ia.isAfter(ce)) {
    warnings.add('Initial Assessment is after the Exam date.');
  }
  if (ce != null && del != null && ce.isAfter(del)) {
    warnings.add('Exam date is after Deliberation.');
  }
  if (del != null && jo != null && del.isAfter(jo)) {
    warnings.add('Deliberation is after the Job Offer date.');
  }
  if (jo != null && acc != null && jo.isAfter(acc)) {
    warnings.add('Job Offer date is after Offer Accepted.');
  }
  if (acc != null && asm != null && acc.isAfter(asm)) {
    warnings.add('Offer Accepted date is after Assumption to Duty.');
  }
  return warnings;
}

/// RSP: Turn-Around Time — recruitment milestone tracking from publication
/// to assumption of duty (after Work Experience Sheet).
class RspTurnAroundTimeSection extends StatefulWidget {
  const RspTurnAroundTimeSection({super.key});

  @override
  State<RspTurnAroundTimeSection> createState() =>
      _RspTurnAroundTimeSectionState();
}

class _RspTurnAroundTimeSectionState extends State<RspTurnAroundTimeSection> {
  List<TurnAroundTimeEntry> _entries = [];
  bool _loading = true;
  TurnAroundTimeEntry? _editing;
  bool _requirementCompleted = false;
  String? _signatureStatus;
  bool _historyLoaded = false;
  List<Map<String, dynamic>> _edits = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TurnAroundTimeRepo.instance.list();
      if (!mounted) return;
      setState(() {
        _entries = visibleTurnAroundTimeEntries(list);
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

  Future<void> _startNew() async {
    try {
      final announcement = await JobVacancyAnnouncementRepo.instance.fetch();
      final applications = await RecruitmentRepo.instance.finalHiringSources();
      if (!mounted) return;
      final positions = _tatPositions(announcement, applications);
      _matchedVacancy = {
        for (final vacancy in announcement.listedVacancies)
          if ((vacancy.positionKey ?? '').trim().isNotEmpty)
            vacancy.positionKey!.trim().toLowerCase(): vacancy,
      };
      if (positions.isEmpty) {
        setState(() {
          _editing = const TurnAroundTimeEntry();
          _requirementCompleted = false;
          _signatureStatus = null;
          _historyLoaded = false;
          _edits = [];
        });
        return;
      }
      final choice = await _pickTatPosition(positions);
      if (!mounted || choice == null || choice == _cancelledTatChoice) return;
      if (choice == _blankTatChoice) {
        setState(() {
          _editing = const TurnAroundTimeEntry();
          _requirementCompleted = false;
          _signatureStatus = null;
          _historyLoaded = false;
          _edits = [];
        });
        return;
      }
      setState(() {
        _editing = _buildAutoPrefilledTat(choice);
        _requirementCompleted = false;
        _signatureStatus = null;
        _historyLoaded = false;
        _edits = [];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load vacancy data. ${userFacingApiError(e)}')),
      );
      setState(() {
        _editing = const TurnAroundTimeEntry();
        _requirementCompleted = false;
        _signatureStatus = null;
        _historyLoaded = false;
        _edits = [];
      });
    }
  }

  void _edit(TurnAroundTimeEntry e) {
    setState(() {
      _editing = e;
      _requirementCompleted = false;
      _signatureStatus = null;
      _historyLoaded = false;
      _edits = [];
    });
    _refreshTatCompletion();
    final id = e.id;
    if (id != null) _loadEditHistory(id);
  }

  void _cancelEdit() => setState(() {
    _editing = null;
    _requirementCompleted = false;
    _signatureStatus = null;
    _historyLoaded = false;
    _edits = [];
  });

  void _onSignaturesChanged(DocuTrackerSourceSignatureBundle bundle) {
    if (_editing?.id == null || bundle.sourceRecordId != _editing!.id) return;
    setState(() => _signatureStatus = bundle.sourceStatus);
  }

  Future<void> _loadEditHistory(String id) async {
    try {
      final edits = await RspLdSavedEntriesApi.editHistory(
        TurnAroundTimeEntry.tableName,
        id,
      );
      if (!mounted || _editing?.id != id) return;
      setState(() {
        _edits = edits;
        _historyLoaded = true;
      });
    } catch (_) {
      if (!mounted || _editing?.id != id) return;
      setState(() {
        _edits = [];
        _historyLoaded = true;
      });
    }
  }

  Future<void> _showEditHistory(String id) async {
    await _loadEditHistory(id);
    if (!mounted || _editing?.id != id) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit history'),
          content: SizedBox(
            width: 560,
            child: TurnAroundTimeEditHistoryView(edits: _edits),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshTatCompletion() async {
    final id = _editing?.id;
    if (id == null) return;
    try {
      final payload = await RecruitmentRepo.instance.turnAroundTimeCompletion(id);
      if (!mounted || _editing?.id != id) return;
      setState(() => _requirementCompleted = payload['allCompleted'] == true);
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _markTatCompleted() async {
    final id = _editing?.id;
    if (id == null || _requirementCompleted) return;
    try {
      await RecruitmentRepo.instance.completeTurnAroundTimeEntry(id);
      if (!mounted) return;
      setState(() => _requirementCompleted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn-Around Time marked completed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    }
  }

  static const _cancelledTatChoice = '__cancel__';
  static const _blankTatChoice = '__blank__';

  bool _sameTatPosition(String? a, String? b) {
    final left = (a ?? '').trim().toLowerCase();
    final right = (b ?? '').trim().toLowerCase();
    return left.isNotEmpty && left == right;
  }

  List<String> _tatPositions(
    JobVacancyAnnouncement announcement,
    List<Map<String, dynamic>> applications,
  ) {
    final titles = <String>[];
    void add(String? raw) {
      final title = (raw ?? '').trim();
      if (title.isEmpty) return;
      if (titles.any((existing) => _sameTatPosition(existing, title))) return;
      titles.add(title);
    }

    for (final vacancy in announcement.listedVacancies) {
      add(vacancy.positionKey);
    }
    for (final app in applications) {
      add(app['position_applied_for']?.toString());
    }
    return titles;
  }

  String _qualificationStandard(JobVacancyItem vacancy) {
    final parts = <String>[];
    void add(String label, String? value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return;
      parts.add('$label: $text');
    }

    add('Education', vacancy.education);
    add('Experience', vacancy.experience);
    add('Training', vacancy.training);
    if (parts.isNotEmpty) return parts.join('\n');
    return (vacancy.body ?? '').trim();
  }

  TurnAroundTimeEntry _buildAutoPrefilledTat(String position) {
    final vacancy = _matchedVacancy[position.trim().toLowerCase()];
    final qs = vacancy == null ? null : _qualificationStandard(vacancy);
    return turnAroundTimeEntryFromVacancy(
      position: position,
      noOfVacantPosition: vacancy?.maxApplicants?.toString(),
      endSearch: vacancy?.closingDate == null
          ? null
          : _formatTatDate(vacancy!.closingDate!),
      qualificationStandard: qs,
    );
  }

  Map<String, JobVacancyItem> _matchedVacancy = {};

  Future<String?> _pickTatPosition(List<String> positions) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select vacancy'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final position in positions)
                ListTile(
                  title: Text(position),
                  onTap: () => Navigator.of(ctx).pop(position),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_blankTatChoice),
            child: const Text('Blank form'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_cancelledTatChoice),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSave(TurnAroundTimeEntry entry) async {
    try {
      if (entry.id == null) {
        await TurnAroundTimeRepo.instance.insert(entry);
      } else {
        await TurnAroundTimeRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn-around time saved.')),
      );
      setState(() {
        _editing = null;
        _signatureStatus = null;
        _historyLoaded = false;
        _edits = [];
      });
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
      await TurnAroundTimeRepo.instance.delete(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _print(TurnAroundTimeEntry entry) async {
    try {
      final signatureProvider = context.read<DocuTrackerProvider>();
      final signatures = entry.id == null
          ? null
          : await signatureProvider.loadSourceSignatures(
              sourceModule: 'rsp',
              sourceTable: TurnAroundTimeEntry.tableName,
              sourceRecordId: entry.id!,
            );
      if (entry.id != null && signatures == null) {
        throw StateError(
          signatureProvider.sourceSignatureError ??
              'The form signatures could not be loaded.',
        );
      }
      if (!mounted) return;
      await FormPdf.printForm(
        context: context,
        buildDocument: () =>
            FormPdf.buildTurnAroundTimePdf(entry, signatures: signatures),
        filename: 'Turn_Around_Time.pdf',
        format: FormPdf.pageLetterLandscape,
        printModule: 'rsp',
        printFormKey: 'turn_around_time',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed. ${userFacingApiError(error)}')),
      );
    }
  }

  Future<void> _preview(TurnAroundTimeEntry entry) {
    return openFormDocumentPreview(
      context: context,
      title: 'Turn Around Time',
      filename: 'Turn_Around_Time.pdf',
      format: FormPdf.pageLetterLandscape,
      printModule: 'rsp',
      printFormKey: 'turn_around_time',
      buildDocument: () async {
        final signatureProvider = context.read<DocuTrackerProvider>();
        final signatures = entry.id == null
            ? null
            : await signatureProvider.loadSourceSignatures(
                sourceModule: 'rsp',
                sourceTable: TurnAroundTimeEntry.tableName,
                sourceRecordId: entry.id!,
              );
        if (entry.id != null && signatures == null) {
          throw StateError(
            signatureProvider.sourceSignatureError ??
                'The form signatures could not be loaded.',
          );
        }
        return FormPdf.buildTurnAroundTimePdf(entry, signatures: signatures);
      },
    );
  }

  Future<void> _download(TurnAroundTimeEntry entry) async {
    try {
      final signatureProvider = context.read<DocuTrackerProvider>();
      final signatures = entry.id == null
          ? null
          : await signatureProvider.loadSourceSignatures(
              sourceModule: 'rsp',
              sourceTable: TurnAroundTimeEntry.tableName,
              sourceRecordId: entry.id!,
            );
      if (entry.id != null && signatures == null) {
        throw StateError(
          signatureProvider.sourceSignatureError ??
              'The form signatures could not be loaded.',
        );
      }
      final doc = await FormPdf.buildTurnAroundTimePdf(
        entry,
        signatures: signatures,
      );
      await FormPdf.sharePdf(doc, name: 'Turn_Around_Time.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF ready to save or share.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('Download failed. ${userFacingApiError(e)}')),
      );
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved turn-around time records',
      emptyMessage: 'No entries yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.position?.trim().isNotEmpty == true
            ? e.position!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle: '${e.office ?? "—"} · ${e.applicants.length} applicant(s)',
          detailDialogTitle: 'Turn-around time — $pos',
          previewContentWidth: 1100,
          previewBuilder: () => TurnAroundTimeEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _print(e),
          onDocumentPreview: () => _preview(e),
          onEdit: () => _edit(e),
          onDelete: e.id == null ? null : () => _onDelete(e.id!),
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
          onPressed: _loading ? null : () => _startNew(),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add Turn-Around Time'),
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
        if (_editing != null)
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RspLdFormHeader(
          module: 'RSP',
          title: 'Turn-Around Time',
          subtitle:
              'Track recruitment milestones from publication to assumption of duty.',
          actions: _toolbar(context),
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          TurnAroundTimeEditor(
            key: ValueKey('${_editing?.id ?? 'new'}-$_requirementCompleted'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _print,
            onPreview: _preview,
            onDownloadPdf: _download,
            requirementCompleted: _requirementCompleted,
            onMarkCompleted: _editing?.id == null ? null : _markTatCompleted,
          ),
          if (_editing?.id != null) ...[
            const SizedBox(height: 16),
            DocuTrackerRspSignatureSection(
              sourceTable: TurnAroundTimeEntry.tableName,
              sourceRecordId: _editing!.id!,
              signatureStatus: _signatureStatus,
              onChanged: _onSignaturesChanged,
              helperText:
                  'Prepared by is the form creator and signs first. Noted by is the HRMDO official and signs second. The form stays editable. A real content change asks both to sign again.',
              slots: const [
                DocuTrackerRspSignatureSlot('prepared_by', 'Prepared by'),
                DocuTrackerRspSignatureSlot('noted_by', 'Noted by'),
              ],
            ),
            if (_historyLoaded &&
                tatSignaturesNeedRenewal(
                  signatureStatus: _signatureStatus,
                  edits: _edits,
                ))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Signatures need renewal because the form was updated.',
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showEditHistory(_editing!.id!),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('View edit history'),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ] else ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_entries.isEmpty)
            const RspFormEmptyState(
              message:
                  'No turn-around time entries yet. Tap "Add Turn-Around Time" to add one.',
              icon: Icons.schedule_rounded,
            )
          else
            _TurnAroundTimeList(
              entries: _entries,
              onEdit: _edit,
              onDelete: _onDelete,
              onPrint: _print,
              onDownloadPdf: _download,
            ),
        ],
      ],
    );
  }
}

/// Screen editor for a Turn-Around Time record.
///
/// This widget renders a modern HRMS recruitment-tracking experience only.
/// It is intentionally NOT styled like the official printed form — the
/// print/PDF output (see [FormPdf.buildTurnAroundTimePdf]) is a fully
/// independent template that reads the same [TurnAroundTimeEntry] data
/// produced here.
class TurnAroundTimeEditor extends StatefulWidget {
  const TurnAroundTimeEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    this.onPreview,
    required this.onDownloadPdf,
    this.requirementCompleted = false,
    this.onMarkCompleted,
    this.loadLinkableApplications,
  });

  final TurnAroundTimeEntry entry;
  final bool readOnly;
  final void Function(TurnAroundTimeEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(TurnAroundTimeEntry) onPrint;
  final Future<void> Function(TurnAroundTimeEntry)? onPreview;
  final Future<void> Function(TurnAroundTimeEntry) onDownloadPdf;
  final bool requirementCompleted;
  final Future<void> Function()? onMarkCompleted;

  /// Recruitment applications HR may attach while adding an applicant.
  /// Defaults to the final-hiring source list. Tests can supply a fixed list.
  final Future<List<Map<String, dynamic>>> Function()? loadLinkableApplications;

  @override
  State<TurnAroundTimeEditor> createState() => _TurnAroundTimeEditorState();
}

class _TurnAroundTimeEditorState extends State<TurnAroundTimeEditor> {
  late TextEditingController _position;
  late TextEditingController _office;
  late TextEditingController _noOfVacantPosition;
  late TextEditingController _dateOfPublication;
  late TextEditingController _endSearch;
  late TextEditingController _qs;
  late TextEditingController _preparedByName;
  late TextEditingController _preparedByTitle;
  late TextEditingController _notedByName;
  late TextEditingController _notedByTitle;

  /// Each applicant's field values, keyed by the same names as the official
  /// form columns (see [_tatRowKeys]).
  late List<Map<String, String>> _applicants;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _positionError;
  String? _officeError;

  bool get _creating => widget.entry.id == null && !widget.readOnly;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _position = TextEditingController(text: e.position ?? '');
    _office = TextEditingController(text: e.office ?? '');
    _noOfVacantPosition = TextEditingController(text: e.noOfVacantPosition ?? '');
    _dateOfPublication = TextEditingController(text: e.dateOfPublication ?? '');
    _endSearch = TextEditingController(text: e.endSearch ?? '');
    _qs = TextEditingController(text: e.qs ?? '');
    _preparedByName = TextEditingController(text: e.preparedByName ?? '');
    _preparedByTitle = TextEditingController(text: e.preparedByTitle ?? '');
    _notedByName = TextEditingController(text: e.notedByName ?? '');
    _notedByTitle = TextEditingController(text: e.notedByTitle ?? '');
    _applicants = e.applicants.map(_tatValuesFromApplicant).toList();
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    for (final c in [
      _position,
      _office,
      _noOfVacantPosition,
      _dateOfPublication,
      _endSearch,
      _qs,
      _preparedByName,
      _preparedByTitle,
      _notedByName,
      _notedByTitle,
      _search,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  TurnAroundTimeEntry _buildEntry() {
    return TurnAroundTimeEntry(
      id: widget.entry.id,
      position: _opt(_position),
      office: _opt(_office),
      noOfVacantPosition: _opt(_noOfVacantPosition),
      dateOfPublication: _opt(_dateOfPublication),
      endSearch: _opt(_endSearch),
      qs: _opt(_qs),
      applicants: _applicants.map(_tatApplicantFromValues).toList(),
      preparedByName: _opt(_preparedByName),
      preparedByTitle: _opt(_preparedByTitle),
      notedByName: _opt(_notedByName),
      notedByTitle: _opt(_notedByTitle),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  bool _validateCreateFields() {
    final positionError =
        _position.text.trim().isEmpty ? 'Position is required.' : null;
    final officeError =
        _office.text.trim().isEmpty ? 'Office is required.' : null;
    setState(() {
      _positionError = positionError;
      _officeError = officeError;
    });
    return positionError == null && officeError == null;
  }

  void _save() {
    if (widget.readOnly) return;
    if (widget.entry.id == null && !_validateCreateFields()) return;
    widget.onSave(_buildEntry());
  }

  Future<void> _pickHeaderDate(TextEditingController c) async {
    if (widget.readOnly) return;
    final now = DateTime.now();
    final parsed = _tryParseTatDate(c.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() => c.text = _formatTatDate(picked));
  }

  Future<void> _addApplicant() async {
    final load = widget.loadLinkableApplications ??
        RecruitmentRepo.instance.tatApplicantChoices;
    final result = await _showApplicantEditorDialog(
      context,
      initial: _emptyTatValues(),
      isNew: true,
      applicationsFuture: load(),
      selectedPosition: _position.text,
    );
    if (result == null || !mounted) return;
    if (tatApplicantIdAlreadyTracked(_applicants, result['application_id'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This applicant is already on the form.')),
      );
      return;
    }
    setState(() => _applicants.add(result));
  }

  Future<void> _editApplicant(int i) async {
    final result = await _showApplicantEditorDialog(
      context,
      initial: Map<String, String>.from(_applicants[i]),
      isNew: false,
    );
    if (result == null || !mounted) return;
    final kept = (_applicants[i]['application_id'] ?? '').trim();
    setState(() {
      _applicants[i] = result;
      if (kept.isNotEmpty) _applicants[i]['application_id'] = kept;
    });
  }

  Future<void> _confirmRemoveApplicant(int i) async {
    final name = _applicants[i]['name']?.trim() ?? '';
    final label = name.isEmpty ? 'Applicant ${i + 1}' : name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove applicant?'),
        content: Text(
          'Are you sure you want to remove $label? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _applicants.removeAt(i));
    }
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
    String? errorText,
    Widget? suffixIcon,
    Widget? prefixIcon,
  }) => AppTheme.dashInputDecoration(
    context,
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
  ).copyWith(errorText: errorText);

  Widget _textField(
    TextEditingController c,
    String label,
    bool ro, {
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: c,
      readOnly: ro,
      onChanged: onChanged,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: _decoration(
        context,
        label: label,
        hint: hint,
        errorText: errorText,
      ),
    );
  }

  Widget _headerDateField(TextEditingController c, String label, bool ro) {
    return TextFormField(
      controller: c,
      readOnly: true,
      onTap: ro ? null : () => _pickHeaderDate(c),
      decoration: _decoration(
        context,
        label: label,
        hint: ro ? null : 'Select date',
        suffixIcon: ro
            ? null
            : IconButton(
                tooltip: 'Pick date',
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                onPressed: () => _pickHeaderDate(c),
              ),
      ),
    );
  }

  Widget _responsivePairs(List<(Widget, Widget)> pairs, {double breakpoint = 640}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > breakpoint;
        final rows = pairs.map((pair) {
          final (a, b) = pair;
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 14),
                    Expanded(child: b),
                  ],
                )
              : Column(children: [a, const SizedBox(height: 14), b]);
        }).toList();
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              rows[i],
            ],
          ],
        );
      },
    );
  }

  Widget _infoCard({
    required BuildContext context,
    required String title,
    required List<(Widget, Widget)> pairs,
  }) {
    return Container(
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
          _responsivePairs(pairs),
        ],
      ),
    );
  }

  Future<void> _pickFromOpenPosition() async {
    final selected = await showDialog<JobVacancyItem>(
      context: context,
      builder: (ctx) => const _OpenPositionPickerDialog(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final headline = selected.headline?.trim();
      if (headline != null && headline.isNotEmpty) {
        _position.text = headline;
        _positionError = null;
      }
      if (_endSearch.text.trim().isEmpty && selected.closingDate != null) {
        _endSearch.text = _formatTatDate(selected.closingDate!);
      }
    });
  }

  Widget _positionField(bool ro) {
    return TextFormField(
      controller: _position,
      readOnly: ro,
      onChanged: _creating
          ? (_) {
              if (_positionError != null) setState(() => _positionError = null);
            }
          : null,
      decoration: _decoration(
        context,
        label: _creating ? 'Position *' : 'Position',
        hint: 'e.g. Administrative Officer II',
        errorText: _positionError,
        suffixIcon: ro
            ? null
            : IconButton(
                tooltip: 'Prefill from an open job vacancy',
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                onPressed: _pickFromOpenPosition,
              ),
      ),
    );
  }

  Widget _vacancyInformationCard(BuildContext context, bool ro) {
    return _infoCard(
      context: context,
      title: 'VACANCY INFORMATION',
      pairs: [
        (
          _positionField(ro),
          _textField(
            _office,
            _creating ? 'Office *' : 'Office',
            ro,
            hint: 'e.g. Office of the Municipal Mayor',
            errorText: _officeError,
            onChanged: _creating
                ? (_) {
                    if (_officeError != null) {
                      setState(() => _officeError = null);
                    }
                  }
                : null,
          ),
        ),
        (
          _textField(
            _noOfVacantPosition,
            'No. of Vacancies',
            ro,
            hint: 'e.g. 1',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _textField(_qs, 'Qualification Standard', ro, hint: 'e.g. Q.S. code'),
        ),
        (
          _headerDateField(_dateOfPublication, 'Date of Publication', ro),
          _headerDateField(_endSearch, 'End Search', ro),
        ),
      ],
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _headerBar(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final position = _position.text.trim();
    final title = position.isEmpty ? 'New Turn-Around Time' : position;
    final entryStatus = tatEntryStatus(_buildEntry());
    final statusLabel = ro ? 'Read-only preview' : entryStatus;
    final statusColor = ro ? Colors.blueGrey : _tatStatusColor(entryStatus);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statusChip(statusLabel, statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Track recruitment milestones from publication to assumption of duty.',
                  style: TextStyle(fontSize: 12.5, color: secondary),
                ),
              ],
            ),
          ),
          _actionBar(context, ro),
        ],
      ),
    );
  }

  Widget _applicantTrackingHeader(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final count = _applicants.length;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 16,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Applicant Tracking',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: primary),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count ${count == 1 ? 'Applicant' : 'Applicants'}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.primaryNavy),
              ),
            ),
          ],
        ),
        if (!ro)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
            child: TextField(
              controller: _search,
              decoration: _decoration(
                context,
                hint: 'Search applicants...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
        if (!ro)
          FilledButton.icon(
            onPressed: _addApplicant,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Applicant'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy),
          ),
      ],
    );
  }

  List<int> get _filteredIndices {
    if (_query.isEmpty) return List.generate(_applicants.length, (i) => i);
    final out = <int>[];
    for (var i = 0; i < _applicants.length; i++) {
      final name = (_applicants[i]['name'] ?? '').toLowerCase();
      if (name.contains(_query)) out.add(i);
    }
    return out;
  }

  Widget _applicantsBody(BuildContext context, bool ro) {
    if (_applicants.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 32,
              color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            Text(
              ro
                  ? 'No applicants recorded.'
                  : 'No applicants added yet. Click Add Applicant to manually include applicants in this Turn-Around Time form.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppTheme.dashTextSecondaryOf(context)),
            ),
          ],
        ),
      );
    }
    final indices = _filteredIndices;
    if (indices.isEmpty) {
      return RspFormEmptyState(
        message: 'No applicants match "${_search.text.trim()}".',
        icon: Icons.search_off_rounded,
      );
    }
    return Column(
      children: [
        for (var pos = 0; pos < indices.length; pos++) ...[
          if (pos > 0) const SizedBox(height: 14),
          _ApplicantTrackingCard(
            index: indices[pos],
            values: _applicants[indices[pos]],
            readOnly: ro,
            onEdit: ro ? null : () => _editApplicant(indices[pos]),
            onRemove: ro ? null : () => _confirmRemoveApplicant(indices[pos]),
          ),
        ],
      ],
    );
  }

  Widget _signatureSpace(BuildContext context) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 8),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.dashHairlineOf(context))),
      ),
    );
  }

  Widget _signatoryCard(
    BuildContext context, {
    required String title,
    required TextEditingController name,
    required TextEditingController role,
    required bool ro,
    required String nameHint,
    required String roleHint,
  }) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.dashSectionTitle(context)),
            const SizedBox(height: 10),
            _signatureSpace(context),
            ro
                ? Text(
                    name.text.trim().isEmpty ? '—' : name.text.trim(),
                    style: TextStyle(color: primary, fontWeight: FontWeight.w700),
                  )
                : TextFormField(
                    controller: name,
                    onChanged: (_) => setState(() {}),
                    decoration: _decoration(context, hint: nameHint),
                    style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
            const SizedBox(height: 8),
            ro
                ? Text(
                    role.text.trim().isEmpty ? '—' : role.text.trim(),
                    style: TextStyle(color: secondary, fontSize: 12),
                  )
                : TextFormField(
                    controller: role,
                    decoration: _decoration(context, hint: roleHint),
                    style: TextStyle(color: secondary, fontSize: 12.5),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _preparedNotedByRow(BuildContext context, bool ro) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 560;
        final preparedBy = _signatoryCard(
          context,
          title: 'PREPARED BY',
          name: _preparedByName,
          role: _preparedByTitle,
          ro: ro,
          nameHint: 'Printed name / over signature',
          roleHint: 'e.g. HRMO Staff',
        );
        final notedBy = _signatoryCard(
          context,
          title: 'NOTED BY',
          name: _notedByName,
          role: _notedByTitle,
          ro: ro,
          nameHint: 'Printed name / over signature',
          roleHint: 'e.g. HRMO III',
        );
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [preparedBy, const SizedBox(width: 14), notedBy],
              )
            : Column(
                children: [preparedBy, const SizedBox(height: 14), notedBy],
              );
      },
    );
  }

  Widget _actionBar(BuildContext context, bool ro) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!ro) ...[
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel'),
          ),
          if (widget.entry.id != null &&
              widget.onMarkCompleted != null &&
              !widget.requirementCompleted)
            FilledButton.icon(
              onPressed: widget.onMarkCompleted,
              icon: const Icon(Icons.task_alt_rounded, size: 18),
              label: const Text('Mark Completed'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
        ],
        if (widget.requirementCompleted)
          const Chip(
            avatar: Icon(Icons.check_circle, size: 18, color: Color(0xFF2E7D32)),
            label: Text('Completed'),
          ),
        if (widget.onPreview != null)
          FormPreviewPrintButtons(
            onPreview: () => widget.onPreview!(_buildEntry()),
            onPrint: () => widget.onPrint(_buildEntry()),
          )
        else
          RspLdBusyIconButton(
            tooltip: 'Print Form',
            icon: Icons.print_rounded,
            busyTooltip: 'Preparing print…',
            onPressed: () => widget.onPrint(_buildEntry()),
          ),
        IconButton(
          tooltip: 'Export PDF',
          style: rspLdRecordIconButtonStyle(),
          onPressed: () => widget.onDownloadPdf(_buildEntry()),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerBar(context, ro),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _vacancyInformationCard(context, ro),
                const SizedBox(height: 24),
                _applicantTrackingHeader(context, ro),
                const SizedBox(height: 14),
                _applicantsBody(context, ro),
                const SizedBox(height: 20),
                _preparedNotedByRow(context, ro),
                if (ro && (widget.entry.createdAt != null || widget.entry.updatedAt != null)) ...[
                  const SizedBox(height: 16),
                  if (widget.entry.createdAt != null)
                    Text(
                      'Created: ${widget.entry.createdAt!.toLocal()}',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  if (widget.entry.updatedAt != null)
                    Text(
                      'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recruitment tracking row for one applicant — desktop shows a horizontal
/// milestone timeline, narrow screens fall back to a vertical timeline.
class _ApplicantTrackingCard extends StatelessWidget {
  const _ApplicantTrackingCard({
    required this.index,
    required this.values,
    required this.readOnly,
    this.onEdit,
    this.onRemove,
  });

  final int index;
  final Map<String, String> values;
  final bool readOnly;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  String _milestoneDisplay(_TatMilestone m) {
    final raw = (values[m.key] ?? '').trim();
    if (raw.isEmpty) return '—';
    if (!m.isDate) return raw;
    final parsed = _tryParseTatDate(raw);
    return parsed != null ? _formatTatDate(parsed) : raw;
  }

  Widget _metricBadge({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.85)),
              ),
              Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _milestoneItem(BuildContext context, _TatMilestone m, {required bool filled}) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final color = filled ? AppTheme.primaryNavy : secondary.withValues(alpha: 0.5);
    return SizedBox(
      width: 128,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? AppTheme.primaryNavy.withValues(alpha: 0.14) : AppTheme.dashMutedSurfaceOf(context),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: filled ? 0.4 : 0.3)),
            ),
            child: Icon(m.icon, size: 15, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            m.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: secondary),
          ),
          const SizedBox(height: 2),
          Text(
            _milestoneDisplay(m),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
              color: filled ? primary : secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _horizontalTimeline(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _tatMilestones.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.4),
                ),
              ),
            _milestoneItem(
              context,
              _tatMilestones[i],
              filled: (values[_tatMilestones[i].key] ?? '').trim().isNotEmpty,
            ),
          ],
        ],
      ),
    );
  }

  Widget _verticalTimeline(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _tatMilestones.length; i++) ...[
          _VerticalTimelineRow(
            milestone: _tatMilestones[i],
            display: _milestoneDisplay(_tatMilestones[i]),
            filled: (values[_tatMilestones[i].key] ?? '').trim().isNotEmpty,
            isLast: i == _tatMilestones.length - 1,
            secondary: secondary,
            primary: primary,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _tatApplicantStatus(values);
    final statusColor = _tatStatusColor(status);
    final name = (values['name'] ?? '').trim();
    final daysRaw = (values['no_of_days_to_fill_up'] ?? '').trim();
    final costRaw = (values['overall_cost_per_hire'] ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.primaryNavy),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Applicant ${index + 1}' : name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.32)),
                ),
                child: Text(
                  status,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 700;
              return desktop ? _horizontalTimeline(context) : _verticalTimeline(context);
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricBadge(
                context: context,
                icon: Icons.timer_outlined,
                label: 'DAYS TO FILL',
                value: daysRaw.isEmpty ? '—' : '$daysRaw days',
                color: const Color(0xFF6A1B9A),
              ),
              _metricBadge(
                context: context,
                icon: Icons.payments_outlined,
                label: 'COST PER HIRE',
                value: _formatTatPeso(costRaw),
                color: const Color(0xFF2E7D32),
              ),
            ],
          ),
          if (!readOnly) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('View / Edit'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red.shade700),
                  label: Text('Remove', style: TextStyle(color: Colors.red.shade700)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VerticalTimelineRow extends StatelessWidget {
  const _VerticalTimelineRow({
    required this.milestone,
    required this.display,
    required this.filled,
    required this.isLast,
    required this.secondary,
    required this.primary,
  });

  final _TatMilestone milestone;
  final String display;
  final bool filled;
  final bool isLast;
  final Color secondary;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final color = filled ? AppTheme.primaryNavy : secondary.withValues(alpha: 0.5);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: filled ? AppTheme.primaryNavy.withValues(alpha: 0.14) : AppTheme.dashMutedSurfaceOf(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: filled ? 0.4 : 0.3)),
                ),
                child: Icon(milestone.icon, size: 13, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppTheme.dashHairlineOf(context)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: secondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    display,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                      color: filled ? primary : secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TatLinkableApplication {
  const _TatLinkableApplication({
    required this.id,
    required this.name,
    required this.label,
    required this.searchText,
  });

  final String id;
  final String name;
  final String label;
  final String searchText;
}

List<_TatLinkableApplication> _tatLinkableApplications(
  List<Map<String, dynamic>> rows,
) {
  final usedLabels = <String>{};
  final choices = <_TatLinkableApplication>[];
  for (final row in rows) {
    final id = (row['id'] ?? '').toString().trim();
    final name = (row['full_name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) continue;
    final number = (row['applicant_number'] ?? '').toString().trim();
    final position = (row['position_applied_for'] ?? '').toString().trim();
    final statusLabel = RspApplicationsReportExport.statusDisplayLabel(
      (row['status'] ?? '').toString(),
    );
    final parts = <String>[
      name,
      if (number.isNotEmpty) number,
      if (position.isNotEmpty) position,
      if (statusLabel.isNotEmpty && statusLabel != '-') statusLabel,
    ];
    var label = parts.join(' · ');
    if (!usedLabels.add(label)) {
      label = '$label ($id)';
      usedLabels.add(label);
    }
    choices.add(
      _TatLinkableApplication(
        id: id,
        name: name,
        label: label,
        searchText: tatApplicantChoiceSearchText(
          name: name,
          applicantNumber: number,
          position: position,
          statusLabel: statusLabel,
        ),
      ),
    );
  }
  return choices;
}

Future<Map<String, String>?> _showApplicantEditorDialog(
  BuildContext context, {
  required Map<String, String> initial,
  required bool isNew,
  Future<List<Map<String, dynamic>>>? applicationsFuture,
  String? selectedPosition,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ApplicantEditorDialog(
      initial: initial,
      isNew: isNew,
      applicationsFuture: applicationsFuture,
      selectedPosition: selectedPosition,
    ),
  );
}

/// Add / Edit Applicant modal — organizes fields as Applicant, Recruitment
/// Timeline, and Hiring Metrics per the redesigned RSP UX.
class _ApplicantEditorDialog extends StatefulWidget {
  const _ApplicantEditorDialog({
    required this.initial,
    required this.isNew,
    this.applicationsFuture,
    this.selectedPosition,
  });

  final Map<String, String> initial;
  final bool isNew;
  final Future<List<Map<String, dynamic>>>? applicationsFuture;
  final String? selectedPosition;

  @override
  State<_ApplicantEditorDialog> createState() => _ApplicantEditorDialogState();
}

class _ApplicantEditorDialogState extends State<_ApplicantEditorDialog> {
  late final Map<String, TextEditingController> _c;
  List<_TatLinkableApplication> _choices = const [];
  String? _nameError;
  String? _linkedApplicationId;
  String? _linkedLabel;
  bool _loadingChoices = false;
  String? _choiceError;

  @override
  void initState() {
    super.initState();
    _c = {
      for (final k in _tatRowKeys) k: TextEditingController(text: widget.initial[k] ?? ''),
    };
    final existingId = (widget.initial['application_id'] ?? '').trim();
    if (existingId.isNotEmpty) _linkedApplicationId = existingId;
    for (final c in _c.values) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    if (widget.isNew && widget.applicationsFuture != null) {
      _loadingChoices = true;
      _loadChoices();
    }
  }

  Future<void> _loadChoices() async {
    try {
      final rows = await widget.applicationsFuture!;
      if (!mounted) return;
      final position = widget.selectedPosition;
      setState(() {
        _choices = _tatLinkableApplications([
          for (final row in rows)
            if (tatApplicationMatchesSelectedPosition(row, position)) row,
        ]);
        _loadingChoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _choiceError = 'Failed to load applicants.';
        _loadingChoices = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickMilestoneDate(String key) async {
    final now = DateTime.now();
    final parsed = _tryParseTatDate(_c[key]!.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() => _c[key]!.text = _formatTatDate(picked));
  }

  void _calculateDaysToFill() {
    final startText = _c['date_initial_assessment']!.text.trim();
    final endText = _c['date_assumption_to_duty']!.text.trim();
    final days = _tatDaysBetween(
      startText.isEmpty ? null : startText,
      endText.isEmpty ? null : endText,
    );
    if (days == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add Initial Assessment and Assumption to Duty dates first.'),
        ),
      );
      return;
    }
    setState(() => _c['no_of_days_to_fill_up']!.text = days.abs().toString());
  }

  void _save() {
    final name = _c['name']!.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      return;
    }
    Navigator.of(context).pop({
      for (final e in _c.entries) e.key: e.value.text.trim(),
      if ((_linkedApplicationId ?? '').trim().isNotEmpty)
        'application_id': _linkedApplicationId!.trim(),
    });
  }

  void _onApplicationPicked(String? label) {
    final picked = label?.trim() ?? '';
    _TatLinkableApplication? match;
    for (final choice in _choices) {
      if (choice.label == picked) {
        match = choice;
        break;
      }
    }
    setState(() {
      if (match == null) {
        _linkedApplicationId = null;
        _linkedLabel = null;
        return;
      }
      _linkedApplicationId = match.id;
      _linkedLabel = match.label;
      _c['name']!.text = match.name;
      _nameError = null;
    });
  }

  InputDecoration _decoration(BuildContext context, {String? label, String? hint, Widget? suffixIcon, Widget? prefixIcon}) =>
      AppTheme.dashInputDecoration(context, labelText: label, hintText: hint, suffixIcon: suffixIcon, prefixIcon: prefixIcon);

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(text, style: AppTheme.dashSectionTitle(context)),
    );
  }

  Widget _milestoneField(BuildContext context, _TatMilestone m) {
    final c = _c[m.key]!;
    if (!m.isDate) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          decoration: _decoration(context, label: m.label, hint: 'e.g. Passed / 85%'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        readOnly: true,
        onTap: () => _pickMilestoneDate(m.key),
        decoration: _decoration(
          context,
          label: m.label,
          hint: 'Select date',
          suffixIcon: IconButton(
            tooltip: 'Pick date',
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            onPressed: () => _pickMilestoneDate(m.key),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final values = {for (final e in _c.entries) e.key: e.value.text};
    final warnings = _tatChronologyWarnings(values);
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width < 620 ? size.width - 32 : 560.0;
    final maxH = size.height - 80;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isNew ? 'Add Applicant' : 'Edit Applicant',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.dashTextPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('APPLICANT', style: AppTheme.dashSectionTitle(context)),
                    const SizedBox(height: 10),
                    if (widget.isNew && _loadingChoices)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (widget.isNew && _choiceError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _choiceError!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),
                    if (widget.isNew && !_loadingChoices && _choiceError == null && _choices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'No matching applicants.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    if (widget.isNew && _choices.isNotEmpty) ...[
                      SearchableDropdownField(
                        options: [for (final choice in _choices) choice.label],
                        value: _linkedLabel,
                        searchText: (label) {
                          for (final choice in _choices) {
                            if (choice.label == label) return choice.searchText;
                          }
                          return label;
                        },
                        onChanged: _onApplicationPicked,
                        decoration: _decoration(
                          context,
                          label: 'Recruitment application',
                          hint: 'Search name, applicant number, or position',
                        ),
                      ),
                      if (_linkedApplicationId != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 6),
                          child: Text(
                            'This row keeps the selected application id.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _c['name'],
                      decoration: _decoration(
                        context,
                        label: 'Name of Applicant',
                        hint: widget.isNew && _linkedApplicationId == null
                            ? 'Name only. This does not update Applicant Monitoring.'
                            : 'Full name',
                      ).copyWith(errorText: _nameError),
                      onChanged: (_) {
                        if (_nameError != null) setState(() => _nameError = null);
                      },
                    ),
                    _sectionLabel(context, 'RECRUITMENT TIMELINE'),
                    for (final m in _tatMilestones) _milestoneField(context, m),
                    if (warnings.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade800),
                                const SizedBox(width: 6),
                                Text(
                                  'Unusual date sequence',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.amber.shade900),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final w in warnings)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '• $w',
                                  style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                                ),
                              ),
                          ],
                        ),
                      ),
                    _sectionLabel(context, 'HIRING METRICS'),
                    TextFormField(
                      controller: _c['no_of_days_to_fill_up'],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _decoration(
                        context,
                        label: 'No. of Days to Fill-Up Position',
                        hint: 'e.g. 30',
                        suffixIcon: TextButton(
                          onPressed: _calculateDaysToFill,
                          child: const Text('Calculate', style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _c['overall_cost_per_hire'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: _decoration(
                        context,
                        label: 'Overall Cost per Hire',
                        hint: '0.00',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 6),
                          child: Align(
                            widthFactor: 1,
                            child: Text('\u20b1', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy),
                    child: const Text('Save Applicant'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets HR reuse an already-listed job vacancy's Position (and End Search,
/// if set) instead of retyping it — avoids duplicate vacancy data entry.
class _OpenPositionPickerDialog extends StatelessWidget {
  const _OpenPositionPickerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pick an open position',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.dashTextPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Flexible(
              child: FutureBuilder<JobVacancyAnnouncement>(
                future: JobVacancyAnnouncementRepo.instance.fetch(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final listed = snapshot.data?.listedVacancies ?? const [];
                  if (listed.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No open job vacancies are currently listed on Job Vacancies.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: listed.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: AppTheme.dashHairlineOf(context),
                    ),
                    itemBuilder: (ctx, i) {
                      final v = listed[i];
                      final closing = v.closingDate;
                      return ListTile(
                        title: Text(
                          v.headline ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: closing != null
                            ? Text('Closes ${_formatTatDate(closing)}')
                            : null,
                        onTap: () => Navigator.of(context).pop(v),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnAroundTimeList extends StatelessWidget {
  const _TurnAroundTimeList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<TurnAroundTimeEntry> entries;
  final void Function(TurnAroundTimeEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(TurnAroundTimeEntry) onPrint;
  final Future<void> Function(TurnAroundTimeEntry) onDownloadPdf;

  Widget _statusCell(BuildContext context, String status) {
    final color = _tatStatusColor(status);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          status,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Position', flex: 2.2),
      RspRecordsColumn('Office', flex: 1.8),
      RspRecordsColumn('Applicants', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Status', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, e.position ?? '', bold: true),
              rspRecordsTextCell(context, e.office ?? ''),
              rspRecordsTextCell(
                context,
                '${e.applicants.length}',
                align: TextAlign.center,
                bold: true,
              ),
              _statusCell(context, tatEntryStatus(e)),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Turn-around time',
                  subtitle: '${e.position ?? ''} ┬╖ ${e.office ?? ''}',
                  previewBuilder: () => TurnAroundTimeEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 1100,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete entry?',
              ),
            ],
          )
          .toList(),
    );
  }
}

/// True when a saved revision cleared signatures and they are not complete again.
bool tatSignaturesNeedRenewal({
  required String? signatureStatus,
  required List<Map<String, dynamic>> edits,
}) {
  if (signatureStatus == null || signatureStatus == 'completed') return false;
  return edits.any((edit) => edit['renewal_required'] == true);
}

/// Read-only list of Turn Around Time content revisions.
class TurnAroundTimeEditHistoryView extends StatelessWidget {
  const TurnAroundTimeEditHistoryView({super.key, required this.edits});

  final List<Map<String, dynamic>> edits;

  @override
  Widget build(BuildContext context) {
    if (edits.isEmpty) {
      return const Text('No content changes have been recorded yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: edits.length,
      separatorBuilder: (_, __) => const Divider(height: 20),
      itemBuilder: (_, index) {
        final edit = edits[index];
        final parsed = DateTime.tryParse(edit['edited_at']?.toString() ?? '');
        final when = parsed == null
            ? (edit['edited_at']?.toString() ?? '')
            : parsed.toLocal().toString();
        final who = edit['edited_by_name']?.toString().trim().isNotEmpty == true
            ? edit['edited_by_name'].toString()
            : 'Unknown user';
        final renewed = edit['renewal_required'] == true;
        final signedBefore = edit['signed_before_edit'] == true;
        final changes = edit['changes'];
        final cleared = edit['signatures_cleared'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$who · $when',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              renewed
                  ? 'Content was already signed. Those signatures were cleared and belong to the earlier revision.'
                  : signedBefore
                  ? 'Edited while a signature was on file.'
                  : 'Edited before the current signatures were complete.',
            ),
            if ((edit['integrity_note']?.toString() ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(edit['integrity_note'].toString()),
              ),
            if (cleared is List)
              ...cleared.map((slot) {
                final row = slot is Map
                    ? Map<String, dynamic>.from(slot)
                    : <String, dynamic>{};
                final slotKey = row['slot_key']?.toString() ?? 'signature';
                final label = slotKey == 'noted_by' ? 'Noted by' : 'Prepared by';
                final name = row['signer_name_snapshot']?.toString().trim();
                final signedAt = row['signed_at']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Earlier $label signature: ${name == null || name.isEmpty ? 'Unknown signer' : name} · $signedAt',
                  ),
                );
              }),
            if (changes is List)
              ...changes.map((change) {
                final row = change is Map
                    ? Map<String, dynamic>.from(change)
                    : <String, dynamic>{};
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tatEditHistoryLine(row)),
                );
              }),
          ],
        );
      },
    );
  }
}

String tatEditHistoryLine(Map<String, dynamic> change) {
  final applicant = change['applicant']?.toString().trim() ?? '';
  final label = change['label']?.toString().trim().isNotEmpty == true
      ? change['label'].toString()
      : (change['field']?.toString() ?? 'Field');
  final prefix = applicant.isEmpty ? label : '$applicant · $label';
  return '$prefix: ${tatHistoryValue(change['previous'])} → ${tatHistoryValue(change['next'])}';
}

String tatHistoryValue(dynamic value) {
  if (value == null) return '—';
  if (value is List) {
    final text = value.map((item) => item.toString()).join(', ');
    return text.isEmpty ? '—' : text;
  }
  if (value is Map) {
    const keys = [
      'name',
      'application_id',
      'date_initial_assessment',
      'date_contract_exam',
      'skills_trade_exam_result',
      'date_deliberation',
      'date_job_offer',
      'acceptance_date',
      'date_assumption_to_duty',
      'no_of_days_to_fill_up',
      'overall_cost_per_hire',
    ];
    final parts = <String>[];
    for (final key in keys) {
      final item = value[key];
      if (item == null || item.toString().trim().isEmpty) continue;
      parts.add('$key $item');
    }
    return parts.isEmpty ? '—' : parts.join(', ');
  }
  final text = value.toString().trim();
  return text.isEmpty ? '—' : text;
}
