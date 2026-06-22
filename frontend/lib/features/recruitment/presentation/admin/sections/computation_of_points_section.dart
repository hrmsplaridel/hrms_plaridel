import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_form_header_footer.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// RSP: Computation of Points (Personnel Selection Board) — after Selection Line-up.
class RspComputationOfPointsSection extends StatefulWidget {
  const RspComputationOfPointsSection({super.key});

  @override
  State<RspComputationOfPointsSection> createState() =>
      _RspComputationOfPointsSectionState();
}

class _RspComputationOfPointsSectionState
    extends State<RspComputationOfPointsSection> {
  List<ComputationOfPointsEntry> _entries = [];
  bool _loading = true;
  ComputationOfPointsEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ComputationOfPointsRepo.instance.list();
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
      setState(() => _editing = const ComputationOfPointsEntry());
  void _edit(ComputationOfPointsEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ComputationOfPointsEntry entry) async {
    try {
      if (entry.id == null) {
        await ComputationOfPointsRepo.instance.insert(entry);
      } else {
        await ComputationOfPointsRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Computation of points saved.')),
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
      await ComputationOfPointsRepo.instance.delete(id);
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

  Future<void> _print(ComputationOfPointsEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildComputationOfPointsPdf(entry),
        filename: 'Computation_of_Points.pdf',
        format: FormPdf.pageLetterLandscape,
      );
    } catch (_) {}
  }

  Future<void> _download(ComputationOfPointsEntry entry) async {
    try {
      final doc = await FormPdf.buildComputationOfPointsPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Computation_of_Points.pdf');
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
      sheetTitle: 'Saved computation of points',
      emptyMessage: 'No records yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.position?.trim().isNotEmpty == true
            ? e.position!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle: '${e.date ?? "—"} · ${e.candidates.length} candidate(s)',
          detailDialogTitle: 'Computation of points — $pos',
          previewContentWidth: 1100,
          previewBuilder: () => ComputationOfPointsEditor(
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
          'Computation of Points',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Personnel Selection Board scoring sheet: position details, minimum requirements, and candidate points (education, eligibility, experience, training, performance, potential, work attitude).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          ComputationOfPointsEditor(
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
              label: const Text('Add record'),
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
                'No computation of points records yet. Tap "Add record" to create one.',
            icon: Icons.calculate_rounded,
          )
        else
          _ComputationOfPointsList(
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

class ComputationOfPointsEditor extends StatefulWidget {
  const ComputationOfPointsEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final ComputationOfPointsEntry entry;
  final bool readOnly;
  final void Function(ComputationOfPointsEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ComputationOfPointsEntry) onPrint;
  final Future<void> Function(ComputationOfPointsEntry) onDownloadPdf;

  @override
  State<ComputationOfPointsEditor> createState() =>
      _ComputationOfPointsEditorState();
}

class _ComputationOfPointsEditorState extends State<ComputationOfPointsEditor> {
  late TextEditingController _date;
  late TextEditingController _positionLevel;
  late TextEditingController _position;
  late TextEditingController _salaryGrade;
  late TextEditingController _rate;
  late TextEditingController _office;
  late TextEditingController _minEducation;
  late TextEditingController _minTraining;
  late TextEditingController _minExperience;
  late TextEditingController _minEligibility;
  late TextEditingController _preparedBy;
  late List<Map<String, TextEditingController>> _rows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _date = TextEditingController(text: e.date ?? '');
    _positionLevel = TextEditingController(
      text: e.positionLevel ?? 'Second Level Position',
    );
    _position = TextEditingController(text: e.position ?? '');
    _salaryGrade = TextEditingController(text: e.salaryGrade ?? '');
    _rate = TextEditingController(text: e.rate ?? '');
    _office = TextEditingController(text: e.office ?? '');
    _minEducation = TextEditingController(text: e.minEducation ?? '');
    _minTraining = TextEditingController(text: e.minTraining ?? '');
    _minExperience = TextEditingController(text: e.minExperience ?? '');
    _minEligibility = TextEditingController(text: e.minEligibility ?? '');
    _preparedBy = TextEditingController(text: e.preparedByName ?? '');
    _rows = e.candidates.isEmpty
        ? [_candidateRow()]
        : e.candidates.map(_candidateRowFrom).toList();
  }

  Map<String, TextEditingController> _candidateRow() => {
    'name': TextEditingController(),
    'position': TextEditingController(),
    'salaryGrade': TextEditingController(),
    'rate': TextEditingController(),
    'education': TextEditingController(),
    'eligibility': TextEditingController(),
    'experience': TextEditingController(),
    'training': TextEditingController(),
    'performance': TextEditingController(),
    'potential': TextEditingController(),
    'workAttitude': TextEditingController(),
    'total': TextEditingController(),
    'rank': TextEditingController(),
  };

  Map<String, TextEditingController> _candidateRowFrom(
    ComputationOfPointsCandidate c,
  ) {
    final row = _candidateRow();
    row['name']!.text = c.name ?? '';
    row['position']!.text = c.position ?? '';
    row['salaryGrade']!.text = c.salaryGrade ?? '';
    row['rate']!.text = c.rate ?? '';
    row['education']!.text = c.education ?? '';
    row['eligibility']!.text = c.eligibility ?? '';
    row['experience']!.text = c.experience ?? '';
    row['training']!.text = c.training ?? '';
    row['performance']!.text = c.performance ?? '';
    row['potential']!.text = c.potential ?? '';
    row['workAttitude']!.text = c.workAttitude ?? '';
    row['total']!.text = c.total ?? '';
    row['rank']!.text = c.rank ?? '';
    return row;
  }

  @override
  void dispose() {
    for (final c in [
      _date,
      _positionLevel,
      _position,
      _salaryGrade,
      _rate,
      _office,
      _minEducation,
      _minTraining,
      _minExperience,
      _minEligibility,
      _preparedBy,
    ]) {
      c.dispose();
    }
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_candidateRow()));

  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  ComputationOfPointsEntry _buildEntry() {
    final candidates = _rows
        .map(
          (r) => ComputationOfPointsCandidate(
            name: _opt(r['name']!),
            position: _opt(r['position']!),
            salaryGrade: _opt(r['salaryGrade']!),
            rate: _opt(r['rate']!),
            education: _opt(r['education']!),
            eligibility: _opt(r['eligibility']!),
            experience: _opt(r['experience']!),
            training: _opt(r['training']!),
            performance: _opt(r['performance']!),
            potential: _opt(r['potential']!),
            workAttitude: _opt(r['workAttitude']!),
            total: _opt(r['total']!),
            rank: _opt(r['rank']!),
          ),
        )
        .toList();
    return ComputationOfPointsEntry(
      id: widget.entry.id,
      date: _opt(_date),
      positionLevel: _opt(_positionLevel),
      position: _opt(_position),
      salaryGrade: _opt(_salaryGrade),
      rate: _opt(_rate),
      office: _opt(_office),
      minEducation: _opt(_minEducation),
      minTraining: _opt(_minTraining),
      minExperience: _opt(_minExperience),
      minEligibility: _opt(_minEligibility),
      candidates: candidates,
      preparedByName: _opt(_preparedBy),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RspSpacedOutlineField(
        child: TextFormField(
          controller: controller,
          readOnly: widget.readOnly,
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
              formTitle: 'COMPUTATION OF POINTS',
              subtitle: 'Personnel Selection Board',
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'OFFICE OF THE MUNICIPAL MAYOR',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 200,
                  child: RspSpacedOutlineField(
                    child: TextFormField(
                      controller: _date,
                      readOnly: ro,
                      decoration: rspUnderlinedField('Date'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '(${_positionLevel.text.trim().isEmpty ? "Second Level Position" : _positionLevel.text.trim()})',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            if (!ro) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 280,
                child: _field('Position level label', _positionLevel),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _field('POSITION', _position),
                      _field('SALARY GRADE', _salaryGrade),
                      _field('RATE', _rate),
                      _field('OFFICE', _office),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _field('EDUCATION', _minEducation),
                      _field('TRAINING', _minTraining),
                      _field('EXPERIENCE', _minExperience),
                      _field('ELIGIBILITY', _minEligibility),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: rspFormSectionGap),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Candidates scoring table',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!ro)
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add candidate'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCandidatesScoringTable(ro),
            const SizedBox(height: 16),
            _field('Prepared by (Printed Name / Over Signature)', _preparedBy),
            if (!ro) ...[
              const SizedBox(height: 20),
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

  static const _scoreKeys = [
    ('education', 'Education', '25%'),
    ('eligibility', 'Eligibility', '20%'),
    ('experience', 'Experience', '15%'),
    ('training', 'Training', '10%'),
    ('performance', 'Performance', '10%'),
    ('potential', 'Potential', '10%'),
    ('workAttitude', 'Work attitude', '10%'),
  ];

  Widget _buildCandidatesScoringTable(bool ro) {
    const candidateWidth = 320.0;
    const scoreWidth = 96.0;
    const totalWidth = 88.0;
    const rankWidth = 80.0;
    const actionWidth = 52.0;

    TextStyle headerStyle(Color color) => TextStyle(
      color: color,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      height: 1.2,
    );

    Widget headerCell(String title, {String? weight, double? width}) {
      return SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, textAlign: TextAlign.center, style: headerStyle(Colors.white)),
            if (weight != null) ...[
              const SizedBox(height: 2),
              Text(
                weight,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.35),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: AppTheme.primaryNavy,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: candidateWidth,
                        child: headerCell('Name of candidates'),
                      ),
                      for (final (_, label, weight) in _scoreKeys)
                        headerCell(label, weight: weight, width: scoreWidth),
                      headerCell('Total', weight: '100%', width: totalWidth),
                      headerCell('Rank', width: rankWidth),
                      if (!ro) SizedBox(width: actionWidth),
                    ],
                  ),
                ),
                for (var i = 0; i < _rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: AppTheme.dashHairlineOf(context),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    color: AppTheme.white,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: candidateWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primaryNavy,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Candidate ${i + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.dashTextPrimaryOf(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _candidateDetailField(
                                '1. Name of candidate',
                                _rows[i]['name']!,
                                ro,
                              ),
                              _candidateDetailField(
                                '2. Position',
                                _rows[i]['position']!,
                                ro,
                              ),
                              _candidateDetailField(
                                '3. Salary grade',
                                _rows[i]['salaryGrade']!,
                                ro,
                              ),
                              _candidateDetailField(
                                '4. Rate',
                                _rows[i]['rate']!,
                                ro,
                              ),
                            ],
                          ),
                        ),
                        for (final score in _scoreKeys)
                          _scoreField(
                            _rows[i][score.$1]!,
                            ro,
                            width: scoreWidth,
                          ),
                        _scoreField(
                          _rows[i]['total']!,
                          ro,
                          width: totalWidth,
                          emphasized: true,
                        ),
                        _scoreField(
                          _rows[i]['rank']!,
                          ro,
                          width: rankWidth,
                          emphasized: true,
                        ),
                        if (!ro)
                          SizedBox(
                            width: actionWidth,
                            child: IconButton(
                              tooltip: 'Remove candidate',
                              onPressed: () => _removeRow(i),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 22,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _candidateDetailField(
    String label,
    TextEditingController c,
    bool ro,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RspSpacedOutlineField(
        child: TextFormField(
          controller: c,
          readOnly: ro,
          style: const TextStyle(fontSize: 14),
          decoration: rspUnderlinedField(label),
        ),
      ),
    );
  }

  Widget _scoreField(
    TextEditingController c,
    bool ro, {
    required double width,
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, right: 4),
      child: SizedBox(
        width: width,
        child: RspSpacedOutlineField(
          child: TextFormField(
            controller: c,
            readOnly: ro,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: emphasized ? 15 : 14,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            ),
            decoration: rspUnderlinedField(''),
          ),
        ),
      ),
    );
  }
}

class _ComputationOfPointsList extends StatelessWidget {
  const _ComputationOfPointsList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<ComputationOfPointsEntry> entries;
  final void Function(ComputationOfPointsEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ComputationOfPointsEntry) onPrint;
  final Future<void> Function(ComputationOfPointsEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Position', flex: 2.4),
      RspRecordsColumn('Date', flex: 1.4),
      RspRecordsColumn('Candidates', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(e.position ?? '', bold: true),
              rspRecordsTextCell(e.date ?? ''),
              rspRecordsTextCell(
                '${e.candidates.length}',
                align: TextAlign.center,
                bold: true,
              ),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Computation of points',
                  subtitle: e.position ?? '',
                  previewBuilder: () => ComputationOfPointsEditor(
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
                deleteDialogTitle: 'Delete record?',
              ),
            ],
          )
          .toList(),
    );
  }
}
