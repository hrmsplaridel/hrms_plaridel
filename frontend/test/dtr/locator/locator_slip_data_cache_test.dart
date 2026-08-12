import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';

void main() {
  test('locator request cache keys are isolated by user ID', () {
    final employeeAKey = LocatorSlipDataCache.requestCacheKeyForUser(
      scope: 'my',
      userId: 'employee-a',
      role: 'employee',
    );
    final employeeBKey = LocatorSlipDataCache.requestCacheKeyForUser(
      scope: 'my',
      userId: 'employee-b',
      role: 'employee',
    );

    expect(employeeAKey, isNot(employeeBKey));
    expect(employeeAKey, contains('employee-a'));
    expect(employeeBKey, contains('employee-b'));
  });

  test('privileged locator cache keys include role and stable filters', () {
    final adminKey = LocatorSlipDataCache.requestCacheKeyForUser(
      scope: 'admin',
      userId: 'reviewer-1',
      role: 'admin',
      query: const {'status': 'approved', 'request_type': 'locator'},
    );
    final hrKey = LocatorSlipDataCache.requestCacheKeyForUser(
      scope: 'admin',
      userId: 'reviewer-1',
      role: 'hr',
      query: const {'request_type': 'locator', 'status': 'approved'},
    );

    expect(adminKey, isNot(hrKey));
    expect(adminKey, contains('role=admin'));
    expect(hrKey, contains('role=hr'));
    expect(
      adminKey.substring(adminKey.indexOf('?')),
      hrKey.substring(hrKey.indexOf('?')),
    );
  });

  test('locator cache keys reject a missing user scope', () {
    expect(
      () => LocatorSlipDataCache.requestCacheKeyForUser(
        scope: 'my',
        userId: '   ',
      ),
      throwsArgumentError,
    );
  });

  test('admin locator pages parse records, totals, and filter options', () {
    final page = LocatorAdminRequestPage.fromData({
      'items': [
        {'id': 'locator-1', 'status': 'approved'},
      ],
      'pagination': {
        'page': 3,
        'page_size': 10,
        'total': 27,
        'page_count': 3,
      },
      'filter_options': {
        'departments': [
          {'id': 'department-1', 'name': 'Human Resources'},
        ],
        'employees': [
          {
            'id': 'employee-1',
            'name': 'Employee One',
            'department_ids': ['department-1'],
          },
        ],
      },
    });

    expect(page.items.single['id'], 'locator-1');
    expect(page.page, 3);
    expect(page.total, 27);
    expect(page.pageCount, 3);
    expect(page.departments.single.name, 'Human Resources');
    expect(page.employees.single.departmentIds, ['department-1']);
  });

  test('admin locator page parser supports the legacy list response', () {
    final page = LocatorAdminRequestPage.fromData([
      {'id': 'locator-1'},
      {'id': 'locator-2'},
    ]);

    expect(page.items, hasLength(2));
    expect(page.total, 2);
    expect(page.pageCount, 1);
  });
}
