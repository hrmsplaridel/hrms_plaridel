import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_form_header_footer.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// L&D: Individual Development Plan (IDP) — list entries and add/edit form.
class IdpAdminSection extends StatefulWidget {
  const IdpAdminSection({super.key});

  @override
  State<IdpAdminSection> createState() => _IdpAdminSectionState();
}

class _IdpAdminSectionState extends State<IdpAdminSection> {
  List<IdpEntry> _entries = [];
  bool _loading = true;
  IdpEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await IdpRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _startNew() => setState(() => _editing = const IdpEntry());
  void _edit(IdpEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(IdpEntry entry) async {
    try {
      if (entry.id == null) {
        await IdpRepo.instance.insert(entry);
      } else {
        await IdpRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IDP saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
      }
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await IdpRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IDP deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printIdp(IdpEntry entry) async {
    try {
      await FormPdf.printIdpPdf(context, entry);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadIdp(IdpEntry entry) async {
    try {
      final doc = await FormPdf.buildIdpPdf(entry);
      await FormPdf.sharePdf(doc, name: 'IDP.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved IDP records',
      emptyMessage: 'No IDP entries yet.',
      loading: _loading,
      items: _entries.map((e) {
        final name = (e.name?.trim().isNotEmpty ?? false)
            ? e.name!
            : '(No name)';
        final sub = '${e.position ?? "â€”"} Â· ${e.department ?? "â€”"}';
        return SavedRecordListItem(
          title: name,
          subtitle: sub,
          detailDialogTitle: 'IDP â€” $name',
          previewContentWidth: 920,
          previewBuilder: () => _IdpFormEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printIdp(e),
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
          'Individual Development Plan (IDP)',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Record employee IDP: personal/position info, qualifications, succession analysis, and development plan rows.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _IdpFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printIdp,
            onDownloadPdf: _downloadIdp,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add IDP'),
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
            message: 'No IDP entries yet. Tap "Add IDP" to add one.',
            icon: Icons.school_outlined,
          )
        else
          _IdpList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printIdp,
            onDownloadPdf: _downloadIdp,
          ),
      ],
    );
  }
}

class _IdpFormEditor extends StatefulWidget {
  const _IdpFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final IdpEntry entry;
  final bool readOnly;
  final void Function(IdpEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(IdpEntry) onPrint;
  final Future<void> Function(IdpEntry) onDownloadPdf;

  @override
  State<_IdpFormEditor> createState() => _IdpFormEditorState();
}

class _IdpFormEditorState extends State<_IdpFormEditor> {
  late List<TextEditingController> _controllers;
  late String? _performanceRating;
  late String? _competenceRating;
  late String? _successionPriorityRating;
  late List<Map<String, TextEditingController>> _planRows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _controllers = [
      TextEditingController(text: e.name ?? ''),
      TextEditingController(text: e.position ?? ''),
      TextEditingController(text: e.category ?? ''),
      TextEditingController(text: e.division ?? ''),
      TextEditingController(text: e.department ?? ''),
      TextEditingController(text: e.education ?? ''),
      TextEditingController(text: e.experience ?? ''),
      TextEditingController(text: e.training ?? ''),
      TextEditingController(text: e.eligibility ?? ''),
      TextEditingController(text: e.significantAccomplishments ?? ''),
      TextEditingController(text: e.targetPosition1 ?? ''),
      TextEditingController(text: e.targetPosition2 ?? ''),
      TextEditingController(text: e.avgRating ?? ''),
      TextEditingController(text: e.opcr ?? ''),
      TextEditingController(text: e.ipcr ?? ''),
      TextEditingController(text: e.competencyDescription ?? ''),
      TextEditingController(text: e.successionPriorityScore ?? ''),
      TextEditingController(text: e.preparedBy ?? ''),
      TextEditingController(text: e.reviewedBy ?? ''),
      TextEditingController(text: e.notedBy ?? ''),
      TextEditingController(text: e.approvedBy ?? ''),
    ];
    _performanceRating = e.performanceRating;
    _competenceRating = e.competenceRating;
    _successionPriorityRating = e.successionPriorityRating;
    final plan = e.developmentPlanRows.isEmpty
        ? <IdpPlanRow>[const IdpPlanRow(), const IdpPlanRow()]
        : List<IdpPlanRow>.from(e.developmentPlanRows);
    while (plan.length < 2) {
      plan.add(const IdpPlanRow());
    }
    _planRows = plan
        .take(2)
        .map(
          (r) => _rowControllers(
            r.objectives ?? '',
            r.ldProgram ?? '',
            r.requirements ?? '',
            r.timeFrame ?? '',
          ),
        )
        .toList();
  }

  Map<String, TextEditingController> _rowControllers(
    String obj,
    String ld,
    String req,
    String tf,
  ) {
    return {
      'objectives': TextEditingController(text: obj),
      'ld_program': TextEditingController(text: ld),
      'requirements': TextEditingController(text: req),
      'time_frame': TextEditingController(text: tf),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final row in _planRows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  IdpEntry _buildCurrentEntry() {
    final rows = _planRows
        .map(
          (r) => IdpPlanRow(
            objectives: r['objectives']!.text.trim().isEmpty
                ? null
                : r['objectives']!.text.trim(),
            ldProgram: r['ld_program']!.text.trim().isEmpty
                ? null
                : r['ld_program']!.text.trim(),
            requirements: r['requirements']!.text.trim().isEmpty
                ? null
                : r['requirements']!.text.trim(),
            timeFrame: r['time_frame']!.text.trim().isEmpty
                ? null
                : r['time_frame']!.text.trim(),
          ),
        )
        .toList();
    return IdpEntry(
      id: widget.entry.id,
      name: _controllers[0].text.trim().isEmpty
          ? null
          : _controllers[0].text.trim(),
      position: _controllers[1].text.trim().isEmpty
          ? null
          : _controllers[1].text.trim(),
      category: _controllers[2].text.trim().isEmpty
          ? null
          : _controllers[2].text.trim(),
      division: _controllers[3].text.trim().isEmpty
          ? null
          : _controllers[3].text.trim(),
      department: _controllers[4].text.trim().isEmpty
          ? null
          : _controllers[4].text.trim(),
      education: _controllers[5].text.trim().isEmpty
          ? null
          : _controllers[5].text.trim(),
      experience: _controllers[6].text.trim().isEmpty
          ? null
          : _controllers[6].text.trim(),
      training: _controllers[7].text.trim().isEmpty
          ? null
          : _controllers[7].text.trim(),
      eligibility: _controllers[8].text.trim().isEmpty
          ? null
          : _controllers[8].text.trim(),
      significantAccomplishments: _controllers[9].text.trim().isEmpty
          ? null
          : _controllers[9].text.trim(),
      targetPosition1: _controllers[10].text.trim().isEmpty
          ? null
          : _controllers[10].text.trim(),
      targetPosition2: _controllers[11].text.trim().isEmpty
          ? null
          : _controllers[11].text.trim(),
      avgRating: _controllers[12].text.trim().isEmpty
          ? null
          : _controllers[12].text.trim(),
      opcr: _controllers[13].text.trim().isEmpty
          ? null
          : _controllers[13].text.trim(),
      ipcr: _controllers[14].text.trim().isEmpty
          ? null
          : _controllers[14].text.trim(),
      performanceRating: _performanceRating,
      competencyDescription: _controllers[15].text.trim().isEmpty
          ? null
          : _controllers[15].text.trim(),
      competenceRating: _competenceRating,
      successionPriorityScore: _controllers[16].text.trim().isEmpty
          ? null
          : _controllers[16].text.trim(),
      successionPriorityRating: _successionPriorityRating,
      developmentPlanRows: rows,
      preparedBy: _controllers[17].text.trim().isEmpty
          ? null
          : _controllers[17].text.trim(),
      reviewedBy: _controllers[18].text.trim().isEmpty
          ? null
          : _controllers[18].text.trim(),
      notedBy: _controllers[19].text.trim().isEmpty
          ? null
          : _controllers[19].text.trim(),
      approvedBy: _controllers[20].text.trim().isEmpty
          ? null
          : _controllers[20].text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
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
              formTitle: 'INDIVIDUAL DEVELOPMENT PLAN',
              subtitle: 'LOCAL GOVERNMENT UNIT OF PLARIDEL',
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field('NAME', _controllers[0]),
                      _field('POSITION', _controllers[1]),
                      _field('CATEGORY', _controllers[2]),
                      _field('DIVISION', _controllers[3]),
                      _field('DEPARTMENT', _controllers[4]),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QUALIFICATIONS',
                        style: TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _field('EDUCATION', _controllers[5]),
                      _field('EXPERIENCE', _controllers[6]),
                      _field('TRAINING', _controllers[7]),
                      _field('ELIGIBILITY', _controllers[8]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'SIGNIFICANT ACCOMPLISHMENTS:',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _field('Significant accomplishments', _controllers[9]),
            const SizedBox(height: 8),
            Text(
              'SUCCESSION ANALYSIS (RESULTS OF THE COMPETENCY-BASED SUCCESSION PRIORITY MATRIX)',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Target position 1', _controllers[10]),
            _field('Target position 2', _controllers[11]),
            const SizedBox(height: 8),
            Text(
              'Required qualifications (reference on printed form)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text(
              'Performance, average 2 latest previous SPMS-IPCR Rating',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('OPCR', _controllers[13])),
                const SizedBox(width: 12),
                Expanded(child: _field('IPCR', _controllers[14])),
                const SizedBox(width: 12),
                Expanded(child: _field('Average rating', _controllers[12])),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: IdpEntry.performanceRatingOptions.map((v) {
                final label = switch (v) {
                  'very_satisfactory' => 'Very Satisfactory',
                  _ => v[0].toUpperCase() + v.substring(1),
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _performanceRating == v,
                  onSelected: ro
                      ? null
                      : (_) => setState(() => _performanceRating = v),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _field('Competency', _controllers[15]),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: IdpEntry.competenceRatingOptions.map((v) {
                final label = switch (v) {
                  'immediate' => 'Immediate',
                  _ => v[0].toUpperCase() + v.substring(1),
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _competenceRating == v,
                  onSelected: ro
                      ? null
                      : (_) => setState(() => _competenceRating = v),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _field('Succession priority total score', _controllers[16]),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: IdpEntry.successionPriorityOptions.map((v) {
                final label = switch (v) {
                  'priority_2' => 'Priority 2',
                  'priority_3' => 'Priority 3',
                  _ => 'Priority',
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _successionPriorityRating == v,
                  onSelected: ro
                      ? null
                      : (_) => setState(() => _successionPriorityRating = v),
                );
              }).toList(),
            ),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Development plan â€” Short Term (6 months)',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 88,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black54),
                    ),
                    child: const Text(
                      'Short Term\n(6 months)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Table(
                      border: TableBorder.all(color: Colors.black54),
                      columnWidths: const {
                        0: FlexColumnWidth(1.4),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(0.9),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'OBJECTIVES',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'L & D PROGRAM',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'REQUIREMENTS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'TIME FRAME',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ...List.generate(_planRows.length, (i) {
                          final r = _planRows[i];
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: TextFormField(
                                  controller: r['objectives'],
                                  readOnly: ro,
                                  decoration: rspUnderlinedField(''),
                                  maxLines: 2,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: TextFormField(
                                  controller: r['ld_program'],
                                  readOnly: ro,
                                  decoration: rspUnderlinedField(''),
                                  maxLines: 2,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: TextFormField(
                                  controller: r['requirements'],
                                  readOnly: ro,
                                  decoration: rspUnderlinedField(''),
                                  maxLines: 2,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: TextFormField(
                                  controller: r['time_frame'],
                                  readOnly: ro,
                                  decoration: rspUnderlinedField(''),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Signatures',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field('Prepared by (Employee)', _controllers[17]),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'Reviewed by (Department Head)',
                    _controllers[18],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field('Noted by', _controllers[19]),
                      Text(
                        IdpEntry.defaultNotedByName,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        IdpEntry.defaultNotedByTitle,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field('Approved by', _controllers[20]),
                      Text(
                        IdpEntry.defaultApprovedByName,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        IdpEntry.defaultApprovedByTitle,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
            if (!ro) ...[
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => widget.onPrint(_buildCurrentEntry()),
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Print',
                  ),
                  IconButton(
                    onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Download PDF',
                  ),
                ],
              ),
            ] else ...[
              if (widget.entry.createdAt != null)
                Text(
                  'Created: ${widget.entry.createdAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return RspSpacedOutlineField(
      child: TextFormField(
        controller: c,
        readOnly: widget.readOnly,
        decoration: rspUnderlinedField(label),
      ),
    );
  }
}

class _IdpList extends StatelessWidget {
  const _IdpList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<IdpEntry> entries;
  final void Function(IdpEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(IdpEntry) onPrint;
  final Future<void> Function(IdpEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Name', flex: 2),
      RspRecordsColumn('Position', flex: 2.2),
      RspRecordsColumn('Department', flex: 1.8),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(e.name ?? '', bold: true),
              rspRecordsTextCell(e.position ?? ''),
              rspRecordsTextCell(e.department ?? ''),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Individual development plan',
                  subtitle: '${e.name} Â· ${e.position ?? ''}',
                  previewBuilder: () => _IdpFormEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 920,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete IDP?',
              ),
            ],
          )
          .toList(),
    );
  }
}
