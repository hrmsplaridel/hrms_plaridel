import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_employee_status.dart';

void main() {
  final today = DateTime(2026, 9, 19);

  test('historical months include all current employee statuses', () {
    expect(
      reportEmployeeStatusForPeriod(year: 2026, month: 8, today: today),
      'All',
    );
    expect(
      reportEmployeeStatusForPeriod(year: 2025, month: 12, today: today),
      'All',
    );
  });

  test('current month defaults to active employees', () {
    expect(
      reportEmployeeStatusForPeriod(year: 2026, month: 9, today: today),
      'Active',
    );
  });

  test('manual status stays selected when the report period changes', () {
    expect(
      reportEmployeeStatusForPeriod(
        year: 2026,
        month: 8,
        today: today,
        manualStatus: 'Inactive',
      ),
      'Inactive',
    );
  });

  test('undated inactive employment is unverified, not disabled login', () {
    expect(hasUndatedInactiveEmployment(employmentStatus: 'inactive'), isTrue);
    expect(hasUndatedInactiveEmployment(employmentStatus: 'active'), isFalse);
    expect(hasUndatedInactiveEmployment(employmentStatus: 'resigned'), isFalse);
  });

  test('only generated absent rows are excluded from unverified reports', () {
    expect(isSyntheticAbsentRow(id: null, status: 'absent'), isTrue);
    expect(isSyntheticAbsentRow(id: 'saved', status: 'absent'), isFalse);
    expect(isSyntheticAbsentRow(id: null, status: 'on_leave'), isFalse);
  });
}
