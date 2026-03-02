import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../data/time_record.dart';
import '../dtr_export.dart';
import '../dtr_provider.dart';
import '../dtr_share.dart';

enum _DtrExportFormat { pdf, word, excel }

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

  Future<void> _generateDtr(
    BuildContext context,
    _DtrExportFormat format, {
    required String selectedName,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) async {
    final baseName = 'DTR_${selectedName.replaceAll(' ', '_')}_${_months[_selectedMonth - 1]}_$_selectedYear';
    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating DTR...')),
      );
      switch (format) {
        case _DtrExportFormat.pdf:
          final bytes = await DtrExport.generatePdf(
            employeeName: selectedName,
            year: _selectedYear,
            month: _selectedMonth,
            end: end,
            recordsByDate: recordsByDate,
          );
          if (!context.mounted) return;
          await shareOrDownloadPdf(bytes, '$baseName.pdf');
          break;
        case _DtrExportFormat.excel:
          final bytes = await DtrExport.generateExcel(
            employeeName: selectedName,
            year: _selectedYear,
            month: _selectedMonth,
            end: end,
            recordsByDate: recordsByDate,
          );
          if (!context.mounted) return;
          await shareOrDownloadFile(bytes, '$baseName.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          break;
        case _DtrExportFormat.word:
          final html = DtrExport.generateWordHtml(
            employeeName: selectedName,
            year: _selectedYear,
            month: _selectedMonth,
            end: end,
            recordsByDate: recordsByDate,
          );
          final bytes = Uint8List.fromList(utf8.encode(html));
          if (!context.mounted) return;
          await shareOrDownloadFile(bytes, '$baseName.doc', 'application/msword');
          break;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DTR exported as ${format.name.toUpperCase()}')),
      );
    } catch (e, st) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
      debugPrint('DTR export error: $e\n$st');
    }
  }

  static int _countWorkingDays(int year, int month) {
    int count = 0;
    final end = DateTime(year, month + 1, 0);
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      if (dt.weekday >= DateTime.monday && dt.weekday <= DateTime.friday) {
        count++;
      }
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final isCompact = w < 900;
        // Use bounded height when parent gives unbounded (e.g. inside scroll view)
        final boundedH = h.isFinite && h > 0 ? h : 1200.0;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: boundedH, maxWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : 1200),
          child: SingleChildScrollView(
            child: Column(
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
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
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
                      _loadEmployeeRecords();
                    },
                  ),
                  DropdownButton<int>(
                    value: _selectedYear,
                    items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                        .map((y) => DropdownMenuItem(
                              value: y,
                              child: Text('$y'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedYear = v);
                      _loadEmployeeRecords();
                    },
                  ),
                  OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8F5E9),
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF81C784)),
                    ),
                    child: const Text('RESET'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              isCompact
                  ? _buildCompactLayout(
                      employees: employees,
                      end: end,
                      recordsByDate: recordsByDate,
                      selectedName: selectedName,
                      workingDays: workingDays,
                      lateCount: lateCount,
                      absentCount: absentCount,
                      tardyCount: tardyCount,
                      tardinessPct: tardinessPct,
                      dtr: dtr,
                    )
                  : SizedBox(
                      height: 520,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEmployeeList(employees),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildDtrTable(
                                    end: end,
                                    recordsByDate: recordsByDate,
                                    dtr: dtr,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _buildSummaryCard(
                                  selectedName: selectedName,
                                  workingDays: workingDays,
                                  lateCount: lateCount,
                                  absentCount: absentCount,
                                  tardyCount: tardyCount,
                                  tardinessPct: tardinessPct,
                                  recordsByDate: recordsByDate,
                                  end: end,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildEmployeeList(List<dynamic> employees) {
    return Container(
      width: 220,
      constraints: const BoxConstraints(maxWidth: 220),
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
                                  ? AppTheme.primaryNavy.withValues(alpha: 0.08)
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
    );
  }

  Widget _buildDtrTable({
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required DtrProvider dtr,
  }) {
    const tableWidth = 550.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
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
            mainAxisSize: MainAxisSize.min,
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
    );
  }

  Widget _buildSummaryCard({
    required String selectedName,
    required int workingDays,
    required int lateCount,
    required int absentCount,
    required int tardyCount,
    required int tardinessPct,
    bool fullWidth = false,
    required Map<DateTime, TimeRecord> recordsByDate,
    required DateTime end,
  }) {
    return Container(
      width: fullWidth ? null : 200,
      constraints: fullWidth
          ? const BoxConstraints(maxHeight: 500)
          : const BoxConstraints(maxWidth: 200, maxHeight: 500),
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
                              borderColor: lateCount > 0 ? Colors.red : const Color(0xFF4CAF50),
                            ),
                            const SizedBox(height: 12),
                            _SummaryStat(
                              label: 'Absent',
                              value: '$absentCount',
                              hasBorder: absentCount > 0,
                              borderColor: Colors.orange,
                            ),
                            const SizedBox(height: 12),
                            _SummaryStat(
                              label: 'Tardy',
                              value: '$tardyCount',
                              hasBorder: tardyCount > 0,
                              borderColor: Colors.orange,
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
                            const Text(
                              'Generate DTR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    builder: (ctx) => SafeArea(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            const Text(
                                              'Export DTR as',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            ListTile(
                                              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                              title: const Text('PDF'),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                _generateDtr(context, _DtrExportFormat.pdf,
                                                    selectedName: selectedName, end: end, recordsByDate: recordsByDate);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.description, color: Colors.blue),
                                              title: const Text('Word (.doc)'),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                _generateDtr(context, _DtrExportFormat.word,
                                                    selectedName: selectedName, end: end, recordsByDate: recordsByDate);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.table_chart, color: Colors.green),
                                              title: const Text('Excel (.xlsx)'),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                _generateDtr(context, _DtrExportFormat.excel,
                                                    selectedName: selectedName, end: end, recordsByDate: recordsByDate);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8F5E9),
                                  foregroundColor: const Color(0xFF2E7D32),
                                  side: const BorderSide(color: Color(0xFF81C784)),
                                ),
                                child: const Text('GENERATE'),
                              ),
                            ),
                          ],
                        ),
                      ),
    );
  }

  Widget _buildCompactLayout({
    required List<dynamic> employees,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required String selectedName,
    required int workingDays,
    required int lateCount,
    required int absentCount,
    required int tardyCount,
    required int tardinessPct,
    required DtrProvider dtr,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 200,
          child: _buildEmployeeListCompact(employees),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 350,
          child: _buildDtrTable(
            end: end,
            recordsByDate: recordsByDate,
            dtr: dtr,
          ),
        ),
        const SizedBox(height: 16),
        _buildSummaryCard(
          selectedName: selectedName,
          workingDays: workingDays,
          lateCount: lateCount,
          absentCount: absentCount,
          tardyCount: tardyCount,
          tardinessPct: tardinessPct,
          fullWidth: true,
          recordsByDate: recordsByDate,
          end: end,
        ),
      ],
    );
  }

  Widget _buildEmployeeListCompact(List<dynamic> employees) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    setState(() => _selectedEmployeeId = e.id);
                    _loadEmployeeRecords();
                  },
                  child: Container(
                    color: isSelected
                        ? AppTheme.primaryNavy.withValues(alpha: 0.08)
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
