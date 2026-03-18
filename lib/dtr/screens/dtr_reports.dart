import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
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
  String? _selectedDepartmentId;
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
    await Future.wait([
      dtr.loadEmployees(departmentId: _selectedDepartmentId),
      dtr.loadDepartments(),
    ]);
    if (!mounted) return;
    if (dtr.employees.isNotEmpty) {
      if (_selectedEmployeeId == null ||
          !dtr.employees.any((e) => e.id == _selectedEmployeeId)) {
        setState(() => _selectedEmployeeId = dtr.employees.first.id);
      }
      _loadEmployeeRecords();
    } else {
      setState(() {
        _selectedEmployeeId = null;
        _employeeRecords = [];
      });
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
      limit: 100,
    );
    if (!mounted) return;
    setState(() => _employeeRecords = List.from(dtr.timeRecords));
  }

  void _reset() {
    setState(() {
      _searchController.clear();
      _selectedMonth = DateTime.now().month;
      _selectedYear = DateTime.now().year;
      _selectedDepartmentId = null;
    });
    _load();
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  static const List<String> _shortWeekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String _formatDate(DateTime d) {
    final weekday = _shortWeekdays[d.weekday - 1];
    return '${d.day} $weekday';
  }

  static String _formatMinutes(int? mins) {
    if (mins == null || mins <= 0) return '—';
    return '$mins min';
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
        case 'holiday':
          return r.holidayName ?? 'Holiday';
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
    final baseName =
        'DTR_${selectedName.replaceAll(' ', '_')}_${_months[_selectedMonth - 1]}_$_selectedYear';
    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generating DTR...')));
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
          await shareOrDownloadFile(
            bytes,
            '$baseName.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          break;
        case _DtrExportFormat.word:
          final html = await DtrExport.generateWordHtml(
            employeeName: selectedName,
            year: _selectedYear,
            month: _selectedMonth,
            end: end,
            recordsByDate: recordsByDate,
          );
          final bytes = Uint8List.fromList(utf8.encode(html));
          if (!context.mounted) return;
          await shareOrDownloadFile(
            bytes,
            '$baseName.doc',
            'application/msword',
          );
          break;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DTR exported as ${format.name.toUpperCase()}')),
      );
    } catch (e, st) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('DTR export error: $e\n$st');
    }
  }

  /// Print DTR report: open system print dialog when supported; otherwise share PDF.
  Future<void> _printDtrReport(
    BuildContext context, {
    required String selectedName,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? department,
    String? position,
  }) async {
    final baseName =
        'DTR_${selectedName.replaceAll(' ', '_')}_${_months[_selectedMonth - 1]}_$_selectedYear';
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Preparing print...')));
    try {
      final bytes = await DtrExport.generatePdf(
        employeeName: selectedName,
        year: _selectedYear,
        month: _selectedMonth,
        end: end,
        recordsByDate: recordsByDate,
        department: department,
        position: position,
      );
      if (!context.mounted) return;
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: baseName,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DTR sent to print')));
    } catch (e) {
      if (!context.mounted) return;
      try {
        final bytes = await DtrExport.generatePdf(
          employeeName: selectedName,
          year: _selectedYear,
          month: _selectedMonth,
          end: end,
          recordsByDate: recordsByDate,
          reportTitle: 'Daily Time Record Report',
          department: department,
          position: position,
        );
        await shareOrDownloadPdf(bytes, '$baseName.pdf');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Print dialog not available. PDF shared — open it to print.',
            ),
          ),
        );
      } catch (e2) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e2'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    // Show all dates that have DTR records (real or synthetic) for the selected employee/month
    final sortedDates = recordsByDate.keys.toList()
      ..sort((a, b) => a.compareTo(b)); // ordered by date ascending

    // Compute summary from real API records (recordsByDate from _employeeRecords).
    // When there are no weekday punches at all, show 0 (no inferred absent).
    final totalWeekdays = _countWorkingDays(_selectedYear, _selectedMonth);
    var lateCount = 0;
    var absentCount = 0;
    var holidaysCount = 0;
    var hasAnyWeekdayPunch = false;
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(_selectedYear, _selectedMonth, d);
      if (dt.weekday >= DateTime.monday && dt.weekday <= DateTime.friday) {
        final rec = recordsByDate[dt];
        if (rec?.status == 'holiday') {
          holidaysCount++;
        } else if (rec?.status == 'on_leave') {
          // On leave: not absent for tardiness
        } else if (rec == null || rec.timeIn == null) {
          absentCount++;
        } else {
          hasAnyWeekdayPunch = true;
          if (rec.status == 'late' || (rec.lateMinutes ?? 0) > 0) {
            lateCount++;
          }
        }
      }
    }
    // No punches on any weekday = show zeros (don't infer 22 absent)
    final hasRecords = hasAnyWeekdayPunch;
    final workingDays = hasRecords ? totalWeekdays - holidaysCount : 0;
    final displayLateCount = hasRecords ? lateCount : 0;
    final displayAbsentCount = hasRecords ? absentCount : 0;
    final tardyCount = hasRecords ? (lateCount + absentCount) : 0;
    final tardinessPct = workingDays > 0
        ? ((tardyCount / workingDays) * 100).round()
        : 0;

    // Total late and undertime minutes for the month (from all records)
    var totalLateMinutes = 0;
    var totalUndertimeMinutes = 0;
    for (final rec in recordsByDate.values) {
      totalLateMinutes += rec.lateMinutes ?? 0;
      totalUndertimeMinutes += rec.undertimeMinutes ?? 0;
    }
    final displayTotalLateMinutes = hasRecords ? totalLateMinutes : 0;
    final displayTotalUndertimeMinutes = hasRecords ? totalUndertimeMinutes : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final isMobile = w < 600;
        final isCompact = w < 1024;
        // Use bounded height when parent gives unbounded (e.g. inside scroll view)
        final boundedH = h.isFinite && h > 0 ? h : 1200.0;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: boundedH,
            maxWidth: constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 1200,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tardiness Report',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                _buildFilters(isMobile),
                const SizedBox(height: 24),
                isMobile
                    ? _buildMobileLayout(
                        employees: employees,
                        end: end,
                        recordsByDate: recordsByDate,
                        sortedDates: sortedDates,
                        selectedName: selectedName,
                        workingDays: workingDays,
                        lateCount: displayLateCount,
                        absentCount: displayAbsentCount,
                        tardyCount: tardyCount,
                        tardinessPct: tardinessPct,
                        totalLateMinutes: displayTotalLateMinutes,
                        totalUndertimeMinutes: displayTotalUndertimeMinutes,
                        hasRecords: hasRecords,
                        dtr: dtr,
                      )
                    : isCompact
                    ? _buildCompactLayout(
                        employees: employees,
                        end: end,
                        recordsByDate: recordsByDate,
                        sortedDates: sortedDates,
                        selectedName: selectedName,
                        workingDays: workingDays,
                        lateCount: displayLateCount,
                        absentCount: displayAbsentCount,
                        tardyCount: tardyCount,
                        tardinessPct: tardinessPct,
                        totalLateMinutes: displayTotalLateMinutes,
                        totalUndertimeMinutes: displayTotalUndertimeMinutes,
                        hasRecords: hasRecords,
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
                              child: LayoutBuilder(
                                builder: (context, layoutConstraints) {
                                  final tableAvailableWidth =
                                      layoutConstraints.maxWidth - 16 - 200;
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _buildDtrTable(
                                          end: end,
                                          recordsByDate: recordsByDate,
                                          sortedDates: sortedDates,
                                          dtr: dtr,
                                          availableWidth: tableAvailableWidth,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      _buildSummaryCard(
                                        selectedName: selectedName,
                                        workingDays: workingDays,
                                        lateCount: displayLateCount,
                                        absentCount: displayAbsentCount,
                                        tardyCount: tardyCount,
                                        tardinessPct: tardinessPct,
                                        totalLateMinutes:
                                            displayTotalLateMinutes,
                                        totalUndertimeMinutes:
                                            displayTotalUndertimeMinutes,
                                        hasRecords: hasRecords,
                                        recordsByDate: recordsByDate,
                                        end: end,
                                      ),
                                    ],
                                  );
                                },
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

  Widget _buildFilters(bool isMobile) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: isMobile ? double.infinity : 280,
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
        if (!isMobile) ...[
          DropdownButton<String?>(
            value: _selectedDepartmentId,
            hint: const Text('All departments'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All departments'),
              ),
              ...context.read<DtrProvider>().departments.map(
                (d) =>
                    DropdownMenuItem<String?>(value: d.id, child: Text(d.name)),
              ),
            ],
            onChanged: (v) {
              setState(() => _selectedDepartmentId = v);
              _load();
            },
          ),
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
        ] else ...[
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String?>(
              value: _selectedDepartmentId,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: AppTheme.white,
              ),
              hint: const Text('All departments'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All departments'),
                ),
                ...context.read<DtrProvider>().departments.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(d.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _selectedDepartmentId = v);
                _load();
              },
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<int>(
                  value: _selectedMonth,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: AppTheme.white,
                  ),
                  items: List.generate(12, (i) => i + 1)
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            _months[m - 1],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedMonth = v);
                    _loadEmployeeRecords();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<int>(
                  value: _selectedYear,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: AppTheme.white,
                  ),
                  items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedYear = v);
                    _loadEmployeeRecords();
                  },
                ),
              ),
            ],
          ),
        ],
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
    );
  }

  Widget _buildMobileLayout({
    required List<dynamic> employees,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required List<DateTime> sortedDates,
    required String selectedName,
    required int workingDays,
    required int lateCount,
    required int absentCount,
    required int tardyCount,
    required int tardinessPct,
    required int totalLateMinutes,
    required int totalUndertimeMinutes,
    required bool hasRecords,
    required DtrProvider dtr,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedEmployeeId,
              isExpanded: true,
              hint: const Text('Select employee'),
              items: employees
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e.id.toString(),
                      child: Text(e.fullName, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedEmployeeId = v);
                  _loadEmployeeRecords();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 320,
          child: _buildDtrTable(
            end: end,
            recordsByDate: recordsByDate,
            sortedDates: sortedDates,
            dtr: dtr,
            compactColumns: true,
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
          totalLateMinutes: totalLateMinutes,
          totalUndertimeMinutes: totalUndertimeMinutes,
          hasRecords: hasRecords,
          fullWidth: true,
          isResponsive: true,
          recordsByDate: recordsByDate,
          end: end,
        ),
      ],
    );
  }

  Widget _buildEmployeeList(List<EmployeeOption> employees) {
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
                  width: 68,
                  child: Text(
                    'No.',
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
                          width: 68,
                          child: Text(
                            e.displayEmployeeNo,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
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
    required List<DateTime> sortedDates,
    required DtrProvider dtr,
    bool compactColumns = false,
    double? availableWidth,
  }) {
    final colDate = compactColumns ? 80.0 : 90.0;
    final colTime = compactColumns ? 58.0 : 70.0;
    final colLate = compactColumns ? 48.0 : 58.0;
    final colUndertime = compactColumns ? 55.0 : 65.0;
    final minTableWidth = compactColumns
        ? (colDate + colTime * 4 + colLate + colUndertime + 70)
        : 550.0 + colLate + colUndertime;
    final tableWidth = availableWidth != null
        ? availableWidth.clamp(minTableWidth, double.infinity)
        : minTableWidth;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Container(
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
                      width: colDate,
                      child: Text(
                        'Date',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text(
                        'AM IN',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text(
                        'AM OUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text(
                        'PM IN',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text(
                        'PM OUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: colLate,
                      child: Text(
                        'Late',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: colUndertime,
                      child: Text(
                        'Undertime',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compactColumns ? 11 : 12,
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
                    ? const Center(child: CircularProgressIndicator())
                    : sortedDates.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No DTR records for this period',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: sortedDates.length,
                        itemBuilder: (context, i) {
                          final dt = sortedDates[i];
                          final rec = recordsByDate[dt]!;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: i % 2 == 0
                                  ? AppTheme.white
                                  : AppTheme.lightGray.withOpacity(0.3),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: colDate,
                                  child: Text(
                                    _formatDate(dt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec.timeIn != null
                                        ? _formatTime(rec.timeIn)
                                        : '—',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec.breakOut != null
                                        ? _formatTime(rec.breakOut)
                                        : '—',
                                    style: TextStyle(
                                      fontSize: compactColumns ? 11 : 12,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec.breakIn != null
                                        ? _formatTime(rec.breakIn)
                                        : '—',
                                    style: TextStyle(
                                      fontSize: compactColumns ? 11 : 12,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec.timeOut != null
                                        ? _formatTime(rec.timeOut)
                                        : '—',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colLate,
                                  child: Text(
                                    _formatMinutes(rec.lateMinutes),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: (rec.lateMinutes ?? 0) > 0
                                          ? Colors.red.shade700
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colUndertime,
                                  child: Text(
                                    _formatMinutes(rec.undertimeMinutes),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: (rec.undertimeMinutes ?? 0) > 0
                                          ? Colors.orange.shade700
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final remark =
                                          rec.attendanceRemark != null &&
                                              rec.attendanceRemark!.isNotEmpty
                                          ? rec.attendanceRemark!
                                          : _getRemarks(rec);
                                      final isLateRemark =
                                          rec.status == 'late' ||
                                          rec.attendanceRemark == 'Late' ||
                                          rec.attendanceRemark ==
                                              'Late + Undertime';
                                      final isHolidayRemark =
                                          rec.status == 'holiday' ||
                                          rec.holidayId != null;
                                      return Text(
                                        remark,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isLateRemark
                                              ? Colors.red.shade700
                                              : isHolidayRemark
                                              ? Colors.purple.shade700
                                              : AppTheme.textPrimary,
                                        ),
                                      );
                                    },
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

  static String _formatTotalMinutes(int minutes) {
    if (minutes <= 0) return '0 min';
    return '$minutes min';
  }

  Widget _buildSummaryCard({
    required String selectedName,
    required int workingDays,
    required int lateCount,
    required int absentCount,
    required int tardyCount,
    required int tardinessPct,
    required int totalLateMinutes,
    required int totalUndertimeMinutes,
    bool hasRecords = true,
    bool fullWidth = false,
    bool isResponsive = false,
    required Map<DateTime, TimeRecord> recordsByDate,
    required DateTime end,
  }) {
    return Container(
      width: fullWidth ? null : 200,
      constraints: fullWidth
          ? const BoxConstraints(maxHeight: 600)
          : const BoxConstraints(maxWidth: 200, maxHeight: 600),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.primaryNavy.withOpacity(0.2),
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
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            isResponsive
                ? Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 140,
                        child: _SummaryStat(
                          label: 'Working Days',
                          value: '$workingDays',
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: _SummaryStat(
                          label: 'Late',
                          value: _formatTotalMinutes(totalLateMinutes),
                          hasBorder: true,
                          borderColor: totalLateMinutes > 0
                              ? Colors.red
                              : const Color(0xFF4CAF50),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: _SummaryStat(
                          label: 'Undertime',
                          value: _formatTotalMinutes(totalUndertimeMinutes),
                          hasBorder: totalUndertimeMinutes > 0,
                          borderColor: Colors.orange,
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: _SummaryStat(
                          label: 'Absent',
                          value: '$absentCount',
                          hasBorder: absentCount > 0,
                          borderColor: Colors.orange,
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: _SummaryStat(
                          label: 'Tardy',
                          value: '$tardyCount',
                          hasBorder: tardyCount > 0,
                          borderColor: Colors.orange,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SummaryStat(
                        label: 'Working Days',
                        value: '$workingDays',
                      ),
                      const SizedBox(height: 12),
                      _SummaryStat(
                        label: 'Late',
                        value: _formatTotalMinutes(totalLateMinutes),
                        hasBorder: true,
                        borderColor: totalLateMinutes > 0
                            ? Colors.red
                            : const Color(0xFF4CAF50),
                      ),
                      const SizedBox(height: 12),
                      _SummaryStat(
                        label: 'Undertime',
                        value: _formatTotalMinutes(totalUndertimeMinutes),
                        hasBorder: totalUndertimeMinutes > 0,
                        borderColor: Colors.orange,
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
                    ],
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
              child: FilledButton.icon(
                onPressed: () => _printDtrReport(
                  context,
                  selectedName: selectedName,
                  end: end,
                  recordsByDate: recordsByDate,
                ),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('PRINT'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                              leading: const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.red,
                              ),
                              title: const Text('PDF'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _generateDtr(
                                  context,
                                  _DtrExportFormat.pdf,
                                  selectedName: selectedName,
                                  end: end,
                                  recordsByDate: recordsByDate,
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.description,
                                color: Colors.blue,
                              ),
                              title: const Text('Word (.doc)'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _generateDtr(
                                  context,
                                  _DtrExportFormat.word,
                                  selectedName: selectedName,
                                  end: end,
                                  recordsByDate: recordsByDate,
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.table_chart,
                                color: Colors.green,
                              ),
                              title: const Text('Excel (.xlsx)'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _generateDtr(
                                  context,
                                  _DtrExportFormat.excel,
                                  selectedName: selectedName,
                                  end: end,
                                  recordsByDate: recordsByDate,
                                );
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
    required List<EmployeeOption> employees,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required List<DateTime> sortedDates,
    required String selectedName,
    required int workingDays,
    required int lateCount,
    required int absentCount,
    required int tardyCount,
    required int tardinessPct,
    required int totalLateMinutes,
    required int totalUndertimeMinutes,
    required bool hasRecords,
    required DtrProvider dtr,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 800.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 200, child: _buildEmployeeListCompact(employees)),
            const SizedBox(height: 16),
            SizedBox(
              height: 350,
              child: _buildDtrTable(
                end: end,
                recordsByDate: recordsByDate,
                sortedDates: sortedDates,
                dtr: dtr,
                availableWidth: availableWidth,
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
              totalLateMinutes: totalLateMinutes,
              totalUndertimeMinutes: totalUndertimeMinutes,
              hasRecords: hasRecords,
              fullWidth: true,
              isResponsive: true,
              recordsByDate: recordsByDate,
              end: end,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmployeeListCompact(List<EmployeeOption> employees) {
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
                  width: 68,
                  child: Text(
                    'No.',
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
                          width: 68,
                          child: Text(
                            e.displayEmployeeNo,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
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
