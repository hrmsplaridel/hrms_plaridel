import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';

/// Official printed IDP lists these required qualifications as instructional
/// text (not a stored field). Shown on screen for reference; Print/PDF keeps
/// the same static wording.
const List<String> _kIdpRequiredQualifications = [
  "Bachelor's degree related to management/admin",
  'Five years\' experience in Management and Administration work',
  '40 hours relevant training',
  '1st Level Eligibility',
];

class _IdpEmployeeOption {
  const _IdpEmployeeOption({
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

Future<List<_IdpEmployeeOption>> _fetchActiveEmployeeOptions() async {
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
          return _IdpEmployeeOption(
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

String? _optText(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : t;
}

/// L&D: Individual Development Plan (IDP) — list entries and add/edit form.
///
/// Screen UI is a modern HR/L&D data-entry interface. Print/PDF (see
/// [FormPdf.buildIdpPdf]) is an independent official template that reads
/// the same [IdpEntry].
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('IDP saved.')));
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
      await IdpRepo.instance.delete(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('IDP deleted.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printIdp(IdpEntry entry) async {
    try {
      await FormPdf.printIdpPdf(context, entry);
    } catch (_) {}
  }

  Future<void> _downloadIdp(IdpEntry entry) async {
    try {
      final doc = await FormPdf.buildIdpPdf(entry);
      await FormPdf.sharePdf(doc, name: 'IDP.pdf');
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
      sheetTitle: 'Saved IDP records',
      emptyMessage: 'No IDP entries yet.',
      loading: _loading,
      items: _entries.map((e) {
        final name = (e.name?.trim().isNotEmpty ?? false)
            ? e.name!
            : '(No name)';
        return SavedRecordListItem(
          title: name,
          subtitle: '${e.position ?? '—'} · ${e.department ?? '—'}',
          detailDialogTitle: 'IDP — $name',
          previewContentWidth: 1000,
          previewBuilder: () => IdpFormEditor(
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

  Widget _toolbar(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: _loading ? null : _startNew,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add IDP'),
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
          'Individual Development Plan (IDP)',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Record employee qualifications, succession analysis, and short-term development actions.',
          style: TextStyle(color: secondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          IdpFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printIdp,
            onDownloadPdf: _downloadIdp,
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
            message: 'No IDP entries yet. Tap "Add IDP" to add one.',
            icon: Icons.trending_up_rounded,
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

/// Modern IDP data-entry screen. Not used for Print/PDF.
class IdpFormEditor extends StatefulWidget {
  const IdpFormEditor({
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
  State<IdpFormEditor> createState() => _IdpFormEditorState();
}

class _IdpFormEditorState extends State<IdpFormEditor> {
  late final TextEditingController _name;
  late final TextEditingController _position;
  late final TextEditingController _category;
  late final TextEditingController _division;
  late final TextEditingController _departmentController;
  late final TextEditingController _education;
  late final TextEditingController _experience;
  late final TextEditingController _training;
  late final TextEditingController _eligibility;
  late final TextEditingController _accomplishments;
  late final TextEditingController _target1;
  late final TextEditingController _target2;
  late final TextEditingController _avgRating;
  late final TextEditingController _opcr;
  late final TextEditingController _ipcr;
  late final TextEditingController _competency;
  late final TextEditingController _priorityScore;
  late final TextEditingController _preparedBy;
  late final TextEditingController _reviewedBy;
  late final TextEditingController _notedBy;
  late final TextEditingController _approvedBy;

  String? _department;
  late String? _performanceRating;
  late String? _competenceRating;
  late String? _successionPriorityRating;
  late List<Map<String, TextEditingController>> _planRows;

  List<_IdpEmployeeOption> _employees = [];
  List<String> _officeNames = [];
  bool _officesLoaded = false;
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final isNew = e.id == null;
    _name = TextEditingController(text: e.name ?? '');
    _position = TextEditingController(text: e.position ?? '');
    _category = TextEditingController(text: e.category ?? '');
    _division = TextEditingController(text: e.division ?? '');
    _department = e.department?.trim().isNotEmpty == true
        ? e.department!.trim()
        : null;
    _departmentController = TextEditingController(text: _department ?? '');
    _departmentController.addListener(() {
      _department = _departmentController.text.trim().isEmpty
          ? null
          : _departmentController.text.trim();
    });
    _education = TextEditingController(text: e.education ?? '');
    _experience = TextEditingController(text: e.experience ?? '');
    _training = TextEditingController(text: e.training ?? '');
    _eligibility = TextEditingController(text: e.eligibility ?? '');
    _accomplishments = TextEditingController(
      text: e.significantAccomplishments ?? '',
    );
    _target1 = TextEditingController(text: e.targetPosition1 ?? '');
    _target2 = TextEditingController(text: e.targetPosition2 ?? '');
    _avgRating = TextEditingController(text: e.avgRating ?? '');
    _opcr = TextEditingController(text: e.opcr ?? '');
    _ipcr = TextEditingController(text: e.ipcr ?? '');
    _competency = TextEditingController(text: e.competencyDescription ?? '');
    _priorityScore = TextEditingController(
      text: e.successionPriorityScore ?? '',
    );
    _preparedBy = TextEditingController(text: e.preparedBy ?? '');
    _reviewedBy = TextEditingController(text: e.reviewedBy ?? '');
    _notedBy = TextEditingController(
      text: e.notedBy ?? (isNew ? IdpEntry.defaultNotedByName : ''),
    );
    _approvedBy = TextEditingController(
      text: e.approvedBy ?? (isNew ? IdpEntry.defaultApprovedByName : ''),
    );
    _performanceRating = e.performanceRating;
    _competenceRating = e.competenceRating;
    _successionPriorityRating = e.successionPriorityRating;
    final plan = e.developmentPlanRows.isEmpty
        ? <IdpPlanRow>[const IdpPlanRow()]
        : List<IdpPlanRow>.from(e.developmentPlanRows);
    _planRows = plan
        .map(
          (r) => _rowControllers(
            r.objectives ?? '',
            r.ldProgram ?? '',
            r.requirements ?? '',
            r.timeFrame ?? '',
          ),
        )
        .toList();
    _nameFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (!widget.readOnly) _loadLookups();
  }

  Future<void> _loadLookups() async {
    final employees = await _fetchActiveEmployeeOptions();
    final offices = await _fetchActiveOfficeNames();
    if (!mounted) return;
    setState(() {
      _employees = employees;
      _officeNames = offices;
      _officesLoaded = offices.isNotEmpty;
    });
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
    _nameFocus.dispose();
    for (final c in [
      _name,
      _position,
      _category,
      _division,
      _departmentController,
      _education,
      _experience,
      _training,
      _eligibility,
      _accomplishments,
      _target1,
      _target2,
      _avgRating,
      _opcr,
      _ipcr,
      _competency,
      _priorityScore,
      _preparedBy,
      _reviewedBy,
      _notedBy,
      _approvedBy,
    ]) {
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
            objectives: _optText(r['objectives']!),
            ldProgram: _optText(r['ld_program']!),
            requirements: _optText(r['requirements']!),
            timeFrame: _optText(r['time_frame']!),
          ),
        )
        .toList();
    return IdpEntry(
      id: widget.entry.id,
      name: _optText(_name),
      position: _optText(_position),
      category: _optText(_category),
      division: _optText(_division),
      department: _department,
      education: _optText(_education),
      experience: _optText(_experience),
      training: _optText(_training),
      eligibility: _optText(_eligibility),
      significantAccomplishments: _optText(_accomplishments),
      targetPosition1: _optText(_target1),
      targetPosition2: _optText(_target2),
      avgRating: _optText(_avgRating),
      opcr: _optText(_opcr),
      ipcr: _optText(_ipcr),
      performanceRating: _performanceRating,
      competencyDescription: _optText(_competency),
      competenceRating: _competenceRating,
      successionPriorityScore: _optText(_priorityScore),
      successionPriorityRating: _successionPriorityRating,
      developmentPlanRows: rows,
      preparedBy: _optText(_preparedBy),
      reviewedBy: _optText(_reviewedBy),
      notedBy: _optText(_notedBy) ?? IdpEntry.defaultNotedByName,
      approvedBy: _optText(_approvedBy) ?? IdpEntry.defaultApprovedByName,
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  void _addPlanRow() {
    if (widget.readOnly) return;
    setState(() => _planRows.add(_rowControllers('', '', '', '')));
  }

  void _removePlanRow(int i) {
    if (widget.readOnly) return;
    if (_planRows.length <= 1) return;
    setState(() {
      for (final c in _planRows[i].values) {
        c.dispose();
      }
      _planRows.removeAt(i);
    });
  }

  void _selectEmployee(_IdpEmployeeOption e) {
    setState(() {
      _name.text = e.fullName;
      if ((e.positionName ?? '').trim().isNotEmpty) {
        _position.text = e.positionName!.trim();
      }
      if ((e.departmentName ?? '').trim().isNotEmpty) {
        _department = e.departmentName!.trim();
        _departmentController.text = _department!;
      }
    });
    _nameFocus.unfocus();
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

  Widget _textField(
    TextEditingController c,
    String label, {
    int minLines = 1,
    String? hint,
  }) {
    return TextFormField(
      controller: c,
      readOnly: widget.readOnly,
      minLines: minLines,
      maxLines: minLines == 1 ? 1 : minLines + 3,
      decoration: _decoration(context, label: label, hint: hint),
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

  Widget _responsiveGrid(List<Widget> fields, {int columns = 2}) {
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

  List<_IdpEmployeeOption> get _nameMatches {
    final q = _name.text.trim().toLowerCase();
    if (q.isEmpty || _employees.isEmpty) return const [];
    return _employees
        .where((e) => e.fullName.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  Widget _nameField() {
    final matches = _nameMatches;
    final show =
        !widget.readOnly &&
        _employees.isNotEmpty &&
        _nameFocus.hasFocus &&
        matches.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _name,
          focusNode: _nameFocus,
          readOnly: widget.readOnly,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(
            context,
            label: 'Name',
            hint: _employees.isNotEmpty ? 'Search or type a name' : 'Full name',
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
          ),
        ),
        if (show)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
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
      ],
    );
  }

  Widget _readOnlyValueBox(String label, String value) {
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

  Widget _departmentField() {
    if (widget.readOnly) {
      return _readOnlyValueBox('Department', _department ?? '—');
    }
    if (_officesLoaded) {
      return DropdownButtonFormField<String>(
        key: ValueKey(_department ?? ''),
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
      );
    }
    return _textField(_departmentController, 'Department');
  }

  Widget _choiceGroup({
    required String label,
    required List<(String value, String label)> options,
    required String? selected,
    required ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options)
              _IdpChoiceCard(
                label: opt.$2,
                selected: selected == opt.$1,
                enabled: onChanged != null,
                onTap: onChanged == null ? null : () => onChanged(opt.$1),
              ),
          ],
        ),
      ],
    );
  }

  /// Blank strip with a bottom rule for a physical pen signature above the
  /// printed name — same pattern as Applicants Profile.
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

  Widget _signatoryCard({
    required String title,
    required String caption,
    required TextEditingController name,
    required bool officialFixed,
    String? officialName,
  }) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final ro = widget.readOnly || officialFixed;
    final displayed = name.text.trim().isNotEmpty
        ? name.text.trim()
        : (officialName ?? '');
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
          Text(title, style: AppTheme.dashSectionTitle(context)),
          const SizedBox(height: 10),
          _signatureSpace(context),
          ro
              ? Text(
                  displayed.isEmpty ? '—' : displayed,
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : TextFormField(
                  controller: name,
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
          Text(caption, style: TextStyle(fontSize: 12, color: secondary)),
        ],
      ),
    );
  }

  Widget _employeeInformation() {
    return _sectionCard(
      title: 'EMPLOYEE INFORMATION',
      child: _responsiveGrid([
        _nameField(),
        _textField(_position, 'Position'),
        _textField(_category, 'Category'),
        _textField(_division, 'Division'),
        _departmentField(),
      ], columns: 3),
    );
  }

  Widget _qualifications() {
    return _sectionCard(
      title: 'QUALIFICATIONS',
      child: _responsiveGrid([
        _textField(_education, 'Education'),
        _textField(_experience, 'Experience'),
        _textField(_training, 'Training'),
        _textField(_eligibility, 'Eligibility'),
      ]),
    );
  }

  Widget _successionAnalysis() {
    return _sectionCard(
      title: 'SUCCESSION ANALYSIS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textField(
            _accomplishments,
            'Significant Accomplishments',
            minLines: 3,
          ),
          const SizedBox(height: 12),
          _responsiveGrid([
            _textField(_target1, 'Target Position 1'),
            _textField(_target2, 'Target Position 2'),
          ]),
          const SizedBox(height: 14),
          Text(
            'REQUIRED QUALIFICATIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Official instructional text (printed on the IDP form):',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                for (final line in _kIdpRequiredQualifications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $line',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppTheme.dashTextPrimaryOf(context),
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

  Widget _performanceAssessment() {
    final ro = widget.readOnly;
    return _sectionCard(
      title: 'PERFORMANCE AND COMPETENCY ASSESSMENT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _responsiveGrid([
            _textField(_opcr, 'OPCR'),
            _textField(_ipcr, 'IPCR'),
            _textField(_avgRating, 'Average Rating'),
          ], columns: 3),
          const SizedBox(height: 16),
          _choiceGroup(
            label: 'Performance Rating',
            options: const [
              ('poor', 'Poor'),
              ('unsatisfactory', 'Unsatisfactory'),
              ('very_satisfactory', 'Very Satisfactory'),
              ('outstanding', 'Outstanding'),
            ],
            selected: _performanceRating,
            onChanged: ro
                ? null
                : (v) => setState(() => _performanceRating = v),
          ),
          const SizedBox(height: 16),
          _textField(_competency, 'Competency'),
          const SizedBox(height: 16),
          _choiceGroup(
            label: 'Competency Level',
            options: const [
              ('basic', 'Basic'),
              ('immediate', 'Immediate'),
              ('advanced', 'Advanced'),
              ('superior', 'Superior'),
            ],
            selected: _competenceRating,
            onChanged: ro
                ? null
                : (v) => setState(() => _competenceRating = v),
          ),
          const SizedBox(height: 16),
          _textField(_priorityScore, 'Succession Priority Total Score'),
          const SizedBox(height: 16),
          _choiceGroup(
            label: 'Priority',
            options: const [
              ('priority', 'Priority 1'),
              ('priority_2', 'Priority 2'),
              ('priority_3', 'Priority 3'),
            ],
            selected: _successionPriorityRating,
            onChanged: ro
                ? null
                : (v) => setState(() => _successionPriorityRating = v),
          ),
        ],
      ),
    );
  }

  Widget _planCell(
    TextEditingController c, {
    required String hint,
    int minLines = 2,
  }) {
    return TextFormField(
      controller: c,
      readOnly: widget.readOnly,
      minLines: minLines,
      maxLines: minLines + 2,
      decoration: _decoration(context, hint: hint),
    );
  }

  Widget _removeRowButton(int i) {
    final canRemove = !widget.readOnly && _planRows.length > 1;
    return IconButton(
      tooltip: 'Remove row',
      onPressed: canRemove ? () => _removePlanRow(i) : null,
      icon: Icon(
        Icons.delete_outline_rounded,
        size: 18,
        color: canRemove
            ? Colors.red.shade700
            : AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.35),
      ),
    );
  }

  Widget _developmentPlan() {
    final ro = widget.readOnly;
    final headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
      color: AppTheme.dashTextSecondaryOf(context),
    );
    return _sectionCard(
      title: 'DEVELOPMENT PLAN — SHORT TERM (6 MONTHS)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final table = constraints.maxWidth > 720;
              if (!table) {
                return Column(
                  children: [
                    for (var i = 0; i < _planRows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.dashPanelOf(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.dashHairlineOf(context),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Row ${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.dashTextPrimaryOf(context),
                                  ),
                                ),
                                const Spacer(),
                                if (!ro) _removeRowButton(i),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _textField(
                              _planRows[i]['objectives']!,
                              'Objectives',
                              minLines: 2,
                            ),
                            const SizedBox(height: 8),
                            _textField(
                              _planRows[i]['ld_program']!,
                              'L & D Program',
                              minLines: 2,
                            ),
                            const SizedBox(height: 8),
                            _textField(
                              _planRows[i]['requirements']!,
                              'Requirements',
                              minLines: 2,
                            ),
                            const SizedBox(height: 8),
                            _textField(
                              _planRows[i]['time_frame']!,
                              'Time Frame',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.dashPanelOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dashHairlineOf(context)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text('OBJECTIVES', style: headerStyle)),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: Text('L & D PROGRAM', style: headerStyle)),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: Text('REQUIREMENTS', style: headerStyle)),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: Text('TIME FRAME', style: headerStyle)),
                          if (!ro) const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                    for (var i = 0; i < _planRows.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _planCell(
                                _planRows[i]['objectives']!,
                                hint: 'Objectives',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: _planCell(
                                _planRows[i]['ld_program']!,
                                hint: 'L & D Program',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: _planCell(
                                _planRows[i]['requirements']!,
                                hint: 'Requirements',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _planCell(
                                _planRows[i]['time_frame']!,
                                hint: 'Time Frame',
                                minLines: 1,
                              ),
                            ),
                            if (!ro) SizedBox(width: 40, child: _removeRowButton(i)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (!ro) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addPlanRow,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Row'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _certification() {
    return _sectionCard(
      title: 'CERTIFICATION / APPROVAL',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 640;
          final cards = [
            _signatoryCard(
              title: 'PREPARED BY',
              caption: 'Employee',
              name: _preparedBy,
              officialFixed: false,
            ),
            _signatoryCard(
              title: 'REVIEWED BY',
              caption: 'Department Head',
              name: _reviewedBy,
              officialFixed: false,
            ),
            _signatoryCard(
              title: 'NOTED BY',
              caption: IdpEntry.defaultNotedByTitle,
              name: _notedBy,
              officialFixed: true,
              officialName: IdpEntry.defaultNotedByName,
            ),
            _signatoryCard(
              title: 'APPROVED BY',
              caption: IdpEntry.defaultApprovedByTitle,
              name: _approvedBy,
              officialFixed: true,
              officialName: IdpEntry.defaultApprovedByName,
            ),
          ];
          if (!wide) {
            return Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  cards[i],
                ],
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[3]),
                ],
              ),
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
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
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
              tooltip: 'Print Preview',
              style: rspLdRecordIconButtonStyle(),
              onPressed: () => widget.onPrint(_buildCurrentEntry()),
              icon: const Icon(Icons.print_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Export PDF',
              style: rspLdRecordIconButtonStyle(),
              onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
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
                        _name.text.trim().isEmpty
                            ? 'New Individual Development Plan'
                            : _name.text.trim(),
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
                  'Local Government Unit of Plaridel',
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
                _employeeInformation(),
                const SizedBox(height: 16),
                _qualifications(),
                const SizedBox(height: 16),
                _successionAnalysis(),
                const SizedBox(height: 16),
                _performanceAssessment(),
                const SizedBox(height: 16),
                _developmentPlan(),
                const SizedBox(height: 16),
                _certification(),
                if (!ro) ...[
                  const SizedBox(height: 24),
                  _actionBar(),
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

class _IdpChoiceCard extends StatelessWidget {
  const _IdpChoiceCard({
    required this.label,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final String label;
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
      label: label,
      child: Material(
        color: selected
            ? navy.withValues(alpha: 0.12)
            : AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? navy : AppTheme.dashHairlineOf(context),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: selected
                      ? navy
                      : AppTheme.dashTextSecondaryOf(context),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? navy
                        : AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
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
              rspRecordsTextCell(context, e.name ?? '', bold: true),
              rspRecordsTextCell(context, e.position ?? ''),
              rspRecordsTextCell(context, e.department ?? ''),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Individual Development Plan',
                  subtitle: '${e.name ?? '—'} · ${e.position ?? ''}',
                  previewBuilder: () => IdpFormEditor(
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
                deleteDialogTitle: 'Delete IDP?',
              ),
            ],
          )
          .toList(),
    );
  }
}
