import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
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
  static const int _codeMaxLength = 64;
  static const int _labelMaxLength = 100;
  static const int _shortLabelMaxLength = 40;
  static const int _locationLabelMaxLength = 100;
  static const int _locationHintMaxLength = 200;
  static const int _dtrLabelMaxLength = 40;

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _labelController = TextEditingController();
  final _shortLabelController = TextEditingController();
  final _locationLabelController = TextEditingController();
  final _locationHintController = TextEditingController();
  final _dtrSlotLabelController = TextEditingController();
  final _dtrPrintLabelController = TextEditingController();
  final _sortOrderController = TextEditingController();

  List<LocatorRequestType> _items = [];
  LocatorRequestType? _selected;
  int _page = 0;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  bool _requiresAttachment = false;
  bool _isActive = true;
  String _coverageMode = 'manual';
  StreamSubscription<AppRealtimeEvent>? _locatorTypeRealtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locatorTypeRealtimeSub ??= context
        .read<AppRealtimeProvider>()
        .events
        .listen((event) {
          if (event.name != 'locator_type_updated') return;
          LocatorSlipDataCache.instance.invalidateTypes();
          if (!_saving) unawaited(_load(forceRefresh: true));
        });
  }

  @override
  void dispose() {
    _locatorTypeRealtimeSub?.cancel();
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await LocatorSlipDataCache.instance.listTypes(
        includeInactive: true,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      final selected = _selected;
      final selectedStillExists =
          selected == null ||
          items.any(
            (item) => selected.id != null
                ? item.id == selected.id
                : item.code == selected.code,
          );
      setState(() {
        _items = items;
        if (!selectedStillExists) _selected = null;
        _loading = false;
      });
      if (_selected == null) _newType();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _loadErrorMessage(e);
      });
    }
  }

  String _loadErrorMessage(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final data = error.response!.data as Map;
      final message = (data['error'] ?? data['message'])?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return 'The locator type catalog is currently unavailable.';
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
        'code': _codeController.text.trim().toLowerCase(),
        'label': _labelController.text.trim(),
        'short_label': _shortLabelController.text.trim(),
        'location_label': _locationLabelController.text.trim(),
        'location_hint': _locationHintController.text.trim(),
        'dtr_slot_label': _dtrSlotLabelController.text.trim(),
        'dtr_print_label': _dtrPrintLabelController.text.trim(),
        'requires_attachment': _requiresAttachment,
        'coverage_mode': _coverageMode,
        'is_active': _isActive,
        'sort_order': int.parse(_sortOrderController.text.trim()),
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
    if (_loading)
      return const SingleChildScrollView(
        child: WorkforceRowsSkeleton(
          columns: [2, 1],
          label: 'Loading locator types',
        ),
      );
    if (_loadError != null) return _buildLoadError();
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
            child: pageItems.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add_rounded,
              size: 34,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            const SizedBox(height: 10),
            Text(
              'No locator types configured',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Create the first locator type to make it available for filing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: Colors.red.shade600,
              ),
              const SizedBox(height: 10),
              Text(
                'Could not load locator types',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _load(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
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
    final catalogReady = !_loading && _loadError == null;
    return IgnorePointer(
      ignoring: !catalogReady,
      child: Opacity(
        opacity: catalogReady ? 1 : 0.55,
        child: Container(
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
                          _field(
                            _codeController,
                            'System code',
                            enabled: isNew,
                            maxLength: _codeMaxLength,
                            validator: _validateSystemCode,
                          ),
                          _field(
                            _labelController,
                            'Request type name',
                            maxLength: _labelMaxLength,
                          ),
                          _field(
                            _shortLabelController,
                            'Short display name',
                            maxLength: _shortLabelMaxLength,
                          ),
                          _field(
                            _sortOrderController,
                            'Sort order',
                            number: true,
                            validator: _validateSortOrder,
                          ),
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
                            maxLength: _locationLabelMaxLength,
                          ),
                          _field(
                            _locationHintController,
                            'Destination placeholder',
                            maxLength: _locationHintMaxLength,
                          ),
                          _field(
                            _dtrSlotLabelController,
                            'DTR display text',
                            maxLength: _dtrLabelMaxLength,
                          ),
                          _field(
                            _dtrPrintLabelController,
                            'DTR print text',
                            maxLength: _dtrLabelMaxLength,
                          ),
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
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        maxLength: maxLength,
        maxLengthEnforcement: maxLength == null
            ? null
            : MaxLengthEnforcement.none,
        decoration: AppTheme.dashInputDecoration(context, labelText: label),
        validator:
            validator ??
            (value) => _validateRequiredText(value, label, maxLength),
      ),
    );
  }

  String? _validateRequiredText(String? value, String label, int? maxLength) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required';
    if (maxLength != null && text.length > maxLength) {
      return '$label must be $maxLength characters or less';
    }
    return null;
  }

  String? _validateSystemCode(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return 'System code is required';
    if (!RegExp(r'^[a-z0-9_][a-z0-9_-]{1,63}$').hasMatch(text)) {
      return 'Use 2-64 letters, numbers, underscores, or hyphens';
    }
    return null;
  }

  String? _validateSortOrder(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Sort order is required';
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      return 'Sort order must be a whole number from 0 to 2147483647';
    }
    final parsed = int.tryParse(text);
    if (parsed == null || parsed > 2147483647) {
      return 'Sort order must be a whole number from 0 to 2147483647';
    }
    return null;
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
