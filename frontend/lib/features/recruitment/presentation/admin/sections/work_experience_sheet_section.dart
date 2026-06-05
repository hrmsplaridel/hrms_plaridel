import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_form_header_footer.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// RSP: Work Experience Sheet — after Computation of Points.
class RspWorkExperienceSheetSection extends StatefulWidget {
  const RspWorkExperienceSheetSection({super.key});

  @override
  State<RspWorkExperienceSheetSection> createState() =>
      _RspWorkExperienceSheetSectionState();
}

class _RspWorkExperienceSheetSectionState
    extends State<RspWorkExperienceSheetSection> {
  List<WorkExperienceSheetEntry> _entries = [];
  bool _loading = true;
  WorkExperienceSheetEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await WorkExperienceSheetRepo.instance.list();
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
      setState(() => _editing = const WorkExperienceSheetEntry());
  void _edit(WorkExperienceSheetEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(WorkExperienceSheetEntry entry) async {
    try {
      if (entry.id == null) {
        await WorkExperienceSheetRepo.instance.insert(entry);
      } else {
        await WorkExperienceSheetRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work experience sheet saved.')),
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
      await WorkExperienceSheetRepo.instance.delete(id);
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

  Future<void> _print(WorkExperienceSheetEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildWorkExperienceSheetPdf(entry),
        filename: 'Work_Experience_Sheet.pdf',
      );
    } catch (_) {}
  }

  Future<void> _download(WorkExperienceSheetEntry entry) async {
    try {
      final doc = await FormPdf.buildWorkExperienceSheetPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Work_Experience_Sheet.pdf');
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
      sheetTitle: 'Saved work experience sheets',
      emptyMessage: 'No records yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.positionAppliedFor?.trim().isNotEmpty == true
            ? e.positionAppliedFor!
            : '(No position)';
        final applicant = e.applicantName?.trim().isNotEmpty == true
            ? e.applicantName!
            : '—';
        return SavedRecordListItem(
          title: pos,
          subtitle: applicant,
          detailDialogTitle: 'Work experience sheet — $pos',
          previewContentWidth: 900,
          previewBuilder: () => WorkExperienceSheetEditor(
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Experience Sheet',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'HRMD work experience form: position applied for, department, four minimum standards, and job description of last work (with COE).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          WorkExperienceSheetEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _print,
            onDownloadPdf: _download,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add sheet'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _loading ? null : _openSavedRecordsBrowser,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
              label: const Text('View records'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          const RspFormEmptyState(
            message:
                'No work experience sheets yet. Tap "Add sheet" to create one.',
            icon: Icons.work_history_rounded,
          )
        else
          _WorkExperienceSheetList(
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

class WorkExperienceSheetEditor extends StatefulWidget {
  const WorkExperienceSheetEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final WorkExperienceSheetEntry entry;
  final bool readOnly;
  final void Function(WorkExperienceSheetEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(WorkExperienceSheetEntry) onPrint;
  final Future<void> Function(WorkExperienceSheetEntry) onDownloadPdf;

  @override
  State<WorkExperienceSheetEditor> createState() =>
      _WorkExperienceSheetEditorState();
}

class _WorkExperienceSheetEditorState extends State<WorkExperienceSheetEditor> {
  late TextEditingController _position;
  late TextEditingController _department;
  late TextEditingController _education;
  late TextEditingController _experience;
  late TextEditingController _training;
  late TextEditingController _eligibility;
  late TextEditingController _jobDescription;
  late TextEditingController _applicantName;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _position = TextEditingController(text: e.positionAppliedFor ?? '');
    _department = TextEditingController(text: e.department ?? '');
    _education = TextEditingController(text: e.minEducation ?? '');
    _experience = TextEditingController(text: e.minExperience ?? '');
    _training = TextEditingController(text: e.minTraining ?? '');
    _eligibility = TextEditingController(text: e.minEligibility ?? '');
    _jobDescription = TextEditingController(text: e.jobDescriptionLastWork ?? '');
    _applicantName = TextEditingController(text: e.applicantName ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _position,
      _department,
      _education,
      _experience,
      _training,
      _eligibility,
      _jobDescription,
      _applicantName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  WorkExperienceSheetEntry _buildEntry() {
    return WorkExperienceSheetEntry(
      id: widget.entry.id,
      positionAppliedFor: _opt(_position),
      department: _opt(_department),
      minEducation: _opt(_education),
      minExperience: _opt(_experience),
      minTraining: _opt(_training),
      minEligibility: _opt(_eligibility),
      jobDescriptionLastWork: _opt(_jobDescription),
      applicantName: _opt(_applicantName),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  Widget _field(String label, TextEditingController controller,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RspSpacedOutlineField(
        child: TextFormField(
          controller: controller,
          readOnly: widget.readOnly,
          maxLines: maxLines,
          decoration: rspUnderlinedField(label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    final entry = _buildEntry();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(
              formTitle: 'WORK EXPERIENCE SHEET',
              subtitle: 'Human Resource Management and Development Office',
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field('POSITION APPLIED FOR', _position),
                      _field('DEPARTMENT', _department),
                      const SizedBox(height: 8),
                      Text(
                        '4 MINIMUM STANDARDS',
                        style: TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _field('1. Education', _education),
                      _field('2. Experience', _experience),
                      _field('3. Training', _training),
                      _field('4. Eligibility', _eligibility),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Job Description of Last Work',
                        style: TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.2),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: TextFormField(
                          controller: _jobDescription,
                          readOnly: ro,
                          maxLines: 14,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText:
                                'Describe duties and responsibilities of last work…',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Note: With COE with detail position description details',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const Text(
                    'Submitted by:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 320,
                    child: RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _applicantName,
                        readOnly: ro,
                        textAlign: TextAlign.center,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Name of Applicant',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!ro) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => widget.onSave(_buildEntry()),
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => widget.onPrint(entry),
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Print',
                  ),
                  IconButton(
                    onPressed: () => widget.onDownloadPdf(entry),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Download PDF',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkExperienceSheetList extends StatelessWidget {
  const _WorkExperienceSheetList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<WorkExperienceSheetEntry> entries;
  final void Function(WorkExperienceSheetEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(WorkExperienceSheetEntry) onPrint;
  final Future<void> Function(WorkExperienceSheetEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Position', flex: 2.2),
      RspRecordsColumn('Applicant', flex: 2),
      RspRecordsColumn('Department', flex: 1.6),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(e.positionAppliedFor ?? '', bold: true),
              rspRecordsTextCell(e.applicantName ?? ''),
              rspRecordsTextCell(e.department ?? ''),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Work experience sheet',
                  subtitle: e.positionAppliedFor ?? '',
                  previewBuilder: () => WorkExperienceSheetEditor(
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
                deleteDialogTitle: 'Delete sheet?',
              ),
            ],
          )
          .toList(),
    );
  }
}
