import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_attendance_month_calendar.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/official_time.dart';

void main() {
  final today = DateTime(2026, 11, 17);
  TimeRecord record(
    int day, {
    String? status,
    int late = 0,
    int under = 0,
    bool leave = false,
  }) => TimeRecord(
    userId: 'employee',
    recordDate: DateTime(2026, 11, day),
    status: status,
    lateMinutes: late,
    undertimeMinutes: under,
    isLeaveCovered: leave,
    attendanceRemark: status == 'present' ? 'On Time' : null,
    timeIn: status == 'present' ? DateTime(2026, 11, day, 8) : null,
    breakOut: status == 'present' ? DateTime(2026, 11, day, 12) : null,
    breakIn: status == 'present' ? DateTime(2026, 11, day, 13) : null,
    timeOut: status == 'present' ? DateTime(2026, 11, day, 17) : null,
  );
  test(
    'calendar uses actual statuses, retains late and undertime, and leaves future/unknown dates unmarked',
    () {
      expect(
        attendanceCalendarStatus(null, today),
        AttendanceCalendarStatus.unprocessed,
      );
      expect(
        attendanceCalendarStatus(record(3), today),
        AttendanceCalendarStatus.unprocessed,
      );
      expect(
        attendanceCalendarStatus(record(18, status: 'absent'), today),
        AttendanceCalendarStatus.future,
      );
      expect(
        attendanceCalendarStatus(record(3, status: 'absent'), today),
        AttendanceCalendarStatus.absent,
      );
      expect(
        attendanceCalendarStatus(record(3, status: 'rest_day'), today),
        AttendanceCalendarStatus.restDay,
      );
      expect(
        attendanceCalendarStatus(record(3, status: 'not_tracked'), today),
        AttendanceCalendarStatus.notTracked,
      );
      expect(
        attendanceCalendarStatus(
          record(3, status: 'present', leave: true),
          today,
        ),
        AttendanceCalendarStatus.leave,
      );
      expect(
        attendanceCalendarStatus(
          record(3, status: 'present', late: 11, under: 46),
          today,
        ),
        AttendanceCalendarStatus.lateUndertime,
      );
    },
  );
  for (final width in [320.0, 430.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'monthly calendar at $width in $brightness opens details and switches to list',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1000);
          addTearDown(tester.view.reset);
          final rows = [
            record(3, status: 'present', late: 11, under: 46).copyWith(
              source: 'adjusted',
              remarks: 'Verified corrected punches',
            ),
            record(4, status: 'holiday'),
            record(5, status: 'rest_day'),
            record(6, status: 'absent'),
            record(18, status: 'absent'),
          ];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: EmployeeAttendanceMonthCalendar(
                    year: 2026,
                    month: 11,
                    officialDate: today,
                    records: rows,
                    formatDate: (date) => '${date.day} Nov',
                    formatTime: (r, time, segment) =>
                        formatOfficialPhilippineTime(
                          time,
                          attendanceDate: r.recordDate,
                        ),
                  ),
                ),
              ),
            ),
          );
          expect(
            find.byKey(const ValueKey('attendance-month-grid')),
            findsOneWidget,
          );
          expect(find.text('November 2026'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('attendance-day-3')));
          await tester.pumpAndSettle();
          expect(find.text('Late: 11 min'), findsOneWidget);
          expect(find.text('Undertime: 46 min'), findsOneWidget);
          expect(find.text('Verified corrected punches'), findsOneWidget);
          expect(find.text('Adjusted'), findsOneWidget);
          await tester.tap(find.byTooltip('Close day details'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('attendance-day-7')));
          await tester.pumpAndSettle();
          expect(
            find.text('No processed attendance record for this date.'),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Close day details'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('List'));
          await tester.tap(find.text('List'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('attendance-month-grid')),
            findsNothing,
          );
          expect(find.text('3 Nov'), findsOneWidget);
          expect(find.text('18 Nov'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'calendar stays usable at 320 pixels with larger text and leaves future cells disabled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1100);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: EmployeeAttendanceMonthCalendar(
                  year: 2026,
                  month: 11,
                  officialDate: today,
                  records: const [],
                  formatDate: (date) => '${date.day}',
                  formatTime: (r, time, segment) => '—',
                  onPreviousMonth: () {},
                  onNextMonth: () {},
                  onCurrentMonth: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('attendance-day-18')))
            .onTap,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
