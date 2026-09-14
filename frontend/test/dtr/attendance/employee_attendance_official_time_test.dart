import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_attendance_mobile_list.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/official_time.dart';

void main() {
  testWidgets('My Attendance keeps UTC punches for official-time formatting', (
    tester,
  ) async {
    final receivedPunches = <DateTime>[];
    final punch = DateTime.parse('2026-09-14T00:00:00Z');
    final record = TimeRecord(
      userId: 'employee-a',
      recordDate: DateTime(2026, 9, 14),
      timeIn: punch,
      status: 'present',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmployeeAttendanceMobileList(
              records: [record],
              formatDate: (_) => 'September 14, 2026',
              formatTime: (_, value, _) {
                if (value != null) receivedPunches.add(value);
                return formatOfficialPhilippineTime(value);
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('8:00 AM'), findsOneWidget);
    expect(receivedPunches, [punch]);
    expect(receivedPunches.single.isUtc, isTrue);
  });
}
