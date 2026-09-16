import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/learning_application_plan.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

const _kLapMonths = [
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

const _kLapMonthsShort = [
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

DateTime? _tryParseLapDate(String raw) {
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
    final mi = _kLapMonths.indexWhere((m) => m.toLowerCase() == monthName);
    if (mi != -1 && day != null && year != null) {
      return DateTime(year, mi + 1, day);
    }
  }
  return null;
}

String _formatLapDate(DateTime date) {
  final d = date.toLocal();
  return '${_kLapMonths[d.month - 1]} ${d.day}, ${d.year}';
}

String _formatLapDateShort(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = _tryParseLapDate(raw);
  if (parsed == null) return raw.trim();
  final d = parsed.toLocal();
  return '${_kLapMonthsShort[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
}

bool _isValidLapCost(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return true;
  final cleaned = t.replaceAll(RegExp(r'[₱,\s]'), '');
  return double.tryParse(cleaned) != null;
}

class _LapEmployeeOption {
  const _LapEmployeeOption({
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

Future<List<_LapEmployeeOption>> _fetchActiveEmployeeOptions() async {
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
          return _LapEmployeeOption(
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

String? _optText(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : t;
}

/// L&D: Learning Application Plan — list entries and add/edit form.
///
/// Screen UI is a modern L&D data-entry interface. Print/PDF (see
/// [FormPdf.buildLearningApplicationPlanPdf]) is an independent official
/// template that reads the same [LearningApplicationPlanEntry].
class LearningApplicationPlanAdminSection extends StatefulWidget {
  const LearningApplicationPlanAdminSection({super.key});

  @override
  State<LearningApplicationPlanAdminSection> createState() =>
      _LearningApplicationPlanAdminSectionState();
}

class _LearningApplicationPlanAdminSectionState
    extends State<LearningApplicationPlanAdminSection> {
  List<LearningApplicationPlanEntry> _entries = [];
  bool _loading = true;
  LearningApplicationPlanEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LearningApplicationPlanRepo.instance.list();
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
      setState(() => _editing = const LearningApplicationPlanEntry());
  void _edit(LearningApplicationPlanEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(LearningApplicationPlanEntry entry) async {
    try {
      if (entry.id == null) {
        await LearningApplicationPlanRepo.instance.insert(entry);
      } else {
        await LearningApplicationPlanRepo.instance.update(entry);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Learning Application Plan saved.')));
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
      await LearningApplicationPlanRepo.instance.delete(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Plan deleted.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _print(LearningApplicationPlanEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildLearningApplicationPlanPdf(entry),
        filename: 'Learning_Application_Plan.pdf',
        format: FormPdf.pageLetterLandscape,
        printModule: 'ld',
        printFormKey: 'learning_application_plan',
      );
    } catch (_) {}
  }

  Future<void> _download(LearningApplicationPlanEntry entry) async {
    try {
      final doc = await FormPdf.buildLearningApplicationPlanPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Learning_Application_Plan.pdf');
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
      sheetTitle: 'Saved Learning Application Plans',
      emptyMessage: 'No Learning Application Plans yet.',
      loading: _loading,
      items: _entries.map((e) {
        final title = (e.title?.trim().isNotEmpty ?? false)
            ? e.title!
            : '(Untitled plan)';
        return SavedRecordListItem(
          title: title,
          subtitle:
              '${_formatLapDateShort(e.date)} · ${e.venue ?? '—'} · ${e.entries.length} ${e.entries.length == 1 ? 'entry' : 'entries'}',
          detailDialogTitle: 'Learning Application Plan — $title',
          previewContentWidth: 1000,
          previewBuilder: () => LearningApplicationPlanFormEditor(
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
          label: const Text('New Plan'),
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
          'Learning Application Plan',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Document how learning from training will be applied in the workplace.',
          style: TextStyle(color: secondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          LearningApplicationPlanFormEditor(
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
            message: 'No Learning Application Plans yet. Tap "New Plan" to add one.',
            icon: Icons.menu_book_rounded,
          )
        else
          _LapList(
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

/// Modern LAP data-entry screen. Not used for Print/PDF.
class LearningApplicationPlanFormEditor extends StatefulWidget {
  const LearningApplicationPlanFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final LearningApplicationPlanEntry entry;
  final bool readOnly;
  final void Function(LearningApplicationPlanEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(LearningApplicationPlanEntry) onPrint;
  final Future<void> Function(LearningApplicationPlanEntry) onDownloadPdf;

  @override
  State<LearningApplicationPlanFormEditor> createState() =>
      _LearningApplicationPlanFormEditorState();
}

class _LearningApplicationPlanFormEditorState
    extends State<LearningApplicationPlanFormEditor> {
  late final TextEditingController _memoReportTo;
  late final TextEditingController _from;
  late final TextEditingController _thru;
  late final TextEditingController _subject;
  late final TextEditingController _title;
  late final TextEditingController _date;
  late final TextEditingController _venue;
  late final TextEditingController _cost;
  late final TextEditingController _otherReap;
  late final TextEditingController _reportedBy;
  late final TextEditingController _receivedBy;

  late List<String> _reapTypes;
  late List<LearningApplicationPlanRow> _planEntries;
  final Set<int> _expanded = {};

  List<_LapEmployeeOption> _employees = [];
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _reportedFocus = FocusNode();

  String? _fromError;
  String? _subjectError;
  String? _titleError;
  String? _dateError;
  String? _costError;
  String? _reportedError;
  String? _entriesError;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final isNew = e.id == null;
    _memoReportTo = TextEditingController(text: e.memoReportTo ?? '');
    _from = TextEditingController(text: e.from ?? '');
    _thru = TextEditingController(text: e.thru ?? '');
    _subject = TextEditingController(text: e.subject ?? '');
    _title = TextEditingController(text: e.title ?? '');
    _date = TextEditingController(text: e.date ?? '');
    _venue = TextEditingController(text: e.venue ?? '');
    _cost = TextEditingController(text: e.cost ?? '');
    _otherReap = TextEditingController(text: e.otherReapType ?? '');
    _reportedBy = TextEditingController(text: e.reportedBy ?? '');
    _receivedBy = TextEditingController(
      text: e.receivedBy ??
          (isNew ? LearningApplicationPlanEntry.defaultReceivedByName : ''),
    );
    _reapTypes = List<String>.from(e.reapTypes);
    _planEntries = List<LearningApplicationPlanRow>.from(e.entries);
    if (_planEntries.length == 1) _expanded.add(0);
    _fromFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _reportedFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (!widget.readOnly) _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final employees = await _fetchActiveEmployeeOptions();
    if (!mounted) return;
    setState(() => _employees = employees);
  }

  @override
  void dispose() {
    _fromFocus.dispose();
    _reportedFocus.dispose();
    for (final c in [
      _memoReportTo,
      _from,
      _thru,
      _subject,
      _title,
      _date,
      _venue,
      _cost,
      _otherReap,
      _reportedBy,
      _receivedBy,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  LearningApplicationPlanEntry _buildCurrent() {
    return LearningApplicationPlanEntry(
      id: widget.entry.id,
      memoReportTo: _optText(_memoReportTo),
      from: _optText(_from),
      thru: _optText(_thru),
      subject: _optText(_subject),
      title: _optText(_title),
      date: _optText(_date),
      venue: _optText(_venue),
      cost: _optText(_cost),
      reapTypes: List<String>.from(_reapTypes),
      otherReapType: _reapTypes.contains('other') ? _optText(_otherReap) : null,
      reportedBy: _optText(_reportedBy),
      receivedBy: _optText(_receivedBy) ??
          LearningApplicationPlanEntry.defaultReceivedByName,
      entries: List<LearningApplicationPlanRow>.from(_planEntries),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  bool _validate() {
    _fromError = _from.text.trim().isEmpty ? 'From is required.' : null;
    _subjectError = _subject.text.trim().isEmpty ? 'Subject is required.' : null;
    _titleError = _title.text.trim().isEmpty ? 'Title is required.' : null;
    _dateError = _date.text.trim().isEmpty ? 'Date is required.' : null;
    _reportedError =
        _reportedBy.text.trim().isEmpty ? 'Reported by is required.' : null;
    _costError = _isValidLapCost(_cost.text)
        ? null
        : 'Enter a valid cost amount.';
    _entriesError = _planEntries.isEmpty
        ? 'Add at least one application plan entry.'
        : null;
    setState(() {});
    return [
      _fromError,
      _subjectError,
      _titleError,
      _dateError,
      _reportedError,
      _costError,
      _entriesError,
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
    final parsed = _tryParseLapDate(_date.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date.text = _formatLapDate(picked);
      _dateError = null;
    });
  }

  Future<void> _addEntry() async {
    if (widget.readOnly) return;
    final result = await showDialog<LearningApplicationPlanRow>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _LapEntryEditorDialog(isNew: true),
    );
    if (result == null || !mounted) return;
    setState(() {
      _planEntries.add(result);
      _expanded.add(_planEntries.length - 1);
      _entriesError = null;
    });
  }

  Future<void> _editEntry(int i) async {
    if (widget.readOnly) return;
    final result = await showDialog<LearningApplicationPlanRow>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LapEntryEditorDialog(
        isNew: false,
        initial: _planEntries[i],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _planEntries[i] = result);
  }

  Future<void> _removeEntry(int i) async {
    if (widget.readOnly) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove entry?'),
        content: const Text('This application plan entry will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _planEntries.removeAt(i);
      _expanded.remove(i);
      final next = <int>{};
      for (final idx in _expanded) {
        if (idx < i) {
          next.add(idx);
        } else if (idx > i) {
          next.add(idx - 1);
        }
      }
      _expanded
        ..clear()
        ..addAll(next);
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

  Widget _textField(
    TextEditingController c,
    String label, {
    String? hint,
    String? error,
    Widget? prefixIcon,
  }) {
    return TextFormField(
      controller: c,
      readOnly: widget.readOnly,
      decoration: _decoration(
        context,
        label: label,
        hint: hint,
        error: error,
        prefixIcon: prefixIcon,
      ),
    );
  }

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

  Widget _responsiveGrid(List<Widget> fields, {int columns = 3}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 640;
        final cols = wide ? columns : 1;
        if (cols == 1) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                fields[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < fields.length; i += cols) {
          final slice = fields.sublist(
            i,
            i + cols > fields.length ? fields.length : i + cols,
          );
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: 12),
                  Expanded(
                    child: j < slice.length ? slice[j] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              rows[i],
            ],
          ],
        );
      },
    );
  }

  Widget _employeeSearchField({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    String? error,
    String? hint,
  }) {
    final q = controller.text.trim().toLowerCase();
    final matches = (!widget.readOnly &&
            _employees.isNotEmpty &&
            focus.hasFocus &&
            q.isNotEmpty)
        ? _employees
              .where((e) => e.fullName.toLowerCase().contains(q))
              .take(6)
              .toList()
        : const <_LapEmployeeOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          focusNode: focus,
          readOnly: widget.readOnly,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(
            context,
            label: label,
            hint: hint ??
                (_employees.isNotEmpty ? 'Search or type a name' : null),
            error: error,
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
                    onTap: () {
                      setState(() => controller.text = m.fullName);
                      focus.unfocus();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _planInformation() {
    return _sectionCard(
      title: 'PLAN INFORMATION',
      child: Column(
        children: [
          _responsiveGrid([
            _textField(_memoReportTo, 'Memo Report To'),
            _employeeSearchField(
              controller: _from,
              focus: _fromFocus,
              label: 'From',
              error: _fromError,
            ),
            _textField(_thru, 'Thru'),
          ]),
          const SizedBox(height: 12),
          _responsiveGrid([
            _textField(_subject, 'Subject', error: _subjectError),
            _textField(_title, 'Title', error: _titleError),
          ], columns: 2),
          const SizedBox(height: 12),
          _responsiveGrid([
            TextFormField(
              controller: _date,
              readOnly: true,
              onTap: widget.readOnly ? null : _pickDate,
              decoration: _decoration(
                context,
                label: 'Date',
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
            _textField(_venue, 'Venue'),
            _textField(
              _cost,
              'Cost',
              hint: '0.00',
              error: _costError,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _entriesSection() {
    final ro = widget.readOnly;
    final count = _planEntries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'APPLICATION PLAN ENTRIES',
              style: AppTheme.dashSectionTitle(context),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count ${count == 1 ? 'Entry' : 'Entries'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryNavy,
                ),
              ),
            ),
            if (!ro)
              FilledButton.icon(
                onPressed: _addEntry,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Entry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                ),
              ),
          ],
        ),
        if (_entriesError != null) ...[
          const SizedBox(height: 8),
          Text(
            _entriesError!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 14),
        if (_planEntries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 32,
                  color: AppTheme.dashTextSecondaryOf(
                    context,
                  ).withValues(alpha: 0.45),
                ),
                const SizedBox(height: 8),
                Text(
                  'No application plan entries yet.',
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
                      ? 'No learning application rows recorded.'
                      : 'Add an entry to document how learning will be applied.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                if (!ro) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Entry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < _planEntries.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _LapEntryCard(
                  index: i,
                  row: _planEntries[i],
                  readOnly: ro,
                  expanded: _expanded.contains(i),
                  onToggleExpand: () => setState(() {
                    if (_expanded.contains(i)) {
                      _expanded.remove(i);
                    } else {
                      _expanded.add(i);
                    }
                  }),
                  onEdit: ro ? null : () => _editEntry(i),
                  onRemove: ro ? null : () => _removeEntry(i),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _reapTypesSection() {
    final ro = widget.readOnly;
    return _sectionCard(
      title: 'TYPES OF REAP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in LearningApplicationPlanEntry.reapTypeOptions)
                FilterChip(
                  label: Text(
                    LearningApplicationPlanEntry.reapTypeLabels[key] ?? key,
                  ),
                  selected: _reapTypes.contains(key),
                  onSelected: ro
                      ? null
                      : (selected) => setState(() {
                          if (selected) {
                            _reapTypes.add(key);
                          } else {
                            _reapTypes.remove(key);
                          }
                        }),
                  selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.14),
                  checkmarkColor: AppTheme.primaryNavy,
                  side: BorderSide(
                    color: _reapTypes.contains(key)
                        ? AppTheme.primaryNavy
                        : AppTheme.dashHairlineOf(context),
                  ),
                ),
            ],
          ),
          if (_reapTypes.contains('other')) ...[
            const SizedBox(height: 12),
            _textField(_otherReap, 'Other REAP Type'),
          ],
        ],
      ),
    );
  }

  Widget _signatureSpace(BuildContext context) {
    return Container(
      height: 30,
      margin: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
    );
  }

  Widget _signOff() {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final reported = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REPORTED BY', style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 10),
          _signatureSpace(context),
          _employeeSearchField(
            controller: _reportedBy,
            focus: _reportedFocus,
            label: 'Employee / Name',
            error: _reportedError,
            hint: 'Printed name / over signature',
          ),
          const SizedBox(height: 6),
          Text(
            'Employee Attended Training',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
    final receivedName = _receivedBy.text.trim().isNotEmpty
        ? _receivedBy.text.trim()
        : LearningApplicationPlanEntry.defaultReceivedByName;
    final received = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECEIVED BY', style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 10),
          _signatureSpace(context),
          Text(
            receivedName,
            style: TextStyle(color: primary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            LearningApplicationPlanEntry.defaultReceivedByTitle,
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
    return _sectionCard(
      title: 'SIGN-OFF',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 640;
          if (!wide) {
            return Column(
              children: [
                reported,
                const SizedBox(height: 12),
                received,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: reported),
              const SizedBox(width: 12),
              Expanded(child: received),
            ],
          );
        },
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
              label: const Text('Save Plan'),
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
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final heading = _title.text.trim().isEmpty
        ? 'New Learning Application Plan'
        : _title.text.trim();
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
                const SizedBox(height: 4),
                Text(
                  'Human Resource Management and Development Office',
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
                _planInformation(),
                const SizedBox(height: 16),
                _entriesSection(),
                const SizedBox(height: 16),
                _reapTypesSection(),
                const SizedBox(height: 16),
                _signOff(),
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

class _LapEntryCard extends StatelessWidget {
  const _LapEntryCard({
    required this.index,
    required this.row,
    required this.readOnly,
    required this.expanded,
    required this.onToggleExpand,
    this.onEdit,
    this.onRemove,
  });

  final int index;
  final LearningApplicationPlanRow row;
  final bool readOnly;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  Widget _block(BuildContext context, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (value ?? '').trim().isEmpty ? '—' : value!.trim(),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final learning = (row.learning ?? '').trim();
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Entry ${index + 1}${learning.isEmpty ? '' : ' — $learning'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ),
              if (!readOnly) ...[
                IconButton(
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ],
          ),
          if (!expanded) ...[
            if ((row.objectives ?? '').trim().isNotEmpty)
              Text(
                row.objectives!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
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
            _block(context, 'LEARNING', row.learning),
            _block(context, 'OBJECTIVES', row.objectives),
            _block(
              context,
              'COMPETENCY GAPS ADDRESSED',
              row.competencyGapsAddressed,
            ),
            _block(context, 'REAP IMPLEMENTATION', row.reapImplementation),
            _block(context, 'TIMELINE', row.timeline),
            _block(context, 'PERSONS INVOLVED', row.personsInvolved),
            _block(context, 'EVIDENCE', row.evidence),
          ],
        ],
      ),
    );
  }
}

class _LapEntryEditorDialog extends StatefulWidget {
  const _LapEntryEditorDialog({required this.isNew, this.initial});

  final bool isNew;
  final LearningApplicationPlanRow? initial;

  @override
  State<_LapEntryEditorDialog> createState() => _LapEntryEditorDialogState();
}

class _LapEntryEditorDialogState extends State<_LapEntryEditorDialog> {
  late final TextEditingController _learning;
  late final TextEditingController _objectives;
  late final TextEditingController _gaps;
  late final TextEditingController _reap;
  late final TextEditingController _timeline;
  late final TextEditingController _persons;
  late final TextEditingController _evidence;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _learning = TextEditingController(text: i?.learning ?? '');
    _objectives = TextEditingController(text: i?.objectives ?? '');
    _gaps = TextEditingController(text: i?.competencyGapsAddressed ?? '');
    _reap = TextEditingController(text: i?.reapImplementation ?? '');
    _timeline = TextEditingController(text: i?.timeline ?? '');
    _persons = TextEditingController(text: i?.personsInvolved ?? '');
    _evidence = TextEditingController(text: i?.evidence ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _learning,
      _objectives,
      _gaps,
      _reap,
      _timeline,
      _persons,
      _evidence,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final row = LearningApplicationPlanRow(
      learning: _optText(_learning),
      objectives: _optText(_objectives),
      competencyGapsAddressed: _optText(_gaps),
      reapImplementation: _optText(_reap),
      timeline: _optText(_timeline),
      personsInvolved: _optText(_persons),
      evidence: _optText(_evidence),
    );
    if (row.isBlank) {
      setState(
        () => _error = 'Please fill in at least one field for this entry.',
      );
      return;
    }
    Navigator.of(context).pop(row);
  }

  Widget _area(TextEditingController c, String label) {
    return TextFormField(
      controller: c,
      minLines: 3,
      maxLines: 6,
      decoration: AppTheme.dashInputDecoration(context, labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Add Entry' : 'Edit Entry'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
                const SizedBox(height: 10),
              ],
              _area(_learning, 'LEARNING'),
              const SizedBox(height: 12),
              _area(_objectives, 'OBJECTIVES'),
              const SizedBox(height: 12),
              _area(_gaps, 'COMPETENCY GAPS ADDRESSED'),
              const SizedBox(height: 12),
              _area(_reap, 'REAP IMPLEMENTATION'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _timeline,
                minLines: 1,
                maxLines: 3,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'TIMELINE',
                ),
              ),
              const SizedBox(height: 12),
              _area(_persons, 'PERSONS INVOLVED'),
              const SizedBox(height: 12),
              _area(_evidence, 'EVIDENCE'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy),
          child: Text(widget.isNew ? 'Add Entry' : 'Save Changes'),
        ),
      ],
    );
  }
}

class _LapList extends StatelessWidget {
  const _LapList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<LearningApplicationPlanEntry> entries;
  final void Function(LearningApplicationPlanEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(LearningApplicationPlanEntry) onPrint;
  final Future<void> Function(LearningApplicationPlanEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Date', flex: 1.4),
      RspRecordsColumn('Title', flex: 2.2),
      RspRecordsColumn('Venue', flex: 1.6),
      RspRecordsColumn('Entries', flex: 0.8),
      RspRecordsColumn('Reported By', flex: 1.6),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, _formatLapDateShort(e.date)),
              rspRecordsTextCell(context, e.title ?? '', bold: true),
              rspRecordsTextCell(context, e.venue ?? ''),
              rspRecordsTextCell(context, '${e.entries.length}'),
              rspRecordsTextCell(context, e.reportedBy ?? ''),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Learning Application Plan',
                  subtitle: '${e.title ?? '—'} · ${_formatLapDateShort(e.date)}',
                  previewBuilder: () => LearningApplicationPlanFormEditor(
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
                deleteDialogTitle: 'Delete Learning Application Plan?',
              ),
            ],
          )
          .toList(),
    );
  }
}
