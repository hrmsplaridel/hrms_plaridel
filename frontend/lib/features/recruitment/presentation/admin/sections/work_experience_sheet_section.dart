import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/form_document_preview.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_form_header.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_rsp_signature_section.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';

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
      final signatureProvider = context.read<DocuTrackerProvider>();
      final signatures = entry.id == null
          ? null
          : await signatureProvider.loadSourceSignatures(
              sourceModule: 'rsp',
              sourceTable: WorkExperienceSheetEntry.tableName,
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
            FormPdf.buildWorkExperienceSheetPdf(entry, signatures: signatures),
        filename: 'Work_Experience_Sheet.pdf',
        format: FormPdf.pageLetterLandscape,
        printModule: 'rsp',
        printFormKey: 'work_experience',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed. ${userFacingApiError(error)}')),
      );
    }
  }

  Future<void> _preview(WorkExperienceSheetEntry entry) {
    return openFormDocumentPreview(
      context: context,
      title: 'Work Experience Sheet',
      filename: 'Work_Experience_Sheet.pdf',
      format: FormPdf.pageLetterLandscape,
      printModule: 'rsp',
      printFormKey: 'work_experience',
      buildDocument: () async {
        final signatureProvider = context.read<DocuTrackerProvider>();
        final signatures = entry.id == null
            ? null
            : await signatureProvider.loadSourceSignatures(
                sourceModule: 'rsp',
                sourceTable: WorkExperienceSheetEntry.tableName,
                sourceRecordId: entry.id!,
              );
        if (entry.id != null && signatures == null) {
          throw StateError(
            signatureProvider.sourceSignatureError ??
                'The form signatures could not be loaded.',
          );
        }
        return FormPdf.buildWorkExperienceSheetPdf(
          entry,
          signatures: signatures,
        );
      },
    );
  }

  Future<void> _download(WorkExperienceSheetEntry entry) async {
    try {
      final signatureProvider = context.read<DocuTrackerProvider>();
      final signatures = entry.id == null
          ? null
          : await signatureProvider.loadSourceSignatures(
              sourceModule: 'rsp',
              sourceTable: WorkExperienceSheetEntry.tableName,
              sourceRecordId: entry.id!,
            );
      if (entry.id != null && signatures == null) {
        throw StateError(
          signatureProvider.sourceSignatureError ??
              'The form signatures could not be loaded.',
        );
      }
      final doc = await FormPdf.buildWorkExperienceSheetPdf(
        entry,
        signatures: signatures,
      );
      await FormPdf.sharePdf(doc, name: 'Work_Experience_Sheet.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF ready to save or share.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed. ${userFacingApiError(e)}')),
      );
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
          onDocumentPreview: () => _preview(e),
          onEdit: () => _edit(e),
          onDelete: e.id == null ? null : () => _onDelete(e.id!),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RspLdFormHeader(
          module: 'RSP',
          title: 'Work Experience Sheet',
          subtitle:
              "Record the applicant's position, minimum qualification standards, and previous work responsibilities.",
          actions: Wrap(
            spacing: 4,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _startNew,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Sheet'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(foregroundColor: primary),
              ),
              if (_editing != null)
                TextButton.icon(
                  onPressed: _loading ? null : _openSavedRecordsBrowser,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('View Records'),
                  style: TextButton.styleFrom(foregroundColor: primary),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_editing != null) ...[
          WorkExperienceSheetEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _print,
            onPreview: _preview,
            onDownloadPdf: _download,
          ),
          if (_editing?.id != null) ...[
            const SizedBox(height: 12),
            DocuTrackerRspSignatureSection(
              sourceTable: WorkExperienceSheetEntry.tableName,
              sourceRecordId: _editing!.id!,
              helperText: 'The applicant signs this sheet after it is saved.',
              slots: const [
                DocuTrackerRspSignatureSlot('applicant', 'Applicant'),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ] else ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_entries.isEmpty)
            const RspFormEmptyState(
              message:
                  'No work experience sheets yet. Tap "Add Sheet" to create one.',
              icon: Icons.work_history_outlined,
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
    this.onPreview,
    required this.onDownloadPdf,
  });

  final WorkExperienceSheetEntry entry;
  final bool readOnly;
  final void Function(WorkExperienceSheetEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(WorkExperienceSheetEntry) onPrint;
  final Future<void> Function(WorkExperienceSheetEntry)? onPreview;
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
    _jobDescription = TextEditingController(
      text: e.jobDescriptionLastWork ?? '',
    );
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

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryNavy),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _helper(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.dashTextSecondaryOf(context),
        fontSize: 12,
        height: 1.3,
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: widget.readOnly,
          style: AppTheme.dashFieldTextStyle(context).copyWith(fontSize: 14),
          decoration: AppTheme.dashInputDecoration(
            context,
            radius: 12,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _applicationDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Application Details', Icons.badge_outlined),
        const SizedBox(height: 12),
        _labeledField('Position Applied For', _position),
        const SizedBox(height: 12),
        _labeledField('Department', _department),
      ],
    );
  }

  Widget _minimumStandards(double width) {
    final twoByTwo = width >= 460;
    final fields = [
      _labeledField('Education', _education),
      _labeledField('Experience', _experience),
      _labeledField('Training', _training),
      _labeledField('Eligibility', _eligibility),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Minimum Standards', Icons.fact_check_outlined),
        const SizedBox(height: 4),
        _helper('Enter the required qualification standards for the position.'),
        const SizedBox(height: 12),
        if (twoByTwo)
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields[2]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[3]),
                ],
              ),
            ],
          )
        else
          Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                fields[i],
              ],
            ],
          ),
      ],
    );
  }

  Widget _jobDescriptionPanel(double height) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Job Description of Last Work', Icons.work_outline),
        const SizedBox(height: 4),
        _helper(
          "Describe the applicant's main duties and responsibilities from their most recent work.",
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          child: TextFormField(
            controller: _jobDescription,
            readOnly: widget.readOnly,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: AppTheme.dashFieldTextStyle(context).copyWith(fontSize: 14),
            decoration: AppTheme.dashInputDecoration(
              context,
              hintText: 'Describe duties and responsibilities...',
              radius: 12,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppTheme.primaryNavy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                    children: const [
                      TextSpan(
                        text: 'COE Reminder — ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            'Include or attach a Certificate of Employment with detailed position/job description when required.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _submittedBy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Submitted By', Icons.person_outline_rounded),
        const SizedBox(height: 10),
        _labeledField('Applicant Name', _applicantName),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool expand,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        minimumSize: Size(expand ? double.infinity : 44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _actionBar(WorkExperienceSheetEntry entry, bool narrow) {
    final save = FilledButton(
      onPressed: () => widget.onSave(_buildEntry()),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        minimumSize: const Size(88, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text('Save'),
    );
    final cancel = TextButton(
      onPressed: widget.onCancel,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.dashTextSecondaryOf(context),
        minimumSize: const Size(44, 44),
      ),
      child: const Text('Cancel'),
    );
    final preview = widget.onPreview == null
        ? null
        : RspLdBusyOutlinedButton(
            icon: Icons.visibility_outlined,
            label: 'Preview Form',
            busyLabel: 'Opening preview…',
            onPressed: () => widget.onPreview!(entry),
            expand: false,
          );
    final print = RspLdBusyOutlinedButton(
      icon: Icons.print_rounded,
      label: 'Print Form',
      busyLabel: 'Preparing print…',
      onPressed: () => widget.onPrint(entry),
      expand: false,
    );
    final download = _actionButton(
      icon: Icons.download_rounded,
      label: 'Download',
      onPressed: () => widget.onDownloadPdf(entry),
      expand: false,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
      children: [
        cancel,
        if (preview != null) preview,
        print,
        download,
        save,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = _buildEntry();
    final primary = AppTheme.dashTextPrimaryOf(context);
    final isNew = widget.entry.id == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final twoColumn = width >= 860;
          final leftFlex = width >= 1100 ? 42 : 45;
          final rightFlex = 100 - leftFlex;
          final jobHeight = twoColumn ? 280.0 : 220.0;
          final left = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _applicationDetails(),
              const SizedBox(height: 16),
              _minimumStandards(twoColumn ? width * leftFlex / 100 : width),
            ],
          );
          final right = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _jobDescriptionPanel(jobHeight),
              const SizedBox(height: 14),
              _submittedBy(),
            ],
          );

          final narrow = width < 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 10,
                spacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Work Experience Details',
                        style: TextStyle(
                          color: primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!widget.readOnly) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isNew ? 'Draft' : 'Saved',
                            style: const TextStyle(
                              color: AppTheme.primaryNavy,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!widget.readOnly) _actionBar(entry, narrow),
                ],
              ),
              const SizedBox(height: 14),
              if (twoColumn)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: leftFlex, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: rightFlex, child: right),
                  ],
                )
              else ...[
                left,
                const SizedBox(height: 16),
                right,
              ],
            ],
          );
        },
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
              rspRecordsTextCell(
                context,
                e.positionAppliedFor ?? '',
                bold: true,
              ),
              rspRecordsTextCell(context, e.applicantName ?? ''),
              rspRecordsTextCell(context, e.department ?? ''),
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
