import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_need_analysis.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// Lightweight employee-directory entry for the "Employee" search field in
/// the Add/Edit modal. Reuses the existing [GET /api/employees] list — no
/// second employee database is created for this form.
class _TnaEmployeeOption {
  const _TnaEmployeeOption({
    required this.id,
    required this.fullName,
    this.positionName,
    this.departmentName,
  });

  final String id;
  final String fullName;
  final String? positionName;
  final String? departmentName;
}

Future<List<_TnaEmployeeOption>> _fetchActiveEmployeeOptions() async {
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
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          return _TnaEmployeeOption(
            id: m['id']?.toString() ?? '',
            fullName: m['full_name']?.toString() ?? '',
            positionName: m['current_position_name']?.toString(),
            departmentName: m['current_department_name']?.toString(),
          );
        })
        .where((e) => e.id.isNotEmpty && e.fullName.trim().isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Existing HRMS office/department names — reused for the "Department"
/// picker. Falls back to free-text entry if this can't be loaded, so
/// behavior is preserved when no office master data exists.
Future<List<String>> _fetchActiveOfficeNames() async {
  try {
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/offices',
      queryParameters: {'status': 'Active'},
    );
    final data = res.data ?? const [];
    final names = data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e)['name']?.toString() ?? '')
        .where((n) => n.trim().isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  } catch (_) {
    return const [];
  }
}

/// Splits the single stored `name_position` field into Name + Position for
/// the editor UI. Legacy free-text rows that don't use the " / " separator
/// fall back to Name-only (no data is dropped — see [_joinNamePosition]).
(String, String) _splitNamePosition(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return ('', '');
  for (final sep in [' / ', '\n', ' — ', ' - ', ' | ']) {
    final i = t.indexOf(sep);
    if (i != -1) {
      return (t.substring(0, i).trim(), t.substring(i + sep.length).trim());
    }
  }
  return (t, '');
}

/// Rejoins Name + Position into the single stored/printed field. The
/// official form has one "NAME/POSITION" column (see
/// [FormPdf.buildTrainingNeedAnalysisPdf]) — this keeps that contract intact.
String _joinNamePosition(String name, String position) {
  final n = name.trim();
  final p = position.trim();
  if (n.isEmpty) return p;
  if (p.isEmpty) return n;
  return '$n / $p';
}

/// Recent-year choices for the "Report Year" picker, always including the
/// entry's existing value (so older/unusual years aren't dropped).
List<String> _tnaYearOptions({String? include}) {
  final now = DateTime.now().year;
  final years = <String>{for (var y = now + 1; y >= now - 8; y--) '$y'};
  final inc = include?.trim();
  if (inc != null && inc.isNotEmpty) years.add(inc);
  final list = years.toList()..sort((a, b) => b.compareTo(a));
  return list;
}

/// L&D: Training Need Analysis and Consolidated Report — list entries and
/// add/edit a report.
///
/// Screen UI here is a modern HR/L&D data-entry interface. Print/PDF (see
/// [FormPdf.buildTrainingNeedAnalysisPdf]) is a fully independent template
/// that reproduces the official six-column paper form from the same
/// [TrainingNeedAnalysisEntry] data — it is intentionally not touched by
/// this redesign.
class TrainingNeedAnalysisAdminSection extends StatefulWidget {
  const TrainingNeedAnalysisAdminSection({super.key});

  @override
  State<TrainingNeedAnalysisAdminSection> createState() =>
      _TrainingNeedAnalysisAdminSectionState();
}

class _TrainingNeedAnalysisAdminSectionState
    extends State<TrainingNeedAnalysisAdminSection> {
  List<TrainingNeedAnalysisEntry> _entries = [];
  bool _loading = true;
  TrainingNeedAnalysisEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TrainingNeedAnalysisRepo.instance.list();
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
      setState(() => _editing = const TrainingNeedAnalysisEntry());
  void _edit(TrainingNeedAnalysisEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(TrainingNeedAnalysisEntry entry) async {
    try {
      if (entry.id == null) {
        await TrainingNeedAnalysisRepo.instance.insert(entry);
      } else {
        await TrainingNeedAnalysisRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Training Need Analysis saved.')),
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
      await TrainingNeedAnalysisRepo.instance.delete(id);
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

  Future<void> _print(TrainingNeedAnalysisEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildTrainingNeedAnalysisPdf(entry),
        filename: 'Training_Need_Analysis.pdf',
        format: FormPdf.pageLetterLandscape,
        printModule: 'ld',
        printFormKey: 'training_need_analysis',
      );
    } catch (_) {}
  }

  Future<void> _download(TrainingNeedAnalysisEntry entry) async {
    try {
      final doc = await FormPdf.buildTrainingNeedAnalysisPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Training_Need_Analysis.pdf');
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
      sheetTitle: 'Saved Training Need Analysis reports',
      emptyMessage: 'No reports yet.',
      loading: _loading,
      items: _entries.map((e) {
        final cy = e.cyYear?.trim().isNotEmpty == true ? e.cyYear! : 'No year';
        final dept = e.department?.trim().isNotEmpty == true
            ? e.department!
            : 'No department';
        return SavedRecordListItem(
          title: 'CY $cy',
          subtitle: '$dept · ${e.rows.length} employee(s)',
          detailDialogTitle: 'Training Need Analysis — CY $cy',
          previewContentWidth: 1000,
          previewBuilder: () => TrainingNeedAnalysisEditor(
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
          label: const Text('New Report'),
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
        Text(
          'Training Need Analysis & Consolidated Report',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Identify employee development needs and recommended training.',
          style: TextStyle(color: secondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          TrainingNeedAnalysisEditor(
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
                'No reports yet. Tap "New Report" to create a Training Need Analysis.',
            icon: Icons.school_outlined,
          )
        else
          _TrainingNeedAnalysisList(
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

/// Screen editor for a Training Need Analysis report.
///
/// This widget renders a modern HR/L&D data-entry experience only. It is
/// intentionally NOT styled like the official printed form — the print/PDF
/// output (see [FormPdf.buildTrainingNeedAnalysisPdf]) is a fully
/// independent template that reads the same [TrainingNeedAnalysisEntry]
/// data produced here.
class TrainingNeedAnalysisEditor extends StatefulWidget {
  const TrainingNeedAnalysisEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final TrainingNeedAnalysisEntry entry;
  final bool readOnly;
  final void Function(TrainingNeedAnalysisEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(TrainingNeedAnalysisEntry) onPrint;
  final Future<void> Function(TrainingNeedAnalysisEntry) onDownloadPdf;

  @override
  State<TrainingNeedAnalysisEditor> createState() =>
      _TrainingNeedAnalysisEditorState();
}

class _TrainingNeedAnalysisEditorState
    extends State<TrainingNeedAnalysisEditor> {
  String? _cyYear;
  String? _department;
  late final TextEditingController _departmentController;
  late List<TrainingNeedAnalysisRow> _rows;

  List<_TnaEmployeeOption> _employees = [];
  List<String> _officeNames = [];
  bool _officesLoaded = false;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _cyYear = e.cyYear?.trim().isNotEmpty == true ? e.cyYear!.trim() : null;
    if (_cyYear == null && e.id == null) {
      // New report: default to the current year for convenience only.
      _cyYear = DateTime.now().year.toString();
    }
    _department = e.department?.trim().isNotEmpty == true
        ? e.department!.trim()
        : null;
    _departmentController = TextEditingController(text: _department ?? '');
    _departmentController.addListener(() {
      _department = _departmentController.text.trim().isEmpty
          ? null
          : _departmentController.text.trim();
    });
    _rows = List<TrainingNeedAnalysisRow>.from(e.rows);
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
    if (!widget.readOnly) {
      _loadEmployees();
      _loadOffices();
    }
  }

  Future<void> _loadEmployees() async {
    final list = await _fetchActiveEmployeeOptions();
    if (!mounted) return;
    setState(() => _employees = list);
  }

  Future<void> _loadOffices() async {
    final list = await _fetchActiveOfficeNames();
    if (!mounted) return;
    setState(() {
      _officeNames = list;
      _officesLoaded = list.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  TrainingNeedAnalysisEntry _buildEntry() {
    return TrainingNeedAnalysisEntry(
      id: widget.entry.id,
      cyYear: _cyYear,
      department: _department,
      rows: _rows,
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildEntry());
  }

  Future<void> _addEmployee() async {
    final result = await showDialog<TrainingNeedAnalysisRow>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _TnaEmployeeEditorDialog(isNew: true, employees: _employees),
    );
    if (result == null || !mounted) return;
    setState(() => _rows.add(result));
  }

  Future<void> _editEmployee(int i) async {
    final result = await showDialog<TrainingNeedAnalysisRow>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TnaEmployeeEditorDialog(
        isNew: false,
        initial: _rows[i],
        employees: _employees,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _rows[i] = result);
  }

  Future<void> _confirmRemoveEmployee(int i) async {
    final (name, _) = _splitNamePosition(_rows[i].namePosition);
    final label = name.isEmpty ? 'Employee ${i + 1}' : name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove employee?'),
        content: Text(
          'Are you sure you want to remove $label from this report? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _rows.removeAt(i));
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
    Widget? prefixIcon,
  }) => AppTheme.dashInputDecoration(
    context,
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
  );

  Widget _readOnlyValueBox(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportInformationCard(BuildContext context, bool ro) {
    final yearField = ro
        ? _readOnlyValueBox(context, 'Report Year', _cyYear ?? '—')
        : DropdownButtonFormField<String>(
            initialValue: _cyYear,
            items: [
              for (final y in _tnaYearOptions(include: _cyYear))
                DropdownMenuItem(value: y, child: Text(y)),
            ],
            onChanged: (v) => setState(() => _cyYear = v),
            decoration: _decoration(
              context,
              label: 'Report Year',
              hint: 'Select year',
            ),
          );

    final deptField = ro
        ? _readOnlyValueBox(context, 'Department', _department ?? '—')
        : (_officesLoaded
              ? DropdownButtonFormField<String>(
                  initialValue: _department,
                  items: [
                    for (final name in <String>{
                      ..._officeNames,
                      if (_department != null) _department!,
                    })
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (v) => setState(() => _department = v),
                  decoration: _decoration(
                    context,
                    label: 'Department',
                    hint: 'Select department',
                  ),
                )
              : TextFormField(
                  controller: _departmentController,
                  decoration: _decoration(
                    context,
                    label: 'Department',
                    hint: 'e.g. Rural Health Unit',
                  ),
                ));

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
          Text(
            'REPORT INFORMATION',
            style: AppTheme.dashSectionTitle(context),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 520;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: yearField),
                        const SizedBox(width: 14),
                        Expanded(flex: 2, child: deptField),
                      ],
                    )
                  : Column(
                      children: [
                        yearField,
                        const SizedBox(height: 14),
                        deptField,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _employeesHeader(BuildContext context, bool ro) {
    final count = _rows.length;
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 16,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Employee Training Needs',
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
                '$count ${count == 1 ? 'Employee' : 'Employees'}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryNavy,
                ),
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
                hint: 'Search employee...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
        if (!ro)
          FilledButton.icon(
            onPressed: _addEmployee,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Employee'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
            ),
          ),
      ],
    );
  }

  List<int> get _filteredIndices {
    if (_query.isEmpty) return List.generate(_rows.length, (i) => i);
    final out = <int>[];
    for (var i = 0; i < _rows.length; i++) {
      final (name, position) = _splitNamePosition(_rows[i].namePosition);
      if (name.toLowerCase().contains(_query) ||
          position.toLowerCase().contains(_query)) {
        out.add(i);
      }
    }
    return out;
  }

  Widget _employeesBody(BuildContext context, bool ro) {
    if (_rows.isEmpty) {
      return RspFormEmptyState(
        message: ro
            ? 'No employees recorded.'
            : 'No employees yet. Tap "Add Employee" to start.',
        icon: Icons.people_outline_rounded,
      );
    }
    final indices = _filteredIndices;
    if (indices.isEmpty) {
      return RspFormEmptyState(
        message: 'No employees match "${_search.text.trim()}".',
        icon: Icons.search_off_rounded,
      );
    }
    return Column(
      children: [
        for (var pos = 0; pos < indices.length; pos++) ...[
          if (pos > 0) const SizedBox(height: 12),
          _TnaEmployeeCard(
            index: indices[pos],
            row: _rows[indices[pos]],
            readOnly: ro,
            expanded: _expanded.contains(indices[pos]),
            onToggleExpand: () => setState(() {
              final idx = indices[pos];
              if (_expanded.contains(idx)) {
                _expanded.remove(idx);
              } else {
                _expanded.add(idx);
              }
            }),
            onEdit: ro ? null : () => _editEmployee(indices[pos]),
            onRemove: ro ? null : () => _confirmRemoveEmployee(indices[pos]),
          ),
        ],
      ],
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
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Report'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
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

  Widget _headerBar(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final title = _cyYear != null
        ? 'Training Need Analysis — CY $_cyYear'
        : 'New Training Need Analysis';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
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
            const SizedBox(height: 4),
            Text(
              'Identify employee development needs and recommended training.',
              style: TextStyle(fontSize: 12.5, color: secondary),
            ),
          ],
        ),
      ),
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
                _reportInformationCard(context, ro),
                const SizedBox(height: 24),
                _employeesHeader(context, ro),
                const SizedBox(height: 14),
                _employeesBody(context, ro),
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

/// Compact summary card for one employee's training need — prominent Need
/// for Training / Recommendation, with an expandable area for the longer
/// Goal / Behavior / Skills-Knowledge assessment fields.
class _TnaEmployeeCard extends StatelessWidget {
  const _TnaEmployeeCard({
    required this.index,
    required this.row,
    required this.readOnly,
    required this.expanded,
    required this.onToggleExpand,
    this.onEdit,
    this.onRemove,
  });

  final int index;
  final TrainingNeedAnalysisRow row;
  final bool readOnly;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  Widget _detailBlock(BuildContext context, String label, String? value) {
    final v = value?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            v == null || v.isEmpty ? '—' : v,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.dashTextPrimaryOf(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (name, position) = _splitNamePosition(row.namePosition);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Employee ${index + 1}' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        position,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: secondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 480;
              final needBlock = _detailBlock(
                context,
                'Need for Training',
                row.needForTraining,
              );
              final recBlock = _detailBlock(
                context,
                'Training Recommendation',
                row.trainingRecommendations,
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: needBlock),
                        const SizedBox(width: 16),
                        Expanded(child: recBlock),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [needBlock, recBlock],
                    );
            },
          ),
          TextButton.icon(
            onPressed: onToggleExpand,
            icon: Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
            ),
            label: Text(expanded ? 'Hide details' : 'View details'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 10),
            _detailBlock(context, 'Goal', row.goal),
            _detailBlock(context, 'Behavior', row.behavior),
            _detailBlock(context, 'Skills / Knowledge', row.skillsKnowledge),
          ],
          if (!readOnly) ...[
            const SizedBox(height: 4),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Colors.red.shade700,
                  ),
                  label: Text(
                    'Remove',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Add / Edit Training Need modal. Organizes fields as Employee (with
/// optional search/select against existing HRMS employee records) and
/// Training Need Assessment (Goal, Behavior, Skills/Knowledge, Need for
/// Training, Training Recommendations).
class _TnaEmployeeEditorDialog extends StatefulWidget {
  const _TnaEmployeeEditorDialog({
    required this.isNew,
    required this.employees,
    this.initial,
  });

  final bool isNew;
  final List<_TnaEmployeeOption> employees;
  final TrainingNeedAnalysisRow? initial;

  @override
  State<_TnaEmployeeEditorDialog> createState() =>
      _TnaEmployeeEditorDialogState();
}

class _TnaEmployeeEditorDialogState extends State<_TnaEmployeeEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _position;
  late final TextEditingController _goal;
  late final TextEditingController _behavior;
  late final TextEditingController _skills;
  late final TextEditingController _need;
  late final TextEditingController _recommendations;
  final FocusNode _nameFocus = FocusNode();
  String? _nameError;
  String? _pickedDepartment;

  @override
  void initState() {
    super.initState();
    final (name, position) = _splitNamePosition(widget.initial?.namePosition);
    _name = TextEditingController(text: name);
    _position = TextEditingController(text: position);
    _goal = TextEditingController(text: widget.initial?.goal ?? '');
    _behavior = TextEditingController(text: widget.initial?.behavior ?? '');
    _skills = TextEditingController(
      text: widget.initial?.skillsKnowledge ?? '',
    );
    _need = TextEditingController(text: widget.initial?.needForTraining ?? '');
    _recommendations = TextEditingController(
      text: widget.initial?.trainingRecommendations ?? '',
    );
    _nameFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _position,
      _goal,
      _behavior,
      _skills,
      _need,
      _recommendations,
    ]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _selectEmployee(_TnaEmployeeOption e) {
    setState(() {
      _name.text = e.fullName;
      if ((e.positionName ?? '').trim().isNotEmpty) {
        _position.text = e.positionName!.trim();
      }
      _pickedDepartment = e.departmentName;
    });
    _nameFocus.unfocus();
  }

  String? _optional(String v) => v.trim().isEmpty ? null : v.trim();

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Please select or enter an employee name.');
      return;
    }
    Navigator.of(context).pop(
      TrainingNeedAnalysisRow(
        namePosition: _joinNamePosition(name, _position.text),
        goal: _optional(_goal.text),
        behavior: _optional(_behavior.text),
        skillsKnowledge: _optional(_skills.text),
        needForTraining: _optional(_need.text),
        trainingRecommendations: _optional(_recommendations.text),
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
  }) => AppTheme.dashInputDecoration(context, labelText: label, hintText: hint);

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(text, style: AppTheme.dashSectionTitle(context)),
  );

  List<_TnaEmployeeOption> get _matches {
    final q = _name.text.trim().toLowerCase();
    if (q.isEmpty || widget.employees.isEmpty) return const [];
    return widget.employees
        .where((e) => e.fullName.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width < 620 ? size.width - 32 : 560.0;
    final maxH = size.height - 80;
    final matches = _matches;
    final showSuggestions =
        widget.employees.isNotEmpty && _nameFocus.hasFocus && matches.isNotEmpty;

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
                gradient: LinearGradient(
                  colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isNew ? 'Add Employee' : 'Edit Training Need',
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
                    Text('EMPLOYEE', style: AppTheme.dashSectionTitle(context)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _name,
                      focusNode: _nameFocus,
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        } else {
                          setState(() {});
                        }
                      },
                      decoration: _decoration(
                        context,
                        label: 'Employee / Name',
                        hint: widget.employees.isNotEmpty
                            ? 'Search or type a name'
                            : 'Full name',
                      ).copyWith(errorText: _nameError),
                    ),
                    if (showSuggestions)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: AppTheme.dashPanelOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.dashHairlineOf(context),
                          ),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
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
                                subtitle: Text(
                                  [m.positionName, m.departmentName]
                                      .where((s) => (s ?? '').trim().isNotEmpty)
                                      .join(' · '),
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                onTap: () => _selectEmployee(m),
                              ),
                          ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _position,
                      decoration: _decoration(
                        context,
                        label: 'Position',
                        hint: 'e.g. Administrative Officer II',
                      ),
                    ),
                    if ((_pickedDepartment ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Department on file: ${_pickedDepartment!.trim()}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                    ],
                    _sectionLabel(context, 'TRAINING NEED ASSESSMENT'),
                    TextFormField(
                      controller: _goal,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _decoration(
                        context,
                        label: 'Goal',
                        hint: 'Departmental / individual goal this addresses',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _behavior,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _decoration(
                        context,
                        label: 'Behavior',
                        hint: 'Observed behavior or performance gap',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _skills,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _decoration(
                        context,
                        label: 'Skills / Knowledge',
                        hint: 'Skill or knowledge gap identified',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _need,
                      minLines: 1,
                      maxLines: 3,
                      decoration: _decoration(
                        context,
                        label: 'Need for Training',
                        hint: 'e.g. Records Management',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _recommendations,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _decoration(
                        context,
                        label: 'Training Recommendations',
                        hint: 'Recommended training / workshop',
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
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                    ),
                    child: Text(widget.isNew ? 'Add to Report' : 'Save Changes'),
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

class _TrainingNeedAnalysisList extends StatelessWidget {
  const _TrainingNeedAnalysisList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<TrainingNeedAnalysisEntry> entries;
  final void Function(TrainingNeedAnalysisEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(TrainingNeedAnalysisEntry) onPrint;
  final Future<void> Function(TrainingNeedAnalysisEntry) onDownloadPdf;

  String _formatUpdated(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('CY', flex: 0.8),
      RspRecordsColumn('Department', flex: 1.8),
      RspRecordsColumn('Employees', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Last Updated', flex: 1.3),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, e.cyYear ?? '', bold: true),
              rspRecordsTextCell(context, e.department ?? ''),
              rspRecordsTextCell(
                context,
                '${e.rows.length}',
                align: TextAlign.center,
                bold: true,
              ),
              rspRecordsTextCell(
                context,
                _formatUpdated(e.updatedAt ?? e.createdAt),
              ),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Training Need Analysis',
                  subtitle: 'CY ${e.cyYear ?? '—'} · ${e.department ?? '—'}',
                  previewBuilder: () => TrainingNeedAnalysisEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 1000,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete report?',
              ),
            ],
          )
          .toList(),
    );
  }
}
