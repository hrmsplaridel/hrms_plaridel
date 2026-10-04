import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/departments/pages/manage_department.dart';

void main() {
  testWidgets('department edits do not load or save reviewer assignments', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    ApiClient.instance.init();
    final requests = <RequestOptions>[];
    final dio = ApiClient.instance.dio;
    dio.interceptors.clear();
    addTearDown(dio.interceptors.clear);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path == '/api/departments' && options.method == 'GET') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {
                    'id': 'department',
                    'name': 'Human Resources',
                    'is_active': true,
                  },
                ],
              ),
            );
          } else if (options.path == '/api/departments/department' &&
              options.method == 'PUT') {
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: {}),
            );
          } else if (options.path == '/api/departments/reviewer-readiness' &&
              options.method == 'GET') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'departments': []},
              ),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ManageDepartment())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Human Resources').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Department'), findsOneWidget);
    expect(find.text('Department Reviewers'), findsNothing);
    expect(find.text('Save Reviewers'), findsNothing);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(
      requests.where(
        (request) =>
            request.path.contains('reviewer-config') ||
            request.path.contains('reviewer-backups'),
      ),
      isEmpty,
    );
    expect(
      requests.where(
        (request) => request.path == '/api/departments/reviewer-readiness',
      ),
      isNotEmpty,
    );
    expect(requests.singleWhere((r) => r.method == 'PUT').data, {
      'name': 'Human Resources',
      'description': null,
    });
    expect(tester.takeException(), isNull);
  });
}
