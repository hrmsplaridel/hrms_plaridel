import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// Official paper worksheet has 15 numbered rows. Existing save/PDF logic
/// does not enforce this as a hard maximum — it is print-page capacity.
const int _kOfficialPrintRowCapacity = 15;

const String _kOfficialInstruction =
    'Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.';

/// Screen-only display extras (position / office). The official form and
/// [ActionBrainstormingRow] store NAME only.
class _AbDisplayRow {
  const _AbDisplayRow({
    required this.row,
    this.position,
    this.office,
  });

  final ActionBrainstormingRow row;
  final String? position;
  final String? office;

  String get name => row.name?.trim() ?? '';
}

class _AbEmployeeOption {
  const _AbEmployeeOption({
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

Future<List<_AbEmployeeOption>> _fetchActiveEmployeeOptions() async {
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
          return _AbEmployeeOption(
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

bool _abRowHasContent(ActionBrainstormingRow r) {
  return [
    r.name,
    r.stopDoing,
    r.doLessOf,
    r.keepDoing,
    r.doMoreOf,
    r.startDoing,
    r.goal,
  ].any((s) => (s ?? '').trim().isNotEmpty);
}

List<ActionBrainstormingRow> _contentRows(List<ActionBrainstormingRow> rows) =>
    rows.where(_abRowHasContent).toList();

DateTime? _tryParseAbDate(String raw) {
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

const List<String> _abMonthNames = [
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

const List<String> _abMonthShort = [
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

String _formatAbDate(DateTime date) {
  final d = date.toLocal();
  return '${_abMonthNames[d.month - 1]} ${d.day}, ${d.year}';
}

String _formatAbDateShort(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = _tryParseAbDate(raw);
  if (parsed == null) return raw.trim();
  final d = parsed.toLocal();
  return '${_abMonthShort[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
}

/// L&D: Action Brainstorming and Coaching Worksheet — list and add/edit.
///
/// Screen UI is a modern coaching workflow. Print/PDF (see
/// [FormPdf.buildActionBrainstormingCoachingPdf]) is an independent official
/// template that reads the same [ActionBrainstormingEntry].
class ActionBrainstormingAdminSection extends StatefulWidget {
  const ActionBrainstormingAdminSection({super.key});

  @override
  State<ActionBrainstormingAdminSection> createState() =>
      _ActionBrainstormingAdminSectionState();
}

class _ActionBrainstormingAdminSectionState
    extends State<ActionBrainstormingAdminSection> {
  List<ActionBrainstormingEntry> _entries = [];
  bool _loading = true;
  ActionBrainstormingEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ActionBrainstormingRepo.instance.list();
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
      setState(() => _editing = const ActionBrainstormingEntry());
  void _edit(ActionBrainstormingEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ActionBrainstormingEntry entry) async {
    try {
      if (entry.id == null) {
        await ActionBrainstormingRepo.instance.insert(entry);
      } else {
        await ActionBrainstormingRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action Brainstorming worksheet saved.'),
        ),
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
      await ActionBrainstormingRepo.instance.delete(id);
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

  Future<void> _print(ActionBrainstormingEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildActionBrainstormingCoachingPdf(entry),
        filename: 'Action_Brainstorming_Coaching.pdf',
        format: FormPdf.pageLetterLandscape,
        printModule: 'ld',
        printFormKey: 'action_brainstorming',
      );
    } catch (_) {}
  }

  Future<void> _download(ActionBrainstormingEntry entry) async {
    try {
      final doc = await FormPdf.buildActionBrainstormingCoachingPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Action_Brainstorming_Coaching.pdf');
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
      sheetTitle: 'Saved Action Brainstorming worksheets',
      emptyMessage: 'No worksheets yet.',
      loading: _loading,
      items: _entries.map((e) {
        final dept = e.department?.trim().isNotEmpty == true
            ? e.department!
            : 'No department';
        final count = _contentRows(e.rows).length;
        return SavedRecordListItem(
          title: dept,
          subtitle: '${_formatAbDateShort(e.date)} · $count employee(s)',
          detailDialogTitle: 'Action Brainstorming — $dept',
          previewContentWidth: 1000,
          previewBuilder: () => ActionBrainstormingEditor(
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
          label: const Text('New Worksheet'),
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
          'Action Brainstorming & Coaching Worksheet',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Plan and document coaching actions that help employees contribute to department goals.',
          style: TextStyle(color: secondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          ActionBrainstormingEditor(
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
                'No worksheets yet. Tap "New Worksheet" to create an Action Brainstorming and Coaching Worksheet.',
            icon: Icons.lightbulb_outline_rounded,
          )
        else
          _ActionBrainstormingList(
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

/// Modern coaching data-entry screen. Not used for Print/PDF.
class ActionBrainstormingEditor extends StatefulWidget {
  const ActionBrainstormingEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final ActionBrainstormingEntry entry;
  final bool readOnly;
  final void Function(ActionBrainstormingEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ActionBrainstormingEntry) onPrint;
  final Future<void> Function(ActionBrainstormingEntry) onDownloadPdf;

  @override
  State<ActionBrainstormingEditor> createState() =>
      _ActionBrainstormingEditorState();
}

class _ActionBrainstormingEditorState extends State<ActionBrainstormingEditor> {
  String? _department;
  late final TextEditingController _departmentController;
  late final TextEditingController _date;
  late final TextEditingController _certifiedBy;
  late final TextEditingController _certificationDate;

  late List<_AbDisplayRow> _rows;
  List<_AbEmployeeOption> _employees = [];
  List<String> _officeNames = [];
  bool _officesLoaded = false;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _department = e.department?.trim().isNotEmpty == true
        ? e.department!.trim()
        : null;
    _departmentController = TextEditingController(text: _department ?? '');
    _departmentController.addListener(() {
      _department = _departmentController.text.trim().isEmpty
          ? null
          : _departmentController.text.trim();
    });
    final initialDate = e.date?.trim().isNotEmpty == true
        ? e.date!.trim()
        : (e.id == null ? _formatAbDate(DateTime.now()) : '');
    _date = TextEditingController(text: initialDate);
    _certifiedBy = TextEditingController(text: e.certifiedBy ?? '');
    _certificationDate = TextEditingController(
      text: e.certificationDate ?? '',
    );
    _rows = _contentRows(e.rows)
        .map((r) => _AbDisplayRow(row: r))
        .toList();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
    if (!widget.readOnly) {
      _loadLookups();
    }
  }

  Future<void> _loadLookups() async {
    final employees = await _fetchActiveEmployeeOptions();
    final offices = await _fetchActiveOfficeNames();
    if (!mounted) return;
    setState(() {
      _employees = employees;
      _officeNames = offices;
      _officesLoaded = offices.isNotEmpty;
      _hydrateDisplayFromEmployees();
    });
  }

  void _hydrateDisplayFromEmployees() {
    if (_employees.isEmpty) return;
    _rows = [
      for (final item in _rows)
        () {
          if ((item.position ?? '').trim().isNotEmpty) return item;
          final name = item.name.toLowerCase();
          if (name.isEmpty) return item;
          _AbEmployeeOption? match;
          for (final e in _employees) {
            if (e.fullName.trim().toLowerCase() == name) {
              match = e;
              break;
            }
          }
          if (match == null) return item;
          return _AbDisplayRow(
            row: item.row,
            position: match.positionName,
            office: match.departmentName,
          );
        }(),
    ];
  }

  @override
  void dispose() {
    _search.dispose();
    _departmentController.dispose();
    _date.dispose();
    _certifiedBy.dispose();
    _certificationDate.dispose();
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  ActionBrainstormingEntry _buildEntry() {
    return ActionBrainstormingEntry(
      id: widget.entry.id,
      department: _department,
      date: _opt(_date),
      rows: _rows.map((e) => e.row).where(_abRowHasContent).toList(),
      certifiedBy: _opt(_certifiedBy),
      certificationDate: _opt(_certificationDate),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildEntry());
  }

  Future<void> _pickDate(TextEditingController c) async {
    if (widget.readOnly) return;
    final now = DateTime.now();
    final parsed = _tryParseAbDate(c.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() => c.text = _formatAbDate(picked));
  }

  Future<void> _addEmployee() async {
    final result = await showDialog<_AbDisplayRow>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AbCoachingEditorDialog(
        isNew: true,
        employees: _employees,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _rows.add(result));
    if (_rows.length > _kOfficialPrintRowCapacity && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The official worksheet has 15 numbered rows. Extra entries are still saved and printed.',
          ),
        ),
      );
    }
  }

  Future<void> _editEmployee(int i) async {
    final result = await showDialog<_AbDisplayRow>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AbCoachingEditorDialog(
        isNew: false,
        initial: _rows[i],
        employees: _employees,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _rows[i] = result);
  }

  Future<void> _confirmRemoveEmployee(int i) async {
    final label = _rows[i].name.isEmpty
        ? 'Employee ${i + 1}'
        : _rows[i].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove employee?'),
        content: Text(
          'Are you sure you want to remove $label from this worksheet? '
          'This action cannot be undone.',
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
    if (ok == true && mounted) setState(() => _rows.removeAt(i));
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) => AppTheme.dashInputDecoration(
    context,
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
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

  Widget _dateField(
    BuildContext context,
    TextEditingController c,
    String label,
    bool ro,
  ) {
    return TextFormField(
      controller: c,
      readOnly: true,
      onTap: ro ? null : () => _pickDate(c),
      decoration: _decoration(
        context,
        label: label,
        hint: ro ? null : 'Select date',
        suffixIcon: ro
            ? null
            : IconButton(
                tooltip: 'Pick date',
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                onPressed: () => _pickDate(c),
              ),
      ),
    );
  }

  Widget _worksheetInformationCard(BuildContext context, bool ro) {
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

    final dateField = ro
        ? _readOnlyValueBox(
            context,
            'Date',
            _date.text.trim().isEmpty ? '—' : _date.text.trim(),
          )
        : _dateField(context, _date, 'Date', ro);

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
            'WORKSHEET INFORMATION',
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
                        Expanded(flex: 2, child: deptField),
                        const SizedBox(width: 14),
                        Expanded(child: dateField),
                      ],
                    )
                  : Column(
                      children: [
                        deptField,
                        const SizedBox(height: 14),
                        dateField,
                      ],
                    );
            },
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _kOfficialInstruction,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppTheme.dashTextSecondaryOf(context),
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

  Widget _coachingHeader(BuildContext context, bool ro) {
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
              'Coaching Entries',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
      final name = _rows[i].name.toLowerCase();
      final position = (_rows[i].position ?? '').toLowerCase();
      if (name.contains(_query) || position.contains(_query)) out.add(i);
    }
    return out;
  }

  Widget _coachingBody(BuildContext context, bool ro) {
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
              Icons.groups_outlined,
              size: 32,
              color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            Text(
              'No coaching entries yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ro
                  ? 'No employees recorded.'
                  : 'Add employees to begin documenting coaching actions and goals.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
            if (!ro) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _addEmployee,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Employee'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                ),
              ),
            ],
          ],
        ),
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
        if (_rows.length > _kOfficialPrintRowCapacity)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This worksheet has ${_rows.length} employees. The official printed form shows 15 numbered rows; extra entries are still saved and printed.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ),
        for (var pos = 0; pos < indices.length; pos++) ...[
          if (pos > 0) const SizedBox(height: 12),
          _AbCoachingCard(
            index: indices[pos],
            item: _rows[indices[pos]],
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

  /// Blank strip with a bottom rule for a physical pen signature above the
  /// printed name — same pattern as Applicants Profile.
  Widget _signatureSpace(BuildContext context) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 8),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
    );
  }

  Widget _certifiedByCard(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CERTIFIED BY', style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 10),
          _signatureSpace(context),
          ro
              ? Text(
                  _certifiedBy.text.trim().isEmpty
                      ? '—'
                      : _certifiedBy.text.trim(),
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : TextFormField(
                  controller: _certifiedBy,
                  decoration: _decoration(
                    context,
                    hint: 'Printed name / over signature',
                  ),
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
          const SizedBox(height: 6),
          Text(
            'Department Head',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _certificationCard(BuildContext context, bool ro) {
    final dateField = ro
        ? _readOnlyValueBox(
            context,
            'Certification Date',
            _certificationDate.text.trim().isEmpty
                ? '—'
                : _certificationDate.text.trim(),
          )
        : _dateField(context, _certificationDate, 'Certification Date', ro);

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
          Text('CERTIFICATION', style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 560;
              final certified = _certifiedByCard(context, ro);
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: certified),
                        const SizedBox(width: 14),
                        Expanded(child: dateField),
                      ],
                    )
                  : Column(
                      children: [
                        certified,
                        const SizedBox(height: 14),
                        dateField,
                      ],
                    );
            },
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
          children: [
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Worksheet'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _department == null
                            ? 'New Coaching Worksheet'
                            : _department!,
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
                const SizedBox(height: 4),
                Text(
                  'Plan and document coaching actions that help employees contribute to department goals.',
                  style: TextStyle(fontSize: 12.5, color: secondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _worksheetInformationCard(context, ro),
                const SizedBox(height: 24),
                _coachingHeader(context, ro),
                const SizedBox(height: 14),
                _coachingBody(context, ro),
                const SizedBox(height: 24),
                _certificationCard(context, ro),
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

class _AbCoachingCard extends StatelessWidget {
  const _AbCoachingCard({
    required this.index,
    required this.item,
    required this.readOnly,
    required this.expanded,
    required this.onToggleExpand,
    this.onEdit,
    this.onRemove,
  });

  final int index;
  final _AbDisplayRow item;
  final bool readOnly;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  Widget _actionBlock(BuildContext context, String label, String? value) {
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
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final name = item.name.isEmpty ? 'Employee ${index + 1}' : item.name;
    final position = item.position?.trim() ?? '';
    final office = item.office?.trim() ?? '';
    final goal = item.row.goal?.trim() ?? '';

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
                      name,
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
                    if (office.isNotEmpty)
                      Text(
                        office,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!expanded && goal.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Goal: $goal',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: primary, height: 1.35),
            ),
          ],
          TextButton.icon(
            onPressed: onToggleExpand,
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
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
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 560;
                final blocks = [
                  _actionBlock(context, 'Stop Doing', item.row.stopDoing),
                  _actionBlock(context, 'Do Less Of', item.row.doLessOf),
                  _actionBlock(context, 'Keep Doing', item.row.keepDoing),
                  _actionBlock(context, 'Do More Of', item.row.doMoreOf),
                  _actionBlock(context, 'Start Doing', item.row.startDoing),
                ];
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: blocks,
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < blocks.length; i += 2)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: blocks[i]),
                          const SizedBox(width: 16),
                          Expanded(
                            child: i + 1 < blocks.length
                                ? blocks[i + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
            _actionBlock(context, 'Goal', item.row.goal),
          ],
          if (!readOnly) ...[
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 8),
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

class _AbCoachingEditorDialog extends StatefulWidget {
  const _AbCoachingEditorDialog({
    required this.isNew,
    required this.employees,
    this.initial,
  });

  final bool isNew;
  final List<_AbEmployeeOption> employees;
  final _AbDisplayRow? initial;

  @override
  State<_AbCoachingEditorDialog> createState() =>
      _AbCoachingEditorDialogState();
}

class _AbCoachingEditorDialogState extends State<_AbCoachingEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _stop;
  late final TextEditingController _less;
  late final TextEditingController _keep;
  late final TextEditingController _more;
  late final TextEditingController _start;
  late final TextEditingController _goal;
  final FocusNode _nameFocus = FocusNode();
  String? _nameError;
  String? _actionError;
  String? _pickedPosition;
  String? _pickedOffice;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _stop = TextEditingController(text: initial?.row.stopDoing ?? '');
    _less = TextEditingController(text: initial?.row.doLessOf ?? '');
    _keep = TextEditingController(text: initial?.row.keepDoing ?? '');
    _more = TextEditingController(text: initial?.row.doMoreOf ?? '');
    _start = TextEditingController(text: initial?.row.startDoing ?? '');
    _goal = TextEditingController(text: initial?.row.goal ?? '');
    _pickedPosition = initial?.position;
    _pickedOffice = initial?.office;
    _nameFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _stop, _less, _keep, _more, _start, _goal]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _selectEmployee(_AbEmployeeOption e) {
    setState(() {
      _name.text = e.fullName;
      _pickedPosition = e.positionName;
      _pickedOffice = e.departmentName;
      _nameError = null;
    });
    _nameFocus.unfocus();
  }

  String? _optional(String v) => v.trim().isEmpty ? null : v.trim();

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Please select or enter an employee.');
      return;
    }
    final hasAction = [
      _stop,
      _less,
      _keep,
      _more,
      _start,
      _goal,
    ].any((c) => c.text.trim().isNotEmpty);
    if (!hasAction) {
      setState(
        () => _actionError =
            'Please enter at least one coaching action or goal.',
      );
      return;
    }
    Navigator.of(context).pop(
      _AbDisplayRow(
        row: ActionBrainstormingRow(
          name: name,
          stopDoing: _optional(_stop.text),
          doLessOf: _optional(_less.text),
          keepDoing: _optional(_keep.text),
          doMoreOf: _optional(_more.text),
          startDoing: _optional(_start.text),
          goal: _optional(_goal.text),
        ),
        position: _pickedPosition,
        office: _pickedOffice,
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? label,
    String? hint,
  }) => AppTheme.dashInputDecoration(context, labelText: label, hintText: hint);

  List<_AbEmployeeOption> get _matches {
    final q = _name.text.trim().toLowerCase();
    if (q.isEmpty || widget.employees.isEmpty) return const [];
    return widget.employees
        .where((e) => e.fullName.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  Widget _textarea(
    BuildContext context,
    TextEditingController c,
    String label, {
    int minLines = 2,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        minLines: minLines,
        maxLines: minLines + 3,
        onChanged: (_) {
          if (_actionError != null) setState(() => _actionError = null);
        },
        decoration: _decoration(context, label: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width < 620 ? size.width - 32 : 560.0;
    final maxH = size.height - 80;
    final matches = _matches;
    final showSuggestions =
        widget.employees.isNotEmpty &&
        _nameFocus.hasFocus &&
        matches.isNotEmpty;

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
                      widget.isNew
                          ? 'Add Coaching Entry'
                          : 'Edit Coaching Entry',
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
                    Text(
                      'EMPLOYEE',
                      style: AppTheme.dashSectionTitle(context),
                    ),
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
                                      .where(
                                        (s) => (s ?? '').trim().isNotEmpty,
                                      )
                                      .join(' · '),
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                onTap: () => _selectEmployee(m),
                              ),
                          ],
                        ),
                      ),
                    if ((_pickedPosition ?? '').trim().isNotEmpty ||
                        (_pickedOffice ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if ((_pickedPosition ?? '').trim().isNotEmpty)
                        Text(
                          _pickedPosition!.trim(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.dashTextPrimaryOf(context),
                          ),
                        ),
                      if ((_pickedOffice ?? '').trim().isNotEmpty)
                        Text(
                          _pickedOffice!.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.dashTextSecondaryOf(context),
                          ),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 18, bottom: 10),
                      child: Text(
                        'COACHING ACTIONS',
                        style: AppTheme.dashSectionTitle(context),
                      ),
                    ),
                    _textarea(context, _stop, 'Stop Doing'),
                    _textarea(context, _less, 'Do Less Of'),
                    _textarea(context, _keep, 'Keep Doing'),
                    _textarea(context, _more, 'Do More Of'),
                    _textarea(context, _start, 'Start Doing'),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 10),
                      child: Text(
                        'GOAL',
                        style: AppTheme.dashSectionTitle(context),
                      ),
                    ),
                    _textarea(context, _goal, 'Goal', minLines: 3),
                    if (_actionError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _actionError!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
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
                    child: Text(
                      widget.isNew ? 'Add to Worksheet' : 'Save Changes',
                    ),
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

class _ActionBrainstormingList extends StatelessWidget {
  const _ActionBrainstormingList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<ActionBrainstormingEntry> entries;
  final void Function(ActionBrainstormingEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ActionBrainstormingEntry) onPrint;
  final Future<void> Function(ActionBrainstormingEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Date', flex: 1.2),
      RspRecordsColumn('Department', flex: 1.8),
      RspRecordsColumn('Employees', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map((e) {
            final count = _contentRows(e.rows).length;
            return [
              rspRecordsTextCell(
                context,
                _formatAbDateShort(e.date),
                bold: true,
              ),
              rspRecordsTextCell(context, e.department ?? ''),
              rspRecordsTextCell(
                context,
                '$count',
                align: TextAlign.center,
                bold: true,
              ),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Action Brainstorming Worksheet',
                  subtitle: '${e.department ?? '—'} · ${e.date ?? '—'}',
                  previewBuilder: () => ActionBrainstormingEditor(
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
                deleteDialogTitle: 'Delete worksheet?',
              ),
            ];
          })
          .toList(),
    );
  }
}
