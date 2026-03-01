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

/// Tardiness Report: employee list, DTR table, and summary card.
/// Matches reference design: search, month/year filters, two-column layout.
class DtrReports extends StatefulWidget {
  const DtrReports({super.key});

  @override
  State<DtrReports> createState() => _DtrReportsState();
}

class _DtrReportsState extends State<DtrReports> {
  final _searchController = TextEditingController();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedEmployeeId;
  List<TimeRecord> _employeeRecords = [];

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
    if (dtr.employees.isNotEmpty) {
      if (_selectedEmployeeId == null ||
          !dtr.employees.any((e) => e.id == _selectedEmployeeId)) {
        setState(() => _selectedEmployeeId = dtr.employees.first.id);
      }
      _loadEmployeeRecords();
    }
  }

  Future<void> _loadEmployeeRecords() async {
    if (_selectedEmployeeId == null) return;
    final start = DateTime(_selectedYear, _selectedMonth, 1);
    final end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final dtr = context.read<DtrProvider>();
    await dtr.loadTimeRecordsForAdmin(
      startDate: start,
      endDate: end,
      userId: _selectedEmployeeId,
    );
    setState(() => _employeeRecords = dtr.timeRecords);
  }

  void _reset() {
    setState(() {
      _searchController.clear();
      _selectedMonth = DateTime.now().month;
      _selectedYear = DateTime.now().year;
    });
    _loadEmployeeRecords();
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _getRemarks(TimeRecord r) {
    if (r.status != null && r.status!.isNotEmpty) {
      switch (r.status!) {
        case 'late':
          return 'Late';
        case 'absent':
          return 'Absent';
        case 'on_leave':
          return 'On Leave';
        default:
          return 'On Time';
      }
    }
    if (r.timeIn == null) return 'Absent';
    final local = r.timeIn!.toLocal();
    final officeStart = DateTime(
      r.recordDate.year,
      r.recordDate.month,
      r.recordDate.day,
      8,
      0,
    );
    if (local.isAfter(officeStart)) return 'Late';
    return 'On Time';
  }

  static int _countWorkingDays(int year, int month) {
    int count = 0;
    final end = DateTime(year, month + 1, 0);
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      if (dt.weekday >= DateTime.monday && dt.weekday <= DateTime.friday)
        count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final search = _searchController.text.toLowerCase();
    final employees = search.isEmpty
        ? dtr.employees
        : dtr.employees
              .where((e) => e.fullName.toLowerCase().contains(search))
              .toList();
    final selectedList = employees
        .where((e) => e.id == _selectedEmployeeId)
        .toList();
    final selectedEmp = selectedList.isNotEmpty ? selectedList.first : null;
    String selectedName = selectedEmp?.fullName ?? 'Select an employee';
    if (selectedName == 'Select an employee' && _selectedEmployeeId != null) {
      final byId = dtr.employees
          .where((e) => e.id == _selectedEmployeeId)
          .toList();
      if (byId.isNotEmpty) selectedName = byId.first.fullName;
    }

    final end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final recordsByDate = <DateTime, TimeRecord>{};
    for (final r in _employeeRecords) {
      final key = DateTime(
        r.recordDate.year,
        r.recordDate.month,
        r.recordDate.day,
      );
      recordsByDate[key] = r;
    }

    final workingDays = _countWorkingDays(_selectedYear, _selectedMonth);
    var lateCount = 0;
    var absentCount = 0;
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(_selectedYear, _selectedMonth, d);
      if (dt.weekday >= DateTime.monday && dt.weekday <= DateTime.friday) {
        final rec = recordsByDate[dt];
        if (rec == null || rec.timeIn == null) {
          absentCount++;
        } else {
          final local = rec.timeIn!.toLocal();
          final officeStart = DateTime(dt.year, dt.month, dt.day, 8, 0);
          if (local.isAfter(officeStart)) lateCount++;
        }
      }
    }
    final tardyCount = lateCount + absentCount;
    final tardinessPct = workingDays > 0
        ? ((tardyCount / workingDays) * 100).round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tardiness Report',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
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
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _selectedMonth,
              items: List.generate(12, (i) => i + 1)
                  .map(
                    (m) =>
                        DropdownMenuItem(value: m, child: Text(_months[m - 1])),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedMonth = v);
                _loadEmployeeRecords();
              },
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _selectedYear,
              items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedYear = v);
                _loadEmployeeRecords();
              },
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFE8F5E9),
                foregroundColor: const Color(0xFF2E7D32),
              ),
              child: const Text('RESET'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 520,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Employee list
              Container(
                width: 220,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
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
                            width: 40,
                            child: Text(
                              'ID',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Employee Name',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (context, i) {
                          final e = employees[i];
                          final isSelected = e.id == _selectedEmployeeId;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedEmployeeId = e.id;
                              });
                              _loadEmployeeRecords();
                            },
                            child: Container(
                              color: isSelected
                                  ? AppTheme.primaryNavy.withOpacity(0.12)
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      e.fullName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Right: DTR table + summary card
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
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
                                    width: 90,
                                    child: Text(
                                      'Date',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      'AM IN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      'AM OUT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      'PM IN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      'PM OUT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Remarks',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: dtr.loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : ListView.builder(
                                      itemCount: end.day,
                                      itemBuilder: (context, i) {
                                        final d = end.day - i;
                                        final dt = DateTime(
                                          _selectedYear,
                                          _selectedMonth,
                                          d,
                                        );
                                        final rec = recordsByDate[dt];
                                        final isWeekend =
                                            dt.weekday == DateTime.saturday ||
                                            dt.weekday == DateTime.sunday;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: i % 2 == 0
                                                ? AppTheme.white
                                                : AppTheme.lightGray
                                                      .withOpacity(0.3),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 90,
                                                child: Text(
                                                  _formatDate(dt),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 70,
                                                child: Text(
                                                  rec?.timeIn != null
                                                      ? _formatTime(rec!.timeIn)
                                                      : '—',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 70,
                                                child: Text(
                                                  '—',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppTheme.textSecondary,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 70,
                                                child: Text(
                                                  '—',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppTheme.textSecondary,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 70,
                                                child: Text(
                                                  rec?.timeOut != null
                                                      ? _formatTime(
                                                          rec!.timeOut,
                                                        )
                                                      : '—',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  rec != null
                                                      ? _getRemarks(rec)
                                                      : (isWeekend
                                                            ? '—'
                                                            : 'Absent'),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: rec?.status == 'late'
                                                        ? Colors.red.shade700
                                                        : AppTheme.textPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Summary card
                    Container(
                      width: 200,
                      constraints: const BoxConstraints(maxHeight: 500),
                      decoration: BoxDecoration(
                        color: AppTheme.lightGray.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: AppTheme.primaryNavy.withOpacity(
                                0.2,
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                size: 32,
                                color: AppTheme.primaryNavy,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              selectedName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_months[_selectedMonth - 1]}, $_selectedYear',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            _SummaryStat(
                              label: 'Working Days',
                              value: '$workingDays',
                            ),
                            const SizedBox(height: 12),
                            _SummaryStat(
                              label: 'Late',
                              value: '$lateCount',
                              hasBorder: true,
                              borderColor: Colors.red,
                            ),
                            const SizedBox(height: 12),
                            _SummaryStat(
                              label: 'Absent',
                              value: '$absentCount',
                              hasBorder: true,
                              borderColor: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            _SummaryStat(
                              label: 'Tardy',
                              value: '$tardyCount',
                              hasBorder: true,
                              borderColor: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '$tardinessPct% TARDINESS',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Generate DTR coming soon.',
                                      ),
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: AppTheme.white,
                                ),
                                child: const Text('Generate DTR'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    this.hasBorder = false,
    this.borderColor = Colors.grey,
  });

  final String label;
  final String value;
  final bool hasBorder;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(8),
        border: hasBorder ? Border.all(color: borderColor, width: 1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
