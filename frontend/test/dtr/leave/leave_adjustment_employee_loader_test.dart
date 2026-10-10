import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_adjustment_employee_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ApiClient.instance.init());
  setUp(() => ApiClient.instance.dio.interceptors.clear());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  test(
    'adjustment picker excludes JO/COS and disabled credits and loads all pages',
    () async {
      final offsets = <int>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            expect(o.queryParameters['credit_adjustment'], 'true');
            expect(o.queryParameters['limit'], 100);
            final offset = o.queryParameters['offset'] as int;
            offsets.add(offset);
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'total': 103,
                  'employees': offset == 0
                      ? List.generate(
                          100,
                          (i) => {
                            'id': 'eligible-$i',
                            'employment_type': 'permanent',
                            'leave_credit_eligible': true,
                          },
                        )
                      : [
                          {
                            'id': 'jo',
                            'employment_type': 'job_order',
                            'leave_credit_eligible': true,
                          },
                          {
                            'id': 'cos',
                            'employment_type': 'contract_of_service',
                            'leave_credit_eligible': true,
                          },
                          {
                            'id': 'disabled',
                            'employment_type': 'permanent',
                            'leave_credit_eligible': false,
                          },
                        ],
                },
              ),
            );
          },
        ),
      );
      final rows = await loadLeaveAdjustmentEmployees();
      expect(rows.length, 100);
      expect(offsets, [0, 100]);
      expect(
        rows.any((e) => ['jo', 'cos', 'disabled'].contains(e['id'])),
        isFalse,
      );
    },
  );
}
