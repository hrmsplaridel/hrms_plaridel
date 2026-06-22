import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_share.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';

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
  int _rangeStartDay = 1;
  int _rangeEndDay = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  ).day;
  String? _selectedEmployeeId;
  String? _selectedDepartmentId;
  final Set<String> _selectedEmployeeIds = <String>{};
  List<TimeRecord> _employeeRecords = [];
  bool _showMinutesFormat = true;
  bool _bulkExportBusy = false;
  bool _multiSelectMode = false;

  /// Shift working days (ISO 1=Mon..7=Sun) for selected employee in report month. Null = use Mon–Fri.
  List<int>? _shiftWorkingDays;

  /// Official hours string from assigned shift, e.g. "8:00AM-12:00PM 01:00PM-5:00PM".
  String? _shiftOfficialHours;

  /// Active assignment window (calendar dates) for the selected employee; drives export + summary.
  DateTime? _assignmentEffectiveFrom;
  DateTime? _assignmentEffectiveTo;

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
      final availableIds = dtr.employees.map((e) => e.id).toSet();
      setState(() {
        _selectedEmployeeIds.removeWhere((id) => !availableIds.contains(id));
        if (_selectedEmployeeId == null ||
            !availableIds.contains(_selectedEmployeeId)) {
          _selectedEmployeeId = dtr.employees.first.id;
        }
      });
      _loadEmployeeRecords();
    } else {
      setState(() {
        _selectedEmployeeId = null;
        _selectedEmployeeIds.clear();
        _multiSelectMode = false;
        _employeeRecords = [];
      });
    }
  }

  Future<void> _loadEmployeeRecords() async {
    if (_selectedEmployeeId == null) return;
    _clampRangeToSelectedMonth();
    final start = DateTime(_selectedYear, _selectedMonth, 1);
    final end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final dtr = context.read<DtrProvider>();
    await Future.wait([
      dtr.loadTimeRecordsForAdmin(
        startDate: start,
        endDate: end,
        userId: _selectedEmployeeId,
        limit: 100,
      ),
      _loadShiftWorkingDays(),
    ]);
    if (!mounted) return;
    setState(() => _employeeRecords = List.from(dtr.timeRecords));
  }

  int _daysInSelectedMonth() {
    return DateTime(_selectedYear, _selectedMonth + 1, 0).day;
  }

  DateTime _rangeStartDate() {
    _clampRangeToSelectedMonth();
    return DateTime(_selectedYear, _selectedMonth, _rangeStartDay);
  }

  DateTime _rangeEndDate() {
    _clampRangeToSelectedMonth();
    return DateTime(_selectedYear, _selectedMonth, _rangeEndDay);
  }

  void _clampRangeToSelectedMonth() {
    final lastDay = _daysInSelectedMonth();
    _rangeStartDay = _rangeStartDay.clamp(1, lastDay).toInt();
    _rangeEndDay = _rangeEndDay.clamp(1, lastDay).toInt();
    if (_rangeStartDay > _rangeEndDay) {
      _rangeEndDay = _rangeStartDay;
    }
  }

  void _setSelectedMonth(int month) {
    setState(() {
      _selectedMonth = month;
      _rangeStartDay = 1;
      _rangeEndDay = _daysInSelectedMonth();
    });
    _loadEmployeeRecords();
  }

  void _setSelectedYear(int year) {
    setState(() {
      _selectedYear = year;
      _rangeStartDay = 1;
      _rangeEndDay = _daysInSelectedMonth();
    });
    _loadEmployeeRecords();
  }

  static String _formatOfficialHours(String start, String end) {
    String toAmPm(String t) {
      final parts = t.trim().split(RegExp(r'[:.\s]'));
      if (parts.isEmpty) return t;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final isPm = h >= 12;
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}${isPm ? 'PM' : 'AM'}';
    }

    return '${toAmPm(start)}-${toAmPm(end)}';
  }

  Future<_DtrAssignmentInfo> _fetchAssignmentInfoForEmployee(
    String employeeId,
  ) async {
    final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final monthEnd = DateTime(_selectedYear, _selectedMonth + 1, 0);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/assignments',
        queryParameters: {'employee_id': employeeId, 'status': 'Active'},
      );
      final list = res.data ?? [];
      for (final a in list) {
        final m = a as Map<String, dynamic>;
        final from = m['effective_from'] != null
            ? DateTime.tryParse(m['effective_from'].toString())
            : null;
        final to =
            m['effective_to'] != null &&
                m['effective_to'].toString().trim().isNotEmpty
            ? DateTime.tryParse(m['effective_to'].toString())
            : null;
        if (from == null) continue;
        if (from.isAfter(monthEnd)) continue;
        if (to != null && to.isBefore(monthStart)) continue;
        final wd = m['working_days'];
        List<int>? days;
        if (wd is List) {
          days = wd
              .map((x) => x is int ? x : int.tryParse(x.toString()))
              .whereType<int>()
              .where((x) => x >= 1 && x <= 7)
              .toList();
        }
        String? officialHours;
        final st = m['start_time'];
        final et = m['end_time'];
        if (st != null && et != null) {
          officialHours = _formatOfficialHours(st.toString(), et.toString());
        }
        return _DtrAssignmentInfo(
          workingDays: (days != null && days.isNotEmpty) ? days : null,
          officialHours: officialHours,
          effectiveFrom: DateTime(from.year, from.month, from.day),
          effectiveTo: to != null ? DateTime(to.year, to.month, to.day) : null,
          department: m['department_name']?.toString().trim(),
          position: m['position_name']?.toString().trim(),
        );
      }
    } catch (_) {
      return const _DtrAssignmentInfo();
    }
    return const _DtrAssignmentInfo();
  }

  /// Fetch assignment for selected employee and set _shiftWorkingDays for report month.
  Future<void> _loadShiftWorkingDays() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) return;
    final info = await _fetchAssignmentInfoForEmployee(employeeId);
    if (!mounted) return;
    setState(() {
      _shiftWorkingDays = info.workingDays;
      _shiftOfficialHours = info.officialHours;
      _assignmentEffectiveFrom = info.effectiveFrom;
      _assignmentEffectiveTo = info.effectiveTo;
    });
  }

  _DtrAssignmentInfo _currentAssignmentInfo() {
    return _DtrAssignmentInfo(
      workingDays: _shiftWorkingDays,
      officialHours: _shiftOfficialHours,
      effectiveFrom: _assignmentEffectiveFrom,
      effectiveTo: _assignmentEffectiveTo,
    );
  }

  /// Shift weekday and within assignment effective dates when loaded.
  bool _isScheduledWorkDayFor(DateTime dt, _DtrAssignmentInfo assignment) {
    final shiftWd =
        assignment.workingDays != null && assignment.workingDays!.isNotEmpty
        ? assignment.workingDays!.toSet()
        : {1, 2, 3, 4, 5};
    if (!shiftWd.contains(dt.weekday)) return false;
    if (assignment.effectiveFrom != null) {
      if (dt.isBefore(assignment.effectiveFrom!)) return false;
    }
    if (assignment.effectiveTo != null) {
      if (dt.isAfter(assignment.effectiveTo!)) return false;
    }
    return true;
  }

  bool _isScheduledWorkDay(DateTime dt) {
    return _isScheduledWorkDayFor(dt, _currentAssignmentInfo());
  }

  /// Holiday rows from the API are omitted when they are not meaningful for tardiness:
  /// no assignment overlapping the month, or the date is not a scheduled work day for this employee.
  Map<DateTime, TimeRecord> _filterRecordsForTardinessReportFor(
    Map<DateTime, TimeRecord> raw,
    _DtrAssignmentInfo assignment,
  ) {
    final hasAssignment = assignment.effectiveFrom != null;
    final out = <DateTime, TimeRecord>{};
    for (final e in raw.entries) {
      final dt = e.key;
      final r = e.value;
      final isHoliday = r.status == 'holiday' || (r.holidayId != null);
      if (isHoliday) {
        if (!hasAssignment) continue;
        if (!_isScheduledWorkDayFor(dt, assignment)) continue;
      }
      out[dt] = r;
    }
    return out;
  }

  Map<DateTime, TimeRecord> _filterRecordsForTardinessReport(
    Map<DateTime, TimeRecord> raw,
  ) {
    return _filterRecordsForTardinessReportFor(raw, _currentAssignmentInfo());
  }

  /// Last date in the selected month included in tardiness/absent/late stats. Days after this
  /// cutoff are not treated as absent (no attendance record exists yet). We use *yesterday*
  /// rather than today because the current day's shift may not have ended — the backend only
  /// injects synthetic "Absent" rows after the shift is over. If the backend already sent a
  /// record for today (employee clocked in, or post-shift absent), it still shows in the grid
  /// because it exists in [recordsByDate]; this cutoff only governs the *client-side* fallback
  /// when no record exists.
  DateTime _tardinessStatsInclusiveEnd() {
    final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final reportEnd = _rangeEndDate();
    final monthEnd = DateTime(_selectedYear, _selectedMonth, lastDay);
    final now = DateTime.now();
    // Use yesterday: today's shift may still be in progress.
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    if (monthEnd.isBefore(yesterday)) {
      return reportEnd.isBefore(monthEnd) ? reportEnd : monthEnd;
    }
    if (yesterday.isBefore(monthStart)) {
      return monthStart.subtract(const Duration(days: 1));
    }
    final capped = yesterday.isAfter(monthEnd) ? monthEnd : yesterday;
    return capped.isAfter(reportEnd) ? reportEnd : capped;
  }

  /// Scheduled work days in the month on or before [inclusiveEnd].
  int _countScheduledWorkDaysThrough(DateTime inclusiveEnd) {
    final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    var n = 0;
    for (var d = _rangeStartDay; d <= lastDay; d++) {
      final dt = DateTime(_selectedYear, _selectedMonth, d);
      if (dt.isAfter(inclusiveEnd)) continue;
      if (_isScheduledWorkDay(dt)) n++;
    }
    return n;
  }

  List<DateTime> _calendarDatesInSelectedRange(DateTime end) {
    final startDay = _rangeStartDay.clamp(1, end.day).toInt();
    final endDay = _rangeEndDay.clamp(startDay, end.day).toInt();
    return List<DateTime>.generate(
      endDay - startDay + 1,
      (i) => DateTime(_selectedYear, _selectedMonth, startDay + i),
    );
  }

  void _reset() {
    setState(() {
      _searchController.clear();
      _selectedMonth = DateTime.now().month;
      _selectedYear = DateTime.now().year;
      _rangeStartDay = 1;
      _rangeEndDay = _daysInSelectedMonth();
      _selectedDepartmentId = null;
      _selectedEmployeeIds.clear();
      _multiSelectMode = false;
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

  static String _cellDisplayForSegment({
    required TimeRecord record,
    required DateTime? timeValue,
    required String segment,
  }) {
    if (timeValue != null) return _formatTime(timeValue);
    final segs = record.locatorSlipSegments ?? const <String>[];
    if (segs.any((s) => s.toUpperCase() == segment)) {
      return record.locatorSlipSlotLabel;
    }
    return '—';
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
          return r.leaveTypeName ?? r.attendanceRemark ?? 'On Leave';
        case 'holiday':
          return r.holidayName ?? 'Holiday';
        case 'on_field':
          return r.locatorSlipDisplayLabel;
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

  static String _getReportRowRemark({
    required TimeRecord? record,
    required bool isQuietPlaceholder,
    required bool isMissingScheduledWorkDay,
  }) {
    if (isQuietPlaceholder) return '—';
    if (isMissingScheduledWorkDay) return 'Absent';
    final rec = record;
    if (rec == null) return '';
    final attendanceRemark = rec.attendanceRemark?.trim();
    if (attendanceRemark != null && attendanceRemark.isNotEmpty) {
      return _normalizeAttendanceRemark(attendanceRemark);
    }
    return _getRemarks(rec);
  }

  static String _normalizeAttendanceRemark(String remark) {
    final value = remark.trim();
    if (value.toLowerCase().startsWith('work from home')) return 'WFH';
    return value;
  }

  Future<void> _generateDtr(
    BuildContext context,
    _DtrExportFormat format, {
    required String selectedName,
    required DateTime start,
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
            start: start,
            end: end,
            recordsByDate: recordsByDate,
            officialHours: _shiftOfficialHours,
            workingDays: _shiftWorkingDays,
            assignmentEffectiveFrom: _assignmentEffectiveFrom,
            assignmentEffectiveTo: _assignmentEffectiveTo,
          );
          if (!context.mounted) return;
          await shareOrDownloadPdf(bytes, '$baseName.pdf');
          break;
        case _DtrExportFormat.excel:
          final bytes = await DtrExport.generateExcel(
            employeeName: selectedName,
            year: _selectedYear,
            month: _selectedMonth,
            start: start,
            end: end,
            recordsByDate: recordsByDate,
            officialHours: _shiftOfficialHours,
            workingDays: _shiftWorkingDays,
            assignmentEffectiveFrom: _assignmentEffectiveFrom,
            assignmentEffectiveTo: _assignmentEffectiveTo,
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
            start: start,
            end: end,
            recordsByDate: recordsByDate,
            officialHours: _shiftOfficialHours,
            workingDays: _shiftWorkingDays,
            assignmentEffectiveFrom: _assignmentEffectiveFrom,
            assignmentEffectiveTo: _assignmentEffectiveTo,
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
    required DateTime start,
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
        start: start,
        end: end,
        recordsByDate: recordsByDate,
        department: department,
        position: position,
        officialHours: _shiftOfficialHours,
        workingDays: _shiftWorkingDays,
        assignmentEffectiveFrom: _assignmentEffectiveFrom,
        assignmentEffectiveTo: _assignmentEffectiveTo,
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
          start: start,
          end: end,
          recordsByDate: recordsByDate,
          reportTitle: 'Daily Time Record Report',
          department: department,
          position: position,
          officialHours: _shiftOfficialHours,
          workingDays: _shiftWorkingDays,
          assignmentEffectiveFrom: _assignmentEffectiveFrom,
          assignmentEffectiveTo: _assignmentEffectiveTo,
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

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showReportSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  void _setEmployeeBulkSelected(String employeeId, bool selected) {
    setState(() {
      _multiSelectMode = true;
      if (selected) {
        _selectedEmployeeIds.add(employeeId);
      } else {
        _selectedEmployeeIds.remove(employeeId);
      }
    });
  }

  void _selectAllFilteredEmployees(List<EmployeeOption> employees) {
    setState(() {
      _multiSelectMode = true;
      _selectedEmployeeIds.addAll(employees.map((e) => e.id));
    });
  }

  void _clearSelectedEmployees() {
    setState(() => _selectedEmployeeIds.clear());
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) _selectedEmployeeIds.clear();
    });
  }

  void _exitMultiSelectMode() {
    if (!_multiSelectMode && _selectedEmployeeIds.isEmpty) return;
    setState(() {
      _multiSelectMode = false;
      _selectedEmployeeIds.clear();
    });
  }

  void _toggleEmployeeSelection(EmployeeOption employee) {
    setState(() {
      _multiSelectMode = true;
      if (_selectedEmployeeIds.contains(employee.id)) {
        _selectedEmployeeIds.remove(employee.id);
      } else {
        _selectedEmployeeIds.add(employee.id);
      }
    });
  }

  List<EmployeeOption> _selectedEmployeesForBulk(DtrProvider dtr) {
    final byId = {for (final e in dtr.employees) e.id: e};
    return _selectedEmployeeIds
        .map((id) => byId[id])
        .whereType<EmployeeOption>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  Future<DtrExportItem> _prepareDtrExportItem(EmployeeOption employee) async {
    final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final monthEnd = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final records = await TimeRecordRepo.instance.listForAdmin(
      startDate: monthStart,
      endDate: monthEnd,
      userId: employee.id,
      limit: 500,
    );
    final assignment = await _fetchAssignmentInfoForEmployee(employee.id);
    final rawRecordsByDate = <DateTime, TimeRecord>{};
    for (final r in records) {
      rawRecordsByDate[DateTime(
            r.recordDate.year,
            r.recordDate.month,
            r.recordDate.day,
          )] =
          r;
    }
    final filteredRecords = _filterRecordsForTardinessReportFor(
      rawRecordsByDate,
      assignment,
    );
    final start = _rangeStartDate();
    final end = _rangeEndDate();
    final rangedRecords = Map<DateTime, TimeRecord>.fromEntries(
      filteredRecords.entries.where(
        (e) => !e.key.isBefore(start) && !e.key.isAfter(end),
      ),
    );
    return DtrExportItem(
      employeeName: employee.fullName,
      recordsByDate: rangedRecords,
      department: _nonEmpty(assignment.department) ?? employee.departmentName,
      position: _nonEmpty(assignment.position),
      officialHours: assignment.officialHours,
      workingDays: assignment.workingDays,
      assignmentEffectiveFrom: assignment.effectiveFrom,
      assignmentEffectiveTo: assignment.effectiveTo,
    );
  }

  Future<Uint8List> _buildSelectedDtrPdf(DtrProvider dtr) async {
    final selected = _selectedEmployeesForBulk(dtr);
    if (selected.length < 2) {
      throw StateError('Select at least two employees first.');
    }
    final items = <DtrExportItem>[];
    for (final employee in selected) {
      items.add(await _prepareDtrExportItem(employee));
    }
    return DtrExport.generateBulkPdf(
      items: items,
      year: _selectedYear,
      month: _selectedMonth,
      start: _rangeStartDate(),
      end: _rangeEndDate(),
      reportTitle: 'Daily Time Record Report',
    );
  }

  Future<void> _printSelectedDtrs(BuildContext context, DtrProvider dtr) async {
    if (_bulkExportBusy) return;
    final selectedCount = _selectedEmployeesForBulk(dtr).length;
    if (selectedCount < 2) {
      _showReportSnack('Select at least two employees to bulk print.');
      return;
    }
    setState(() => _bulkExportBusy = true);
    Uint8List? bytes;
    try {
      _showReportSnack('Preparing $selectedCount selected DTRs...');
      bytes = await _buildSelectedDtrPdf(dtr);
      if (!context.mounted) return;
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes!,
        name: 'DTR_Selected_${_months[_selectedMonth - 1]}_$_selectedYear',
      );
      if (!context.mounted) return;
      _showReportSnack('Selected DTRs sent to print.');
    } catch (e) {
      if (!context.mounted) return;
      if (bytes != null) {
        await shareOrDownloadPdf(
          bytes,
          'DTR_Selected_${_months[_selectedMonth - 1]}_$_selectedYear.pdf',
        );
        _showReportSnack('Print dialog not available. PDF shared instead.');
      } else {
        _showReportSnack('Bulk print failed: $e', backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _bulkExportBusy = false);
    }
  }

  Future<void> _exportSelectedDtrs(DtrProvider dtr) async {
    if (_bulkExportBusy) return;
    final selectedCount = _selectedEmployeesForBulk(dtr).length;
    if (selectedCount < 2) {
      _showReportSnack('Select at least two employees to export.');
      return;
    }
    setState(() => _bulkExportBusy = true);
    try {
      _showReportSnack('Exporting $selectedCount selected DTRs...');
      final bytes = await _buildSelectedDtrPdf(dtr);
      await shareOrDownloadPdf(
        bytes,
        'DTR_Selected_${_months[_selectedMonth - 1]}_$_selectedYear.pdf',
      );
      _showReportSnack('Selected DTRs exported as PDF.');
    } catch (e) {
      _showReportSnack('Bulk export failed: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _bulkExportBusy = false);
    }
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

    _clampRangeToSelectedMonth();
    final start = _rangeStartDate();
    final end = _rangeEndDate();
    final recordsByDate = <DateTime, TimeRecord>{};
    for (final r in _employeeRecords) {
      final key = DateTime(
        r.recordDate.year,
        r.recordDate.month,
        r.recordDate.day,
      );
      recordsByDate[key] = r;
    }
    final reportRecordsByDate = _filterRecordsForTardinessReport(recordsByDate);
    final rangedRecordsByDate = Map<DateTime, TimeRecord>.fromEntries(
      reportRecordsByDate.entries.where(
        (e) => !e.key.isBefore(start) && !e.key.isAfter(end),
      ),
    );
    // Display the selected calendar range in the report. Non-working days without
    // records are quiet placeholders only; they are not saved or counted.
    final hasAssignment = _assignmentEffectiveFrom != null;
    final shouldShowCalendarRows =
        _selectedEmployeeId != null &&
        (hasAssignment || rangedRecordsByDate.isNotEmpty);
    final sortedDates = shouldShowCalendarRows
        ? _calendarDatesInSelectedRange(end)
        : <DateTime>[];

    // Compute summary from real API records, using shift + assignment window when available.
    // Only count days up to today (elapsed) — future days in the month are not "absent" yet.
    final statsEnd = _tardinessStatsInclusiveEnd();
    final totalWeekdays = _countScheduledWorkDaysThrough(statsEnd);
    var lateCount = 0;
    var absentCount = 0;
    var holidaysCount = 0;
    for (var d = _rangeStartDay; d <= end.day; d++) {
      final dt = DateTime(_selectedYear, _selectedMonth, d);
      if (!_isScheduledWorkDay(dt)) continue;
      if (dt.isAfter(statsEnd)) continue;
      final rec = rangedRecordsByDate[dt];
      if (rec?.status == 'holiday' || (rec?.holidayId != null)) {
        holidaysCount++;
      } else if (rec?.status == 'on_leave') {
        // On leave: not absent for tardiness
      } else if (rec == null || (rec.timeIn == null && rec.breakIn == null)) {
        absentCount++;
      } else {
        if (rec.status == 'late' || (rec.lateMinutes ?? 0) > 0) {
          lateCount++;
        }
      }
    }
    // Show summary whenever this month has any report rows — not only days with punches.
    // (Absent / undertime-only days have no timeIn/breakIn but must still roll up to totals.)
    final hasRecords = rangedRecordsByDate.isNotEmpty || hasAssignment;
    final workingDays = hasRecords ? totalWeekdays - holidaysCount : 0;
    final displayLateCount = hasRecords ? lateCount : 0;
    final displayAbsentCount = hasRecords ? absentCount : 0;
    final tardyCount = hasRecords ? (lateCount + absentCount) : 0;
    final tardinessPct = workingDays > 0
        ? ((tardyCount / workingDays) * 100).round()
        : 0;

    // Total late and undertime minutes (elapsed days only, same window as counts)
    var totalLateMinutes = 0;
    var totalUndertimeMinutes = 0;
    for (final e in rangedRecordsByDate.entries) {
      if (e.key.isAfter(statsEnd)) continue;
      final rec = e.value;
      totalLateMinutes += rec.lateMinutes ?? 0;
      totalUndertimeMinutes += rec.undertimeMinutes ?? 0;
    }
    final displayTotalLateMinutes = hasRecords ? totalLateMinutes : 0;
    final displayTotalUndertimeMinutes = hasRecords ? totalUndertimeMinutes : 0;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true):
            _ToggleDtrMultiSelectIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _ExitDtrMultiSelectIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleDtrMultiSelectIntent:
              CallbackAction<_ToggleDtrMultiSelectIntent>(
                onInvoke: (_) {
                  _toggleMultiSelectMode();
                  return null;
                },
              ),
          _ExitDtrMultiSelectIntent: CallbackAction<_ExitDtrMultiSelectIntent>(
            onInvoke: (_) {
              _exitMultiSelectMode();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
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
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: isMobile ? 20 : 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFilters(context, isMobile),
                      const SizedBox(height: 24),
                      isMobile
                          ? _buildMobileLayout(
                              context: context,
                              employees: employees,
                              start: start,
                              end: end,
                              recordsByDate: rangedRecordsByDate,
                              sortedDates: sortedDates,
                              selectedName: selectedName,
                              workingDays: workingDays,
                              lateCount: displayLateCount,
                              absentCount: displayAbsentCount,
                              tardyCount: tardyCount,
                              tardinessPct: tardinessPct,
                              totalLateMinutes: displayTotalLateMinutes,
                              totalUndertimeMinutes:
                                  displayTotalUndertimeMinutes,
                              hasRecords: hasRecords,
                              dtr: dtr,
                            )
                          : isCompact
                          ? _buildCompactLayout(
                              employees: employees,
                              start: start,
                              end: end,
                              recordsByDate: rangedRecordsByDate,
                              sortedDates: sortedDates,
                              selectedName: selectedName,
                              workingDays: workingDays,
                              lateCount: displayLateCount,
                              absentCount: displayAbsentCount,
                              tardyCount: tardyCount,
                              tardinessPct: tardinessPct,
                              totalLateMinutes: displayTotalLateMinutes,
                              totalUndertimeMinutes:
                                  displayTotalUndertimeMinutes,
                              hasRecords: hasRecords,
                              dtr: dtr,
                            )
                          : SizedBox(
                              height: 520,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildEmployeeList(context, employees),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, layoutConstraints) {
                                        final tableAvailableWidth =
                                            layoutConstraints.maxWidth -
                                            16 -
                                            200;
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: _buildDtrTable(
                                                context,
                                                end: end,
                                                recordsByDate:
                                                    rangedRecordsByDate,
                                                sortedDates: sortedDates,
                                                dtr: dtr,
                                                availableWidth:
                                                    tableAvailableWidth,
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
                                              recordsByDate:
                                                  rangedRecordsByDate,
                                              start: start,
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
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context, bool isMobile) {
    final dark = AppTheme.dashIsDark(context);
    final dayItems = List.generate(_daysInSelectedMonth(), (i) => i + 1);
    final dtr = context.read<DtrProvider>();
    final selectedCount = _selectedEmployeesForBulk(dtr).length;
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
            style: AppTheme.dashFieldTextStyle(context),
            decoration: AppTheme.dashInputDecoration(
              context,
              hintText: 'Search name...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              radius: 8,
            ),
          ),
        ),
        if (!isMobile) ...[
          DropdownButton<String?>(
            value: _selectedDepartmentId,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            hint: Text(
              'All departments',
              style: AppTheme.dashFieldHintStyle(context),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All departments',
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
              ...context.read<DtrProvider>().departments.map(
                (d) => DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(
                    d.name,
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _selectedDepartmentId = v);
              _load();
            },
          ),
          DropdownButton<int>(
            value: _selectedMonth,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: List.generate(12, (i) => i + 1)
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      _months[m - 1],
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _setSelectedMonth(v);
            },
          ),
          DropdownButton<int>(
            value: _selectedYear,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                .map(
                  (y) => DropdownMenuItem(
                    value: y,
                    child: Text(
                      '$y',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _setSelectedYear(v);
            },
          ),
          DropdownButton<int>(
            value: _rangeStartDay,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: dayItems
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      'From day $d',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _rangeStartDay = v;
                if (_rangeEndDay < v) _rangeEndDay = v;
              });
            },
          ),
          DropdownButton<int>(
            value: _rangeEndDay,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: dayItems
                .where((d) => d >= _rangeStartDay)
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      'To day $d',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _rangeEndDay = v);
            },
          ),
        ] else ...[
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedDepartmentId,
              dropdownColor: AppTheme.dashPanelOf(context),
              style: AppTheme.dashFieldTextStyle(context),
              decoration: AppTheme.dashInputDecoration(
                context,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                radius: 8,
              ),
              hint: Text(
                'All departments',
                style: AppTheme.dashFieldHintStyle(context),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'All departments',
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
                ...context.read<DtrProvider>().departments.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(
                      d.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
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
                  initialValue: _selectedMonth,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: List.generate(12, (i) => i + 1)
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            _months[m - 1],
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _setSelectedMonth(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedYear,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                      .map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text(
                            '$y',
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _setSelectedYear(v);
                  },
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 112,
                child: DropdownButtonFormField<int>(
                  initialValue: _rangeStartDay,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: dayItems
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            'From $d',
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _rangeStartDay = v;
                      if (_rangeEndDay < v) _rangeEndDay = v;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<int>(
                  initialValue: _rangeEndDay,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: dayItems
                      .where((d) => d >= _rangeStartDay)
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            'To $d',
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _rangeEndDay = v);
                  },
                ),
              ),
            ],
          ),
        ],
        OutlinedButton(
          onPressed: _reset,
          style: OutlinedButton.styleFrom(
            backgroundColor: dark
                ? Colors.green.shade900.withValues(alpha: 0.4)
                : const Color(0xFFE8F5E9),
            foregroundColor: dark
                ? Colors.green.shade300
                : const Color(0xFF2E7D32),
            side: BorderSide(
              color: dark ? Colors.green.shade700 : const Color(0xFF81C784),
            ),
          ),
          child: const Text('RESET'),
        ),
        if (selectedCount > 1) ...[
          Text(
            '$selectedCount selected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          FilledButton.icon(
            onPressed: _bulkExportBusy
                ? null
                : () => _printSelectedDtrs(context, dtr),
            icon: _bulkExportBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded, size: 18),
            label: Text(_bulkExportBusy ? 'Preparing' : 'Bulk print'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.white,
              disabledBackgroundColor: AppTheme.dashMutedSurfaceOf(context),
              disabledForegroundColor: AppTheme.dashTextSecondaryOf(
                context,
              ).withValues(alpha: 0.7),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _bulkExportBusy ? null : () => _exportSelectedDtrs(dtr),
            icon: const Icon(Icons.file_download_rounded, size: 18),
            label: const Text('Export selected'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              side: BorderSide(
                color: AppTheme.primaryNavy.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileLayout({
    required BuildContext context,
    required List<EmployeeOption> employees,
    required DateTime start,
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
            color: AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedEmployeeId,
              isExpanded: true,
              dropdownColor: AppTheme.dashPanelOf(context),
              style: AppTheme.dashFieldTextStyle(context),
              hint: Text(
                'Select employee',
                style: AppTheme.dashFieldHintStyle(context),
              ),
              items: employees
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e.id.toString(),
                      child: Text(
                        e.fullName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.dashFieldTextStyle(context),
                      ),
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
        if (_multiSelectMode) ...[
          const SizedBox(height: 16),
          _buildEmployeeSelectionToolbar(context, employees, compact: true),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 320,
          child: _buildDtrTable(
            context,
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
          start: start,
          end: end,
        ),
      ],
    );
  }

  Widget _buildEmployeeSelectionToolbar(
    BuildContext context,
    List<EmployeeOption> employees, {
    bool compact = false,
  }) {
    final selectedCount = _selectedEmployeeIds.length;
    final allFilteredSelected =
        employees.isNotEmpty &&
        employees.every((e) => _selectedEmployeeIds.contains(e.id));
    if (!_multiSelectMode) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 10,
        vertical: compact ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              selectedCount == 0 ? '' : '$selectedCount selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Select all filtered employees',
            onPressed: employees.isEmpty || allFilteredSelected
                ? null
                : () => _selectAllFilteredEmployees(employees),
            icon: const Icon(Icons.select_all_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          ),
          if (selectedCount > 0)
            IconButton(
              tooltip: 'Clear selected employees',
              onPressed: _clearSelectedEmployees,
              icon: const Icon(Icons.clear_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            ),
          IconButton(
            tooltip: 'Exit multi-select (Esc)',
            onPressed: _exitMultiSelectMode,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeList(
    BuildContext context,
    List<EmployeeOption> employees,
  ) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: 260,
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEmployeeSelectionToolbar(context, employees),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                if (_multiSelectMode) const SizedBox(width: 32),
                SizedBox(
                  width: 58,
                  child: Text(
                    'No.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Employee Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: employees.length,
              itemBuilder: (ctx, i) {
                final e = employees[i];
                final isSelected = e.id == _selectedEmployeeId;
                final isChecked = _selectedEmployeeIds.contains(e.id);
                return InkWell(
                  onTap: () {
                    if (_multiSelectMode) {
                      _toggleEmployeeSelection(e);
                    } else {
                      setState(() {
                        _selectedEmployeeId = e.id;
                      });
                      _loadEmployeeRecords();
                    }
                  },
                  child: Container(
                    color: isSelected
                        ? (dark
                              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                              : AppTheme.primaryNavy.withValues(alpha: 0.08))
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (_multiSelectMode) ...[
                          SizedBox(
                            width: 28,
                            child: Checkbox(
                              value: isChecked,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (value) => _setEmployeeBulkSelected(
                                e.id,
                                value ?? false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        SizedBox(
                          width: 58,
                          child: Text(
                            e.displayEmployeeNo,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.dashTextPrimaryOf(ctx),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.dashTextPrimaryOf(ctx),
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

  Widget _buildDtrTable(
    BuildContext context, {
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
    final dark = AppTheme.dashIsDark(context);
    final cellStyle = TextStyle(
      fontSize: 12,
      color: AppTheme.dashTextPrimaryOf(context),
    );
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: compactColumns ? 11 : 12,
      color: AppTheme.dashTextPrimaryOf(context),
    );
    final statsEnd = _tardinessStatsInclusiveEnd();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Container(
          decoration: AppTheme.dashSurfaceCard(context, radius: 12),
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
                  color: AppTheme.dashMutedSurfaceOf(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: colDate,
                      child: Text('Date', style: headerStyle),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text('AM IN', style: headerStyle),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text('AM OUT', style: headerStyle),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text('PM IN', style: headerStyle),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text('PM OUT', style: headerStyle),
                    ),
                    SizedBox(
                      width: colLate,
                      child: Text('Late', style: headerStyle),
                    ),
                    SizedBox(
                      width: colUndertime,
                      child: Text('Undertime', style: headerStyle),
                    ),
                    Expanded(child: Text('Remarks', style: headerStyle)),
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
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: sortedDates.length,
                        itemBuilder: (context, i) {
                          final dt = sortedDates[i];
                          final rec = recordsByDate[dt];
                          final isScheduled =
                              _assignmentEffectiveFrom != null &&
                              _isScheduledWorkDay(dt);
                          final isQuietPlaceholder =
                              rec == null &&
                              (!isScheduled || dt.isAfter(statsEnd));
                          final isMissingScheduledWorkDay =
                              rec == null && !isQuietPlaceholder;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: i % 2 == 0
                                  ? AppTheme.dashPanelOf(context)
                                  : AppTheme.dashMutedSurfaceOf(
                                      context,
                                    ).withValues(alpha: dark ? 0.65 : 1),
                              border: Border(
                                bottom: BorderSide(
                                  color: AppTheme.dashHairlineOf(
                                    context,
                                  ).withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: colDate,
                                  child: Text(
                                    _formatDate(dt),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : _cellDisplayForSegment(
                                            record: rec,
                                            timeValue: rec.timeIn,
                                            segment: 'AM IN',
                                          ),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : _cellDisplayForSegment(
                                            record: rec,
                                            timeValue: rec.breakOut,
                                            segment: 'AM OUT',
                                          ),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : _cellDisplayForSegment(
                                            record: rec,
                                            timeValue: rec.breakIn,
                                            segment: 'PM IN',
                                          ),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : _cellDisplayForSegment(
                                            record: rec,
                                            timeValue: rec.timeOut,
                                            segment: 'PM OUT',
                                          ),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colLate,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : _formatMinutes(rec.lateMinutes),
                                    style: cellStyle.copyWith(
                                      color: (rec?.lateMinutes ?? 0) > 0
                                          ? (dark
                                                ? Colors.red.shade300
                                                : Colors.red.shade700)
                                          : AppTheme.dashTextPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colUndertime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : _formatMinutes(rec.undertimeMinutes),
                                    style: cellStyle.copyWith(
                                      color: (rec?.undertimeMinutes ?? 0) > 0
                                          ? (dark
                                                ? Colors.orange.shade300
                                                : Colors.orange.shade700)
                                          : AppTheme.dashTextPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Builder(
                                    builder: (rowCtx) {
                                      final remark = _getReportRowRemark(
                                        record: rec,
                                        isQuietPlaceholder: isQuietPlaceholder,
                                        isMissingScheduledWorkDay:
                                            isMissingScheduledWorkDay,
                                      );
                                      final isHoliday =
                                          rec?.status == 'holiday' ||
                                          rec?.holidayId != null;
                                      return Text(
                                        remark,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorForRemarkText(
                                            rowCtx,
                                            remark,
                                            isHoliday: isHoliday,
                                          ),
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

  String _formatMinutesOrHours(int minutes) {
    if (minutes <= 0) return _showMinutesFormat ? '0 min' : '0 hrs';
    if (_showMinutesFormat) return '$minutes min';
    final hours = minutes / 60;
    return hours == hours.roundToDouble()
        ? '${hours.toInt()} hrs'
        : '${hours.toStringAsFixed(2)} hrs';
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
    required DateTime start,
    required DateTime end,
  }) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: fullWidth ? null : 200,
      constraints: fullWidth
          ? const BoxConstraints(maxHeight: 600)
          : const BoxConstraints(maxWidth: 200, maxHeight: 600),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.primaryNavy.withValues(
                alpha: dark ? 0.35 : 0.2,
              ),
              child: Icon(
                Icons.person_rounded,
                size: 32,
                color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              selectedName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${_months[_selectedMonth - 1]}, $_selectedYear',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Show time as:',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('Min')),
                            ButtonSegment(value: false, label: Text('Hrs')),
                          ],
                          selected: {_showMinutesFormat},
                          onSelectionChanged: (selected) {
                            setState(() => _showMinutesFormat = selected.first);
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
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
                          value: _formatMinutesOrHours(totalLateMinutes),
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
                          value: _formatMinutesOrHours(totalUndertimeMinutes),
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
                        value: _formatMinutesOrHours(totalLateMinutes),
                        hasBorder: true,
                        borderColor: totalLateMinutes > 0
                            ? Colors.red
                            : const Color(0xFF4CAF50),
                      ),
                      const SizedBox(height: 12),
                      _SummaryStat(
                        label: 'Undertime',
                        value: _formatMinutesOrHours(totalUndertimeMinutes),
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
                color: AppTheme.dashTextPrimaryOf(context),
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
                  start: start,
                  end: end,
                  recordsByDate: recordsByDate,
                ),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('PRINT CURRENT'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Generate DTR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: AppTheme.dashPanelOf(context),
                    builder: (ctx) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Export DTR as',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.dashTextPrimaryOf(ctx),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.red,
                              ),
                              title: Text(
                                'PDF',
                                style: TextStyle(
                                  color: AppTheme.dashTextPrimaryOf(ctx),
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _generateDtr(
                                  context,
                                  _DtrExportFormat.pdf,
                                  selectedName: selectedName,
                                  start: start,
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
                              title: Text(
                                'Word (.doc)',
                                style: TextStyle(
                                  color: AppTheme.dashTextPrimaryOf(ctx),
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _generateDtr(
                                  context,
                                  _DtrExportFormat.word,
                                  selectedName: selectedName,
                                  start: start,
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
                              title: Text(
                                'Excel (.xlsx)',
                                style: TextStyle(
                                  color: AppTheme.dashTextPrimaryOf(ctx),
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _generateDtr(
                                  context,
                                  _DtrExportFormat.excel,
                                  selectedName: selectedName,
                                  start: start,
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
                  backgroundColor: dark
                      ? Colors.green.shade900.withValues(alpha: 0.4)
                      : const Color(0xFFE8F5E9),
                  foregroundColor: dark
                      ? Colors.green.shade300
                      : const Color(0xFF2E7D32),
                  side: BorderSide(
                    color: dark
                        ? Colors.green.shade700
                        : const Color(0xFF81C784),
                  ),
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
    required DateTime start,
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
            SizedBox(
              height: 240,
              child: _buildEmployeeListCompact(context, employees),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 350,
              child: _buildDtrTable(
                context,
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
              start: start,
              end: end,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmployeeListCompact(
    BuildContext context,
    List<EmployeeOption> employees,
  ) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEmployeeSelectionToolbar(context, employees, compact: true),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                if (_multiSelectMode) const SizedBox(width: 32),
                SizedBox(
                  width: 58,
                  child: Text(
                    'No.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Employee Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: employees.length,
              itemBuilder: (ctx, i) {
                final e = employees[i];
                final isSelected = e.id == _selectedEmployeeId;
                final isChecked = _selectedEmployeeIds.contains(e.id);
                return InkWell(
                  onTap: () {
                    if (_multiSelectMode) {
                      _toggleEmployeeSelection(e);
                    } else {
                      setState(() => _selectedEmployeeId = e.id);
                      _loadEmployeeRecords();
                    }
                  },
                  child: Container(
                    color: isSelected
                        ? (dark
                              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                              : AppTheme.primaryNavy.withValues(alpha: 0.08))
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (_multiSelectMode) ...[
                          SizedBox(
                            width: 28,
                            child: Checkbox(
                              value: isChecked,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (value) => _setEmployeeBulkSelected(
                                e.id,
                                value ?? false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        SizedBox(
                          width: 58,
                          child: Text(
                            e.displayEmployeeNo,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.dashTextPrimaryOf(ctx),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.dashTextPrimaryOf(ctx),
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

class _DtrAssignmentInfo {
  const _DtrAssignmentInfo({
    this.workingDays,
    this.officialHours,
    this.effectiveFrom,
    this.effectiveTo,
    this.department,
    this.position,
  });

  final List<int>? workingDays;
  final String? officialHours;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final String? department;
  final String? position;
}

class _ToggleDtrMultiSelectIntent extends Intent {
  const _ToggleDtrMultiSelectIntent();
}

class _ExitDtrMultiSelectIntent extends Intent {
  const _ExitDtrMultiSelectIntent();
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
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(8),
        border: hasBorder ? Border.all(color: borderColor, width: 1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
