import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_attendance_mobile_list.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/official_time.dart';

void main() {
  final record = TimeRecord(
    userId: 'employee',
    recordDate: DateTime(2026, 9, 30),
    timeIn: DateTime.parse('2026-09-30T20:00:00+08:00'),
    timeOut: DateTime.parse('2026-10-01T07:00:00+08:00'),
    totalHours: 11,
    status: 'present',
    shiftPunchMode: 'single_session',
    shiftIsOvernight: true,
  );

  test(
    'two punches complete a single session without invented break punches',
    () {
      expect(getAttendanceRemark(record), 'On Time');
      expect(formatWorkedHours(record), '11 h');
      expect(record.copyWith().shiftIsOvernight, isTrue);
    },
  );

  for (final width in [320.0, 430.0]) {
    testWidgets(
      'night attendance at $width shows one pair and a next-day marker',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EmployeeAttendanceMobileList(
                  records: [record],
                  formatDate: (_) => 'September 30, 2026',
                  formatTime: (r, time, _) => formatOfficialPhilippineTime(
                    time,
                    attendanceDate: r.recordDate,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Time In'), findsOneWidget);
        expect(find.text('Time Out'), findsOneWidget);
        expect(find.text('AM Out'), findsNothing);
        expect(find.text('PM In'), findsNothing);
        expect(find.text('7:00 AM (+1 day)'), findsOneWidget);
        expect(find.text('Hours Worked: 11 h'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
