import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/attendance_overview/attendance_overview_data.dart';

void main() {
  final date = DateTime(2026, 10, 1);
  TimeRecord field({int late = 0, int undertime = 0}) => TimeRecord(
    userId: 'employee',
    recordDate: date,
    status: 'on_field',
    locatorSlipId: 'approved',
    attendanceRemark: 'On Field (AM IN, AM OUT, PM IN, PM OUT)',
    lateMinutes: late,
    undertimeMinutes: undertime,
  );
  for (final minutes in [0, 240]) {
    test(
      'locator attendance is not absent with calculated undertime $minutes',
      () {
        final record = field(undertime: minutes);
        expect(isCompletedAttendanceRecord(record), isTrue);
        final summary = aggregateMonthlyAttendance(
          records: [record],
          year: 2026,
          month: 10,
          now: date,
        );
        expect(summary.absent, 0);
        expect(summary.present, minutes == 0 ? 1 : 0);
        expect(summary.undertime, minutes > 0 ? 1 : 0);
      },
    );
  }
  test('locator-covered attendance retains late category', () {
    final summary = aggregateMonthlyAttendance(
      records: [field(late: 15)],
      year: 2026,
      month: 10,
      now: date,
    );
    expect(summary.late, 1);
    expect(summary.absent, 0);
  });
  test('partial locator with unresolved absence remains absent', () {
    final record = TimeRecord(
      userId: 'employee',
      recordDate: date,
      status: 'absent',
      locatorSlipId: 'partial',
      attendanceRemark: 'Incomplete',
      undertimeMinutes: 240,
      reportDeduction: const AttendanceReportDeduction(
        lateMinutes: 0,
        undertimeMinutes: 0,
        absenceMinutes: 240,
        totalMinutes: 240,
        equivalentDay: 0.5,
      ),
    );
    expect(isCompletedAttendanceRecord(record), isFalse);
    final summary = aggregateMonthlyAttendance(
      records: [record],
      year: 2026,
      month: 10,
      now: date,
    );
    expect(summary.absent, 1);
  });
}
