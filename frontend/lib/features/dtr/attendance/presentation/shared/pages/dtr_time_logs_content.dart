import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart'
    show DtrProvider, DtrUpdateEvent, EmployeeOption;
import 'package:hrms_plaridel/features/dtr/attendance/presentation/mobile/widgets/dtr_time_logs_mobile_list.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_source_badge.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/import_biometric_attendance_logs_dialog.dart';

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
    final dark = AppTheme.dashIsDark(context);
    final (color, bg) = _colorsForRemark(
      remark,
      isHoliday: isHoliday,
      dark: dark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
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

  static (Color color, Color bg) _chipPair(
    Color fg,
    Color lightBg, {
    required bool dark,
  }) => dark
      ? (fg.withValues(alpha: 0.92), fg.withValues(alpha: 0.24))
      : (fg, lightBg);

  static (Color color, Color bg) _colorsForRemark(
    String r, {
    bool isHoliday = false,
    required bool dark,
  }) {
    if (isHoliday) {
      return _chipPair(
        Colors.purple.shade700,
        Colors.purple.shade50,
        dark: dark,
      );
    }
    switch (r) {
      case 'On Time':
        return _chipPair(
          Colors.green.shade800,
          Colors.green.shade50,
          dark: dark,
        );
      case 'Late':
        return _chipPair(Colors.red.shade800, Colors.red.shade50, dark: dark);
      case 'Undertime':
        return _chipPair(
          Colors.orange.shade800,
          Colors.orange.shade50,
          dark: dark,
        );
      case 'Late + Undertime':
        return _chipPair(
          Colors.deepOrange.shade800,
          Colors.deepOrange.shade50,
          dark: dark,
        );
      case 'Absent':
        return _chipPair(
          Colors.orange.shade700,
          Colors.orange.shade50,
          dark: dark,
        );
      case 'Holiday':
        return _chipPair(
          Colors.purple.shade700,
          Colors.purple.shade50,
          dark: dark,
        );
      case 'Leave':
        return _chipPair(Colors.blue.shade700, Colors.blue.shade50, dark: dark);
      case 'Locator / Official Business':
      case 'On Field':
      case 'Pass Slip':
      case 'Work From Home':
      case 'WFH':
        return _chipPair(Colors.teal.shade700, Colors.teal.shade50, dark: dark);
      case 'Incomplete':
        return _chipPair(
          Colors.amber.shade800,
          Colors.amber.shade50,
          dark: dark,
        );
      case 'Invalid Log':
        return _chipPair(Colors.red.shade900, Colors.red.shade100, dark: dark);
      default:
        if (r.toLowerCase().contains('leave')) {
          return _chipPair(
            Colors.blue.shade700,
            Colors.blue.shade50,
            dark: dark,
          );
        }
        return dark
            ? (const Color(0xFFB0B8C4), const Color(0xFF343B4A))
            : (AppTheme.textPrimary, AppTheme.lightGray.withValues(alpha: 0.5));
    }
  }
}

class _TimeEntryInfoChip extends StatelessWidget {
  const _TimeEntryInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.sectionAltOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.dashTextSecondaryOf(context)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin Time Logs: list, filters, add/edit/delete.
class DtrTimeLogsContent extends StatefulWidget {
  const DtrTimeLogsContent({super.key});

  @override
  State<DtrTimeLogsContent> createState() => _DtrTimeLogsState();
}

class _DtrTimeLogsState extends State<DtrTimeLogsContent>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  StreamSubscription? _wsSub;
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

  /// Latest day the user can pick for the selected month/year. Past months: full month.
  /// Current month/year: cannot pick future days (no time logs yet). Future months: full month (usually empty).
  int get _maxSelectableCalendarDay {
    final now = DateTime.now();
    final last = _lastDayOfSelectedMonth;
    if (_selectedYear < now.year ||
        (_selectedYear == now.year && _selectedMonth < now.month)) {
      return last;
    }
    if (_selectedYear > now.year ||
        (_selectedYear == now.year && _selectedMonth > now.month)) {
      return last;
    }
    final today = now.day;
    return today < last ? today : last;
  }

  /// Keeps [_selectedDay] within the month and not beyond today when viewing current month/year.
  void _clampSelectedDayIfNeeded() {
    if (_selectedDay == null) return;
    final last = _lastDayOfSelectedMonth;
    final maxD = _maxSelectableCalendarDay;
    if (_selectedDay! > last) {
      _selectedDay = null;
      return;
    }
    if (_selectedDay! > maxD) {
      _selectedDay = maxD;
    }
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

  bool _shouldRefreshForDtrEvent(DtrUpdateEvent event) {
    final userId = _selectedUserId;
    if (userId != null && userId.isNotEmpty && !event.affectsUser(userId)) {
      return false;
    }
    final (start, end) = _getIntendedFilterRange();
    return event.affectsDateRange(start, end);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _selectedDay = now.day;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (mounted) {
        _wsSub = context.read<DtrProvider>().onDtrEvent.listen((event) {
          if (mounted && _shouldRefreshForDtrEvent(event)) {
            _applyFilters(silent: true);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _applyFilters(silent: true);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final dtr = context.read<DtrProvider>();
    await Future.wait([
      dtr.loadEmployees(departmentId: _selectedDepartmentId),
      dtr.loadDepartments(),
    ]);
    if (!mounted) return;
    await _applyFilters();
  }

  Future<void> _applyFilters({
    bool silent = false,
    bool forceRefresh = false,
  }) async {
    if (!mounted) return;
    final dayBefore = _selectedDay;
    _clampSelectedDayIfNeeded();
    if (dayBefore != _selectedDay && mounted) {
      setState(() {});
    }
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
      forceRefresh: forceRefresh,
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

  static const List<String> _shortWeekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String _formatDateWithWeekday(DateTime d) {
    final w = _shortWeekdays[d.weekday - 1];
    return '${_formatDate(d)} · $w';
  }

  static String _formatTimeOfDay12h(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute;
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

  /// Prefer [preferredUserId] if still in list; otherwise first employee.
  static String? _pickUserIdForEmployeeList(
    List<EmployeeOption> emps,
    String? preferredUserId,
  ) {
    if (emps.isEmpty) return null;
    if (preferredUserId != null && emps.any((e) => e.id == preferredUserId)) {
      return preferredUserId;
    }
    return emps.first.id;
  }

  /// Fallback attendance remark when backend does not send attendanceRemark (e.g. hardcoded preview).
  /// Backend sends shift-aware attendance_remark; this is a simple fallback.
  static String getAttendanceRemark(TimeRecord r) {
    if (r.attendanceRemark != null && r.attendanceRemark!.isNotEmpty) {
      return _normalizeAttendanceRemark(r.attendanceRemark!);
    }
    if (r.status == 'holiday' || r.holidayId != null) {
      return r.holidayName ?? 'Holiday';
    }
    if (r.status == 'on_leave' || r.leaveRequestId != null) {
      return r.leaveTypeName ?? 'Leave';
    }
    if (r.status == 'on_field' || r.locatorSlipId != null) {
      return r.locatorSlipDisplayLabel;
    }
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

  static String _normalizeAttendanceRemark(String remark) {
    final value = remark.trim();
    if (value.toLowerCase().startsWith('work from home')) return 'WFH';
    return value;
  }

  /// Display late minutes: "X min", "0 min", or "—" for holiday/leave.
  static String formatLateMinutes(TimeRecord r) {
    if (r.status == 'holiday' ||
        r.holidayId != null ||
        r.status == 'on_leave' ||
        r.leaveRequestId != null) {
      return '—';
    }
    final m = r.lateMinutes ?? 0;
    return m == 0 ? '0 min' : '$m min';
  }

  /// Display undertime minutes: "X min", "0 min", or "—" for holiday/leave.
  static String formatUndertimeMinutes(TimeRecord r) {
    if (r.status == 'holiday' ||
        r.holidayId != null ||
        r.status == 'on_leave' ||
        r.leaveRequestId != null) {
      return '—';
    }

    final m = r.undertimeMinutes ?? 0;
    return m == 0 ? '0 min' : '$m min';
  }

  Widget _headerLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppTheme.dashTextPrimaryOf(context),
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
    final dark = AppTheme.dashIsDark(context);
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
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage and correct daily time-in/out records. Add, edit, or delete entries.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 14,
            ),
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
                    color: dark
                        ? AppTheme.primaryNavyLight
                        : AppTheme.primaryNavy,
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
                color: dark
                    ? Colors.blue.shade900.withValues(alpha: 0.35)
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: dark ? Colors.blue.shade700 : Colors.blue.shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: dark ? Colors.blue.shade300 : Colors.blue.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing sample data. DTR data comes from the backend (dtr_daily_summary). Add records via Clock In or admin Time Logs to see live data.',
                      style: TextStyle(
                        color: dark
                            ? Colors.blue.shade100
                            : Colors.blue.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: dark ? Colors.blue.shade300 : Colors.blue.shade700,
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
                color: dark
                    ? Colors.red.shade900.withValues(alpha: 0.35)
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: dark ? Colors.red.shade700 : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: dark ? Colors.red.shade300 : Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dtr.error!,
                      style: TextStyle(
                        color: dark ? Colors.red.shade100 : Colors.red.shade900,
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
                          style: AppTheme.dashFieldTextStyle(context),
                          decoration: AppTheme.dashInputDecoration(
                            context,
                            hintText: 'Search name...',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 20,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            radius: 8,
                          ),
                        ),
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
                          if (v != null) {
                            setState(() {
                              _selectedMonth = v;
                              if (_selectedDay != null &&
                                  _selectedDay! > _lastDayOfSelectedMonth) {
                                _selectedDay = null;
                              }
                              _clampSelectedDayIfNeeded();
                            });
                          }
                          _applyFilters();
                        },
                      ),
                      DropdownButton<int>(
                        value: _selectedYear,
                        dropdownColor: AppTheme.dashPanelOf(context),
                        style: AppTheme.dashFieldTextStyle(context),
                        items:
                            List.generate(
                                  11,
                                  (i) => DateTime.now().year - 5 + i,
                                )
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(
                                      '$y',
                                      style: AppTheme.dashFieldTextStyle(
                                        context,
                                      ),
                                    ),
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
                              _clampSelectedDayIfNeeded();
                            });
                          }
                          _applyFilters();
                        },
                      ),
                      DropdownButton<int?>(
                        value: _selectedDay,
                        dropdownColor: AppTheme.dashPanelOf(context),
                        style: AppTheme.dashFieldTextStyle(context),
                        hint: Text(
                          'All days',
                          style: AppTheme.dashFieldHintStyle(context),
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All days',
                              style: AppTheme.dashFieldTextStyle(context),
                            ),
                          ),
                          ...List.generate(
                            _maxSelectableCalendarDay,
                            (i) => i + 1,
                          ).map(
                            (d) => DropdownMenuItem<int?>(
                              value: d,
                              child: Text(
                                'Day $d',
                                style: AppTheme.dashFieldTextStyle(context),
                              ),
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
                          ...dtr.departments.map(
                            (d) => DropdownMenuItem<String?>(
                              value: d.id,
                              child: Text(
                                d.name,
                                style: AppTheme.dashFieldTextStyle(context),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) async {
                          final dtr = context.read<DtrProvider>();
                          setState(() {
                            _selectedDepartmentId = v;
                            _selectedUserId = null;
                          });
                          await dtr.loadEmployees(departmentId: v);
                          if (!mounted) return;
                          setState(() {});
                          _applyFilters();
                        },
                      ),
                      DropdownButton<String?>(
                        value: _selectedUserId,
                        dropdownColor: AppTheme.dashPanelOf(context),
                        style: AppTheme.dashFieldTextStyle(context),
                        hint: Text(
                          'All employees',
                          style: AppTheme.dashFieldHintStyle(context),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'All employees',
                              style: AppTheme.dashFieldTextStyle(context),
                            ),
                          ),
                          ...dtr.employees.map(
                            (e) => DropdownMenuItem<String?>(
                              value: e.id,
                              child: Text(
                                e.fullName,
                                style: AppTheme.dashFieldTextStyle(context),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedUserId = v);
                          _applyFilters();
                        },
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final dtr = context.read<DtrProvider>();
                          setState(() {
                            _searchController.clear();
                            _selectedMonth = now.month;
                            _selectedYear = now.year;
                            _selectedDay = now.day;
                            _selectedUserId = null;
                            _selectedDepartmentId = null;
                          });
                          await dtr.loadEmployees();
                          if (!mounted) return;
                          _applyFilters();
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: dark
                              ? Colors.green.shade900.withValues(alpha: 0.4)
                              : const Color(0xFFE8F5E9),
                          foregroundColor: dark
                              ? Colors.green.shade300
                              : const Color(0xFF2E7D32),
                        ),
                        child: const Text('RESET'),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Time log actions',
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: AppTheme.dashPanelOf(context),
                        onSelected: (value) {
                          switch (value) {
                            case 'add':
                              _showAddDialog(context, dtr);
                              break;
                            case 'import':
                              _showImportBiometricLogsDialog();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'add',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 20,
                                  color: AppTheme.primaryNavy,
                                ),
                                const SizedBox(width: 12),
                                const Text('Add manual entry'),
                              ],
                            ),
                          ),
                          if (isAdmin)
                            PopupMenuItem<String>(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.file_upload_rounded,
                                    size: 20,
                                    color: AppTheme.primaryNavy,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Import biometric logs'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (isHardcodedPreview && !dtr.tableMissing) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: dark
                    ? AppTheme.primaryNavy.withValues(alpha: 0.22)
                    : AppTheme.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(
                    alpha: dark ? 0.45 : 0.2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: dark
                        ? AppTheme.primaryNavyLight
                        : AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing sample data for UI overview. Add real records or adjust filters to see live data.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dashTextPrimaryOf(context),
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
              decoration: AppTheme.dashSurfaceCard(context, radius: 12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 56,
                      color: AppTheme.dashTextSecondaryOf(
                        context,
                      ).withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No time records match your filters.',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use Add manual entry above, or try a different date range.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          if (!dtr.loading && displayRecords.isNotEmpty)
            LayoutBuilder(
              builder: (context, tableConstraints) {
                if (tableConstraints.maxWidth < 600) {
                  return _buildMobileTimeLogsList(
                    context: context,
                    records: displayRecords,
                    dtr: dtr,
                    isHardcodedPreview: isHardcodedPreview,
                  );
                }
                final tableWidth = tableConstraints.maxWidth.clamp(
                  600.0,
                  double.infinity,
                );
                final contentHeight = (displayRecords.length + 1) * 56.0 + 30;
                final viewportCap = (MediaQuery.sizeOf(context).height * 0.68)
                    .clamp(320.0, 720.0);
                final maxHeight = tableConstraints.maxHeight.isFinite
                    ? tableConstraints.maxHeight
                    : viewportCap;
                final constrainedHeight = contentHeight.clamp(100.0, maxHeight);
                return Container(
                  decoration: AppTheme.dashSurfaceCard(context, radius: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: constrainedHeight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
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
                                color: AppTheme.dashMutedSurfaceOf(context),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppTheme.dashHairlineOf(context),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: _headerLabel(context, 'Employee'),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: _headerLabel(context, 'Date'),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'AM In'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'AM Out'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'PM In'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'PM Out'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'Late'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'Undertime'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: _headerLabel(context, 'Remarks'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _headerLabel(context, 'Source'),
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
                            Expanded(
                              child: ListView.builder(
                                itemCount: displayRecords.length,
                                itemBuilder: (context, index) =>
                                    _buildTimeLogRow(
                                      context: context,
                                      index: index,
                                      record: displayRecords[index],
                                      dtr: dtr,
                                      isHardcodedPreview: isHardcodedPreview,
                                    ),
                              ),
                            ),
                          ],
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

  Widget _buildMobileTimeLogsList({
    required BuildContext context,
    required List<TimeRecord> records,
    required DtrProvider dtr,
    required bool isHardcodedPreview,
  }) {
    return DtrTimeLogsMobileList(
      children: List.generate(records.length, (index) {
        final record = records[index];
        final remark = getAttendanceRemark(record);
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == records.length - 1 ? 0 : 12,
          ),
          child: DtrTimeLogMobileCard(
            employeeName: record.employeeName ?? record.userId,
            dateLabel: _formatDate(record.recordDate),
            amIn: _cellDisplayForSegment(
              record: record,
              timeValue: record.timeIn?.toLocal(),
              segment: 'AM IN',
            ),
            amOut: _cellDisplayForSegment(
              record: record,
              timeValue: record.breakOut?.toLocal(),
              segment: 'AM OUT',
            ),
            pmIn: _cellDisplayForSegment(
              record: record,
              timeValue: record.breakIn?.toLocal(),
              segment: 'PM IN',
            ),
            pmOut: _cellDisplayForSegment(
              record: record,
              timeValue: record.timeOut?.toLocal(),
              segment: 'PM OUT',
            ),
            late: formatLateMinutes(record),
            undertime: formatUndertimeMinutes(record),
            remarkChip: _RemarksChip(
              remark: remark,
              isHoliday: record.status == 'holiday' || record.holidayId != null,
            ),
            source: record.source,
            showActions: !isHardcodedPreview,
            onEdit: () => _showEditDialog(context, dtr, record),
            onDelete: () => _confirmDelete(context, dtr, record),
          ),
        );
      }),
    );
  }

  Widget _buildTimeLogRow({
    required BuildContext context,
    required int index,
    required TimeRecord record,
    required DtrProvider dtr,
    required bool isHardcodedPreview,
  }) {
    final dark = AppTheme.dashIsDark(context);
    final cellStyle = TextStyle(
      fontSize: 13,
      color: AppTheme.dashTextPrimaryOf(context),
    );
    final timeIn = record.timeIn?.toLocal();
    final breakOut = record.breakOut?.toLocal();
    final breakIn = record.breakIn?.toLocal();
    final timeOut = record.timeOut?.toLocal();
    final remark = getAttendanceRemark(record);
    final lateStr = formatLateMinutes(record);
    final underStr = formatUndertimeMinutes(record);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
      decoration: BoxDecoration(
        color: index % 2 == 0
            ? AppTheme.dashPanelOf(context)
            : AppTheme.dashMutedSurfaceOf(
                context,
              ).withValues(alpha: dark ? 0.65 : 1),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.dashHairlineOf(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              record.employeeName ?? record.userId,
              style: cellStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(record.recordDate),
              style: cellStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                _cellDisplayForSegment(
                  record: record,
                  timeValue: timeIn,
                  segment: 'AM IN',
                ),
                style: cellStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                _cellDisplayForSegment(
                  record: record,
                  timeValue: breakOut,
                  segment: 'AM OUT',
                ),
                style: cellStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                _cellDisplayForSegment(
                  record: record,
                  timeValue: breakIn,
                  segment: 'PM IN',
                ),
                style: cellStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                _cellDisplayForSegment(
                  record: record,
                  timeValue: timeOut,
                  segment: 'PM OUT',
                ),
                style: cellStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                lateStr,
                style: cellStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                underStr,
                style: cellStyle,
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
                    record.status == 'holiday' || record.holidayId != null,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: AttendanceSourceBadge(
                source: record.source,
                compact: true,
              ),
            ),
          ),
          if (!isHardcodedPreview)
            Expanded(
              flex: 1,
              child: Center(
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 22,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Actions',
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditDialog(context, dtr, record);
                    } else if (value == 'delete') {
                      _confirmDelete(context, dtr, record);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            size: 20,
                            color: AppTheme.dashTextPrimaryOf(ctx),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(ctx),
                            ),
                          ),
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
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Delete',
                            style: TextStyle(color: Colors.red.shade700),
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
  }

  Widget _manualEntryPunchTile(
    BuildContext context, {
    required String label,
    required TimeOfDay? value,
    required VoidCallback onTap,
    required IconData icon,
    VoidCallback? onClear,
  }) {
    return Material(
      color: AppTheme.sectionAltOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: AppTheme.dashIsDark(context)
                    ? AppTheme.primaryNavyLight
                    : AppTheme.primaryNavy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value != null ? _formatTimeOfDay12h(value) : 'Tap to set',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: value != null
                            ? AppTheme.dashTextPrimaryOf(context)
                            : AppTheme.dashTextSecondaryOf(
                                context,
                              ).withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (value != null && onClear != null) ...[
                IconButton(
                  tooltip: 'Clear $label',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.dashTextSecondaryOf(
                      context,
                    ).withValues(alpha: 0.75),
                  ),
                ),
              ] else
                Icon(
                  Icons.schedule_rounded,
                  size: 20,
                  color: AppTheme.dashTextSecondaryOf(
                    context,
                  ).withValues(alpha: 0.65),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, DtrProvider dtr) async {
    if (dtr.departments.isEmpty) {
      await dtr.loadDepartments();
      if (!context.mounted) return;
    }

    var addDeptId = _selectedDepartmentId;
    await dtr.loadEmployees(departmentId: addDeptId);
    if (!context.mounted) return;

    if (dtr.employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No employees for this department filter. Try All departments or add employee profiles.',
          ),
        ),
      );
      return;
    }

    String? userId = _pickUserIdForEmployeeList(dtr.employees, _selectedUserId);
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
    var employeesLoading = false;

    bool? updated;
    try {
      updated = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              final hasAnyTime =
                  timeIn != null ||
                  breakOut != null ||
                  breakIn != null ||
                  timeOut != null;
              final screenH = MediaQuery.sizeOf(ctx).height;
              final empList = dtr.employees;
              final String? employeeDropdownValue = empList.isEmpty
                  ? null
                  : (userId != null && empList.any((e) => e.id == userId))
                  ? userId
                  : empList.first.id;
              final canSubmit =
                  !employeesLoading &&
                  employeeDropdownValue != null &&
                  empList.isNotEmpty;
              return Dialog(
                backgroundColor: AppTheme.dashPanelOf(ctx),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppTheme.dashHairlineOf(ctx)),
                ),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 440,
                    maxHeight: screenH * 0.92,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryNavy.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.edit_calendar_rounded,
                                color: AppTheme.primaryNavy,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add time entry',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.dashTextPrimaryOf(ctx),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Department filters the list below (defaults to your Time Logs filter). One employee, one date; empty punches stay blank.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: AppTheme.dashTextSecondaryOf(
                                        ctx,
                                      ).withValues(alpha: 0.95),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<String?>(
                                initialValue: addDeptId,
                                isExpanded: true,
                                dropdownColor: AppTheme.dashPanelOf(ctx),
                                style: AppTheme.dashFieldTextStyle(ctx),
                                decoration: AppTheme.dashInputDecoration(
                                  ctx,
                                  labelText: 'Department',
                                  radius: 12,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('All departments'),
                                  ),
                                  ...dtr.departments.map(
                                    (d) => DropdownMenuItem<String?>(
                                      value: d.id,
                                      child: Text(
                                        d.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: employeesLoading
                                    ? null
                                    : (v) async {
                                        addDeptId = v;
                                        setState(() => employeesLoading = true);
                                        await dtr.loadEmployees(
                                          departmentId: v,
                                        );
                                        if (!ctx.mounted) return;
                                        setState(() {
                                          employeesLoading = false;
                                          userId = _pickUserIdForEmployeeList(
                                            dtr.employees,
                                            userId,
                                          );
                                        });
                                      },
                              ),
                              const SizedBox(height: 10),
                              if (employeesLoading)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: LinearProgressIndicator(minHeight: 3),
                                ),
                              if (!employeesLoading && empList.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'No employees in this department. Choose All departments or another office.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                              DropdownButtonFormField<String>(
                                initialValue: employeeDropdownValue,
                                isExpanded: true,
                                dropdownColor: AppTheme.dashPanelOf(ctx),
                                style: AppTheme.dashFieldTextStyle(ctx),
                                decoration: AppTheme.dashInputDecoration(
                                  ctx,
                                  labelText: 'Employee',
                                  radius: 12,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                items: empList
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.id,
                                        child: Text(
                                          e.fullName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: employeesLoading || empList.isEmpty
                                    ? null
                                    : (v) {
                                        if (v != null) {
                                          setState(() => userId = v);
                                        }
                                      },
                              ),
                              const SizedBox(height: 14),
                              Material(
                                color: AppTheme.dashInputFillOf(ctx),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () async {
                                    final d = await showDatePicker(
                                      context: ctx,
                                      initialDate: recordDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2030),
                                    );
                                    if (d != null) {
                                      setState(() => recordDate = d);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_rounded,
                                          size: 20,
                                          color: AppTheme.dashIsDark(ctx)
                                              ? AppTheme.primaryNavyLight
                                              : AppTheme.primaryNavy,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Date',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      AppTheme.dashTextSecondaryOf(
                                                        ctx,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _formatDateWithWeekday(
                                                  recordDate,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      AppTheme.dashTextPrimaryOf(
                                                        ctx,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppTheme.dashTextSecondaryOf(
                                            ctx,
                                          ).withValues(alpha: 0.7),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Morning',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: AppTheme.dashTextSecondaryOf(
                                    ctx,
                                  ).withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _manualEntryPunchTile(
                                ctx,
                                label: 'AM In (time in)',
                                value: timeIn,
                                icon: Icons.wb_sunny_outlined,
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: ctx,
                                    initialTime: timeIn ?? TimeOfDay.now(),
                                  );
                                  if (t != null) setState(() => timeIn = t);
                                },
                              ),
                              const SizedBox(height: 8),
                              _manualEntryPunchTile(
                                ctx,
                                label: 'AM Out (break out)',
                                value: breakOut,
                                icon: Icons.restaurant_outlined,
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: ctx,
                                    initialTime: breakOut ?? TimeOfDay.now(),
                                  );
                                  if (t != null) setState(() => breakOut = t);
                                },
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Afternoon',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: AppTheme.dashTextSecondaryOf(
                                    ctx,
                                  ).withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _manualEntryPunchTile(
                                ctx,
                                label: 'PM In (break in)',
                                value: breakIn,
                                icon: Icons.nightlight_outlined,
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: ctx,
                                    initialTime: breakIn ?? TimeOfDay.now(),
                                  );
                                  if (t != null) setState(() => breakIn = t);
                                },
                              ),
                              const SizedBox(height: 8),
                              _manualEntryPunchTile(
                                ctx,
                                label: 'PM Out (time out)',
                                value: timeOut,
                                icon: Icons.logout_rounded,
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: ctx,
                                    initialTime: timeOut ?? TimeOfDay.now(),
                                  );
                                  if (t != null) setState(() => timeOut = t);
                                },
                              ),
                              if (hasAnyTime) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => setState(() {
                                      timeIn = null;
                                      breakOut = null;
                                      breakIn = null;
                                      timeOut = null;
                                    }),
                                    child: const Text('Clear all times'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: AppTheme.dashHairlineOf(ctx)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: !canSubmit
                                  ? null
                                  : () {
                                      userId = employeeDropdownValue;
                                      Navigator.pop(ctx, true);
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryNavy,
                                foregroundColor: AppTheme.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Add entry'),
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
        },
      );
    } finally {
      if (mounted) {
        await dtr.loadEmployees(departmentId: _selectedDepartmentId);
      }
    }

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
      context.read<DtrProvider>().invalidateCachedDtrData();
      _applyFilters(forceRefresh: true);
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
    final originalRecordDate = recordDate;
    final originalTimeIn = timeIn;
    final originalBreakOut = breakOut;
    final originalBreakIn = breakIn;
    final originalTimeOut = timeOut;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            int? minutes(TimeOfDay? t) =>
                t == null ? null : (t.hour * 60) + t.minute;

            Future<void> pickTime(
              TimeOfDay? current,
              void Function(TimeOfDay value) assign,
            ) async {
              final t = await showTimePicker(
                context: ctx,
                initialTime: current ?? TimeOfDay.now(),
              );
              if (t != null) setState(() => assign(t));
            }

            final amInM = minutes(timeIn);
            final amOutM = minutes(breakOut);
            final pmInM = minutes(breakIn);
            final pmOutM = minutes(timeOut);
            String? validationMessage;
            if (amInM != null && amOutM != null && amOutM <= amInM) {
              validationMessage = 'AM Out must be later than AM In.';
            } else if (pmInM != null && pmOutM != null && pmOutM <= pmInM) {
              validationMessage = 'PM Out must be later than PM In.';
            } else if (amOutM != null && pmInM != null && pmInM < amOutM) {
              validationMessage = 'PM In should not be earlier than AM Out.';
            }

            var workedMinutes = 0;
            if (validationMessage == null) {
              if (amInM != null && amOutM != null) {
                workedMinutes += amOutM - amInM;
              }
              if (pmInM != null && pmOutM != null) {
                workedMinutes += pmOutM - pmInM;
              }
              if (workedMinutes == 0 && amInM != null && pmOutM != null) {
                workedMinutes = pmOutM - amInM;
              }
            }
            final hasAnyTime =
                timeIn != null ||
                breakOut != null ||
                breakIn != null ||
                timeOut != null;
            final canSave = validationMessage == null;
            final screenH = MediaQuery.sizeOf(ctx).height;

            return Dialog(
              backgroundColor: AppTheme.dashPanelOf(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppTheme.dashHairlineOf(ctx)),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: screenH * 0.92,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryNavy.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.edit_calendar_rounded,
                              color: AppTheme.primaryNavy,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit time entry',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.dashTextPrimaryOf(ctx),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  r.employeeName ?? r.userId,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: AppTheme.dashTextSecondaryOf(
                                      ctx,
                                    ).withValues(alpha: 0.95),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _TimeEntryInfoChip(
                                  icon: Icons.badge_outlined,
                                  label: r.employeeName ?? r.userId,
                                ),
                                _TimeEntryInfoChip(
                                  icon: Icons.calendar_today_rounded,
                                  label: _formatDateWithWeekday(recordDate),
                                ),
                                if (r.source != null && r.source!.isNotEmpty)
                                  AttendanceSourceBadge(
                                    source: r.source,
                                    compact: true,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Material(
                              color: AppTheme.dashInputFillOf(ctx),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: recordDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (d != null) {
                                    setState(() => recordDate = d);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        size: 20,
                                        color: AppTheme.dashIsDark(ctx)
                                            ? AppTheme.primaryNavyLight
                                            : AppTheme.primaryNavy,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Correction date',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppTheme.dashTextSecondaryOf(
                                                      ctx,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDateWithWeekday(
                                                recordDate,
                                              ),
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppTheme.dashTextPrimaryOf(
                                                      ctx,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppTheme.dashTextSecondaryOf(
                                          ctx,
                                        ).withValues(alpha: 0.7),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.sectionAltOf(ctx),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.dashHairlineOf(ctx),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 20,
                                    color: AppTheme.dashTextSecondaryOf(ctx),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      workedMinutes > 0
                                          ? 'Estimated worked time: ${(workedMinutes / 60).toStringAsFixed(2)} hours'
                                          : 'Set only the punches that should appear. Empty slots stay blank.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.dashTextSecondaryOf(
                                          ctx,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (validationMessage != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 20,
                                      color: Colors.orange.shade800,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        validationMessage,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Text(
                              'Morning',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppTheme.dashTextSecondaryOf(
                                  ctx,
                                ).withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _manualEntryPunchTile(
                              ctx,
                              label: 'AM In (time in)',
                              value: timeIn,
                              icon: Icons.wb_sunny_outlined,
                              onTap: () =>
                                  pickTime(timeIn, (value) => timeIn = value),
                              onClear: () => setState(() => timeIn = null),
                            ),
                            const SizedBox(height: 8),
                            _manualEntryPunchTile(
                              ctx,
                              label: 'AM Out (break out)',
                              value: breakOut,
                              icon: Icons.restaurant_outlined,
                              onTap: () => pickTime(
                                breakOut,
                                (value) => breakOut = value,
                              ),
                              onClear: () => setState(() => breakOut = null),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Afternoon',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppTheme.dashTextSecondaryOf(
                                  ctx,
                                ).withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _manualEntryPunchTile(
                              ctx,
                              label: 'PM In (break in)',
                              value: breakIn,
                              icon: Icons.nightlight_outlined,
                              onTap: () =>
                                  pickTime(breakIn, (value) => breakIn = value),
                              onClear: () => setState(() => breakIn = null),
                            ),
                            const SizedBox(height: 8),
                            _manualEntryPunchTile(
                              ctx,
                              label: 'PM Out (time out)',
                              value: timeOut,
                              icon: Icons.logout_rounded,
                              onTap: () =>
                                  pickTime(timeOut, (value) => timeOut = value),
                              onClear: () => setState(() => timeOut = null),
                            ),
                            if (hasAnyTime) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => setState(() {
                                    timeIn = null;
                                    breakOut = null;
                                    breakIn = null;
                                    timeOut = null;
                                  }),
                                  icon: const Icon(
                                    Icons.cleaning_services_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Clear all times'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: AppTheme.dashHairlineOf(ctx)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              recordDate = originalRecordDate;
                              timeIn = originalTimeIn;
                              breakOut = originalBreakOut;
                              breakIn = originalBreakIn;
                              timeOut = originalTimeOut;
                            }),
                            child: const Text('Reset'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: canSave
                                ? () => Navigator.pop(ctx, true)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryNavy,
                              foregroundColor: AppTheme.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Save changes'),
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
      },
    );

    if (updated == true) {
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
      final hasAnyTime =
          tin != null || bo != null || bi != null || tout != null;
      if (r.id != null && !hasAnyTime) {
        final removed = await dtr.deleteEntry(r.id!);
        if (!context.mounted) return;
        _showTimeLogSnack(
          context,
          removed
              ? 'Time entry removed.'
              : (dtr.error ?? 'Unable to remove this time entry.'),
        );
        if (removed) await _applyFilters(forceRefresh: true);
        return;
      }
      final updatedRec = TimeRecord(
        id: r.id,
        userId: r.userId,
        recordDate: date,
        timeIn: tin,
        breakOut: bo,
        breakIn: bi,
        timeOut: tout,
        totalHours: hours,
        lateMinutes: r.lateMinutes,
        undertimeMinutes: r.undertimeMinutes,
        status: r.status,
        pmStatus: r.pmStatus,
        remarks: r.remarks,
        holidayId: r.holidayId,
        leaveRequestId: r.leaveRequestId,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        employeeName: r.employeeName,
        holidayName: r.holidayName,
        coverage: r.coverage,
        attendanceRemark: r.attendanceRemark,
        leaveTypeName: r.leaveTypeName,
        source: r.source,
        locatorSlipId: r.locatorSlipId,
        locatorSlipRequestType: r.locatorSlipRequestType,
        locatorSlipSegments: r.locatorSlipSegments,
      );
      final saved = r.id != null
          ? await dtr.updateEntry(updatedRec)
          : await dtr.addManualEntry(updatedRec);
      if (!context.mounted) return;
      _showTimeLogSnack(
        context,
        saved
            ? 'Time entry updated.'
            : (dtr.error ?? 'Unable to update this time entry.'),
      );
      if (!saved) return;
      await _applyFilters(forceRefresh: true);
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
      final deleted = await dtr.deleteEntry(r.id!);
      if (!context.mounted) return;
      _showTimeLogSnack(
        context,
        deleted
            ? 'Time entry deleted.'
            : (dtr.error ??
                  'Unable to delete this time log. Please try again.'),
      );
      if (deleted) await _applyFilters(forceRefresh: true);
    }
  }

  void _showTimeLogSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
