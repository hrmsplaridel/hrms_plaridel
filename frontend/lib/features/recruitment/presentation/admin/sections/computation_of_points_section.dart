import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// One Personnel Selection Board scoring criterion (row-map key, label, max points).
/// Order here drives the on-screen table only — the official print/PDF column
/// order lives independently in [FormPdf.buildComputationOfPointsPdf].
class _ScoreCriterion {
  const _ScoreCriterion(this.key, this.label, this.max);
  final String key;
  final String label;
  final double max;
}

const List<_ScoreCriterion> _scoreCriteria = [
  _ScoreCriterion('education', 'Education', 25),
  _ScoreCriterion('eligibility', 'Eligibility', 20),
  _ScoreCriterion('experience', 'Experience', 15),
  _ScoreCriterion('training', 'Training', 10),
  _ScoreCriterion('performance', 'Performance', 10),
  _ScoreCriterion('potential', 'Potential', 10),
  _ScoreCriterion('workAttitude', 'Work Attitude', 10),
];

double? _parseScore(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String _formatScore(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Friendly inline validation message for one score field, or null if valid.
String? _scoreFieldError(String raw, double max) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null) return 'Enter a valid number';
  if (v < 0) return 'Cannot be negative';
  if (v > max) return 'Max is ${_formatScore(max)}';
  return null;
}

/// Standard competition ranking: tied totals share a rank, and the next rank
/// skips ahead accordingly (e.g. 1, 1, 3).
Map<int, int> _computeRanks(Map<int, double> totalsByRowIndex) {
  final ordered = totalsByRowIndex.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final ranks = <int, int>{};
  var rank = 0;
  var position = 0;
  double? lastTotal;
  for (final entry in ordered) {
    position++;
    if (lastTotal == null || entry.value != lastTotal) {
      rank = position;
      lastTotal = entry.value;
    }
    ranks[entry.key] = rank;
  }
  return ranks;
}

/// A candidate "counts" toward ranking once a name has been entered.
bool _rowHasCandidate(Map<String, TextEditingController> row) =>
    row['name']!.text.trim().isNotEmpty;

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
        printModule: 'rsp',
        printFormKey: 'computation_of_points',
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

  Widget _toolbar(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: _loading ? null : _startNew,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add Record'),
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
              'Computation of Points',
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
          'Computation of Points',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Personnel Selection Board scoring and candidate evaluation.',
          style: TextStyle(color: secondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
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
                'No computation of points records yet. Tap "Add Record" to create one.',
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

/// Screen editor for a Computation of Points record.
///
/// This widget renders a modern HRMS data-entry experience only. It is
/// intentionally NOT styled like the official printed form — the print/PDF
/// output (see [FormPdf.buildComputationOfPointsPdf]) is a fully independent
/// template that reads the same [ComputationOfPointsEntry] data produced here.
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

  /// Row indices whose Position / Salary Grade / Rate details are expanded.
  final Set<int> _expandedDetails = {};

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
    _rows = e.candidates.map(_candidateRowFrom).toList();
    // Correct any legacy/blank Total & Rank values before the first frame.
    _recompute();
    for (final row in _rows) {
      _attachRowListeners(row);
    }
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

  void _attachRowListeners(Map<String, TextEditingController> row) {
    row['name']!.addListener(_handleLiveRecompute);
    for (final c in _scoreCriteria) {
      row[c.key]!.addListener(_handleLiveRecompute);
    }
  }

  void _handleLiveRecompute() {
    if (!mounted) return;
    setState(_recompute);
  }

  /// Recomputes Total (sum of the 7 scores, capped per-criterion) and Rank
  /// (standard competition ranking, highest Total = Rank 1) for every row.
  /// Only rows with a candidate name participate in ranking.
  void _recompute() {
    final totals = <int, double>{};
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (!_rowHasCandidate(row)) {
        row['total']!.text = '';
        continue;
      }
      var sum = 0.0;
      for (final c in _scoreCriteria) {
        final v = _parseScore(row[c.key]!.text);
        if (v == null) continue;
        sum += v.clamp(0, c.max);
      }
      // Always two decimals for Total, matching the official form's display.
      row['total']!.text = sum.toStringAsFixed(2);
      totals[i] = sum;
    }
    final ranks = _computeRanks(totals);
    for (var i = 0; i < _rows.length; i++) {
      _rows[i]['rank']!.text = ranks.containsKey(i) ? ranks[i].toString() : '';
    }
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

  void _addRow() {
    final row = _candidateRow();
    _attachRowListeners(row);
    setState(() {
      _rows.add(row);
      _recompute();
    });
  }

  Future<void> _confirmRemoveRow(int i) async {
    if (i < 0 || i >= _rows.length) return;
    final name = _rows[i]['name']!.text.trim();
    final label = name.isEmpty ? 'Candidate ${i + 1}' : name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove candidate?'),
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
    if (ok == true) _removeRow(i);
  }

  void _removeRow(int i) {
    if (i < 0 || i >= _rows.length) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
      final shifted = <int>{
        for (final idx in _expandedDetails)
          if (idx != i) (idx > i ? idx - 1 : idx),
      };
      _expandedDetails
        ..clear()
        ..addAll(shifted);
      _recompute();
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

  String? _findValidationError() {
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (!_rowHasCandidate(row)) continue;
      for (final c in _scoreCriteria) {
        final err = _scoreFieldError(row[c.key]!.text, c.max);
        if (err != null) {
          final name = row['name']!.text.trim();
          final label = name.isEmpty ? 'Candidate ${i + 1}' : name;
          return '$label — ${c.label}: $err';
        }
      }
    }
    return null;
  }

  void _handleSaveTap() {
    final err = _findValidationError();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fix invalid scores. $err'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    widget.onSave(_buildEntry());
  }

  static DateTime? _tryParseDate(String raw) {
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
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    final named = RegExp(
      r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$',
    ).firstMatch(s);
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

  static String _formatCopDate(DateTime date) {
    const monthNames = <String>[
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
    final d = date.toLocal();
    return '${monthNames[d.month - 1]} ${d.day}, ${d.year}';
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
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() => _date.text = _formatCopDate(picked));
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
    final title = position.isEmpty ? 'New Computation of Points' : position;
    final statusLabel = ro
        ? 'Read-only preview'
        : (widget.entry.id == null ? 'Draft' : 'Saved');
    final statusColor = ro
        ? Colors.blueGrey
        : (widget.entry.id == null
              ? const Color(0xFFB26A00)
              : const Color(0xFF2E7D32));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
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
              'Personnel Selection Board scoring and candidate evaluation',
              style: TextStyle(fontSize: 12.5, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
    Widget? suffixIcon,
  }) => AppTheme.dashInputDecoration(
    context,
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
  );

  Widget _dateField(bool ro) {
    return TextFormField(
      controller: _date,
      readOnly: true,
      onTap: ro ? null : _pickDate,
      decoration: _decoration(
        context,
        label: 'Date',
        hint: ro ? null : 'Select date',
        suffixIcon: ro
            ? null
            : IconButton(
                tooltip: 'Pick date',
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                onPressed: _pickDate,
              ),
      ),
    );
  }

  Widget _textField(
    TextEditingController c,
    String label,
    bool ro, {
    String? hint,
  }) {
    return TextFormField(
      controller: c,
      readOnly: ro,
      decoration: _decoration(context, label: label, hint: hint),
    );
  }

  Widget _responsivePairs(
    List<(Widget, Widget)> pairs, {
    double breakpoint = 640,
  }) {
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

  Widget _positionInformationCard(BuildContext context, bool ro) {
    return _infoCard(
      context: context,
      title: 'POSITION INFORMATION',
      pairs: [
        (
          _dateField(ro),
          _textField(
            _positionLevel,
            'Position Level',
            ro,
            hint: 'e.g. Second Level Position',
          ),
        ),
        (
          _textField(_position, 'Position', ro, hint: 'e.g. Administrative Officer II'),
          _textField(_office, 'Office', ro, hint: 'e.g. Office of the Municipal Mayor'),
        ),
        (
          _textField(_salaryGrade, 'Salary Grade', ro, hint: 'e.g. SG-11'),
          _textField(_rate, 'Rate', ro, hint: 'e.g. 25,439.00'),
        ),
      ],
    );
  }

  Widget _minimumRequirementsCard(BuildContext context, bool ro) {
    return _infoCard(
      context: context,
      title: 'MINIMUM REQUIREMENTS',
      pairs: [
        (
          _textField(_minEducation, 'Education', ro, hint: "e.g. Bachelor's degree"),
          _textField(_minTraining, 'Training', ro, hint: 'e.g. 8 hours relevant training'),
        ),
        (
          _textField(_minExperience, 'Experience', ro, hint: 'e.g. 1 year relevant experience'),
          _textField(_minEligibility, 'Eligibility', ro, hint: 'e.g. Career Service (Professional)'),
        ),
      ],
    );
  }

  Widget _criterionChip(BuildContext context, _ScoreCriterion c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        '${c.label} ${_formatScore(c.max)}%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
    );
  }

  Widget _scoringSectionHeader(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final candidateCount = _rows.length;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      runSpacing: 12,
      spacing: 16,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Candidate Scoring',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$candidateCount candidate(s)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _scoreCriteria
                    .map((c) => _criterionChip(context, c))
                    .toList(),
              ),
            ],
          ),
        ),
        if (!ro)
          FilledButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Candidate'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy),
          ),
      ],
    );
  }

  Widget _totalDisplay(TextEditingController totalController) {
    final text = totalController.text.trim();
    final has = text.isNotEmpty;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          has ? text : '—',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: has ? AppTheme.primaryNavy : secondary,
          ),
        ),
        Text('/ 100', style: TextStyle(fontSize: 9, color: secondary)),
      ],
    );
  }

  Widget _rankDisplay(TextEditingController rankController) {
    final text = rankController.text.trim();
    final has = text.isNotEmpty;
    final isTop = has && text == '1';
    final bg = isTop
        ? Colors.amber.withValues(alpha: 0.18)
        : AppTheme.dashPanelOf(context);
    final fg = isTop ? Colors.amber.shade900 : AppTheme.dashTextPrimaryOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isTop ? Colors.amber.shade400 : AppTheme.dashHairlineOf(context),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTop) ...[
            Icon(Icons.emoji_events_rounded, size: 13, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            has ? '#$text' : '—',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _scoreField(
    Map<String, TextEditingController> row,
    _ScoreCriterion c,
    bool ro,
  ) {
    final controller = row[c.key]!;
    final error = _scoreFieldError(controller.text, c.max);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: controller,
          readOnly: ro,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
          decoration: AppTheme.dashInputDecoration(context, hintText: '0')
              .copyWith(
                errorText: error,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
              ),
        ),
        const SizedBox(height: 4),
        Text(
          error == null ? 'max ${_formatScore(c.max)}' : '',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  Widget _candidateDetailsToggle(int i, bool ro) {
    final expanded = _expandedDetails.contains(i);
    return Tooltip(
      message: 'Position, salary grade, and rate for this candidate',
      child: InkWell(
        onTap: () => setState(() {
          if (expanded) {
            _expandedDetails.remove(i);
          } else {
            _expandedDetails.add(i);
          }
        }),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 16,
                color: AppTheme.primaryNavy,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  expanded ? 'Hide details' : 'Candidate details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallField(TextEditingController c, String label, bool ro) {
    return TextFormField(
      controller: c,
      readOnly: ro,
      style: const TextStyle(fontSize: 12.5),
      decoration: AppTheme.dashInputDecoration(context, labelText: label).copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _candidateDetailsFields(int i, bool ro) {
    final row = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _smallField(row['position']!, 'Position', ro),
          const SizedBox(height: 8),
          _smallField(row['salaryGrade']!, 'Salary Grade', ro),
          const SizedBox(height: 8),
          _smallField(row['rate']!, 'Rate', ro),
        ],
      ),
    );
  }

  Widget _candidateNameCell(int i, bool ro) {
    final row = _rows[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryNavy,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: row['name']!,
                readOnly: ro,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
                decoration:
                    AppTheme.dashInputDecoration(
                      context,
                      hintText: 'Candidate name',
                    ).copyWith(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _candidateDetailsToggle(i, ro),
        if (_expandedDetails.contains(i)) _candidateDetailsFields(i, ro),
      ],
    );
  }

  Widget _scoringTable(BuildContext context, bool ro) {
    const cellPad = EdgeInsets.symmetric(horizontal: 8, vertical: 12);
    const minName = 220.0;
    const minScore = 92.0;
    const minTotal = 80.0;
    const minRank = 68.0;
    const minAction = 48.0;
    final minTableWidth = minName +
        (minScore * _scoreCriteria.length) +
        minTotal +
        minRank +
        (ro ? 0.0 : minAction);

    final columnWidths = <int, TableColumnWidth>{
      0: const FlexColumnWidth(2.6),
      for (var i = 0; i < _scoreCriteria.length; i++)
        i + 1: const FlexColumnWidth(1.15),
      8: const FlexColumnWidth(1.0),
      9: const FlexColumnWidth(0.85),
      if (!ro) 10: const FlexColumnWidth(0.55),
    };

    Widget headerCell(String label, {String? sub}) {
      return Padding(
        padding: cellPad,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget pad(Widget child) => Padding(padding: cellPad, child: child);

    final header = TableRow(
      decoration: const BoxDecoration(color: AppTheme.primaryNavy),
      children: [
        headerCell('Candidate'),
        for (final c in _scoreCriteria)
          headerCell(c.label, sub: '${_formatScore(c.max)}%'),
        headerCell('Total', sub: '100%'),
        headerCell('Rank'),
        if (!ro) const SizedBox.shrink(),
      ],
    );

    final bodyRows = <TableRow>[
      for (var i = 0; i < _rows.length; i++)
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd
                ? AppTheme.dashMutedSurfaceOf(context)
                : AppTheme.dashPanelOf(context),
          ),
          children: [
            pad(_candidateNameCell(i, ro)),
            for (final c in _scoreCriteria) pad(_scoreField(_rows[i], c, ro)),
            pad(Center(child: _totalDisplay(_rows[i]['total']!))),
            pad(Center(child: _rankDisplay(_rows[i]['rank']!))),
            if (!ro)
              pad(
                IconButton(
                  tooltip: 'Remove candidate',
                  onPressed: () => _confirmRemoveRow(i),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 22,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
          ],
        ),
    ];

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth.isFinite
                ? (constraints.maxWidth < minTableWidth
                      ? minTableWidth
                      : constraints.maxWidth)
                : minTableWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Table(
                      columnWidths: columnWidths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: AppTheme.dashHairlineOf(context),
                        ),
                      ),
                      children: [header, ...bodyRows],
                    ),
                  ),
                ),
                if (_rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 16,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 32,
                          color: AppTheme.dashTextSecondaryOf(
                            context,
                          ).withValues(alpha: 0.45),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No candidates yet. Tap “Add Candidate” to start scoring.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.dashTextSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _candidateCard(BuildContext context, int i, bool ro) {
    final row = _rows[i];
    return Container(
      padding: const EdgeInsets.all(14),
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
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Candidate ${i + 1}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ),
              if (!ro)
                IconButton(
                  tooltip: 'Remove candidate',
                  onPressed: () => _confirmRemoveRow(i),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Colors.red.shade700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row['name']!,
            readOnly: ro,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Candidate Name',
              hintText: 'Full name',
            ),
          ),
          const SizedBox(height: 8),
          _candidateDetailsToggle(i, ro),
          if (_expandedDetails.contains(i)) _candidateDetailsFields(i, ro),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _scoreCriteria)
                SizedBox(width: 140, child: _scoreField(row, c, ro)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.dashMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text('TOTAL', style: AppTheme.dashSectionTitle(context)),
                      const SizedBox(height: 4),
                      _totalDisplay(row['total']!),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.dashMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text('RANK', style: AppTheme.dashSectionTitle(context)),
                      const SizedBox(height: 4),
                      _rankDisplay(row['rank']!),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoringCards(BuildContext context, bool ro) {
    if (_rows.isEmpty) {
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
              color: AppTheme.dashTextSecondaryOf(
                context,
              ).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            Text(
              'No candidates yet. Tap “Add Candidate” to start scoring.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _candidateCard(context, i, ro),
        ],
      ],
    );
  }

  static String _initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _signatureSpace(BuildContext context) {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 8),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
    );
  }

  Widget _preparedByCard(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.14),
            child: Text(
              _initialsOf(_preparedBy.text),
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PREPARED BY', style: AppTheme.dashSectionTitle(context)),
                const SizedBox(height: 6),
                _signatureSpace(context),
                ro
                    ? Text(
                        _preparedBy.text.trim().isEmpty
                            ? '—'
                            : _preparedBy.text.trim(),
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : TextFormField(
                        controller: _preparedBy,
                        onChanged: (_) => setState(() {}),
                        decoration: AppTheme.dashInputDecoration(
                          context,
                          hintText: 'Printed Name / Over Signature',
                        ),
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                const SizedBox(height: 6),
                Text(
                  '(Printed Name/Over Signature)',
                  style: TextStyle(fontSize: 11, color: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 12,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _handleSaveTap,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
            ),
            OutlinedButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Print',
              style: rspLdRecordIconButtonStyle(),
              onPressed: () => widget.onPrint(_buildEntry()),
              icon: const Icon(Icons.print_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Export PDF',
              style: rspLdRecordIconButtonStyle(),
              onPressed: () => widget.onDownloadPdf(_buildEntry()),
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
                _positionInformationCard(context, ro),
                const SizedBox(height: 20),
                _minimumRequirementsCard(context, ro),
                const SizedBox(height: 24),
                _scoringSectionHeader(context, ro),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final mobile = constraints.maxWidth < 760;
                    return mobile
                        ? _scoringCards(context, ro)
                        : _scoringTable(context, ro);
                  },
                ),
                const SizedBox(height: 20),
                _preparedByCard(context, ro),
                if (!ro) ...[
                  const SizedBox(height: 24),
                  _actionBar(context),
                ],
                if (ro &&
                    (widget.entry.createdAt != null ||
                        widget.entry.updatedAt != null)) ...[
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

String _dashRecordStatus(ComputationOfPointsEntry e) {
  if (e.candidates.isEmpty) return 'Draft';
  final anyScored = e.candidates.any((c) => (c.total ?? '').trim().isNotEmpty);
  return anyScored ? 'Scored' : 'Draft';
}

ComputationOfPointsCandidate? _dashTopCandidate(ComputationOfPointsEntry e) {
  ComputationOfPointsCandidate? best;
  var bestTotal = double.negativeInfinity;
  for (final c in e.candidates) {
    final t = double.tryParse((c.total ?? '').trim());
    if (t != null && t > bestTotal) {
      bestTotal = t;
      best = c;
    }
  }
  return best;
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

  Widget _statusCell(BuildContext context, String status) {
    final scored = status == 'Scored';
    final color = scored ? const Color(0xFF2E7D32) : const Color(0xFFB26A00);
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
      RspRecordsColumn('Position', flex: 2.0),
      RspRecordsColumn('Date', flex: 1.2),
      RspRecordsColumn('Candidates', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Top Candidate', flex: 1.8),
      RspRecordsColumn('Status', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map((e) {
            final top = _dashTopCandidate(e);
            final topLabel = top == null
                ? ''
                : '${top.name ?? "—"}${top.total != null ? " (${top.total})" : ""}';
            return [
              rspRecordsTextCell(context, e.position ?? '', bold: true),
              rspRecordsTextCell(context, e.date ?? ''),
              rspRecordsTextCell(
                context,
                '${e.candidates.length}',
                align: TextAlign.center,
                bold: true,
              ),
              rspRecordsTextCell(context, topLabel),
              _statusCell(context, _dashRecordStatus(e)),
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
            ];
          })
          .toList(),
    );
  }
}
