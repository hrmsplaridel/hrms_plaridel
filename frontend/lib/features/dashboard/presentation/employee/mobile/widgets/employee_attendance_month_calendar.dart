import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/attendance_overview/attendance_overview_data.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'employee_attendance_mobile_list.dart';

enum AttendanceCalendarStatus {
  present,
  late,
  undertime,
  lateUndertime,
  absent,
  leave,
  holiday,
  restDay,
  locator,
  incomplete,
  invalid,
  notTracked,
  unprocessed,
  future,
}

AttendanceCalendarStatus attendanceCalendarStatus(
  TimeRecord? record,
  DateTime officialDate,
) {
  if (record == null) return AttendanceCalendarStatus.unprocessed;
  if (DateUtils.dateOnly(
    record.recordDate,
  ).isAfter(DateUtils.dateOnly(officialDate))) {
    return AttendanceCalendarStatus.future;
  }
  if (record.status == 'not_tracked') {
    return AttendanceCalendarStatus.notTracked;
  }
  if (record.isLeaveCovered ||
      record.leaveCoverageId != null ||
      record.leaveRequestId != null ||
      record.status == 'on_leave') {
    return AttendanceCalendarStatus.leave;
  }
  if (record.status == 'holiday' || record.holidayId != null) {
    return AttendanceCalendarStatus.holiday;
  }
  if (record.status == 'rest_day') return AttendanceCalendarStatus.restDay;
  if (record.status == 'absent') return AttendanceCalendarStatus.absent;
  if (record.status == 'invalid' || record.attendanceRemark == 'Invalid Log') {
    return AttendanceCalendarStatus.invalid;
  }
  if (record.status == 'incomplete' ||
      record.attendanceRemark == 'Incomplete') {
    return AttendanceCalendarStatus.incomplete;
  }
  final late = (record.lateMinutes ?? 0) > 0 || record.status == 'late';
  final under = (record.undertimeMinutes ?? 0) > 0;
  if (late && under) return AttendanceCalendarStatus.lateUndertime;
  if (late) return AttendanceCalendarStatus.late;
  if (under) return AttendanceCalendarStatus.undertime;
  if (record.locatorSlipId != null || record.status == 'on_field') {
    return AttendanceCalendarStatus.locator;
  }
  if (record.status == 'present') return AttendanceCalendarStatus.present;
  if (record.attendanceRemark == 'Absent') {
    return AttendanceCalendarStatus.absent;
  }
  if ([
    record.timeIn,
    record.breakOut,
    record.breakIn,
    record.timeOut,
  ].any((time) => time != null)) {
    return isCompletedAttendanceRecord(record)
        ? AttendanceCalendarStatus.present
        : AttendanceCalendarStatus.incomplete;
  }
  return AttendanceCalendarStatus.unprocessed;
}

extension on AttendanceCalendarStatus {
  String get label => switch (this) {
    AttendanceCalendarStatus.present => 'Present',
    AttendanceCalendarStatus.late => 'Late',
    AttendanceCalendarStatus.undertime => 'Undertime',
    AttendanceCalendarStatus.lateUndertime => 'Late + undertime',
    AttendanceCalendarStatus.absent => 'Absent',
    AttendanceCalendarStatus.leave => 'Approved leave',
    AttendanceCalendarStatus.holiday => 'Holiday',
    AttendanceCalendarStatus.restDay => 'Rest day',
    AttendanceCalendarStatus.locator => 'Official business',
    AttendanceCalendarStatus.incomplete => 'Incomplete',
    AttendanceCalendarStatus.invalid => 'Invalid log',
    AttendanceCalendarStatus.notTracked => 'Not tracked',
    AttendanceCalendarStatus.unprocessed => 'Not processed',
    AttendanceCalendarStatus.future => 'Future date',
  };
  Color get color => switch (this) {
    AttendanceCalendarStatus.present => const Color(0xFF2E7D32),
    AttendanceCalendarStatus.late ||
    AttendanceCalendarStatus.undertime ||
    AttendanceCalendarStatus.lateUndertime => const Color(0xFFEF6C00),
    AttendanceCalendarStatus.absent ||
    AttendanceCalendarStatus.invalid => const Color(0xFFC62828),
    AttendanceCalendarStatus.leave => const Color(0xFF1976D2),
    AttendanceCalendarStatus.holiday => const Color(0xFF8E24AA),
    AttendanceCalendarStatus.locator => const Color(0xFF00897B),
    AttendanceCalendarStatus.incomplete => const Color(0xFF9E7300),
    _ => const Color(0xFF737B87),
  };
  IconData get icon => switch (this) {
    AttendanceCalendarStatus.present => Icons.check_rounded,
    AttendanceCalendarStatus.late => Icons.schedule_rounded,
    AttendanceCalendarStatus.undertime => Icons.hourglass_bottom_rounded,
    AttendanceCalendarStatus.lateUndertime => Icons.more_time_rounded,
    AttendanceCalendarStatus.absent => Icons.close_rounded,
    AttendanceCalendarStatus.leave => Icons.event_available_rounded,
    AttendanceCalendarStatus.holiday => Icons.celebration_outlined,
    AttendanceCalendarStatus.restDay => Icons.bedtime_outlined,
    AttendanceCalendarStatus.locator => Icons.business_center_outlined,
    AttendanceCalendarStatus.incomplete ||
    AttendanceCalendarStatus.invalid => Icons.error_outline_rounded,
    AttendanceCalendarStatus.notTracked => Icons.block_rounded,
    _ => Icons.remove_rounded,
  };
  bool get marked =>
      this != AttendanceCalendarStatus.unprocessed &&
      this != AttendanceCalendarStatus.future;
}

class EmployeeAttendanceMonthCalendar extends StatefulWidget {
  const EmployeeAttendanceMonthCalendar({
    super.key,
    required this.year,
    required this.month,
    required this.officialDate,
    required this.records,
    required this.formatDate,
    required this.formatTime,
    this.viewMode = 'auto',
    this.onPreviousMonth,
    this.onNextMonth,
    this.onCurrentMonth,
  });
  final int year, month;
  final DateTime officialDate;
  final List<TimeRecord> records;
  final String Function(DateTime) formatDate;
  final EmployeeAttendanceTimeFormatter formatTime;
  final String viewMode;
  final VoidCallback? onPreviousMonth, onNextMonth, onCurrentMonth;
  @override
  State<EmployeeAttendanceMonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<EmployeeAttendanceMonthCalendar> {
  bool _list = false;
  int? _selected;
  List<TimeRecord> get _records => widget.records
      .where(
        (r) =>
            r.recordDate.year == widget.year &&
            r.recordDate.month == widget.month &&
            !DateUtils.dateOnly(
              r.recordDate,
            ).isAfter(DateUtils.dateOnly(widget.officialDate)),
      )
      .toList();
  @override
  void didUpdateWidget(covariant EmployeeAttendanceMonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.month != widget.month) {
      _selected = null;
    }
  }

  String _remark(TimeRecord record) {
    final status = attendanceCalendarStatus(record, widget.officialDate);
    if ([
      AttendanceCalendarStatus.unprocessed,
      AttendanceCalendarStatus.notTracked,
      AttendanceCalendarStatus.restDay,
    ].contains(status)) {
      return status.label;
    }
    if (status == AttendanceCalendarStatus.leave) {
      return record.leaveTypeName ?? 'Approved leave';
    }
    if (status == AttendanceCalendarStatus.holiday) {
      return record.holidayName ?? record.attendanceRemark ?? 'Holiday';
    }
    if (status == AttendanceCalendarStatus.lateUndertime) {
      return 'Late + Undertime';
    }
    if (status == AttendanceCalendarStatus.late) return 'Late';
    if (status == AttendanceCalendarStatus.undertime) return 'Undertime';
    if (status == AttendanceCalendarStatus.incomplete) return 'Incomplete';
    return record.attendanceRemark ??
        (status == AttendanceCalendarStatus.locator
            ? record.locatorSlipDisplayLabel
            : status.label);
  }

  Future<void> _details(int day, TimeRecord? record) async {
    setState(() => _selected = day);
    final date = DateTime(widget.year, widget.month, day);
    final status = attendanceCalendarStatus(record, widget.officialDate);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${kAttendanceOverviewMonthNames[widget.month - 1]} $day, ${widget.year}',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close day details',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (record == null ||
                    status == AttendanceCalendarStatus.unprocessed)
                  const Text('No processed attendance record for this date.')
                else if (status == AttendanceCalendarStatus.notTracked)
                  const Text('Attendance was not tracked for this date.')
                else ...[
                  EmployeeAttendanceMobileList(
                    records: [record],
                    viewMode: widget.viewMode,
                    formatDate: widget.formatDate,
                    formatTime: widget.formatTime,
                    remarkForRecord: _remark,
                  ),
                  if ((record.remarks ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(record.remarks!),
                    ),
                  if (record.locatorSlipId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(record.locatorSlipDisplayLabel),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  widget.formatDate(date),
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(List<TimeRecord> rows) {
    final present = rows
        .where(
          (r) =>
              [
                AttendanceCalendarStatus.present,
                AttendanceCalendarStatus.late,
                AttendanceCalendarStatus.undertime,
                AttendanceCalendarStatus.lateUndertime,
              ].contains(attendanceCalendarStatus(r, widget.officialDate)) ||
              (attendanceCalendarStatus(r, widget.officialDate) ==
                      AttendanceCalendarStatus.locator &&
                  isCompletedAttendanceRecord(r)),
        )
        .length;
    final absent = rows
        .where(
          (r) =>
              attendanceCalendarStatus(r, widget.officialDate) ==
              AttendanceCalendarStatus.absent,
        )
        .length;
    final timed = rows.where(
      (r) => ![
        AttendanceCalendarStatus.leave,
        AttendanceCalendarStatus.holiday,
        AttendanceCalendarStatus.restDay,
        AttendanceCalendarStatus.notTracked,
        AttendanceCalendarStatus.unprocessed,
      ].contains(attendanceCalendarStatus(r, widget.officialDate)),
    );
    final values = {
      'Present': '$present ${present == 1 ? 'day' : 'days'}',
      'Absences': '$absent ${absent == 1 ? 'day' : 'days'}',
      'Total late':
          '${timed.fold<int>(0, (sum, r) => sum + (r.lateMinutes ?? 0))} min',
      'Total undertime':
          '${timed.fold<int>(0, (sum, r) => sum + (r.undertimeMinutes ?? 0))} min',
    };
    return LayoutBuilder(
      builder: (context, size) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in values.entries)
            Container(
              width: (size.maxWidth - 8) / 2,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.key,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _records;
    final byDay = {for (final row in rows) row.recordDate.day: row};
    final first = DateTime(widget.year, widget.month, 1).weekday - 1;
    final days = DateTime(widget.year, widget.month + 1, 0).day;
    final cells = ((first + days + 6) ~/ 7) * 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summary(rows),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: widget.onPreviousMonth,
              tooltip: 'Previous attendance month',
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${kAttendanceOverviewMonthNames[widget.month - 1]} ${widget.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: widget.onNextMonth,
              tooltip: 'Next attendance month',
              icon: const Icon(Icons.chevron_right),
            ),
            if (widget.onCurrentMonth != null)
              IconButton(
                onPressed: widget.onCurrentMonth,
                tooltip: 'Current month',
                icon: const Icon(Icons.today_outlined),
              ),
          ],
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Calendar'),
              icon: Icon(Icons.calendar_month_outlined, size: 18),
            ),
            ButtonSegment(
              value: true,
              label: Text('List'),
              icon: Icon(Icons.view_agenda_outlined, size: 18),
            ),
          ],
          selected: {_list},
          showSelectedIcon: false,
          onSelectionChanged: (values) => setState(() => _list = values.first),
        ),
        const SizedBox(height: 14),
        if (_list) ...[
          if (rows.isEmpty)
            const Text('No time records for the selected period.')
          else
            EmployeeAttendanceMobileList(
              records: rows,
              viewMode: widget.viewMode,
              formatDate: widget.formatDate,
              formatTime: widget.formatTime,
              remarkForRecord: _remark,
            ),
        ] else
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final name in const [
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun',
                    ])
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            name,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  key: const ValueKey('attendance-month-grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cells,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    mainAxisExtent: 64,
                  ),
                  itemBuilder: (context, index) {
                    final day = index - first + 1;
                    if (day < 1 || day > days) return const SizedBox.shrink();
                    final date = DateTime(widget.year, widget.month, day);
                    final future = date.isAfter(
                      DateUtils.dateOnly(widget.officialDate),
                    );
                    final record = byDay[day];
                    final status = future
                        ? AttendanceCalendarStatus.future
                        : attendanceCalendarStatus(record, widget.officialDate);
                    final today = DateUtils.isSameDay(
                      date,
                      widget.officialDate,
                    );
                    final selected = _selected == day;
                    final description =
                        '${widget.year}-${widget.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}, ${_remarkIfPresent(record, status)}';
                    final color = status.color;
                    return Semantics(
                      button: !future,
                      enabled: !future,
                      label: description,
                      selected: selected,
                      child: Tooltip(
                        message: description,
                        child: Material(
                          color: status.marked
                              ? color.withValues(
                                  alpha: AppTheme.dashIsDark(context)
                                      ? 0.23
                                      : 0.10,
                                )
                              : AppTheme.dashMutedSurfaceOf(context),
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            key: ValueKey('attendance-day-$day'),
                            borderRadius: BorderRadius.circular(9),
                            onTap: future ? null : () => _details(day, record),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: selected || today
                                      ? AppTheme.primaryNavy
                                      : Colors.transparent,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '$day',
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: future
                                            ? AppTheme.dashTextSecondaryOf(
                                                context,
                                              ).withValues(alpha: .45)
                                            : AppTheme.dashTextPrimaryOf(
                                                context,
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (status.marked)
                                    Icon(
                                      status.icon,
                                      size: 16,
                                      color: AppTheme.dashIsDark(context)
                                          ? Color.lerp(color, Colors.white, .30)
                                          : color,
                                    )
                                  else
                                    const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final status in const [
                      AttendanceCalendarStatus.present,
                      AttendanceCalendarStatus.late,
                      AttendanceCalendarStatus.undertime,
                      AttendanceCalendarStatus.lateUndertime,
                      AttendanceCalendarStatus.absent,
                      AttendanceCalendarStatus.leave,
                      AttendanceCalendarStatus.holiday,
                      AttendanceCalendarStatus.restDay,
                      AttendanceCalendarStatus.locator,
                      AttendanceCalendarStatus.incomplete,
                      AttendanceCalendarStatus.invalid,
                      AttendanceCalendarStatus.notTracked,
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.icon, size: 14, color: status.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              status.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tap a date for details. Unmarked dates are future dates or have no processed record.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _remarkIfPresent(
    TimeRecord? record,
    AttendanceCalendarStatus status,
  ) => record == null || !status.marked ? status.label : _remark(record);
}
