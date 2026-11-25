import '../../data/dtr_report_bulk_export.dart';
import '../services/dtr_report_document_actions.dart';
import '../widgets/dtr_report_paper_size.dart';
import '../../data/dtr_report_period.dart';
import '../widgets/dtr_report_filters.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_readiness.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_summary_equivalent_day.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_request_guard.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_employee_status.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_assignments.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_repository.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_share.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/habitual_attendance_page.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_employee_list.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_summary_card.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_table.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

export '../widgets/dtr_pdf_preview_panel.dart' show DtrPdfPreviewPanel;

/// Tardiness Report: employee list, DTR table, and summary card.
/// Matches reference design: search, month/year filters, two-column layout.
class DtrReports extends StatefulWidget {
  const DtrReports({super.key, this.selfService = false});

  /// Restricts the report to the authenticated employee and hides management
  /// filters and bulk actions.
  final bool selfService;

  @override
  State<DtrReports> createState() => _DtrReportsState();
}

class _DtrReportsState extends State<DtrReports> {
  final _repository = DtrReportRepository();
  final _searchController = TextEditingController();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  List<int> _availableReportYears = <int>[DateTime.now().year];
  int _rangeStartDay = 1;
  int _rangeEndDay = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  ).day;
  String? _selectedEmployeeId;
  String? _selectedDepartmentId;
  String _selectedEmployeeStatus = 'Active';
  String? _manualEmployeeStatus;
  final Set<String> _selectedEmployeeIds = <String>{};
  final DtrReportRequestGuard _requestGuard = DtrReportRequestGuard();
  List<EmployeeOption> _reportEmployeeOptions = const [];
  List<TimeRecord> _employeeRecords = [];
  DateTime? _reportableThrough;
  DtrExportSignatories? _reportSignatories;
  bool _reportLoading = false;
  bool _showMinutesFormat = true;
  bool _bulkExportBusy = false;
  int _bulkExportPrepared = 0;
  int _bulkExportTotal = 0;
  bool _multiSelectMode = false;
  DtrReportDataState _employeesState = DtrReportDataState.idle;
  DtrReportDataState _recordsState = DtrReportDataState.idle;
  DtrReportDataState _assignmentsState = DtrReportDataState.idle;
  DtrReportDataState _policyState = DtrReportDataState.idle;
  DtrReportDataState _signatoriesState = DtrReportDataState.idle;

  EmployeeOption? get _selectedReportEmployee {
    for (final employee in _reportEmployees()) {
      if (employee.id == _selectedEmployeeId) return employee;
    }
    return null;
  }

  bool get _hasUnverifiedInactiveAttendance =>
      _assignmentEffectiveFrom != null &&
      _selectedReportEmployee != null &&
      hasUndatedInactiveEmployment(
        employmentStatus: _selectedReportEmployee!.employmentStatus,
      );

  bool get _hasUnverifiedBulkAttendance => _selectedEmployeesForBulk().any(
    (employee) => hasUndatedInactiveEmployment(
      employmentStatus: employee.employmentStatus,
    ),
  );

  DtrReportReadiness get _reportReadiness {
    final selectedAssignments = _assignmentsInSelectedRange;
    final assignmentsState =
        _assignmentsState == DtrReportDataState.ready &&
            (selectedAssignments.isEmpty ||
                !hasCompleteDtrAssignments(selectedAssignments))
        ? DtrReportDataState.missing
        : _assignmentsState;
    final policyState =
        _recordsState == DtrReportDataState.ready &&
            assignmentsState == DtrReportDataState.ready
        ? hasVerifiedDtrPolicyCoverage(
                records: _employeeRecords,
                timeline: _assignmentTimeline,
                year: _selectedYear,
                month: _selectedMonth,
                startDay: _rangeStartDay,
                endDay: _rangeEndDay,
                reportableThrough: _reportableThrough,
              )
              ? DtrReportDataState.ready
              : DtrReportDataState.missing
        : _policyState;
    return DtrReportReadiness(
      employees: _employeesState,
      records: _recordsState,
      assignments: assignmentsState,
      policy: policyState,
      signatories: _signatoriesState,
    );
  }

  /// Historical assignments overlapping the report month, ordered oldest first.
  List<DtrReportAssignment> _assignmentTimeline = const [];

  List<DtrReportAssignment> get _assignmentsInSelectedRange =>
      assignmentsOverlappingDtrRange(
        _assignmentTimeline,
        _rangeStartDate(),
        _rangeEndDate(),
      );

  DtrReportAssignment? get _latestAssignment =>
      _assignmentsInSelectedRange.isEmpty
      ? null
      : _assignmentsInSelectedRange.last;

  List<int>? get _shiftWorkingDays => _assignmentsInSelectedRange.length == 1
      ? _latestAssignment?.workingDays
      : null;
  String? get _shiftOfficialHours => dtrAssignmentHeaderValue(
    _assignmentsInSelectedRange.map((assignment) => assignment.officialHours),
    multipleLabel: 'Multiple schedules (see notes)',
  );
  String? get _reportDepartment => dtrAssignmentHeaderValue(
    _assignmentsInSelectedRange.map((assignment) => assignment.department),
    multipleLabel: 'Multiple departments (see notes)',
  );
  String? get _reportPosition => dtrAssignmentHeaderValue(
    _assignmentsInSelectedRange.map((assignment) => assignment.position),
    multipleLabel: 'Multiple positions (see notes)',
  );
  double? get _shiftWorkHoursPerDay => _assignmentsInSelectedRange.length == 1
      ? _latestAssignment?.workHoursPerDay
      : null;
  String? get _shiftPunchMode => _assignmentsInSelectedRange.length == 1
      ? _latestAssignment?.punchMode
      : null;
  DateTime? get _assignmentEffectiveFrom => _assignmentsInSelectedRange.isEmpty
      ? null
      : _assignmentsInSelectedRange.first.effectiveFrom;
  DateTime? get _assignmentEffectiveTo => _assignmentsInSelectedRange.isEmpty
      ? null
      : _assignmentsInSelectedRange.last.effectiveTo;

  List<DtrAssignmentSegment> get _exportAssignmentSegments =>
      _assignmentsInSelectedRange
          .map(
            (assignment) => DtrAssignmentSegment(
              effectiveFrom: assignment.effectiveFrom,
              effectiveTo: assignment.effectiveTo,
              department: assignment.department,
              position: assignment.position,
              officialHours: assignment.officialHours,
              scheduledWorkHoursPerDay: assignment.workHoursPerDay,
              punchMode: assignment.punchMode,
              overnight: assignment.overnight,
              shiftEndMinutes: assignment.shiftEndMinutes,
              workingDays: assignment.workingDays,
              scheduleOverrides: assignment.scheduleOverrides,
            ),
          )
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadAvailableReportYears();
      if (mounted) await _load();
    });
  }

  @override
  void dispose() {
    _requestGuard.invalidate();
    _searchController.dispose();
    super.dispose();
  }

  EmployeeOption? _selfServiceEmployee() {
    if (!widget.selfService) return null;
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null || user.id.trim().isEmpty) return null;
    final fullName = (user.fullName ?? '').trim();
    return EmployeeOption(
      id: user.id,
      fullName: fullName.isNotEmpty ? fullName : auth.displayName,
      employeeNumber: user.employeeNumber,
      departmentName: user.departmentName,
    );
  }

  List<EmployeeOption> _reportEmployees() {
    final employee = _selfServiceEmployee();
    return widget.selfService
        ? [if (employee != null) employee]
        : _reportEmployeeOptions;
  }

  Future<void> _loadAvailableReportYears() async {
    try {
      final years = await _repository.fetchAvailableReportYears(
        selectedYear: _selectedYear,
      );
      if (!mounted || years.isEmpty) return;
      setState(() => _availableReportYears = years);
    } catch (_) {
      // Keep the report usable with the local fallback if metadata is unavailable.
    }
  }

  bool _acceptsRequest(DtrReportRequestToken token) {
    return mounted &&
        _requestGuard.accepts(
          token,
          employeeId: _selectedEmployeeId,
          departmentId: _selectedDepartmentId,
          employeeStatus: _selectedEmployeeStatus,
          year: _selectedYear,
          month: _selectedMonth,
        );
  }

  Future<void> _load() async {
    final dtr = context.read<DtrProvider>();
    if (widget.selfService) {
      final employee = _selfServiceEmployee();
      if (!mounted) return;
      setState(() {
        _selectedDepartmentId = null;
        _selectedEmployeeId = employee?.id;
        _reportEmployeeOptions = [if (employee != null) employee];
        _employeesState = employee == null
            ? DtrReportDataState.missing
            : DtrReportDataState.ready;
        _selectedEmployeeIds.clear();
        _multiSelectMode = false;
        if (employee == null) {
          _employeeRecords = [];
          _reportableThrough = null;
          _assignmentTimeline = const [];
          _reportSignatories = null;
          _recordsState = DtrReportDataState.idle;
          _assignmentsState = DtrReportDataState.idle;
          _policyState = DtrReportDataState.idle;
          _signatoriesState = DtrReportDataState.idle;
          _reportLoading = false;
        }
      });
      if (employee != null) await _loadEmployeeRecords();
      return;
    }
    final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final monthEnd = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final token = _requestGuard.begin(
      employeeId: _selectedEmployeeId,
      departmentId: _selectedDepartmentId,
      employeeStatus: _selectedEmployeeStatus,
      year: _selectedYear,
      month: _selectedMonth,
    );
    setState(() {
      _reportLoading = true;
      _reportEmployeeOptions = const [];
      _employeeRecords = [];
      _reportableThrough = null;
      _assignmentTimeline = const [];
      _reportSignatories = null;
      _employeesState = DtrReportDataState.loading;
      _recordsState = DtrReportDataState.idle;
      _assignmentsState = DtrReportDataState.idle;
      _policyState = DtrReportDataState.idle;
      _signatoriesState = DtrReportDataState.idle;
    });
    try {
      final employeesFuture = _repository.fetchReportEmployees(
        departmentId: token.departmentId,
        employeeStatus: token.employeeStatus,
        startDate: monthStart,
        endDate: monthEnd,
      );
      final departmentsFuture = dtr.loadDepartments();
      final employees = await employeesFuture;
      await departmentsFuture;
      if (!_acceptsRequest(token)) return;
      if (employees.isNotEmpty) {
        final availableIds = employees.map((e) => e.id).toSet();
        final employeesByDisplayedOrder = List<EmployeeOption>.from(employees)
          ..sort(_compareEmployeesByNumber);
        setState(() {
          _reportEmployeeOptions = List<EmployeeOption>.from(employees);
          _employeesState = DtrReportDataState.ready;
          _selectedEmployeeIds.removeWhere((id) => !availableIds.contains(id));
          if (_selectedEmployeeId == null ||
              !availableIds.contains(_selectedEmployeeId)) {
            _selectedEmployeeId = employeesByDisplayedOrder.first.id;
          }
        });
        await _loadEmployeeRecords();
      } else {
        setState(() {
          _reportEmployeeOptions = const [];
          _selectedEmployeeId = null;
          _selectedEmployeeIds.clear();
          _multiSelectMode = false;
          _employeeRecords = [];
          _reportableThrough = null;
          _assignmentTimeline = const [];
          _reportSignatories = null;
          _employeesState = DtrReportDataState.missing;
          _recordsState = DtrReportDataState.idle;
          _assignmentsState = DtrReportDataState.idle;
          _policyState = DtrReportDataState.idle;
          _signatoriesState = DtrReportDataState.idle;
          _reportLoading = false;
        });
      }
    } catch (_) {
      if (!_acceptsRequest(token)) return;
      setState(() {
        _reportEmployeeOptions = const [];
        _selectedEmployeeId = null;
        _employeeRecords = [];
        _reportableThrough = null;
        _assignmentTimeline = const [];
        _reportSignatories = null;
        _employeesState = DtrReportDataState.failed;
        _recordsState = DtrReportDataState.idle;
        _assignmentsState = DtrReportDataState.idle;
        _policyState = DtrReportDataState.idle;
        _signatoriesState = DtrReportDataState.idle;
        _reportLoading = false;
      });
    }
  }

  Future<void> _loadEmployeeRecords() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) {
      _requestGuard.invalidate();
      if (mounted) {
        setState(() {
          _employeeRecords = [];
          _reportableThrough = null;
          _assignmentTimeline = const [];
          _reportSignatories = null;
          _recordsState = DtrReportDataState.idle;
          _assignmentsState = DtrReportDataState.idle;
          _policyState = DtrReportDataState.idle;
          _signatoriesState = DtrReportDataState.idle;
          _reportLoading = false;
        });
      }
      return;
    }
    _clampRangeToSelectedMonth();
    final year = _selectedYear;
    final month = _selectedMonth;
    final token = _requestGuard.begin(
      employeeId: employeeId,
      departmentId: _selectedDepartmentId,
      employeeStatus: _selectedEmployeeStatus,
      year: year,
      month: month,
    );
    setState(() {
      _reportLoading = true;
      _employeeRecords = [];
      _reportableThrough = null;
      _assignmentTimeline = const [];
      _reportSignatories = null;
      _recordsState = DtrReportDataState.loading;
      _assignmentsState = DtrReportDataState.loading;
      _policyState = DtrReportDataState.loading;
      _signatoriesState = DtrReportDataState.loading;
    });
    final loaded = await _repository.fetchEmployeeReport(
      employeeId,
      year: year,
      month: month,
    );
    final recordsResult = loaded.records;
    final assignmentResult = loaded.assignments;
    final signatoriesResult = loaded.signatories;
    if (!_acceptsRequest(token)) return;

    final recordsPage = recordsResult.value;
    final records = recordsPage?.items ?? const <TimeRecord>[];
    final timeline = assignmentResult.value ?? const <DtrReportAssignment>[];
    final assignmentsState = !assignmentResult.succeeded
        ? DtrReportDataState.failed
        : timeline.isEmpty
        ? DtrReportDataState.missing
        : DtrReportDataState.ready;
    final policyState =
        !recordsResult.succeeded || assignmentsState != DtrReportDataState.ready
        ? DtrReportDataState.idle
        : hasVerifiedDtrPolicyCoverage(
            records: records,
            timeline: timeline,
            year: year,
            month: month,
            reportableThrough: recordsPage?.reportableThrough,
          )
        ? DtrReportDataState.ready
        : DtrReportDataState.missing;

    setState(() {
      _employeeRecords = List<TimeRecord>.from(records);
      _reportableThrough = recordsPage?.reportableThrough;
      _assignmentTimeline = timeline;
      _reportSignatories = signatoriesResult.value;
      _recordsState = recordsResult.succeeded
          ? DtrReportDataState.ready
          : DtrReportDataState.failed;
      _assignmentsState = assignmentsState;
      _policyState = policyState;
      _signatoriesState = !signatoriesResult.succeeded
          ? DtrReportDataState.failed
          : signatoriesResult.value?.isConfigured == true
          ? DtrReportDataState.ready
          : DtrReportDataState.missing;
      _reportLoading = false;
    });
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
      _selectedEmployeeStatus = reportEmployeeStatusForPeriod(
        year: _selectedYear,
        month: _selectedMonth,
        today: DateTime.now(),
        manualStatus: _manualEmployeeStatus,
      );
      _rangeStartDay = 1;
      _rangeEndDay = _daysInSelectedMonth();
    });
    _load();
  }

  void _setSelectedYear(int year) {
    setState(() {
      _selectedYear = year;
      _selectedEmployeeStatus = reportEmployeeStatusForPeriod(
        year: _selectedYear,
        month: _selectedMonth,
        today: DateTime.now(),
        manualStatus: _manualEmployeeStatus,
      );
      _rangeStartDay = 1;
      _rangeEndDay = _daysInSelectedMonth();
    });
    _load();
  }

  bool _isScheduledWorkDay(DateTime dt) {
    return !_hasUnverifiedInactiveAttendance &&
        isDtrScheduledWorkDay(dt, _assignmentTimeline);
  }

  Map<DateTime, TimeRecord> _filterRecordsForTardinessReport(
    Map<DateTime, TimeRecord> raw,
  ) {
    return filterDtrReportRecords(raw, _assignmentTimeline);
  }

  /// Last server-finalized date included in report statistics and missing-day inference.
  DateTime _tardinessStatsInclusiveEnd() {
    final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final reportEnd = _rangeEndDate();
    final monthEnd = DateTime(_selectedYear, _selectedMonth, lastDay);
    final authoritativeEnd = _reportableThrough;
    if (authoritativeEnd == null) {
      return monthStart.subtract(const Duration(days: 1));
    }
    final finalized = DateTime(
      authoritativeEnd.year,
      authoritativeEnd.month,
      authoritativeEnd.day,
    );
    if (monthEnd.isBefore(finalized)) {
      return reportEnd.isBefore(monthEnd) ? reportEnd : monthEnd;
    }
    if (finalized.isBefore(monthStart)) {
      return monthStart.subtract(const Duration(days: 1));
    }
    final capped = finalized.isAfter(monthEnd) ? monthEnd : finalized;
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
      _selectedEmployeeStatus = 'Active';
      _manualEmployeeStatus = null;
      _selectedEmployeeIds.clear();
      _multiSelectMode = false;
    });
    _load();
  }

  DtrReportDocumentActions get _documentActions => DtrReportDocumentActions(
    year: _selectedYear,
    month: _selectedMonth,
    signatories: _reportSignatories!,
    department: _reportDepartment,
    position: _reportPosition,
    officialHours: _shiftOfficialHours,
    scheduledWorkHoursPerDay: _shiftWorkHoursPerDay,
    punchMode: _shiftPunchMode,
    workingDays: _shiftWorkingDays,
    assignmentEffectiveFrom: _assignmentEffectiveFrom,
    assignmentEffectiveTo: _assignmentEffectiveTo,
    assignmentSegments: _exportAssignmentSegments,
    reportableThrough: _reportableThrough,
  );

  Future<void> _generateDtr(
    BuildContext context,
    DtrReportExportFormat format, {
    required String selectedName,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) async {
    if (!_guardOfficialReportAction()) return;
    await _documentActions.generateDtr(
      context,
      format,
      selectedName: selectedName,
      start: start,
      end: end,
      recordsByDate: recordsByDate,
    );
  }

  Future<void> _previewDtrReport(
    BuildContext context, {
    required String selectedName,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? department,
    String? position,
  }) async {
    if (!_guardOfficialReportAction()) return;
    await _documentActions.previewDtrReport(
      context,
      selectedName: selectedName,
      start: start,
      end: end,
      recordsByDate: recordsByDate,
      department: department,
      position: position,
    );
  }

  Future<void> _printDtrReport(
    BuildContext context, {
    required String selectedName,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? department,
    String? position,
  }) async {
    if (!_guardOfficialReportAction()) return;
    await _documentActions.printDtrReport(
      context,
      selectedName: selectedName,
      start: start,
      end: end,
      recordsByDate: recordsByDate,
      department: department,
      position: position,
    );
  }

  void _showReportSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  bool get _officialActionsEnabled =>
      _reportReadiness.canGenerateOfficialReport &&
      _reportSignatories != null &&
      !_hasUnverifiedInactiveAttendance &&
      !_reportLoading;

  bool _guardOfficialReportAction() {
    if (_officialActionsEnabled) return true;
    if (_hasUnverifiedInactiveAttendance) {
      _showReportSnack(
        'Attendance is unverified: employment is marked inactive without a dated end, but the assignment is still open. Record the last day of service before exporting.',
        backgroundColor: Colors.red.shade700,
      );
      return false;
    }
    final issues = _reportReadiness.blockingIssues;
    final message = _reportReadiness.isLoading || _reportLoading
        ? 'Official report data is still being verified.'
        : issues.isNotEmpty
        ? issues.first
        : 'Official report data is not ready. Retry loading the report.';
    _showReportSnack(message, backgroundColor: Colors.red.shade700);
    return false;
  }

  Widget _buildReadinessBanner(BuildContext context) {
    final issues = _reportReadiness.blockingIssues;
    if (issues.isEmpty) return const SizedBox.shrink();
    final dark = AppTheme.dashIsDark(context);
    final borderColor = Colors.orange.withValues(alpha: dark ? 0.75 : 0.55);
    final backgroundColor = Colors.orange.withValues(alpha: dark ? 0.12 : 0.08);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Official report unavailable',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final issue in issues)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            issue,
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _reportLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
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
    if (widget.selfService) return;
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

  List<EmployeeOption> _selectedEmployeesForBulk() {
    if (widget.selfService) return const <EmployeeOption>[];
    final byId = {for (final e in _reportEmployeeOptions) e.id: e};
    return _selectedEmployeeIds
        .map((id) => byId[id])
        .whereType<EmployeeOption>()
        .toList()
      ..sort(_compareEmployeesByNumber);
  }

  int _compareEmployeesByNumber(EmployeeOption a, EmployeeOption b) {
    int compareNatural(String left, String right) {
      final leftParts = RegExp(r'\d+|\D+').allMatches(left.toUpperCase());
      final rightParts = RegExp(r'\d+|\D+').allMatches(right.toUpperCase());
      final leftValues = leftParts.map((match) => match.group(0)!).toList();
      final rightValues = rightParts.map((match) => match.group(0)!).toList();
      final count = leftValues.length < rightValues.length
          ? leftValues.length
          : rightValues.length;
      for (var i = 0; i < count; i++) {
        final leftNumber = int.tryParse(leftValues[i]);
        final rightNumber = int.tryParse(rightValues[i]);
        final comparison = leftNumber != null && rightNumber != null
            ? leftNumber.compareTo(rightNumber)
            : leftValues[i].compareTo(rightValues[i]);
        if (comparison != 0) return comparison;
      }
      return leftValues.length.compareTo(rightValues.length);
    }

    final byNumber = compareNatural(a.displayEmployeeNo, b.displayEmployeeNo);
    if (byNumber != 0) return byNumber;
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  }

  void _onReportEmployeeTap(EmployeeOption e) {
    if (_multiSelectMode) {
      _toggleEmployeeSelection(e);
    } else {
      setState(() => _selectedEmployeeId = e.id);
      _loadEmployeeRecords();
    }
  }

  Future<Uint8List> _buildSelectedDtrPdf({
    PdfPageFormat pageFormat = PdfPageFormat.legal,
  }) async {
    final buildPdf = await _prepareSelectedDtrPdf();
    return buildPdf(pageFormat);
  }

  Future<LayoutCallback> _prepareSelectedDtrPdf() =>
      DtrReportBulkExporter(
        repository: _repository,
        year: _selectedYear,
        month: _selectedMonth,
        start: _rangeStartDate(),
        end: _rangeEndDate(),
        signatories: _reportSignatories!,
      ).prepare(
        selected: _selectedEmployeesForBulk(),
        onProgress: (prepared, total) {
          if (!mounted) return;
          setState(() {
            _bulkExportPrepared = prepared;
            _bulkExportTotal = total;
          });
        },
      );

  Future<void> _printSelectedDtrs(BuildContext context) async {
    if (_bulkExportBusy) return;
    if (!_guardOfficialReportAction()) return;
    final selectedCount = _selectedEmployeesForBulk().length;
    if (selectedCount < 2) {
      _showReportSnack('Select at least two employees to bulk print.');
      return;
    }
    final pageFormat = await chooseDtrReportPaperSize(context);
    if (pageFormat == null || !context.mounted) return;
    setState(() => _bulkExportBusy = true);
    Uint8List? bytes;
    try {
      _showReportSnack('Preparing $selectedCount selected DTRs...');
      final buildPdf = await _prepareSelectedDtrPdf();
      bytes = await buildPdf(pageFormat);
      if (!context.mounted) return;
      await Printing.layoutPdf(
        onLayout: buildPdf,
        name:
            'DTR_Selected_${dtrReportMonths[_selectedMonth - 1]}_$_selectedYear',
        format: pageFormat,
      );
      if (!context.mounted) return;
      _showReportSnack('Selected DTRs sent to print.');
    } catch (e) {
      if (!context.mounted) return;
      if (bytes != null) {
        await shareOrDownloadPdf(
          bytes,
          'DTR_Selected_${dtrReportMonths[_selectedMonth - 1]}_$_selectedYear.pdf',
        );
        _showReportSnack('Print dialog not available. PDF shared instead.');
      } else {
        _showReportSnack('Bulk print failed: $e', backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _bulkExportBusy = false;
          _bulkExportPrepared = 0;
          _bulkExportTotal = 0;
        });
      }
    }
  }

  Future<void> _exportSelectedDtrs() async {
    if (_bulkExportBusy) return;
    if (!_guardOfficialReportAction()) return;
    final selectedCount = _selectedEmployeesForBulk().length;
    if (selectedCount < 2) {
      _showReportSnack('Select at least two employees to export.');
      return;
    }
    setState(() => _bulkExportBusy = true);
    try {
      _showReportSnack('Exporting $selectedCount selected DTRs...');
      final bytes = await _buildSelectedDtrPdf();
      await shareOrDownloadPdf(
        bytes,
        'DTR_Selected_${dtrReportMonths[_selectedMonth - 1]}_$_selectedYear.pdf',
      );
      _showReportSnack('Selected DTRs exported as PDF.');
    } catch (e) {
      _showReportSnack('Bulk export failed: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _bulkExportBusy = false;
          _bulkExportPrepared = 0;
          _bulkExportTotal = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<DtrProvider>();
    final search = _searchController.text.toLowerCase();
    final reportEmployees = _reportEmployees();
    final employees =
        reportEmployees
            .where(
              (e) =>
                  search.isEmpty ||
                  e.fullName.toLowerCase().contains(search) ||
                  e.displayEmployeeNo.toLowerCase().contains(search),
            )
            .toList()
          ..sort(_compareEmployeesByNumber);
    final selectedList = employees
        .where((e) => e.id == _selectedEmployeeId)
        .toList();
    final selectedEmp = selectedList.isNotEmpty ? selectedList.first : null;
    String selectedName = selectedEmp?.fullName ?? 'Select an employee';
    if (selectedName == 'Select an employee' && _selectedEmployeeId != null) {
      final byId = reportEmployees
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
        (e) =>
            !e.key.isBefore(start) &&
            !e.key.isAfter(end) &&
            (!_hasUnverifiedInactiveAttendance ||
                !isSyntheticAbsentRow(id: e.value.id, status: e.value.status)),
      ),
    );
    // Display the selected calendar range in the report. Non-working days without
    // records are quiet placeholders only; they are not saved or counted.
    final hasAssignment = _assignmentEffectiveFrom != null;
    final shouldShowCalendarRows =
        _selectedEmployeeId != null &&
        ((hasAssignment && !_hasUnverifiedInactiveAttendance) ||
            rangedRecordsByDate.isNotEmpty);
    final sortedDates = shouldShowCalendarRows
        ? _hasUnverifiedInactiveAttendance
              ? (rangedRecordsByDate.keys.toList()..sort())
              : _calendarDatesInSelectedRange(end)
        : <DateTime>[];

    // Compute summary from real API records, using shift + assignment window when available.
    // Only count days up to today (elapsed) — future days in the month are not "absent" yet.
    final statsEnd = _tardinessStatsInclusiveEnd();
    final totalWeekdays = _countScheduledWorkDaysThrough(statsEnd);
    var absentCount = 0;
    var holidaysCount = 0;
    var untrackedCount = 0;
    for (var d = _rangeStartDay; d <= end.day; d++) {
      final dt = DateTime(_selectedYear, _selectedMonth, d);
      if (!_isScheduledWorkDay(dt)) continue;
      if (dt.isAfter(statsEnd)) continue;
      final rec = rangedRecordsByDate[dt];
      if(rec?.status=='not_tracked') {untrackedCount++;continue;}
      if (rec?.status == 'holiday' || (rec?.holidayId != null)) {
        holidaysCount++;
      } else if (rec?.status == 'on_leave') {
        // On leave: not absent for tardiness
      } else if (rec == null ||
          (rec.timeIn == null &&
              rec.breakIn == null &&
              !isCompletedAttendanceRecord(rec))) {
        absentCount++;
      }
    }
    // Show summary whenever this month has any report rows — not only days with punches.
    // (Absent / undertime-only days have no timeIn/breakIn but must still roll up to totals.)
    final hasRecords =
        rangedRecordsByDate.isNotEmpty ||
        (hasAssignment && !_hasUnverifiedInactiveAttendance);
    final workingDays = hasRecords ? totalWeekdays - holidaysCount - untrackedCount : 0;
    final displayAbsentCount = hasRecords ? absentCount : 0;

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
                        widget.selfService
                            ? 'My DTR Report'
                            : 'Tardiness Report',
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: isMobile ? 20 : 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.selfService
                            ? 'Review and export your attendance by date range.'
                            : 'Review employee late arrivals and undertime by date range, department, and employee.',
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFilters(context, isMobile),
                      if (_reportReadiness.blockingIssues.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildReadinessBanner(context),
                      ],
                      if (_hasUnverifiedInactiveAttendance) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Attendance unverified: employment is marked inactive without a dated end, but the assignment is still open. Missing days are not counted as absent. Record the last day of service to finalize the DTR.',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 13,
                          ),
                        ),
                      ],
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
                              absentCount: displayAbsentCount,
                              totalLateMinutes: displayTotalLateMinutes,
                              totalUndertimeMinutes:
                                  displayTotalUndertimeMinutes,
                              hasRecords: hasRecords,
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
                              absentCount: displayAbsentCount,
                              totalLateMinutes: displayTotalLateMinutes,
                              totalUndertimeMinutes:
                                  displayTotalUndertimeMinutes,
                              hasRecords: hasRecords,
                            )
                          : SizedBox(
                              height: 520,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!widget.selfService) ...[
                                    _buildEmployeeList(context, employees),
                                    const SizedBox(width: 16),
                                  ],
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
                                                availableWidth:
                                                    tableAvailableWidth,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            _buildSummaryCard(
                                              selectedName: selectedName,
                                              workingDays: workingDays,
                                              absentCount: displayAbsentCount,
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

  bool _canViewHabitualAttendance() {
    if (widget.selfService) return false;
    try {
      final role = context.read<AuthProvider>().user?.role;
      return role == 'admin' || role == 'hr';
    } on ProviderNotFoundException {
      return false;
    }
  }

  Widget _buildFilters(BuildContext context, bool isMobile) => DtrReportFilters(
    isMobile: isMobile,
    selfService: widget.selfService,
    searchController: _searchController,
    departments: context.read<DtrProvider>().departments,
    selectedDepartmentId: _selectedDepartmentId,
    selectedEmployeeStatus: _selectedEmployeeStatus,
    selectedMonth: _selectedMonth,
    selectedYear: _selectedYear,
    availableReportYears: _availableReportYears,
    rangeStartDay: _rangeStartDay,
    rangeEndDay: _rangeEndDay,
    selectedCount: _selectedEmployeesForBulk().length,
    bulkExportBusy: _bulkExportBusy,
    bulkExportPrepared: _bulkExportPrepared,
    bulkExportTotal: _bulkExportTotal,
    officialActionsEnabled: _officialActionsEnabled,
    hasUnverifiedBulkAttendance: _hasUnverifiedBulkAttendance,
    onSearchChanged: (_) => setState(() {}),
    onDepartmentChanged: (value) {
      setState(() => _selectedDepartmentId = value);
      _load();
    },
    onEmployeeStatusChanged: (value) {
      setState(() {
        _selectedEmployeeStatus = value;
        _manualEmployeeStatus = value;
      });
      _load();
    },
    onMonthChanged: _setSelectedMonth,
    onYearChanged: _setSelectedYear,
    onRangeStartChanged: (value) => setState(() {
      _rangeStartDay = value;
      if (_rangeEndDay < value) _rangeEndDay = value;
    }),
    onRangeEndChanged: (value) => setState(() => _rangeEndDay = value),
    onReset: _reset,
    onBulkPrint: () => _printSelectedDtrs(context),
    onBulkExport: _exportSelectedDtrs,
    onHabitualAttendance: !_canViewHabitualAttendance()
        ? null
        : () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HabitualAttendancePage(
                departments: context.read<DtrProvider>().departments,
              ),
            ),
          ),
  );

  Widget _buildMobileLayout({
    required BuildContext context,
    required List<EmployeeOption> employees,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required List<DateTime> sortedDates,
    required String selectedName,
    required int workingDays,
    required int absentCount,
    required int totalLateMinutes,
    required int totalUndertimeMinutes,
    required bool hasRecords,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.selfService) ...[
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
                          e.isActive
                              ? e.fullName
                              : '${e.fullName} (${e.currentStatusLabel})',
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
        ],
        SizedBox(
          height: 320,
          child: _buildDtrTable(
            context,
            end: end,
            recordsByDate: recordsByDate,
            sortedDates: sortedDates,
            compactColumns: true,
          ),
        ),
        const SizedBox(height: 16),
        _buildSummaryCard(
          selectedName: selectedName,
          workingDays: workingDays,
          absentCount: absentCount,
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
    return DtrEmployeeSelectionToolbar(
      employees: employees,
      selectedEmployeeIds: _selectedEmployeeIds,
      multiSelectMode: _multiSelectMode,
      bulkExportBusy: _bulkExportBusy,
      bulkExportPrepared: _bulkExportPrepared,
      bulkExportTotal: _bulkExportTotal,
      onSelectAll: () => _selectAllFilteredEmployees(employees),
      onClear: _clearSelectedEmployees,
      onExit: _exitMultiSelectMode,
      compact: compact,
    );
  }

  Widget _buildEmployeeList(
    BuildContext context,
    List<EmployeeOption> employees,
  ) {
    return DtrReportEmployeeList(
      loading: _employeesState == DtrReportDataState.loading,
      employees: employees,
      selectedEmployeeId: _selectedEmployeeId,
      checkedEmployeeIds: _selectedEmployeeIds,
      multiSelectMode: _multiSelectMode,
      toolbar: _buildEmployeeSelectionToolbar(context, employees),
      onEmployeeTap: _onReportEmployeeTap,
      onCheckedChanged: _setEmployeeBulkSelected,
    );
  }

  Widget _buildDtrTable(
    BuildContext context, {
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required List<DateTime> sortedDates,
    bool compactColumns = false,
    double? availableWidth,
  }) {
    return DtrReportTable(
      end: end,
      recordsByDate: recordsByDate,
      sortedDates: sortedDates,
      compactColumns: compactColumns,
      availableWidth: availableWidth,
      showMinutesFormat: _showMinutesFormat,
      shiftPunchMode: _shiftPunchMode,
      reportLoading: _reportLoading,
      statsInclusiveEnd: _tardinessStatsInclusiveEnd(),
      isScheduledWorkDay: _isScheduledWorkDay,
      assignmentEffectiveFrom: _assignmentEffectiveFrom,
    );
  }

  Widget _buildSummaryCard({
    required String selectedName,
    required int workingDays,
    required int absentCount,
    required int totalLateMinutes,
    required int totalUndertimeMinutes,
    bool hasRecords = true,
    bool fullWidth = false,
    bool isResponsive = false,
    bool dense = false,
    required Map<DateTime, TimeRecord> recordsByDate,
    required DateTime start,
    required DateTime end,
  }) {
    void exportAs(DtrReportExportFormat format) => _generateDtr(
      context,
      format,
      selectedName: selectedName,
      start: start,
      end: end,
      recordsByDate: recordsByDate,
    );
    return DtrReportSummaryCard(
      loading: _reportLoading || _employeesState == DtrReportDataState.loading,
      selectedName: selectedName,
      periodLabel: '${dtrReportMonths[_selectedMonth - 1]}, $_selectedYear',
      workingDays: workingDays,
      absentCount: absentCount,
      totalLateMinutes: totalLateMinutes,
      totalUndertimeMinutes: totalUndertimeMinutes,
      hideCounts: _hasUnverifiedInactiveAttendance,
      showMinutesFormat: _showMinutesFormat,
      onShowMinutesFormatChanged: (value) =>
          setState(() => _showMinutesFormat = value),
      resolveEquivalentDay: () => summaryEquivalentDay(
        employeeId: _selectedEmployeeId,
        hasRecords: hasRecords,
        hasUnverifiedInactiveAttendance: _hasUnverifiedInactiveAttendance,
        calculate: () => DtrExport.calculateOfficialTotals(
          year: _selectedYear,
          month: _selectedMonth,
          start: start,
          end: end,
          recordsByDate: recordsByDate,
          scheduledWorkHoursPerDay: _shiftWorkHoursPerDay,
          workingDays: _shiftWorkingDays,
          assignmentEffectiveFrom: _assignmentEffectiveFrom,
          assignmentEffectiveTo: _assignmentEffectiveTo,
          assignmentSegments: _exportAssignmentSegments,
          reportableThrough: _reportableThrough,
        ).equivalentDay,
      ),
      actionsEnabled: _officialActionsEnabled,
      onPreview: () => _previewDtrReport(
        context,
        selectedName: selectedName,
        start: start,
        end: end,
        recordsByDate: recordsByDate,
      ),
      onPrint: () => _printDtrReport(
        context,
        selectedName: selectedName,
        start: start,
        end: end,
        recordsByDate: recordsByDate,
      ),
      onExportPdf: () => exportAs(DtrReportExportFormat.pdf),
      onExportWord: () => exportAs(DtrReportExportFormat.word),
      onExportExcel: () => exportAs(DtrReportExportFormat.excel),
      fullWidth: fullWidth,
      isResponsive: isResponsive,
      dense: dense,
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
    required int absentCount,
    required int totalLateMinutes,
    required int totalUndertimeMinutes,
    required bool hasRecords,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 800.0;
        final summaryPanelWidth = (availableWidth * 0.43)
            .clamp(330.0, 420.0)
            .toDouble();
        final topPanelHeight = availableWidth < 760 ? 380.0 : 360.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: topPanelHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.selfService) ...[
                    Expanded(
                      child: _buildEmployeeListCompact(context, employees),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (widget.selfService)
                    Expanded(
                      child: _buildSummaryCard(
                        selectedName: selectedName,
                        workingDays: workingDays,
                        absentCount: absentCount,
                        totalLateMinutes: totalLateMinutes,
                        totalUndertimeMinutes: totalUndertimeMinutes,
                        hasRecords: hasRecords,
                        fullWidth: true,
                        isResponsive: true,
                        dense: true,
                        recordsByDate: recordsByDate,
                        start: start,
                        end: end,
                      ),
                    )
                  else
                    SizedBox(
                      width: summaryPanelWidth,
                      child: _buildSummaryCard(
                        selectedName: selectedName,
                        workingDays: workingDays,
                        absentCount: absentCount,
                        totalLateMinutes: totalLateMinutes,
                        totalUndertimeMinutes: totalUndertimeMinutes,
                        hasRecords: hasRecords,
                        fullWidth: true,
                        isResponsive: true,
                        dense: true,
                        recordsByDate: recordsByDate,
                        start: start,
                        end: end,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 350,
              child: _buildDtrTable(
                context,
                end: end,
                recordsByDate: recordsByDate,
                sortedDates: sortedDates,
                availableWidth: availableWidth,
              ),
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
    return DtrReportEmployeeList(
      loading: _employeesState == DtrReportDataState.loading,
      employees: employees,
      selectedEmployeeId: _selectedEmployeeId,
      checkedEmployeeIds: _selectedEmployeeIds,
      multiSelectMode: _multiSelectMode,
      toolbar: _buildEmployeeSelectionToolbar(
        context,
        employees,
        compact: true,
      ),
      onEmployeeTap: _onReportEmployeeTap,
      onCheckedChanged: _setEmployeeBulkSelected,
      compact: true,
    );
  }
}

class _ToggleDtrMultiSelectIntent extends Intent {
  const _ToggleDtrMultiSelectIntent();
}

class _ExitDtrMultiSelectIntent extends Intent {
  const _ExitDtrMultiSelectIntent();
}
