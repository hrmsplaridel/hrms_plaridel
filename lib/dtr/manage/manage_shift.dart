import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

/// ISO weekday: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
const List<int> _allDays = [1, 2, 3, 4, 5, 6, 7];
const List<String> _dayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _punchModes = [
  'auto',
  'full_day',
  'am_only',
  'pm_only',
  'single_session',
];
const Map<String, String> _punchModeLabels = {
  'auto': 'Auto',
  'full_day': 'Full day with break',
  'am_only': 'AM only',
  'pm_only': 'PM only',
  'single_session': 'Single session',
};

/// Shift record for display/CRUD.
class _ShiftRecord {
  const _ShiftRecord({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.isActive,
    this.gracePeriodMinutes = 0,
    this.workingDays = const [1, 2, 3, 4, 5],
    this.shiftNumber,
    this.breakEndTime,
    this.punchMode = 'auto',
  });
  final String id;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final TimeOfDay? breakEndTime;
  final bool isActive;
  final int gracePeriodMinutes;
  final List<int> workingDays;
  final int? shiftNumber;
  final String punchMode;

  /// Display as SHF-001, SHF-002, etc., or "—" if null.
  String get displayShiftNo => shiftNumber != null
      ? 'SHF-${shiftNumber!.toString().padLeft(3, '0')}'
      : '—';

  String get workingDaysDisplay {
    if (workingDays.isEmpty) return '—';
    return workingDays.map((d) => _dayLabels[d - 1]).join(', ');
  }

  String get punchModeDisplay => _punchModeLabels[punchMode] ?? 'Auto';
}

/// Shift management screen: list with search/status filter + form.
class ManageShift extends StatefulWidget {
  const ManageShift({super.key});

  @override
  State<ManageShift> createState() => _ManageShiftState();
}

class _ManageShiftState extends State<ManageShift> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _graceController = TextEditingController();

  String _statusFilter = 'Active';
  List<_ShiftRecord> _shifts = [];
  bool _loading = false;
  _ShiftRecord? _selectedShift;
  StateSetter? _drawerSetState;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  TimeOfDay?
  _breakEndTime; // PM resume time (e.g. 13:00 for 1PM) – used for PM late check
  Set<int> _workingDays = {1, 2, 3, 4, 5}; // Mon–Fri default
  String _punchMode = 'auto';

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  BoxDecoration _filterDecoration(BuildContext context) => BoxDecoration(
        color: _isDark(context)
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDark(context)
              ? AppTheme.dashHairlineOf(context)
              : Colors.transparent,
        ),
      );

  void _updateShiftFormState(VoidCallback update) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadShifts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _graceController.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length >= 5) {
      final parts = s.substring(0, 5).split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
      }
    }
    return null;
  }

  String _timeStr(TimeOfDay t, {bool includeSeconds = true}) {
    if (includeSeconds) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
    }
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _parsePunchMode(dynamic value) {
    final mode = value?.toString().trim().toLowerCase();
    return _punchModes.contains(mode) ? mode! : 'auto';
  }

  Future<void> _loadShifts() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/shifts',
        queryParameters: {'status': _statusFilter},
      );
      final data = res.data ?? [];
      _shifts = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final st = m['start_time'];
        final et = m['end_time'];
        final be = m['break_end'];
        final grace = m['grace_period_minutes'];
        final wd = m['working_days'];
        final shiftNum = m['shift_number'];
        List<int> days = [1, 2, 3, 4, 5];
        if (wd is List) {
          final parsed = wd
              .map((d) {
                if (d is int) return d;
                final n = int.tryParse(d?.toString() ?? '');
                return (n != null && n >= 1 && n <= 7) ? n : null;
              })
              .whereType<int>()
              .toList();
          if (parsed.isNotEmpty) {
            days = parsed..sort();
          }
        }
        return _ShiftRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          startTime: _parseTime(st) ?? const TimeOfDay(hour: 0, minute: 0),
          endTime: _parseTime(et) ?? const TimeOfDay(hour: 0, minute: 0),
          breakEndTime: _parseTime(be),
          punchMode: _parsePunchMode(m['punch_mode']),
          isActive: m['is_active'] as bool? ?? true,
          gracePeriodMinutes: grace is int
              ? grace
              : (grace != null ? int.tryParse(grace.toString()) ?? 0 : 0),
          workingDays: days,
          shiftNumber: shiftNum is int
              ? shiftNum
              : (shiftNum != null ? int.tryParse(shiftNum.toString()) : null),
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load shifts failed: ${e.response?.data ?? e.message}');
      _shifts = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectShift(_ShiftRecord s) {
    setState(() {
      _selectedShift = s;
      _nameController.text = s.name;
      _graceController.text = s.gracePeriodMinutes > 0
          ? s.gracePeriodMinutes.toString()
          : '';
      _startTime = s.startTime;
      _endTime = s.endTime;
      _punchMode = s.punchMode;
      _breakEndTime = _punchMode == 'single_session' ? null : s.breakEndTime;
      _workingDays = s.workingDays.toSet();
    });
  }

  void _clearForm() {
    setState(() {
      _selectedShift = null;
      _nameController.clear();
      _graceController.clear();
      _startTime = null;
      _endTime = null;
      _breakEndTime = null;
      _workingDays = {1, 2, 3, 4, 5};
      _punchMode = 'auto';
    });
  }

  void _toggleWorkingDay(int day) {
    _updateShiftFormState(() {
      if (_workingDays.contains(day)) {
        _workingDays = {..._workingDays}..remove(day);
      } else {
        _workingDays = {..._workingDays, day};
      }
    });
  }

  Future<bool> _addShift() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a shift name.')),
      );
      return false;
    }
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Start Time and End Time.')),
      );
      return false;
    }
    if (_workingDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one working day.')),
      );
      return false;
    }
    try {
      final body = <String, dynamic>{
        'name': name,
        'start_time': _timeStr(_startTime!),
        'end_time': _timeStr(_endTime!),
        'punch_mode': _punchMode,
        if (_breakEndTime != null && _punchMode != 'single_session')
          'break_end': _timeStr(_breakEndTime!),
        'is_active': true,
        'grace_period_minutes': int.tryParse(_graceController.text.trim()) ?? 0,
        'working_days': _workingDays.toList()..sort(),
      };
      await ApiClient.instance.post('/api/shifts', data: body);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Shift added.')));
        _clearForm();
        _loadShifts();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add: ${e.response?.data ?? e.message}'),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _updateShift() async {
    final s = _selectedShift;
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a shift to update.')),
      );
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a shift name.')),
      );
      return false;
    }
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Start Time and End Time.')),
      );
      return false;
    }
    if (_workingDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one working day.')),
      );
      return false;
    }
    try {
      final body = <String, dynamic>{
        'name': name,
        'start_time': _timeStr(_startTime!),
        'end_time': _timeStr(_endTime!),
        'punch_mode': _punchMode,
        'break_end': _breakEndTime != null && _punchMode != 'single_session'
            ? _timeStr(_breakEndTime!)
            : null,
        'grace_period_minutes': int.tryParse(_graceController.text.trim()) ?? 0,
        'working_days': _workingDays.toList()..sort(),
      };
      await ApiClient.instance.put('/api/shifts/${s.id}', data: body);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Shift updated.')));
        _clearForm();
        _loadShifts();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: ${e.response?.data ?? e.message}'),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _deactivateShift() async {
    final s = _selectedShift;
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a shift to deactivate.')),
      );
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate shift?'),
        content: Text(
          'This will deactivate "${s.name}". It will no longer appear in active lists.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    try {
      await ApiClient.instance.put(
        '/api/shifts/${s.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.name} has been deactivated.')),
        );
        _clearForm();
        _loadShifts();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to deactivate: ${e.response?.data ?? e.message}',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _openShiftDrawer({_ShiftRecord? shift}) async {
    _drawerSetState = null;
    if (shift == null) {
      _clearForm();
    } else {
      _selectShift(shift);
    }

    try {
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
                    return _buildShiftDrawer(dialogContext);
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

  Widget _buildShiftDrawer(BuildContext drawerContext) {
    final isEditing = _selectedShift != null;
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
                    isEditing ? 'Edit Shift' : 'Add Shift',
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
    final isEditing = _selectedShift != null;
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
                final ok = await _deactivateShift();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = isEditing ? await _updateShift() : await _addShift();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Shift'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Shift',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openShiftDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Shift'),
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
        _buildLeftPanel(),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final dark = _isDark(context);
    final search = _searchController.text.toLowerCase();
    const shiftNoColumnWidth = 76.0;
    final filtered = search.isEmpty
        ? _shifts
        : _shifts.where((s) => s.name.toLowerCase().contains(search)).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 180, child: _buildSearchField()),
              _buildStatusDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: shiftNoColumnWidth,
                  child: Text(
                    'ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Shift',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Start',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'End',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Working Days',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              child: Text(
                'No shifts',
                style: TextStyle(
                  color: _mutedColor(context).withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ...filtered.map((s) {
              final isSelected = _selectedShift?.id == s.id;
              return Material(
                color: isSelected
                    ? (dark
                        ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                        : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _openShiftDrawer(shift: s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: shiftNoColumnWidth,
                          child: Text(
                            s.displayShiftNo,
                            style: TextStyle(
                              fontSize: 12,
                              color: _mutedColor(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _headingColor(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                s.punchModeDisplay,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _mutedColor(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            s.startTime.format(context),
                            style: TextStyle(
                              fontSize: 13,
                              color: _headingColor(context),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            s.endTime.format(context),
                            style: TextStyle(
                              fontSize: 13,
                              color: _headingColor(context),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            s.workingDaysDisplay,
                            style: TextStyle(
                              fontSize: 13,
                              color: _headingColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search',
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
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String>(
        value: _statusFilter,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['Active', 'Inactive', 'All']
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: (v) {
          setState(() => _statusFilter = v ?? 'Active');
          _loadShifts();
        },
      ),
    );
  }

  Widget _buildPunchModeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _punchMode,
          dropdownColor: AppTheme.dashPanelOf(context),
          style: AppTheme.dashFieldTextStyle(context),
          isExpanded: true,
          items: _punchModes
              .map(
                (mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(
                    _punchModeLabels[mode] ?? mode,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
              )
              .toList(),
          onChanged: (mode) {
            _updateShiftFormState(() {
              _punchMode = mode ?? 'auto';
              if (_punchMode == 'single_session') {
                _breakEndTime = null;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildFormPanel({
    bool framed = true,
    bool showActions = true,
  }) {
    final dark = _isDark(context);
    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Shift Name',
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
            decoration: _inputDecoration('Shift Name'),
          ),
          const SizedBox(height: 20),
          Text(
            'Start Time',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          _buildTimePicker(
            _startTime,
            (t) => _updateShiftFormState(() => _startTime = t),
          ),
          const SizedBox(height: 20),
          Text(
            'End Time',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          _buildTimePicker(
            _endTime,
            (t) => _updateShiftFormState(() => _endTime = t),
          ),
          const SizedBox(height: 20),
          Text(
            'Attendance Mode',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose Single session for schedules like 10:00 AM to 2:00 PM.',
            style: TextStyle(
              fontSize: 11,
              color: _mutedColor(context).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          _buildPunchModeDropdown(),
          const SizedBox(height: 20),
          Text(
            'PM Start (Break End)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _punchMode == 'single_session'
                ? 'Not used for single-session shifts.'
                : 'When PM shift starts; used for PM late check. Leave empty if not needed.',
            style: TextStyle(
              fontSize: 11,
              color: _mutedColor(context).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          _buildTimePicker(
            _breakEndTime,
            (t) => _updateShiftFormState(() => _breakEndTime = t),
            allowClear: true,
            enabled: _punchMode != 'single_session',
          ),
          const SizedBox(height: 20),
          Text(
            'Grace Period (minutes)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _graceController,
            keyboardType: TextInputType.number,
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration('0'),
          ),
          const SizedBox(height: 20),
          Text(
            'Working Days',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allDays.map((day) {
              final isOn = _workingDays.contains(day);
              return FilterChip(
                selected: isOn,
                label: Text(
                  _dayLabels[day - 1],
                  style: TextStyle(
                    color: isOn
                        ? (dark
                            ? AppTheme.primaryNavyLight
                            : AppTheme.primaryNavy)
                        : _headingColor(context),
                  ),
                ),
                onSelected: (_) => _toggleWorkingDay(day),
                selectedColor: dark
                    ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                    : AppTheme.primaryNavy.withValues(alpha: 0.2),
                checkmarkColor:
                    dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
                backgroundColor: AppTheme.dashMutedSurfaceOf(context),
              );
            }).toList(),
          ),
          if (showActions) ...[
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _addShift(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Shift'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _selectedShift != null
                      ? () => _updateShift()
                      : null,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Update'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _selectedShift != null
                      ? () => _deactivateShift()
                      : null,
                  icon: const Icon(Icons.person_off_rounded, size: 18),
                  label: const Text('Deactivate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
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

  Widget _buildTimePicker(
    TimeOfDay? value,
    ValueChanged<TimeOfDay?> onChanged, {
    bool allowClear = false,
    bool enabled = true,
  }) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: enabled
                ? () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: value ?? const TimeOfDay(hour: 13, minute: 0),
                    );
                    if (t != null) onChanged(t);
                  }
                : null,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('HH:MM').copyWith(
                suffixIcon: Icon(
                  Icons.access_time_rounded,
                  size: 20,
                  color: _mutedColor(context),
                ),
              ),
              child: Text(
                value != null ? value.format(context) : '',
                style: TextStyle(
                  fontSize: 14,
                  color: !enabled
                      ? _mutedColor(context).withValues(alpha: 0.5)
                      : value != null
                      ? _headingColor(context)
                      : _mutedColor(context),
                ),
              ),
            ),
          ),
        ),
        if (allowClear && value != null && enabled)
          IconButton(
            icon: Icon(
              Icons.clear_rounded,
              size: 20,
              color: _mutedColor(context),
            ),
            onPressed: () => onChanged(null),
            tooltip: 'Clear',
          ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
        context,
        hintText: hint,
        radius: 8,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      );
}
