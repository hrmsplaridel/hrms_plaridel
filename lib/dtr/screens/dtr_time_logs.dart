import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../data/time_record.dart';
import '../../providers/auth_provider.dart';
import '../dtr_provider.dart';
import '../widgets/attendance_source_badge.dart';
import '../widgets/import_biometric_attendance_logs_dialog.dart';

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

/// Badge/chip for attendance remark. Government-style clean styling.
class _RemarksChip extends StatelessWidget {
  const _RemarksChip({required this.remark, this.isHoliday = false});

  final String remark;
  final bool isHoliday;

  @override
  Widget build(BuildContext context) {
    final (color, bg) = _colorsForRemark(remark, isHoliday: isHoliday);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        remark,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static (Color color, Color bg) _colorsForRemark(
    String r, {
    bool isHoliday = false,
  }) {
    if (isHoliday) return (Colors.purple.shade700, Colors.purple.shade50);
    switch (r) {
      case 'On Time':
        return (Colors.green.shade800, Colors.green.shade50);
      case 'Late':
        return (Colors.red.shade800, Colors.red.shade50);
      case 'Undertime':
        return (Colors.orange.shade800, Colors.orange.shade50);
      case 'Late + Undertime':
        return (Colors.deepOrange.shade800, Colors.deepOrange.shade50);
      case 'Absent':
        return (Colors.orange.shade700, Colors.orange.shade50);
      case 'Holiday':
        return (Colors.purple.shade700, Colors.purple.shade50);
      case 'Leave':
        return (Colors.blue.shade700, Colors.blue.shade50);
      case 'Incomplete':
        return (Colors.amber.shade800, Colors.amber.shade50);
      case 'Invalid Log':
        return (Colors.red.shade900, Colors.red.shade100);
      default:
        if (r.toLowerCase().contains('leave'))
          return (Colors.blue.shade700, Colors.blue.shade50);
        return (AppTheme.textPrimary, AppTheme.lightGray.withOpacity(0.5));
    }
  }
}

/// Admin Time Logs: list, filters, add/edit/delete.
class DtrTimeLogs extends StatefulWidget {
  const DtrTimeLogs({super.key});

  @override
  State<DtrTimeLogs> createState() => _DtrTimeLogsState();
}

class _DtrTimeLogsState extends State<DtrTimeLogs> {
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  /// When non-null and >= 1, filter to this day only (realtime-style single-day view).
  int? _selectedDay;
  String? _selectedUserId;
  String? _selectedDepartmentId;
  final bool _showHardcodedPreview = false;
  bool _bannerDismissed = false;

  /// Last day of the currently selected month (1–31).
  int get _lastDayOfSelectedMonth {
    final end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    return end.day;
  }

  /// Intended filter range based on current month/year/day selection.
  (DateTime, DateTime) _getIntendedFilterRange() {
    final lastDay = _lastDayOfSelectedMonth;
    final int day =
        (_selectedDay != null && _selectedDay! >= 1 && _selectedDay! <= lastDay)
        ? _selectedDay!
        : 0;
    if (day >= 1) {
      final d = DateTime(_selectedYear, _selectedMonth, day);
      return (d, d);
    }
    return (
      DateTime(_selectedYear, _selectedMonth, 1),
      DateTime(_selectedYear, _selectedMonth + 1, 0),
    );
  }

  /// True if provider's filter range matches our intended range. Prevents showing
  /// stale data from DtrDashboard (no date filter) or DtrReports (month range)
  /// when Time Logs expects a different range.
  bool _providerFilterMatches(DtrProvider dtr) {
    final (intendedStart, intendedEnd) = _getIntendedFilterRange();
    final start = dtr.filterStart;
    final end = dtr.filterEnd;
    if (start == null || end == null) return false;
    return start.year == intendedStart.year &&
        start.month == intendedStart.month &&
        start.day == intendedStart.day &&
        end.year == intendedEnd.year &&
        end.month == intendedEnd.month &&
        end.day == intendedEnd.day;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = now.day;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // Auto-refresh every 30s so new time-in/time-out shows without manual refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _applyFilters(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final dtr = context.read<DtrProvider>();
    await Future.wait([dtr.loadEmployees(), dtr.loadDepartments()]);
    if (!mounted) return;
    await _applyFilters();
  }

  Future<void> _applyFilters({bool silent = false}) async {
    if (!mounted) return;
    final dtr = context.read<DtrProvider>();
    final lastDay = _lastDayOfSelectedMonth;
    final int day =
        (_selectedDay != null && _selectedDay! >= 1 && _selectedDay! <= lastDay)
        ? _selectedDay!
        : 0;
    final DateTime start;
    final DateTime end;
    if (day >= 1) {
      start = DateTime(_selectedYear, _selectedMonth, day);
      end = start;
    } else {
      start = DateTime(_selectedYear, _selectedMonth, 1);
      end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    }
    await dtr.loadTimeRecordsForAdmin(
      startDate: start,
      endDate: end,
      userId: _selectedUserId?.isEmpty == true ? null : _selectedUserId,
      departmentId: _selectedDepartmentId?.isEmpty == true
          ? null
          : _selectedDepartmentId,
      silent: silent,
    );
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

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Fallback attendance remark when backend does not send attendanceRemark (e.g. hardcoded preview).
  /// Backend sends shift-aware attendance_remark; this is a simple fallback.
  static String getAttendanceRemark(TimeRecord r) {
    if (r.attendanceRemark != null && r.attendanceRemark!.isNotEmpty)
      return r.attendanceRemark!;
    if (r.status == 'holiday' || r.holidayId != null)
      return r.holidayName ?? 'Holiday';
    if (r.status == 'on_leave' || r.leaveRequestId != null)
      return r.leaveTypeName ?? 'Leave';
    final hasAnyLog =
        r.timeIn != null ||
        r.breakOut != null ||
        r.breakIn != null ||
        r.timeOut != null;
    if (!hasAnyLog) return 'Absent';
    if (r.status == 'invalid') return 'Invalid Log';
    // Without shift info, treat as full-day (require all 4) for fallback
    final hasAllFour =
        r.timeIn != null &&
        r.breakOut != null &&
        r.breakIn != null &&
        r.timeOut != null;
    if (!hasAllFour) return 'Incomplete';
    final late = (r.lateMinutes ?? 0) > 0;
    final under = (r.undertimeMinutes ?? 0) > 0;
    if (late && under) return 'Late + Undertime';
    if (late) return 'Late';
    if (under) return 'Undertime';
    return 'On Time';
  }

  /// Display late minutes: "X min", "0 min", or "—" for holiday/leave.
  static String formatLateMinutes(TimeRecord r) {
    if (r.status == 'holiday' ||
        r.holidayId != null ||
        r.status == 'on_leave' ||
        r.leaveRequestId != null)
      return '—';
    final m = r.lateMinutes ?? 0;
    return m == 0 ? '0 min' : '$m min';
  }

  /// Display undertime minutes: "X min", "0 min", or "—" for holiday/leave.
  static String formatUndertimeMinutes(TimeRecord r) {
    if (r.status == 'holiday' ||
        r.holidayId != null ||
        r.status == 'on_leave' ||
        r.leaveRequestId != null)
      return '—';
    final m = r.undertimeMinutes ?? 0;
    return m == 0 ? '0 min' : '$m min';
  }

  Widget _headerLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppTheme.textPrimary,
      ),
    );
  }

  List<TimeRecord> _getDisplayRecords(DtrProvider dtr) {
    if (dtr.loading) return [];
    // Don't show records when filter range doesn't match our selection (avoids
    // displaying stale data from DtrDashboard or DtrReports that overwrote
    // _timeRecords with a different date range).
    if (!_providerFilterMatches(dtr)) return [];
    if (dtr.timeRecords.isNotEmpty) return dtr.timeRecords;
    if (_showHardcodedPreview) return _hardcodedSampleRecords();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final auth = context.watch<AuthProvider>();
    final search = _searchController.text.toLowerCase();
    final isAdmin = (auth.user?.role ?? 'employee') == 'admin';
    final displayRecords = _getDisplayRecords(dtr).where((r) {
      if (search.isEmpty) return true;
      return (r.employeeName ?? '').toLowerCase().contains(search);
    }).toList();
    final isHardcodedPreview =
        dtr.timeRecords.isEmpty && displayRecords.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
          if (_selectedDay != null && _selectedDay! >= 1) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.today_rounded,
                  size: 16,
                  color: AppTheme.primaryNavy,
                ),
                const SizedBox(width: 6),
                Text(
                  _selectedMonth == DateTime.now().month &&
                          _selectedYear == DateTime.now().year &&
                          _selectedDay == DateTime.now().day
                      ? "Showing today's time logs (realtime view)"
                      : 'Showing time logs for ${_formatDate(DateTime(_selectedYear, _selectedMonth, _selectedDay!))}',
                  style: TextStyle(
                    color: AppTheme.primaryNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
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
                      'Showing sample data. DTR data comes from the backend (dtr_daily_summary). Add records via Clock In or admin Time Logs to see live data.',
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
          SizedBox(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 700;
                final boundedHeight = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 300.0;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: boundedHeight,
                  ),
                  child: Wrap(
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
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 20,
                            ),
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
                          if (v != null) {
                            setState(() {
                              _selectedMonth = v;
                              if (_selectedDay != null &&
                                  _selectedDay! > _lastDayOfSelectedMonth) {
                                _selectedDay = null;
                              }
                            });
                          }
                          _applyFilters();
                        },
                      ),
                      DropdownButton<int>(
                        value: _selectedYear,
                        items:
                            List.generate(
                                  11,
                                  (i) => DateTime.now().year - 5 + i,
                                )
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text('$y'),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _selectedYear = v;
                              if (_selectedDay != null &&
                                  _selectedDay! > _lastDayOfSelectedMonth) {
                                _selectedDay = null;
                              }
                            });
                          }
                          _applyFilters();
                        },
                      ),
                      DropdownButton<int?>(
                        value: _selectedDay,
                        hint: const Text('All days'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All days'),
                          ),
                          ...List.generate(
                            _lastDayOfSelectedMonth,
                            (i) => i + 1,
                          ).map(
                            (d) => DropdownMenuItem<int?>(
                              value: d,
                              child: Text('Day $d'),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedDay = v);
                          _applyFilters();
                        },
                      ),
                      DropdownButton<String?>(
                        value: _selectedDepartmentId,
                        hint: const Text('All departments'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All departments'),
                          ),
                          ...dtr.departments.map(
                            (d) => DropdownMenuItem<String?>(
                              value: d.id,
                              child: Text(d.name),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedDepartmentId = v);
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
                          final now = DateTime.now();
                          setState(() {
                            _searchController.clear();
                            _selectedMonth = now.month;
                            _selectedYear = now.year;
                            _selectedDay = now.day;
                            _selectedUserId = null;
                            _selectedDepartmentId = null;
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
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              if (isAdmin)
                FilledButton.icon(
                  onPressed: _showImportBiometricLogsDialog,
                  icon: const Icon(Icons.file_upload_rounded, size: 18),
                  label: const Text('Import Biometric Logs'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: () => _showAddDialog(context, dtr),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add manual entry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
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
            LayoutBuilder(
              builder: (context, tableConstraints) {
                final tableWidth = tableConstraints.maxWidth.clamp(
                  600.0,
                  double.infinity,
                );
                final contentHeight = (displayRecords.length + 1) * 56.0 + 30;
                final maxHeight = tableConstraints.maxHeight;
                final constrainedHeight = contentHeight.clamp(100.0, maxHeight);
                return Container(
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
                    width: double.infinity,
                    height: constrainedHeight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  24,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.lightGray.withOpacity(0.5),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _headerLabel('Employee'),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: _headerLabel('Date'),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('AM In'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('AM Out'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('PM In'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('PM Out'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('Late'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('Undertime'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Center(
                                        child: _headerLabel('Remarks'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: _headerLabel('Source'),
                                      ),
                                    ),
                                    if (!isHardcodedPreview)
                                      const Expanded(
                                        flex: 1,
                                        child: SizedBox.shrink(),
                                      ),
                                  ],
                                ),
                              ),
                              ...displayRecords.asMap().entries.map((entry) {
                                final i = entry.key;
                                final r = entry.value;
                                final timeIn = r.timeIn?.toLocal();
                                final breakOut = r.breakOut?.toLocal();
                                final breakIn = r.breakIn?.toLocal();
                                final timeOut = r.timeOut?.toLocal();
                                final remark = getAttendanceRemark(r);
                                final lateStr = formatLateMinutes(r);
                                final underStr = formatUndertimeMinutes(r);
                                return Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    24,
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i % 2 == 0
                                        ? AppTheme.white
                                        : AppTheme.lightGray.withOpacity(0.25),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          r.employeeName ?? r.userId,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _formatDate(r.recordDate),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            _formatTime(timeIn),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            _formatTime(breakOut),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            _formatTime(breakIn),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            _formatTime(timeOut),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            lateStr,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            underStr,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Center(
                                          child: _RemarksChip(
                                            remark: remark,
                                            isHoliday:
                                                r.status == 'holiday' ||
                                                r.holidayId != null,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: AttendanceSourceBadge(
                                            source: r.source,
                                            compact: true,
                                          ),
                                        ),
                                      ),
                                      if (!isHardcodedPreview)
                                        Expanded(
                                          flex: 1,
                                          child: Center(
                                            child: PopupMenuButton<String>(
                                              icon: const Icon(
                                                Icons.more_vert,
                                                size: 22,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              tooltip: 'Actions',
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _showEditDialog(
                                                    context,
                                                    dtr,
                                                    r,
                                                  );
                                                } else if (value == 'delete') {
                                                  _confirmDelete(
                                                    context,
                                                    dtr,
                                                    r,
                                                  );
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem<String>(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.edit_rounded,
                                                        size: 20,
                                                        color: AppTheme
                                                            .textPrimary,
                                                      ),
                                                      SizedBox(width: 12),
                                                      Text('Edit'),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem<String>(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.delete_rounded,
                                                        size: 20,
                                                        color:
                                                            Colors.red.shade700,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        'Delete',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .red
                                                              .shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
                  ),
                );
              },
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
    // Use the currently selected day/month/year so manual entry goes to the right date
    final day = _selectedDay;
    final lastDay = _lastDayOfSelectedMonth;
    DateTime recordDate = (day != null && day >= 1 && day <= lastDay)
        ? DateTime(_selectedYear, _selectedMonth, day)
        : DateTime.now();
    TimeOfDay? timeIn;
    TimeOfDay? breakOut;
    TimeOfDay? breakIn;
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
                  title: const Text('AM In'),
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
                  title: const Text('AM Out'),
                  subtitle: Text(
                    breakOut != null
                        ? '${breakOut!.hour.toString().padLeft(2, '0')}:${breakOut!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: breakOut ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => breakOut = t);
                  },
                ),
                ListTile(
                  title: const Text('PM In'),
                  subtitle: Text(
                    breakIn != null
                        ? '${breakIn!.hour.toString().padLeft(2, '0')}:${breakIn!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: breakIn ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => breakIn = t);
                  },
                ),
                ListTile(
                  title: const Text('PM Out'),
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
      DateTime? bo;
      DateTime? bi;
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
      if (breakOut != null) {
        bo = DateTime(
          date.year,
          date.month,
          date.day,
          breakOut!.hour,
          breakOut!.minute,
        );
      }
      if (breakIn != null) {
        bi = DateTime(
          date.year,
          date.month,
          date.day,
          breakIn!.hour,
          breakIn!.minute,
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
      if (tin != null && bo != null && bi != null && tout != null) {
        hours =
            (bo.difference(tin).inMinutes + tout.difference(bi).inMinutes) /
            60.0;
      } else if (tin != null && tout != null) {
        hours = tout.difference(tin).inMinutes / 60.0;
      }
      final record = TimeRecord(
        userId: uid,
        recordDate: date,
        timeIn: tin,
        breakOut: bo,
        breakIn: bi,
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

  Future<void> _showImportBiometricLogsDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ImportBiometricAttendanceLogsDialog(
        onCancel: () => Navigator.of(ctx).pop(),
        onImportSuccess: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok == true && mounted) {
      _applyFilters();
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    DtrProvider dtr,
    TimeRecord r,
  ) async {
    final timeInLocal = r.timeIn?.toLocal();
    final breakOutLocal = r.breakOut?.toLocal();
    final breakInLocal = r.breakIn?.toLocal();
    final timeOutLocal = r.timeOut?.toLocal();
    TimeOfDay? timeIn = timeInLocal != null
        ? TimeOfDay(hour: timeInLocal.hour, minute: timeInLocal.minute)
        : null;
    TimeOfDay? breakOut = breakOutLocal != null
        ? TimeOfDay(hour: breakOutLocal.hour, minute: breakOutLocal.minute)
        : null;
    TimeOfDay? breakIn = breakInLocal != null
        ? TimeOfDay(hour: breakInLocal.hour, minute: breakInLocal.minute)
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
                  title: const Text('AM In'),
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
                  title: const Text('AM Out'),
                  subtitle: Text(
                    breakOut != null
                        ? '${breakOut!.hour.toString().padLeft(2, '0')}:${breakOut!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: breakOut ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => breakOut = t);
                  },
                ),
                ListTile(
                  title: const Text('PM In'),
                  subtitle: Text(
                    breakIn != null
                        ? '${breakIn!.hour.toString().padLeft(2, '0')}:${breakIn!.minute.toString().padLeft(2, '0')}'
                        : 'Select',
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: breakIn ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => breakIn = t);
                  },
                ),
                ListTile(
                  title: const Text('PM Out'),
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
      DateTime? bo;
      DateTime? bi;
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
      if (breakOut != null) {
        bo = DateTime(
          date.year,
          date.month,
          date.day,
          breakOut!.hour,
          breakOut!.minute,
        );
      }
      if (breakIn != null) {
        bi = DateTime(
          date.year,
          date.month,
          date.day,
          breakIn!.hour,
          breakIn!.minute,
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
      if (tin != null && bo != null && bi != null && tout != null) {
        hours =
            (bo.difference(tin).inMinutes + tout.difference(bi).inMinutes) /
            60.0;
      } else if (tin != null && tout != null) {
        hours = tout.difference(tin).inMinutes / 60.0;
      }
      final updatedRec = r.copyWith(
        recordDate: date,
        timeIn: tin,
        breakOut: bo,
        breakIn: bi,
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
