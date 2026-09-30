import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/pages/manage_position.dart';

void main() {
  testWidgets('position edits leave approval designations unchanged', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    ApiClient.instance.init();
    final requests = <RequestOptions>[];
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          dynamic data;
          if (options.method == 'PUT') {
            data = {'id': '22222222-2222-4222-8222-222222222222'};
          } else if (options.path == '/api/departments') {
            data = <Map<String, dynamic>>[
              {
                'id': '11111111-1111-4111-8111-111111111111',
                'name': 'Human Resources',
                'is_active': true,
              },
            ];
          } else if (options.path == '/api/positions') {
            data = <String, dynamic>{
              'items': <Map<String, dynamic>>[
                {
                  'id': '22222222-2222-4222-8222-222222222222',
                  'name': 'HR Staff',
                  'department_id': '11111111-1111-4111-8111-111111111111',
                  'department_name': 'Human Resources',
                  'is_active': true,
                  'is_department_head': true,
                  'is_leave_final_reviewer': true,
                  'department_head_period_id': 'existing-period',
                  'department_head_effective_from': '2026-01-01',
                },
              ],
              'pagination': {'page': 1, 'page_count': 1, 'total': 1},
            };
          } else if (options.path ==
              '/api/positions/department-head-conflict') {
            data = <String, dynamic>{
              'position_id': '33333333-3333-4333-8333-333333333333',
              'position_name': 'Department Head',
            };
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ),
            );
            return;
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ManagePosition())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('HR Staff').first);
    await tester.pumpAndSettle();

    expect(find.text('Official Department Head'), findsNothing);
    expect(find.text('Official Leave Final Reviewer'), findsNothing);
    expect(find.text('Save Reviewers'), findsNothing);
    expect(
      requests.where(
        (r) =>
            r.path.contains('reviewer') ||
            r.path.contains('department-head-conflict'),
      ),
      isEmpty,
    );

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    final payload = requests.singleWhere((r) => r.method == 'PUT').data as Map;
    expect(payload, {
      'name': 'HR Staff',
      'description': null,
      'department_id': '11111111-1111-4111-8111-111111111111',
    });
  });
}
