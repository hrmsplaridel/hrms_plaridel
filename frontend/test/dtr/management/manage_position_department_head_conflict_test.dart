import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/pages/manage_position.dart';

void main() {
  testWidgets('disables head designation when another position owns it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data;
          if (options.path == '/api/departments') {
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

    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Official Department Head'),
    );
    expect(toggle.onChanged, isNull);
    expect(
      find.textContaining('Department Head already holds'),
      findsOneWidget,
    );
  });
}
