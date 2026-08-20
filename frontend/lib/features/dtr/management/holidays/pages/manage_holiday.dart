import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';

part '../models/holiday_models.dart';
part '../widgets/philippine_holiday_defaults_dialog.dart';
part '../widgets/holiday_template_upload_dialog.dart';

class ManageHoliday extends StatefulWidget {
  const ManageHoliday({super.key});

  @override
  State<ManageHoliday> createState() => _ManageHolidayState();
}

class _ManageHolidayState extends State<ManageHoliday> {
  static const int _rowsPerPage = 10;

  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _holidayType = 'regular';
  String _coverage = 'whole_day';
  String _typeFilter = 'all';
  bool _isActive = true;
  bool _isRecurring = false;
  int _page = 0;

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
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  void _updateHolidayFormState(VoidCallback update) {
    if (mounted) setState(update);
    final drawerSetState = _drawerSetState;
    if (!mounted || drawerSetState == null) return;
    try {
      drawerSetState(() {});
    } catch (_) {
      _drawerSetState = null;
    }
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
    setState(() {
      _loading = true;
      _page = 0;
    });
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

  String _holidayTypeLabel(String type) {
    switch (type) {
      case 'regular':
        return 'Regular';
      case 'special':
        return 'Special';
      case 'local':
        return 'Local';
      case 'work_suspension':
        return 'Work suspension';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  IconData _holidayTypeIcon(String type) {
    switch (type) {
      case 'regular':
        return Icons.flag_rounded;
      case 'special':
        return Icons.star_rounded;
      case 'local':
        return Icons.location_city_rounded;
      case 'work_suspension':
        return Icons.pause_circle_outline_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Color _holidayTypeColor(String type) {
    switch (type) {
      case 'regular':
        return const Color(0xFFE85D04);
      case 'special':
        return const Color(0xFF7C3AED);
      case 'local':
        return const Color(0xFF0F766E);
      case 'work_suspension':
        return const Color(0xFFB45309);
      default:
        return _mutedColor(context);
    }
  }

  String _coverageLabel(String value) {
    switch (value) {
      case 'am_only':
        return 'AM only';
      case 'pm_only':
        return 'PM only';
      default:
        return 'Whole day';
    }
  }

  String _dateRangeLabel(_HolidayRecord h) {
    if (h.isSingleDay) return _dateToYyyyMmDd(h.dateFrom);
    return '${_dateToYyyyMmDd(h.dateFrom)} - ${_dateToYyyyMmDd(h.dateTo)}';
  }

  String _dateBadgeMonth(_HolidayRecord h) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return months[h.dateFrom.month - 1];
  }

  String _dateBadgeDay(_HolidayRecord h) {
    if (h.isSingleDay) return h.dateFrom.day.toString().padLeft(2, '0');
    return '${h.dateFrom.day}-${h.dateTo.day}';
  }

  int _countType(String type) =>
      _holidays.where((holiday) => holiday.holidayType == type).length;

  int get _activeHolidayCount =>
      _holidays.where((holiday) => holiday.isActive).length;

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

  Future<void> _openPhilippineDefaultsDialog() async {
    final result = await openResponsiveRightSidePanel<_HolidayImportResult>(
      context: context,
      barrierLabel: 'Close Philippine holiday defaults',
      breakpoint: 900,
      minWidth: 720,
      initialWidthFraction: 0.58,
      builder: (_) => const _PhilippineHolidayDefaultsDialog(),
    );
    if (!mounted || result == null) return;
    await _loadHolidays();
    if (!mounted) return;
    final message = result.createdCount > 0
        ? 'Imported ${result.createdCount} PH holidays. ${result.skippedCount} already existed.'
        : 'No new holidays imported. ${result.skippedCount} already existed.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openHolidayDrawer({_HolidayRecord? holiday}) async {
    _drawerSetState = null;
    if (holiday == null) {
      _clearForm();
    } else {
      _selectHoliday(holiday);
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
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
    } finally {
      _drawerSetState = null;
    }
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
                  icon: Icon(Icons.close_rounded, color: _mutedColor(context)),
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
      final rf = '${_dateToYyyyMmDd(h.dateFrom)} ${_dateToYyyyMmDd(h.dateTo)}';
      final haystack =
          '${h.name} ${h.description ?? ''} ${h.holidayType} ${_holidayTypeLabel(h.holidayType)} $rf'
              .toLowerCase();
      final matchesSearch = search.isEmpty || haystack.contains(search);
      final matchesType = _typeFilter == 'all'
          ? true
          : _typeFilter == 'inactive'
          ? !h.isActive
          : h.holidayType == _typeFilter;
      return matchesSearch && matchesType;
    }).toList()..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(),
        const SizedBox(height: 16),
        _buildSummaryStrip(),
        const SizedBox(height: 16),
        _buildListPanel(filtered),
      ],
    );
  }

  Widget _buildPageHeader() {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Holiday Management',
          style: TextStyle(
            color: _headingColor(context),
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage dates that affect DTR attendance, undertime, and payroll rules.',
          style: TextStyle(color: _mutedColor(context), fontSize: 13),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: _openPhilippineDefaultsDialog,
          icon: const Icon(Icons.event_available_rounded, size: 18),
          label: const Text('Import PH Defaults'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE85D04),
            side: const BorderSide(color: Color(0xFFE85D04)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        FilledButton.icon(
          onPressed: () => _openHolidayDrawer(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Holiday'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE85D04),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildSummaryStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth < 720
            ? constraints.maxWidth
            : (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildSummaryTile(
              width: tileWidth,
              icon: Icons.event_available_rounded,
              label: 'Active holidays',
              value: '$_activeHolidayCount',
              detail: '${_holidays.length} total records',
              color: const Color(0xFF16A34A),
            ),
            _buildSummaryTile(
              width: tileWidth,
              icon: Icons.flag_rounded,
              label: 'Regular',
              value: '${_countType('regular')}',
              detail: 'National regular days',
              color: const Color(0xFFE85D04),
            ),
            _buildSummaryTile(
              width: tileWidth,
              icon: Icons.star_rounded,
              label: 'Special',
              value: '${_countType('special')}',
              detail: 'Special non-working days',
              color: const Color(0xFF7C3AED),
            ),
            _buildSummaryTile(
              width: tileWidth,
              icon: Icons.pause_circle_outline_rounded,
              label: 'Local / Suspensions',
              value: '${_countType('local') + _countType('work_suspension')}',
              detail: 'LGU and temporary rules',
              color: const Color(0xFF0F766E),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryTile({
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required String detail,
    required Color color,
  }) {
    final dark = _isDark(context);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.dashSurfaceCard(context, radius: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: dark ? 0.24 : 0.11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _mutedColor(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _mutedColor(context),
                      fontSize: 11.5,
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

  Widget _buildListPanel(List<_HolidayRecord> filtered) {
    final total = filtered.length;
    final pageCount = total == 0
        ? 1
        : ((total + _rowsPerPage - 1) ~/ _rowsPerPage);
    final page = _page >= pageCount ? pageCount - 1 : _page;
    final pageStart = page * _rowsPerPage;
    final pageEnd = pageStart + _rowsPerPage > total
        ? total
        : pageStart + _rowsPerPage;
    final paged = total == 0
        ? <_HolidayRecord>[]
        : filtered.sublist(pageStart, pageEnd);
    return Container(
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHolidayToolbar(total),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          if (_loading)
            _buildLoadingState()
          else if (filtered.isEmpty)
            _buildEmptyState()
          else
            Column(
              children: [
                for (var i = 0; i < paged.length; i++) ...[
                  _buildHolidayRow(
                    paged[i],
                    selected: _selectedHoliday?.id == paged[i].id,
                  ),
                  if (i != paged.length - 1)
                    Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                ],
                _buildPaginationFooter(
                  total: total,
                  page: page,
                  pageCount: pageCount,
                  pageStart: pageStart,
                  pageEnd: pageEnd,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHolidayToolbar(int filteredCount) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Holiday Directory',
                      style: TextStyle(
                        color: _headingColor(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$filteredCount matching ${filteredCount == 1 ? 'holiday' : 'holidays'}',
                      style: TextStyle(
                        color: _mutedColor(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadHolidays,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                color: _mutedColor(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = TextField(
                controller: _searchController,
                onChanged: (_) => setState(() => _page = 0),
                style: AppTheme.dashFieldTextStyle(context),
                decoration: AppTheme.dashInputDecoration(
                  context,
                  hintText: 'Search holiday, date, or type',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: _mutedColor(context).withValues(alpha: 0.7),
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _page = 0);
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: 'Clear search',
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  radius: 10,
                ),
              );

              final filters = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('all', 'All', Icons.layers_rounded),
                  _buildFilterChip('regular', 'Regular', Icons.flag_rounded),
                  _buildFilterChip('special', 'Special', Icons.star_rounded),
                  _buildFilterChip(
                    'local',
                    'Local',
                    Icons.location_city_rounded,
                  ),
                  _buildFilterChip(
                    'work_suspension',
                    'Suspension',
                    Icons.pause_circle_outline_rounded,
                  ),
                  _buildFilterChip(
                    'inactive',
                    'Inactive',
                    Icons.visibility_off_rounded,
                  ),
                ],
              );

              if (constraints.maxWidth < 880) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [searchField, const SizedBox(height: 12), filters],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 360, child: searchField),
                  const SizedBox(width: 12),
                  Expanded(child: filters),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final selected = _typeFilter == value;
    final color = value == 'all'
        ? const Color(0xFFE85D04)
        : value == 'inactive'
        ? const Color(0xFF64748B)
        : _holidayTypeColor(value);
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16, color: selected ? Colors.white : color),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _headingColor(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: _isDark(context) ? 0.16 : 0.07),
      side: BorderSide(
        color: selected
            ? color
            : color.withValues(alpha: _isDark(context) ? 0.28 : 0.18),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => setState(() {
        _typeFilter = value;
        _page = 0;
      }),
    );
  }

  Widget _buildHolidayRow(_HolidayRecord holiday, {required bool selected}) {
    final dark = _isDark(context);
    final accent = _holidayTypeColor(holiday.holidayType);
    final description = holiday.description?.trim();
    return Material(
      color: selected
          ? accent.withValues(alpha: dark ? 0.18 : 0.07)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _openHolidayDrawer(holiday: holiday),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
          child: Row(
            children: [
              _buildDateBadge(holiday, accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            holiday.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _headingColor(context),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!holiday.isActive) ...[
                          const SizedBox(width: 8),
                          _buildMetaPill(
                            'Inactive',
                            Icons.visibility_off_rounded,
                            const Color(0xFF64748B),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaPill(
                          _holidayTypeLabel(holiday.holidayType),
                          _holidayTypeIcon(holiday.holidayType),
                          accent,
                        ),
                        _buildMetaPill(
                          _dateRangeLabel(holiday),
                          Icons.calendar_today_rounded,
                          _mutedColor(context),
                          subtle: true,
                        ),
                        if (holiday.isRecurring)
                          _buildMetaPill(
                            'Repeats yearly',
                            Icons.repeat_rounded,
                            const Color(0xFF2563EB),
                          ),
                        if (holiday.holidayType == 'work_suspension')
                          _buildMetaPill(
                            _coverageLabel(holiday.coverage),
                            Icons.schedule_rounded,
                            const Color(0xFFB45309),
                          ),
                      ],
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _mutedColor(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: _mutedColor(context).withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateBadge(_HolidayRecord holiday, Color accent) {
    final dark = _isDark(context);
    return Container(
      width: 70,
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.22 : 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _dateBadgeMonth(holiday),
            style: TextStyle(
              color: accent,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _dateBadgeDay(holiday),
                maxLines: 1,
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaPill(
    String label,
    IconData icon,
    Color color, {
    bool subtle = false,
  }) {
    final dark = _isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: subtle
            ? AppTheme.dashMutedSurfaceOf(context)
            : color.withValues(alpha: dark ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: subtle
              ? AppTheme.dashHairlineOf(context)
              : color.withValues(alpha: dark ? 0.3 : 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: subtle ? _mutedColor(context) : color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: subtle ? _mutedColor(context) : color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              'Loading holidays...',
              style: TextStyle(color: _mutedColor(context), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters =
        _searchController.text.trim().isNotEmpty || _typeFilter != 'all';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: AppTheme.primaryNavy,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              hasFilters ? 'No matching holidays' : 'No holidays yet',
              style: TextStyle(
                color: _headingColor(context),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters
                  ? 'Try a different search or filter.'
                  : 'Import PH defaults or add the first holiday manually.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedColor(context), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationFooter({
    required int total,
    required int page,
    required int pageCount,
    required int pageStart,
    required int pageEnd,
  }) {
    final summary = total == 0
        ? 'No results'
        : 'Showing ${pageStart + 1}-$pageEnd of $total';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: TextStyle(fontSize: 12, color: _mutedColor(context)),
            ),
          ),
          Text(
            'Page ${page + 1} of $pageCount',
            style: TextStyle(fontSize: 12, color: _mutedColor(context)),
          ),
          if (pageCount > 1) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: page > 0
                  ? () => setState(() => _page = page - 1)
                  : null,
              child: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: page < pageCount - 1
                  ? () => setState(() => _page = page + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormPanel({bool framed = true, bool showActions = true}) {
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
                    style: TextStyle(fontSize: 11, color: _mutedColor(context)),
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
                    style: TextStyle(fontSize: 11, color: _mutedColor(context)),
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
                        _dateTo != null ? _dateToYyyyMmDd(_dateTo!) : 'Select',
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
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: content,
    );
  }
}
