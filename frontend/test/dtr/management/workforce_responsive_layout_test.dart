import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          final dynamic data = switch (o.path) {
            '/api/employees' => {
              'employees': [
                {
                  'id': 'employee',
                  'full_name': 'Employee With A Long Display Name',
                  'employee_number': 1,
                  'is_active': true,
                  'employment_status': 'active',
                },
              ],
              'total': 1,
            },
            '/api/assignments/context' => {
              'official_date': '2026-10-10',
              'first_date': '2020-01-01',
              'last_date': '2030-12-31',
            },
            _ => <dynamic>[],
          };
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  for (final width in [720.0, 900.0, 1040.0]) {
    testWidgets('assignment layout uses available desktop width $width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const ManageAssignment(initialEmployeeId: 'employee'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final listHeader = tester.getRect(find.text('EMP ID'));
      final detailHeader = tester.getRect(
        find.text('Assignments for Employee With A Long Display Name'),
      );
      if (width < 1000) {
        expect(detailHeader.top, greaterThan(listHeader.bottom));
      } else {
        expect(detailHeader.left, greaterThan(listHeader.right));
      }
      final add = tester.getRect(find.text('Add Primary'));
      expect(add.right, lessThanOrEqualTo(width));
    });
  }
}
