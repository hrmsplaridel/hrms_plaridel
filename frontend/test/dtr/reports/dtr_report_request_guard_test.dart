import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_request_guard.dart';

void main() {
  test('only the newest employee request is accepted', () {
    final guard = DtrReportRequestGuard();
    final employeeA = guard.begin(
      employeeId: 'employee-a',
      departmentId: 'hr',
      employeeStatus: 'Active',
      year: 2026,
      month: 8,
    );
    final employeeB = guard.begin(
      employeeId: 'employee-b',
      departmentId: 'hr',
      employeeStatus: 'Active',
      year: 2026,
      month: 8,
    );

    expect(
      guard.accepts(
        employeeB,
        employeeId: 'employee-b',
        departmentId: 'hr',
        employeeStatus: 'Active',
        year: 2026,
        month: 8,
      ),
      isTrue,
    );
    expect(
      guard.accepts(
        employeeA,
        employeeId: 'employee-b',
        departmentId: 'hr',
        employeeStatus: 'Active',
        year: 2026,
        month: 8,
      ),
      isFalse,
    );
  });

  test('month and department changes reject an older response', () {
    final guard = DtrReportRequestGuard();
    final request = guard.begin(
      employeeId: 'employee-a',
      departmentId: 'hr',
      employeeStatus: 'Active',
      year: 2026,
      month: 7,
    );

    expect(
      guard.accepts(
        request,
        employeeId: 'employee-a',
        departmentId: 'finance',
        employeeStatus: 'Active',
        year: 2026,
        month: 8,
      ),
      isFalse,
    );
  });

  test('employee status changes reject an older response', () {
    final guard = DtrReportRequestGuard();
    final request = guard.begin(
      employeeId: 'employee-a',
      departmentId: 'hr',
      employeeStatus: 'Inactive',
      year: 2026,
      month: 8,
    );

    expect(
      guard.accepts(
        request,
        employeeId: 'employee-a',
        departmentId: 'hr',
        employeeStatus: 'Active',
        year: 2026,
        month: 8,
      ),
      isFalse,
    );
  });
}
