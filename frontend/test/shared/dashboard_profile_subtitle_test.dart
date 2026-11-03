import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';

void main() {
  for (final role in ['admin', 'employee', 'mayor', 'mayor_office_staff']) {
    test('sidebar uses assigned position for $role accounts', () {
      final user = AppUser(
        id: 'position-test',
        email: 'position@example.test',
        role: role,
        positionName: '  Human Resource Management Officer  ',
      );
      expect(
        dashboardAccountPositionLabel(user),
        'Human Resource Management Officer',
      );
    });
  }

  for (final position in [null, '', '   ']) {
    test('sidebar falls back to role for unassigned position "$position"', () {
      final user = AppUser(
        id: 'position-test',
        email: 'position@example.test',
        role: 'admin',
        positionName: position,
      );
      expect(dashboardAccountPositionLabel(user), 'Admin');
    });
  }

  test('missing account still has a safe subtitle', () {
    expect(dashboardAccountPositionLabel(null), 'Employee');
  });
}
