import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/data/employee_list_request_guard.dart';

Map<String, dynamic> query({
  String department = 'hr',
  String status = 'Active',
  String role = 'All',
  String search = '',
  String sort = 'employee_number',
  String order = 'asc',
  int limit = 25,
  int offset = 0,
}) => <String, dynamic>{
  'department_id': department,
  'status': status,
  'role': role,
  'q': search,
  'sort': sort,
  'order': order,
  'limit': limit,
  'offset': offset,
};

void main() {
  test('new department request rejects an older successful response', () {
    final guard = EmployeeListRequestGuard();
    final hrRequest = guard.begin(query(department: 'hr'));
    final financeRequest = guard.begin(query(department: 'finance'));

    expect(guard.accepts(financeRequest, query(department: 'finance')), isTrue);
    expect(guard.accepts(hrRequest, query(department: 'finance')), isFalse);
  });

  test(
    'search, sort, paging, and page-size changes invalidate old results',
    () {
      final guard = EmployeeListRequestGuard();
      final request = guard.begin(query());

      expect(guard.accepts(request, query(search: 'maria')), isFalse);
      expect(guard.accepts(request, query(sort: 'full_name')), isFalse);
      expect(guard.accepts(request, query(offset: 25)), isFalse);
      expect(guard.accepts(request, query(limit: 50)), isFalse);
    },
  );

  test('an invalidated request cannot update success or error state', () {
    final guard = EmployeeListRequestGuard();
    final request = guard.begin(query());

    guard.invalidate();

    expect(guard.accepts(request, query()), isFalse);
  });

  test(
    'query-map insertion order does not invalidate an identical request',
    () {
      final guard = EmployeeListRequestGuard();
      final original = query();
      final request = guard.begin(original);
      final reordered = <String, dynamic>{
        for (final key in original.keys.toList().reversed) key: original[key],
      };

      expect(guard.accepts(request, reordered), isTrue);
    },
  );
}
