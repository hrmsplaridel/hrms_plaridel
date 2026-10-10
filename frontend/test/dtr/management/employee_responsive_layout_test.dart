import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: options.path == '/api/employees'
                ? [
                    {
                      'id': 'employee',
                      'employee_number': 1,
                      'full_name': 'Test Employee',
                      'role': 'employee',
                      'is_active': true,
                    },
                  ]
                : options.path == '/api/employees/employee/details'
                ? {'id': 'employee', 'full_name': 'Test Employee', 'assignment_history': []}
                : <dynamic>[],
          ),
        ),
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  testWidgets('selected employee opens full details from the existing panel', (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child: ManageEmployee(canCreateAccount:true)))));
    await tester.pumpAndSettle();
    expect(find.text('View full details'),findsNothing);
    await tester.tap(find.text('Test Employee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View full details'));
    await tester.pumpAndSettle();
    expect(find.text('Employee full details'),findsOneWidget);
    expect(find.text('No assignments recorded.'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  for (final width in [1020.0, 860.0, 600.0, 360.0]) {
    testWidgets('employee content fits $width pixels within a desktop window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const SingleChildScrollView(
                  child: ManageEmployee(canCreateAccount: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Test Employee'), findsOneWidget);
      expect(find.text('Page 1 / 1'), findsOneWidget);
      final employee = tester.getRect(find.text('Test Employee'));
      final details = tester.getRect(find.text('Select an employee'));
      if (width < 900) expect(details.top, greaterThan(employee.bottom));
    });
  }
}
