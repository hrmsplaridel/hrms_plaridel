import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

/// ISO weekday: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
const List<int> _allDays = [1, 2, 3, 4, 5, 6, 7];
const List<String> _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
  });
  final String id;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isActive;
  final int gracePeriodMinutes;
  final List<int> workingDays;
  final int? shiftNumber;

  /// Display as SHF-001, SHF-002, etc., or "—" if null.
  String get displayShiftNo => shiftNumber != null
      ? 'SHF-${shiftNumber!.toString().padLeft(3, '0')}'
      : '—';

  String get workingDaysDisplay {
    if (workingDays.isEmpty) return '—';
    return workingDays.map((d) => _dayLabels[d - 1]).join(', ');
  }
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
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  Set<int> _workingDays = {1, 2, 3, 4, 5}; // Mon–Fri default

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
      _workingDays = {1, 2, 3, 4, 5};
    });
  }

  void _toggleWorkingDay(int day) {
    setState(() {
      if (_workingDays.contains(day)) {
        _workingDays = {..._workingDays}..remove(day);
      } else {
        _workingDays = {..._workingDays, day};
      }
    });
  }

  Future<void> _addShift() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a shift name.')),
      );
      return;
    }
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Start Time and End Time.')),
      );
      return;
    }
    if (_workingDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one working day.')),
      );
      return;
    }
    try {
      final body = <String, dynamic>{
        'name': name,
        'start_time': _timeStr(_startTime!),
        'end_time': _timeStr(_endTime!),
        'is_active': true,
        'grace_period_minutes': int.tryParse(_graceController.text.trim()) ?? 0,
        'working_days': _workingDays.toList()..sort(),
      };
      await ApiClient.instance.post('/api/shifts', data: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift added.')));
        _clearForm();
        _loadShifts();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add: ${e.response?.data ?? e.message}')),
        );
      }
    }
  }

  Future<void> _updateShift() async {
    final s = _selectedShift;
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a shift to update.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a shift name.')),
      );
      return;
    }
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set Start Time and End Time.')),
      );
      return;
    }
    if (_workingDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one working day.')),
      );
      return;
    }
    try {
      final body = <String, dynamic>{
        'name': name,
        'start_time': _timeStr(_startTime!),
        'end_time': _timeStr(_endTime!),
        'grace_period_minutes': int.tryParse(_graceController.text.trim()) ?? 0,
        'working_days': _workingDays.toList()..sort(),
      };
      await ApiClient.instance.put('/api/shifts/${s.id}', data: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift updated.')));
        _clearForm();
        _loadShifts();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: ${e.response?.data ?? e.message}')),
        );
      }
    }
  }

  Future<void> _deactivateShift() async {
    final s = _selectedShift;
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a shift to deactivate.')),
      );
      return;
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
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.put('/api/shifts/${s.id}', data: {'is_active': false});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.name} has been deactivated.')),
        );
        _clearForm();
        _loadShifts();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deactivate: ${e.response?.data ?? e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shift',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        isNarrow ? _buildNarrowLayout() : _buildWideLayout(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1, child: _buildLeftPanel()),
        const SizedBox(width: 24),
        Expanded(flex: 1, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLeftPanel(),
        const SizedBox(height: 24),
        _buildRightPanel(),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final search = _searchController.text.toLowerCase();
    final filtered = search.isEmpty
        ? _shifts
        : _shifts.where((s) => s.name.toLowerCase().contains(search)).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
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
              color: AppTheme.lightGray.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    'ID',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Shift',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Start',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'End',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Working Days',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
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
                style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 14),
              ),
            )
          else
            ...filtered.map((s) {
              final isSelected = _selectedShift?.id == s.id;
              return Material(
                color: isSelected ? AppTheme.primaryNavy.withOpacity(0.08) : Colors.transparent,
                child: InkWell(
                  onTap: () => _selectShift(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: Text(
                            s.displayShiftNo,
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            s.name,
                            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            _timeStr(s.startTime, includeSeconds: false),
                            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            _timeStr(s.endTime, includeSeconds: false),
                            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            s.workingDaysDisplay,
                            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
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
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary.withOpacity(0.7)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: AppTheme.lightGray.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String>(
        value: _statusFilter,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['Active', 'Inactive', 'All']
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          setState(() => _statusFilter = v ?? 'Active');
          _loadShifts();
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Shift Name',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: _inputDecoration('Shift Name'),
          ),
          const SizedBox(height: 20),
          Text(
            'Start Time',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          _buildTimePicker(_startTime, (t) => setState(() => _startTime = t)),
          const SizedBox(height: 20),
          Text(
            'End Time',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          _buildTimePicker(_endTime, (t) => setState(() => _endTime = t)),
          const SizedBox(height: 20),
          Text(
            'Grace Period (minutes)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _graceController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('0'),
          ),
          const SizedBox(height: 20),
          Text(
            'Working Days',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allDays.map((day) {
              final isOn = _workingDays.contains(day);
              return FilterChip(
                selected: isOn,
                label: Text(_dayLabels[day - 1]),
                onSelected: (_) => _toggleWorkingDay(day),
                selectedColor: AppTheme.primaryNavy.withOpacity(0.2),
                checkmarkColor: AppTheme.primaryNavy,
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _addShift,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Shift'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
              FilledButton.icon(
                onPressed: _selectedShift != null ? _updateShift : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
              FilledButton.icon(
                onPressed: _selectedShift != null ? _deactivateShift : null,
                icon: const Icon(Icons.person_off_rounded, size: 18),
                label: const Text('Deactivate'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(TimeOfDay? value, ValueChanged<TimeOfDay> onChanged) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 8, minute: 0),
        );
        if (t != null) onChanged(t);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: _inputDecoration('HH:MM').copyWith(
          suffixIcon: Icon(Icons.access_time_rounded, size: 20, color: AppTheme.textSecondary),
        ),
        child: Text(
          value != null ? _timeStr(value, includeSeconds: false) : '',
          style: TextStyle(
            fontSize: 14,
            color: value != null ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.7), fontSize: 14),
        filled: true,
        fillColor: AppTheme.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.lightGray)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.lightGray)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5)),
      );
}
