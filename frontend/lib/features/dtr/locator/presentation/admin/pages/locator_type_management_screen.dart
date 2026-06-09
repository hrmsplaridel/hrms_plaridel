import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';

class LocatorTypeManagementScreen extends StatefulWidget {
  const LocatorTypeManagementScreen({super.key});

  @override
  State<LocatorTypeManagementScreen> createState() =>
      _LocatorTypeManagementScreenState();
}

class _LocatorTypeManagementScreenState
    extends State<LocatorTypeManagementScreen> {
  static const int _typesPerPage = 8;

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _labelController = TextEditingController();
  final _shortLabelController = TextEditingController();
  final _locationLabelController = TextEditingController();
  final _locationHintController = TextEditingController();
  final _dtrSlotLabelController = TextEditingController();
  final _dtrPrintLabelController = TextEditingController();
  final _sortOrderController = TextEditingController();

  List<LocatorRequestType> _items = LocatorRequestType.values;
  LocatorRequestType? _selected;
  int _page = 0;
  bool _loading = true;
  bool _saving = false;
  bool _requiresAttachment = false;
  bool _isActive = true;
  String _coverageMode = 'manual';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _labelController.dispose();
    _shortLabelController.dispose();
    _locationLabelController.dispose();
    _locationHintController.dispose();
    _dtrSlotLabelController.dispose();
    _dtrPrintLabelController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    try {
      final items = await LocatorSlipDataCache.instance.listTypes(
        includeInactive: true,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _items = items.isEmpty ? LocatorRequestType.values : items;
        _loading = false;
      });
      if (_selected == null) _newType();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load locator types: $e');
    }
  }

  void _newType() {
    setState(() {
      _selected = null;
      _codeController.clear();
      _labelController.clear();
      _shortLabelController.clear();
      _locationLabelController.text = 'Office / Destination';
      _locationHintController.text = 'Enter office or destination';
      _dtrSlotLabelController.clear();
      _dtrPrintLabelController.clear();
      _sortOrderController.text = '${(_items.length + 1) * 10}';
      _requiresAttachment = false;
      _isActive = true;
      _coverageMode = 'manual';
    });
  }

  void _clampPage(int totalItems) {
    final maxPage = totalItems == 0 ? 0 : (totalItems - 1) ~/ _typesPerPage;
    if (_page > maxPage) _page = maxPage;
    if (_page < 0) _page = 0;
  }

  void _select(LocatorRequestType item) {
    setState(() {
      _selected = item;
      _codeController.text = item.code;
      _labelController.text = item.label;
      _shortLabelController.text = item.shortLabel;
      _locationLabelController.text = item.locationLabel;
      _locationHintController.text = item.locationHint;
      _dtrSlotLabelController.text = item.dtrSlotLabel;
      _dtrPrintLabelController.text = item.dtrPrintLabel;
      _sortOrderController.text = item.sortOrder.toString();
      _requiresAttachment = item.requiresAttachment;
      _isActive = item.isActive;
      _coverageMode = item.coverageMode == 'wfh' ? 'wfh' : 'manual';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'code': _codeController.text.trim(),
        'label': _labelController.text.trim(),
        'short_label': _shortLabelController.text.trim(),
        'location_label': _locationLabelController.text.trim(),
        'location_hint': _locationHintController.text.trim(),
        'dtr_slot_label': _dtrSlotLabelController.text.trim(),
        'dtr_print_label': _dtrPrintLabelController.text.trim(),
        'requires_attachment': _requiresAttachment,
        'coverage_mode': _coverageMode,
        'is_active': _isActive,
        'sort_order': int.tryParse(_sortOrderController.text.trim()) ?? 0,
      };
      final selected = _selected;
      if (selected?.id == null || selected!.id!.isEmpty) {
        await ApiClient.instance.post('/api/locator-slips/types', data: data);
        _showMessage('Locator type added.');
      } else {
        await ApiClient.instance.put(
          '/api/locator-slips/types/${selected.id}',
          data: data,
        );
        _showMessage('Locator type updated.');
      }
      LocatorSlipDataCache.instance.invalidateTypes();
      LocatorSlipDataCache.instance.invalidateRequests();
      await _load(forceRefresh: true);
    } on DioException catch (e) {
      _showMessage(
        e.response?.data is Map
            ? ((e.response?.data as Map)['error']?.toString() ??
                  e.message ??
                  '')
            : (e.message ?? 'Save failed.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteOrDeactivate() async {
    final selected = _selected;
    if (selected?.id == null || selected!.id!.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove locator type?'),
        content: const Text(
          'Unused custom types are deleted. Types already used in requests are deactivated instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.delete(
        '/api/locator-slips/types/${selected.id}',
      );
      _selected = null;
      LocatorSlipDataCache.instance.invalidateTypes();
      LocatorSlipDataCache.instance.invalidateRequests();
      await _load(forceRefresh: true);
      _showMessage('Locator type removed.');
    } catch (e) {
      _showMessage('Remove failed: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: AppTheme.dashCanvasOf(context),
        child: Column(
          children: [
            _buildHeader(),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 340, child: _buildList()),
                    const SizedBox(width: 20),
                    Expanded(child: _buildForm()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.dashPanelOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tune_rounded, color: AppTheme.primaryNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Locator Types',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Configure filing types, DTR labels, and attachment rules.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    _clampPage(_items.length);
    final pageStart = _items.isEmpty ? 0 : _page * _typesPerPage;
    final pageEnd = (pageStart + _typesPerPage).clamp(0, _items.length);
    final pageItems = _items.sublist(pageStart, pageEnd);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_items.length} locator types',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_selected != null)
                  FilledButton.icon(
                    onPressed: _newType,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Type'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: pageItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = pageItems[index];
                return _typeListItem(item, item == _selected);
              },
            ),
          ),
          _TypeListPager(
            page: _page,
            pageSize: _typesPerPage,
            total: _items.length,
            itemLabel: 'locator types',
            onPrevious: _page <= 0 ? null : () => setState(() => _page--),
            onNext: pageEnd >= _items.length
                ? null
                : () => setState(() => _page++),
          ),
        ],
      ),
    );
  }

  Widget _typeListItem(LocatorRequestType item, bool selected) {
    final textColor = selected
        ? AppTheme.primaryNavy
        : AppTheme.dashTextPrimaryOf(context);
    return Material(
      color: selected
          ? AppTheme.primaryNavy.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _select(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(_typeIcon(item), size: 20, color: textColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _miniStatusChip(
                item.isActive ? 'Active' : 'Inactive',
                item.isActive ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final isNew = _selected == null;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _formHeader(isNew),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _formSection(
                    title: 'Basic Information',
                    icon: Icons.edit_note_rounded,
                    children: [
                      _field(_codeController, 'System code', enabled: isNew),
                      _field(_labelController, 'Request type name'),
                      _field(_shortLabelController, 'Short display name'),
                      _field(_sortOrderController, 'Sort order', number: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _formSection(
                    title: 'Form and DTR Wording',
                    icon: Icons.article_outlined,
                    children: [
                      _field(
                        _locationLabelController,
                        'Destination field name',
                      ),
                      _field(
                        _locationHintController,
                        'Destination placeholder',
                      ),
                      _field(_dtrSlotLabelController, 'DTR display text'),
                      _field(_dtrPrintLabelController, 'DTR print text'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _rulesSection(),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            _formActions(isNew),
          ],
        ),
      ),
    );
  }

  Widget _formHeader(bool isNew) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isNew ? Icons.add_rounded : _typeIcon(_selected!),
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNew ? 'New locator type' : _selected!.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isNew
                      ? 'Create a filing type employees can select.'
                      : 'Editing ${_selected!.code}',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formActions(bool isNew) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _selected == null ? null : _deleteOrDeactivate,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(isNew ? 'Create Type' : 'Save Changes'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rulesSection() {
    return _formSection(
      title: 'Filing Requirements',
      icon: Icons.fact_check_outlined,
      children: [
        _settingTile(
          icon: Icons.attach_file_rounded,
          title: 'Require attachment',
          subtitle: 'Employees must upload a PDF or image when filing.',
          value: _requiresAttachment,
          onChanged: (value) => setState(() => _requiresAttachment = value),
        ),
        _settingTile(
          icon: Icons.toggle_on_rounded,
          title: 'Available for filing',
          subtitle: 'Inactive types stay in history but cannot be filed.',
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
        ),
        SizedBox(
          width: 360,
          child: DropdownButtonFormField<String>(
            initialValue: _coverageMode,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Time coverage behavior',
              prefixIcon: const Icon(Icons.timelapse_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'manual', child: Text('Manual segments')),
              DropdownMenuItem(value: 'wfh', child: Text('WFH coverage')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _coverageMode = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _formSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryNavy),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 14, runSpacing: 14, children: children),
        ],
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 360,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.dashPanelOf(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryNavy, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    bool number = false,
  }) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: AppTheme.dashInputDecoration(context, labelText: label),
        validator: (value) => (value == null || value.trim().isEmpty)
            ? '$label is required'
            : null,
      ),
    );
  }

  Widget _miniStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  IconData _typeIcon(LocatorRequestType item) {
    if (item.usesWfhCoverage) return Icons.home_work_rounded;
    if (item.code == LocatorRequestType.passSlip.code) {
      return Icons.badge_rounded;
    }
    return Icons.near_me_rounded;
  }
}

class _TypeListPager extends StatelessWidget {
  const _TypeListPager({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.itemLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageSize;
  final int total;
  final String itemLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : page * pageSize + 1;
    final end = total == 0 ? 0 : (page * pageSize + pageSize).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == 0 ? 'No $itemLabel' : 'Showing $start-$end of $total',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
