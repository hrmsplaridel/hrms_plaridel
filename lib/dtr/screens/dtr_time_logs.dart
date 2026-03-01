import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../data/time_record.dart';
import '../dtr_provider.dart';

const List<String> _months = [
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

/// Hardcoded sample records for UI overview when no data exists.
List<TimeRecord> _hardcodedSampleRecords() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, 1);
  return [
    TimeRecord(
      userId: 'demo',
      recordDate: base,
      timeIn: DateTime(base.year, base.month, 1, 8, 5),
      timeOut: DateTime(base.year, base.month, 1, 17, 30),
      totalHours: 8.4,
      status: 'late',
      employeeName: 'Juan Dela Cruz',
    ),
    TimeRecord(
      userId: 'demo',
      recordDate: base.add(const Duration(days: 1)),
      timeIn: DateTime(base.year, base.month, 2, 7, 55),
      timeOut: DateTime(base.year, base.month, 2, 17, 10),
      totalHours: 8.3,
      status: 'present',
      employeeName: 'Juan Dela Cruz',
    ),
    TimeRecord(
      userId: 'demo',
      recordDate: base.add(const Duration(days: 2)),
      timeIn: DateTime(base.year, base.month, 3, 8, 20),
      timeOut: DateTime(base.year, base.month, 3, 17, 45),
      totalHours: 8.4,
      status: 'late',
      employeeName: 'Maria Santos',
    ),
    TimeRecord(
      userId: 'demo',
      recordDate: base.add(const Duration(days: 3)),
      timeIn: DateTime(base.year, base.month, 4, 7, 58),
      timeOut: DateTime(base.year, base.month, 4, 16, 55),
      totalHours: 8.0,
      status: 'present',
      employeeName: 'Carlos Reyes',
    ),
    TimeRecord(
      userId: 'demo',
      recordDate: base.add(const Duration(days: 4)),
      timeIn: null,
      timeOut: null,
      totalHours: null,
      status: 'absent',
      employeeName: 'Ana Garcia',
    ),
    TimeRecord(
      userId: 'demo',
      recordDate: base.add(const Duration(days: 7)),
      timeIn: DateTime(base.year, base.month, 8, 8, 0),
      timeOut: DateTime(base.year, base.month, 8, 17, 15),
      totalHours: 8.3,
      status: 'present',
      employeeName: 'Pedro Cruz',
    ),
  ];
}

/// Admin Time Logs: list, filters, add/edit/delete.
class DtrTimeLogs extends StatefulWidget {
  const DtrTimeLogs({super.key});

  @override
  State<DtrTimeLogs> createState() => _DtrTimeLogsState();
}

class _DtrTimeLogsState extends State<DtrTimeLogs> {
  final _searchController = TextEditingController();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedUserId;
  bool _showHardcodedPreview = true;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dtr = context.read<DtrProvider>();
    await dtr.loadEmployees();
    await _applyFilters();
  }

  Future<void> _applyFilters() async {
    final dtr = context.read<DtrProvider>();
    final start = DateTime(_selectedYear, _selectedMonth, 1);
    final end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    await dtr.loadTimeRecordsForAdmin(
      startDate: start,
      endDate: end,
      userId: _selectedUserId?.isEmpty == true ? null : _selectedUserId,
    );
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  List<TimeRecord> _getDisplayRecords(DtrProvider dtr) {
    if (dtr.loading) return [];
    if (dtr.timeRecords.isNotEmpty) return dtr.timeRecords;
    if (_showHardcodedPreview) return _hardcodedSampleRecords();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final search = _searchController.text.toLowerCase();
    final displayRecords = _getDisplayRecords(dtr).where((r) {
      if (search.isEmpty) return true;
      return (r.employeeName ?? '').toLowerCase().contains(search);
    }).toList();
    final isHardcodedPreview =
        dtr.timeRecords.isEmpty && displayRecords.isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Time Logs',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage and correct daily time-in/out records. Add, edit, or delete entries.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          if (dtr.tableMissing && !_bannerDismissed) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing sample data. Create time_records in Supabase (Query 8, docs/SUPABASE_AUTH_SETUP.md) to enable live data.',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    onPressed: () => setState(() => _bannerDismissed = true),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (dtr.error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dtr.error!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              return Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: isNarrow ? 280 : 220,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search name...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: AppTheme.white,
                      ),
                    ),
                  ),
                  DropdownButton<int>(
                    value: _selectedMonth,
                    items: List.generate(12, (i) => i + 1)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(_months[m - 1]),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedMonth = v);
                      _applyFilters();
                    },
                  ),
                  DropdownButton<int>(
                    value: _selectedYear,
                    items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedYear = v);
                      _applyFilters();
                    },
                  ),
                  DropdownButton<String?>(
                    value: _selectedUserId,
                    hint: const Text('All employees'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All employees'),
                      ),
                      ...dtr.employees.map(
                        (e) => DropdownMenuItem<String?>(
                          value: e.id,
                          child: Text(e.fullName),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedUserId = v);
                      _applyFilters();
                    },
                  ),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _selectedMonth = DateTime.now().month;
                        _selectedYear = DateTime.now().year;
                        _selectedUserId = null;
                      });
                      _applyFilters();
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8F5E9),
                      foregroundColor: const Color(0xFF2E7D32),
                    ),
                    child: const Text('RESET'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showAddDialog(context, dtr),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add manual entry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          if (isHardcodedPreview && !dtr.tableMissing) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryNavy.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing sample data for UI overview. Add real records or adjust filters to see live data.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (dtr.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (!dtr.loading && displayRecords.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 56,
                      color: AppTheme.textSecondary.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No time records match your filters.',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a manual entry or try a different date range.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _showAddDialog(context, dtr),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add manual entry'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: AppTheme.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!dtr.loading && displayRecords.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SizedBox(
                height: (displayRecords.length + 1) * 52.0 + 8,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.lightGray.withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                'Employee',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(
                                'Date',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 75,
                              child: Text(
                                'Time In',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 75,
                              child: Text(
                                'Time Out',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                'Hours',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Status',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (!isHardcodedPreview)
                              SizedBox(
                                width: 80,
                                child: Text(
                                  'Actions',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ...displayRecords.asMap().entries.map((entry) {
                        final i = entry.key;
                        final r = entry.value;
                        final timeIn = r.timeIn?.toLocal();
                        final timeOut = r.timeOut?.toLocal();
                        final hours = r.totalHours != null
                            ? '${r.totalHours!.toStringAsFixed(1)} h'
                            : '—';
                        final statusText = r.status == 'late'
                            ? 'Late'
                            : r.status == 'absent'
                            ? 'Absent'
                            : r.status == 'on_leave'
                            ? 'On Leave'
                            : 'On Time';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: i % 2 == 0
                                ? AppTheme.white
                                : AppTheme.lightGray.withOpacity(0.25),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  r.employeeName ?? r.userId,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  _formatDate(r.recordDate),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 75,
                                child: Text(
                                  _formatTime(timeIn),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 75,
                                child: Text(
                                  _formatTime(timeOut),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  hours,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: r.status == 'late'
                                        ? Colors.red.shade700
                                        : (r.status == 'absent'
                                              ? Colors.orange.shade700
                                              : AppTheme.textPrimary),
                                    fontWeight:
                                        r.status == 'late' ||
                                            r.status == 'absent'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (!isHardcodedPreview)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showEditDialog(context, dtr, r),
                                      tooltip: 'Edit',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_rounded,
                                        size: 20,
                                        color: Colors.red.shade700,
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(context, dtr, r),
                                      tooltip: 'Delete',
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, DtrProvider dtr) async {
    final employees = dtr.employees;
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No employees found. Add profiles first.'),
        ),
      );
      return;
    }
    String? userId = employees.first.id;
    DateTime recordDate = DateTime.now();
    TimeOfDay? timeIn;
    TimeOfDay? timeOut;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add time entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: userId,
                  decoration: const InputDecoration(labelText: 'Employee'),
                  items: employees
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(e.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => userId = v),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(_formatDate(recordDate)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: recordDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => recordDate = d);
                  },
                ),
                ListTile(
                  title: const Text('Time In'),
                  subtitle: Text(
                    timeIn != null
                        ? '${timeIn!.hour.toString().padLeft(2, '0')}:${timeIn!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: timeIn ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => timeIn = t);
                  },
                ),
                ListTile(
                  title: const Text('Time Out'),
                  subtitle: Text(
                    timeOut != null
                        ? '${timeOut!.hour.toString().padLeft(2, '0')}:${timeOut!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: timeOut ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => timeOut = t);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    final uid = userId;
    if (updated == true && uid != null && uid.isNotEmpty) {
      final date = DateTime(recordDate.year, recordDate.month, recordDate.day);
      DateTime? tin;
      DateTime? tout;
      if (timeIn != null) {
        tin = DateTime(
          date.year,
          date.month,
          date.day,
          timeIn!.hour,
          timeIn!.minute,
        );
      }
      if (timeOut != null) {
        tout = DateTime(
          date.year,
          date.month,
          date.day,
          timeOut!.hour,
          timeOut!.minute,
        );
      }
      double? hours;
      if (tin != null && tout != null) {
        hours = tout.difference(tin).inMinutes / 60.0;
      }
      final record = TimeRecord(
        userId: uid,
        recordDate: date,
        timeIn: tin,
        timeOut: tout,
        totalHours: hours,
        status: 'present',
      );
      await dtr.addManualEntry(record);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Time entry added.')));
      }
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    DtrProvider dtr,
    TimeRecord r,
  ) async {
    final timeInLocal = r.timeIn?.toLocal();
    final timeOutLocal = r.timeOut?.toLocal();
    TimeOfDay? timeIn = timeInLocal != null
        ? TimeOfDay(hour: timeInLocal.hour, minute: timeInLocal.minute)
        : null;
    TimeOfDay? timeOut = timeOutLocal != null
        ? TimeOfDay(hour: timeOutLocal.hour, minute: timeOutLocal.minute)
        : null;
    DateTime recordDate = r.recordDate;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Edit time entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Employee: ${r.employeeName ?? r.userId}'),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(_formatDate(recordDate)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: recordDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => recordDate = d);
                  },
                ),
                ListTile(
                  title: const Text('Time In'),
                  subtitle: Text(
                    timeIn != null
                        ? '${timeIn!.hour.toString().padLeft(2, '0')}:${timeIn!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: timeIn ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => timeIn = t);
                  },
                ),
                ListTile(
                  title: const Text('Time Out'),
                  subtitle: Text(
                    timeOut != null
                        ? '${timeOut!.hour.toString().padLeft(2, '0')}:${timeOut!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: timeOut ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => timeOut = t);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (updated == true && r.id != null) {
      final date = DateTime(recordDate.year, recordDate.month, recordDate.day);
      DateTime? tin;
      DateTime? tout;
      if (timeIn != null) {
        tin = DateTime(
          date.year,
          date.month,
          date.day,
          timeIn!.hour,
          timeIn!.minute,
        );
      }
      if (timeOut != null) {
        tout = DateTime(
          date.year,
          date.month,
          date.day,
          timeOut!.hour,
          timeOut!.minute,
        );
      }
      double? hours;
      if (tin != null && tout != null) {
        hours = tout.difference(tin).inMinutes / 60.0;
      }
      final updatedRec = r.copyWith(
        recordDate: date,
        timeIn: tin,
        timeOut: tout,
        totalHours: hours,
      );
      await dtr.updateEntry(updatedRec);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Time entry updated.')));
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DtrProvider dtr,
    TimeRecord r,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete time entry?'),
        content: Text(
          'Delete record for ${r.employeeName ?? r.userId} on ${_formatDate(r.recordDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && r.id != null) {
      await dtr.deleteEntry(r.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Time entry deleted.')));
      }
    }
  }
}
