import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/utils/employee_attendance_period.dart';

void main() {
  final officialDate = DateTime(2026, 9, 14);

  test('attendance period options exclude future years and months', () {
    expect(selectableEmployeeAttendanceYears(officialDate), [
      2021,
      2022,
      2023,
      2024,
      2025,
      2026,
    ]);
    expect(selectableEmployeeAttendanceMonths(2026, officialDate), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
    ]);
    expect(
      selectableEmployeeAttendanceMonths(2025, officialDate),
      hasLength(12),
    );
    expect(selectableEmployeeAttendanceMonths(2027, officialDate), isEmpty);
  });

  test('attendance range rejects reversed and future requests', () {
    expect(
      isValidEmployeeAttendanceRange(
        start: DateTime(2026, 9, 1),
        end: officialDate,
        officialDate: officialDate,
      ),
      isTrue,
    );
    expect(
      isValidEmployeeAttendanceRange(
        start: DateTime(2027, 1, 1),
        end: officialDate,
        officialDate: officialDate,
      ),
      isFalse,
    );
    expect(
      isValidEmployeeAttendanceRange(
        start: DateTime(2026, 9, 15),
        end: DateTime(2026, 9, 15),
        officialDate: officialDate,
      ),
      isFalse,
    );
  });
}
