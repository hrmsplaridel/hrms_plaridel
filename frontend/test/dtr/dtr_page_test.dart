import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/dtr_routes.dart';

/// Locks the admin DTR page permissions that used to live in numbered lists
/// in `admin_dashboard_desktop.dart`.
void main() {
  const managePages = {
    DtrPage.timeLogs,
    DtrPage.assignments,
    DtrPage.departments,
    DtrPage.positions,
    DtrPage.shifts,
    DtrPage.weeklySchedule,
    DtrPage.holidays,
    DtrPage.attendancePolicies,
    DtrPage.biometricDevices,
  };
  const featurePages = {
    DtrPage.employees: 'employees_allowed',
    DtrPage.leave: 'leave_allowed',
    DtrPage.locator: 'locator_allowed',
    DtrPage.approvals: 'approvals_allowed',
  };
  const features = [
    'employees_allowed',
    'leave_allowed',
    'locator_allowed',
    'approvals_allowed',
  ];

  bool expectedAllowed(
    DtrPage page, {
    required bool manage,
    required bool reports,
    required Map<String, bool> access,
  }) {
    if (page == DtrPage.home) return true;
    if (page == DtrPage.reports) return reports;
    if (managePages.contains(page)) return manage;
    return access[featurePages[page]] == true;
  }

  test('every page is covered by exactly one permission rule', () {
    for (final page in DtrPage.values) {
      final rules = [
        page == DtrPage.home,
        page == DtrPage.reports,
        managePages.contains(page),
        featurePages.containsKey(page),
      ].where((r) => r).length;
      expect(rules, 1, reason: page.name);
    }
  });

  test('isAllowed matches the previous permission checks', () {
    for (final manage in [false, true]) {
      for (final reports in [false, true]) {
        for (final granted in [null, ...features]) {
          final access = {if (granted != null) granted: true};
          for (final page in DtrPage.values) {
            expect(
              page.isAllowed(
                canManageDtr: manage,
                canViewReports: reports,
                featureAccess: access,
              ),
              expectedAllowed(
                page,
                manage: manage,
                reports: reports,
                access: access,
              ),
              reason: '$page manage=$manage reports=$reports $granted',
            );
          }
        }
      }
    }
  });

  test('a feature flag set to false does not grant access', () {
    expect(
      DtrPage.leave.isAllowed(
        canManageDtr: true,
        canViewReports: true,
        featureAccess: const {'leave_allowed': false},
      ),
      isFalse,
    );
  });

  test('workforce pages keep the tab order', () {
    expect(DtrPage.workforcePages, [
      DtrPage.assignments,
      DtrPage.departments,
      DtrPage.positions,
      DtrPage.shifts,
      DtrPage.weeklySchedule,
      DtrPage.holidays,
      DtrPage.attendancePolicies,
    ]);
    for (final page in DtrPage.values) {
      expect(
        page.isWorkforce,
        DtrPage.workforcePages.contains(page),
        reason: page.name,
      );
    }
  });

  test('titles match the cards and tabs', () {
    const expected = {
      DtrPage.home: 'DTR',
      DtrPage.timeLogs: 'Time Logs',
      DtrPage.reports: 'Reports',
      DtrPage.employees: 'Employees',
      DtrPage.assignments: 'Assignments',
      DtrPage.departments: 'Departments',
      DtrPage.positions: 'Positions',
      DtrPage.shifts: 'Shifts',
      DtrPage.weeklySchedule: 'Weekly Schedule',
      DtrPage.holidays: 'Holidays',
      DtrPage.attendancePolicies: 'Attendance Policies',
      DtrPage.leave: 'Leave Management',
      DtrPage.biometricDevices: 'Biometric Devices',
      DtrPage.locator: 'Locator & Pass Management',
      DtrPage.approvals: 'Approvals & Signatories',
    };
    expect(DtrPage.values.toSet(), expected.keys.toSet());
    expected.forEach((page, title) => expect(page.title, title));
  });
}
