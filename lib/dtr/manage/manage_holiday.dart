import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

class _HolidayRecord {
  const _HolidayRecord({
    required this.id,
    required this.dateFrom,
    required this.dateTo,
    required this.name,
    required this.holidayType,
    this.description,
    this.isActive = true,
    this.isRecurring = false,
    this.coverage = 'whole_day',
  });
  final String id;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String name;
  final String holidayType;
  final String? description;
  final bool isActive;
  final bool isRecurring;
  final String coverage;

  bool get isSingleDay =>
      dateFrom.year == dateTo.year &&
      dateFrom.month == dateTo.month &&
      dateFrom.day == dateTo.day;
}

class ManageHoliday extends StatefulWidget {
  const ManageHoliday({super.key});

  @override
  State<ManageHoliday> createState() => _ManageHolidayState();
}

class _ManageHolidayState extends State<ManageHoliday> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _holidayType = 'regular';
  String _coverage = 'whole_day';
  bool _isActive = true;
  bool _isRecurring = false;

  List<_HolidayRecord> _holidays = [];
  bool _loading = false;
  _HolidayRecord? _selectedHoliday;
  StateSetter? _drawerSetState;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
        context,
        hintText: hint,
        radius: 8,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      );

  void _updateHolidayFormState(VoidCallback update) {
    if (mounted) setState(update);
    _drawerSetState?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHolidays());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadHolidays() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>('/api/holidays');
      final data = res.data ?? [];
      _holidays = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final fromRaw = m['date_from'] ?? m['holiday_date'];
        final toRaw = m['date_to'] ?? m['holiday_date'];
        return _HolidayRecord(
          id: m['id'] as String,
          dateFrom: _parseDateSafe(fromRaw),
          dateTo: _parseDateSafe(toRaw),
          name: m['name'] as String? ?? '',
          holidayType: m['holiday_type'] as String? ?? 'regular',
          description: m['description'] as String?,
          isActive: m['is_active'] as bool? ?? true,
          isRecurring: m['recurring'] as bool? ?? false,
          coverage: m['coverage'] as String? ?? 'whole_day',
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load holidays failed: ${e.response?.data ?? e.message}');
      _holidays = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectHoliday(_HolidayRecord h) {
    _updateHolidayFormState(() {
      _selectedHoliday = h;
      _nameController.text = h.name;
      _descriptionController.text = h.description ?? '';
      _dateFrom = h.dateFrom;
      _dateTo = h.dateTo;
      _holidayType = h.holidayType;
      _coverage = h.coverage;
      _isActive = h.isActive;
      _isRecurring = h.isRecurring;
    });
  }

  void _clearForm() {
    _updateHolidayFormState(() {
      _selectedHoliday = null;
      _nameController.clear();
      _descriptionController.clear();
      _dateFrom = null;
      _dateTo = null;
      _holidayType = 'regular';
      _coverage = 'whole_day';
      _isActive = true;
      _isRecurring = false;
    });
  }

  String _holidayListSubtitle(_HolidayRecord h) {
    String mmdd(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final typeExtra =
        h.holidayType == 'work_suspension' && h.coverage != 'whole_day'
        ? ' · ${h.coverage}'
        : '';
    final recur = h.isRecurring ? ' (every year)' : '';
    if (h.isSingleDay) {
      return '${mmdd(h.dateFrom)}${h.isRecurring ? recur : ' · ${h.dateFrom.year}'} · ${h.holidayType}$typeExtra';
    }
    final years = h.dateFrom.year == h.dateTo.year
        ? (h.isRecurring ? '' : ' · ${h.dateFrom.year}')
        : ' · ${h.dateFrom.year}–${h.dateTo.year}';
    return '${mmdd(h.dateFrom)}–${mmdd(h.dateTo)}${h.isRecurring ? recur : years} · ${h.holidayType}$typeExtra';
  }

  /// Format date as YYYY-MM-DD using local calendar date (avoids UTC off-by-one).
  static String _dateToYyyyMmDd(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Parse API date string as local calendar date (avoids UTC shift when API returns ISO with Z).
  static DateTime _parseDateSafe(dynamic value) {
    if (value == null) return DateTime.now();
    final s = value.toString().split('T').first;
    final parts = s.split('-');
    if (parts.length != 3) return DateTime.tryParse(s) ?? DateTime.now();
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (y == null || m == null || day == null) {
      return DateTime.tryParse(s) ?? DateTime.now();
    }
    return DateTime(y, m, day); // Local date, no timezone
  }

  Future<bool> _addHoliday() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a holiday name.')),
      );
      return false;
    }
    if (_dateFrom == null || _dateTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates.')),
      );
      return false;
    }
    if (_dateTo!.isBefore(_dateFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after start date.'),
        ),
      );
      return false;
    }
    try {
      await ApiClient.instance.post(
        '/api/holidays',
        data: {
          'date_from': _dateToYyyyMmDd(_dateFrom!),
          'date_to': _dateToYyyyMmDd(_dateTo!),
          'name': name,
          'holiday_type': _holidayType,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'is_active': _isActive,
          'recurring': _isRecurring,
          if (_holidayType == 'work_suspension') 'coverage': _coverage,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Holiday added.')));
        _clearForm();
        _loadHolidays();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to add';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $msg')));
      }
      return false;
    }
  }

  Future<bool> _updateHoliday() async {
    final h = _selectedHoliday;
    if (h == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a holiday to update.')),
      );
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a holiday name.')),
      );
      return false;
    }
    if (_dateFrom == null || _dateTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates.')),
      );
      return false;
    }
    if (_dateTo!.isBefore(_dateFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after start date.'),
        ),
      );
      return false;
    }
    try {
      await ApiClient.instance.put(
        '/api/holidays/${h.id}',
        data: {
          'date_from': _dateToYyyyMmDd(_dateFrom!),
          'date_to': _dateToYyyyMmDd(_dateTo!),
          'name': name,
          'holiday_type': _holidayType,
          'coverage': _holidayType == 'work_suspension'
              ? _coverage
              : 'whole_day',
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'is_active': _isActive,
          'recurring': _isRecurring,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Holiday updated.')));
        _clearForm();
        _loadHolidays();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to update';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $msg')));
      }
      return false;
    }
  }

  Future<bool> _deleteHoliday() async {
    final h = _selectedHoliday;
    if (h == null) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete holiday?'),
        content: Text('Remove "${h.name}" from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    try {
      await ApiClient.instance.delete('/api/holidays/${h.id}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Holiday deleted.')));
        _clearForm();
        _loadHolidays();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to delete';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $msg')));
      }
      return false;
    }
  }

  Future<void> _openHolidayDrawer({_HolidayRecord? holiday}) async {
    if (holiday == null) {
      _clearForm();
    } else {
      _selectHoliday(holiday);
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final drawerWidth = screenWidth < 720 ? screenWidth : 560.0;
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: drawerWidth,
            height: double.infinity,
            child: Material(
              color: AppTheme.dashPanelOf(dialogContext),
              elevation: 18,
              child: StatefulBuilder(
                builder: (context, drawerSetState) {
                  _drawerSetState = drawerSetState;
                  return _buildHolidayDrawer(dialogContext);
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );

    _drawerSetState = null;
  }

  Widget _buildHolidayDrawer(BuildContext drawerContext) {
    final isEditing = _selectedHoliday != null;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Edit Holiday' : 'Add Holiday',
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: _mutedColor(context),
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _buildFormPanel(framed: false, showActions: false),
            ),
          ),
          _buildDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedHoliday != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(drawerContext).pop(),
            child: const Text('Cancel'),
          ),
          if (isEditing)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deleteHoliday();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = isEditing
                  ? await _updateHoliday()
                  : await _addHoliday();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Holiday'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.toLowerCase();
    final filtered = _holidays.where((h) {
      if (h.name.toLowerCase().contains(search)) return true;
      final rf = '${_dateToYyyyMmDd(h.dateFrom)} ${_dateToYyyyMmDd(h.dateTo)}';
      return rf.contains(search);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Holiday Management',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openHolidayDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Holiday'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE85D04),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildListPanel(filtered),
      ],
    );
  }

  Widget _buildListPanel(List<_HolidayRecord> filtered) {
    final dark = _isDark(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: AppTheme.dashFieldTextStyle(context),
            decoration: AppTheme.dashInputDecoration(
              context,
              hintText: 'Search by name or date',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: _mutedColor(context).withValues(alpha: 0.7),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              radius: 10,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No holidays',
                  style: TextStyle(color: _mutedColor(context), fontSize: 14),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final h = filtered[i];
                final isSelected = _selectedHoliday?.id == h.id;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: dark
                      ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                      : AppTheme.primaryNavy.withValues(alpha: 0.08),
                  title: Text(
                    h.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _headingColor(context),
                    ),
                  ),
                  subtitle: Text(
                    _holidayListSubtitle(h),
                    style: TextStyle(
                      fontSize: 12,
                      color: _mutedColor(context),
                    ),
                  ),
                  onTap: () => _openHolidayDrawer(holiday: h),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFormPanel({
    bool framed = true,
    bool showActions = true,
  }) {
    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Holiday name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration('e.g. New Year\'s Day'),
          ),
          const SizedBox(height: 16),
          Text(
            'Date range',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          if (_isRecurring)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Same month/day range repeats every year (e.g. Holy Week).',
                style: TextStyle(fontSize: 11, color: _mutedColor(context)),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start',
                      style: TextStyle(
                        fontSize: 11,
                        color: _mutedColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateFrom ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (d != null) {
                          _updateHolidayFormState(() {
                            _dateFrom = d;
                            if (_dateTo != null && _dateTo!.isBefore(d)) {
                              _dateTo = d;
                            }
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: _inputDecoration(''),
                        child: Text(
                          _dateFrom != null
                              ? _dateToYyyyMmDd(_dateFrom!)
                              : 'Select',
                          style: TextStyle(
                            color: _dateFrom != null
                                ? _headingColor(context)
                                : _mutedColor(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End',
                      style: TextStyle(
                        fontSize: 11,
                        color: _mutedColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateTo ?? _dateFrom ?? DateTime.now(),
                          firstDate: _dateFrom ?? DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (d != null) {
                          _updateHolidayFormState(() => _dateTo = d);
                        }
                      },
                      child: InputDecorator(
                        decoration: _inputDecoration(''),
                        child: Text(
                          _dateTo != null
                              ? _dateToYyyyMmDd(_dateTo!)
                              : 'Select',
                          style: TextStyle(
                            color: _dateTo != null
                                ? _headingColor(context)
                                : _mutedColor(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _isRecurring,
                onChanged: (v) =>
                    _updateHolidayFormState(() => _isRecurring = v ?? false),
                activeColor: AppTheme.primaryNavy,
              ),
              Text(
                'Repeat every year',
                style: TextStyle(color: _headingColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Type',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey(_holidayType),
            initialValue: _holidayType,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration(''),
            items: const [
              DropdownMenuItem(value: 'regular', child: Text('Regular')),
              DropdownMenuItem(value: 'special', child: Text('Special')),
              DropdownMenuItem(value: 'local', child: Text('Local')),
              DropdownMenuItem(
                value: 'work_suspension',
                child: Text('Work suspension'),
              ),
            ],
            onChanged: (v) {
              _updateHolidayFormState(() {
                _holidayType = v ?? 'regular';
                if (_holidayType != 'work_suspension') _coverage = 'whole_day';
              });
            },
          ),
          if (_holidayType == 'work_suspension') ...[
            const SizedBox(height: 16),
            Text(
              'Coverage',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _mutedColor(context),
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey(_coverage),
              initialValue: _coverage,
              dropdownColor: AppTheme.dashPanelOf(context),
              style: AppTheme.dashFieldTextStyle(context),
              decoration: _inputDecoration(''),
              items: const [
                DropdownMenuItem(value: 'whole_day', child: Text('Whole day')),
                DropdownMenuItem(value: 'am_only', child: Text('AM only')),
                DropdownMenuItem(value: 'pm_only', child: Text('PM only')),
              ],
              onChanged: (v) =>
                  _updateHolidayFormState(() => _coverage = v ?? 'whole_day'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Description (optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descriptionController,
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration('Short description'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _isActive,
                onChanged: (v) =>
                    _updateHolidayFormState(() => _isActive = v ?? true),
                activeColor: AppTheme.primaryNavy,
              ),
              Text('Active', style: TextStyle(color: _headingColor(context))),
            ],
          ),
          if (showActions) ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _addHoliday(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Holiday'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedHoliday != null
                      ? () => _updateHoliday()
                      : null,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Update'),
                ),
                FilledButton.icon(
                  onPressed: _selectedHoliday != null
                      ? () => _deleteHoliday()
                      : null,
                  icon: const Icon(Icons.delete_rounded, size: 18),
                  label: const Text('Delete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      );

    if (!framed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: content,
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: content,
    );
  }
}
