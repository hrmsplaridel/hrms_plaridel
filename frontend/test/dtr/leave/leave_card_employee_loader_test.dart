import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_card_employee_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ApiClient.instance.init());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  test('Leave Card loads all eligible employees across paginated results', () async {
    final offsets = <int>[];
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o,h) {
      expect(o.path, '/api/employees');
      expect(o.queryParameters['leave_card'], 'true');
      expect(o.queryParameters['status'], 'Active');
      final offset = o.queryParameters['offset'] as int;
      offsets.add(offset);
      h.resolve(Response(requestOptions:o, statusCode:200, data:{
        'total':101, 'employees':List.generate(offset == 0 ? 100 : 1,
          (i) => {'id':'employee-${offset+i}', 'full_name':'Employee ${offset+i}'}),
      }));
    }));
    final rows = await loadLeaveCardEmployees();
    expect(rows.length,101);
    expect(offsets,[0,100]);
    expect(rows.last['id'],'employee-100');
  });
}
