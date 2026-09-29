import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_summary_equivalent_day.dart';

void main() {
  test('no selected employee does not calculate equivalent days', () {
    var calls = 0;
    final result = summaryEquivalentDay(
      employeeId: null,
      hasRecords: false,
      hasUnverifiedInactiveAttendance: false,
      calculate: () {
        calls++;
        return 16;
      },
    );

    expect(result, 0);
    expect(calls, 0);
  });

  test('selected employee with records uses the official calculation', () {
    expect(
      summaryEquivalentDay(
        employeeId: 'employee-1',
        hasRecords: true,
        hasUnverifiedInactiveAttendance: false,
        calculate: () => 1.25,
      ),
      1.25,
    );
  });

  test('unverified inactive attendance stays unverified', () {
    expect(
      summaryEquivalentDay(
        employeeId: 'employee-1',
        hasRecords: true,
        hasUnverifiedInactiveAttendance: true,
        calculate: () => 16,
      ),
      isNull,
    );
  });
}
