import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';

void main() {
  late List<Map<String, dynamic>> employees;
  late bool legacyList;
  late bool prefillOnly;
  late List<RequestOptions> requests;

  setUp(() {
    employees = [
      {
        'id': 'inactive-employee',
        'full_name': 'Inactive Employee',
        'employee_number': 1,
        'is_active': false,
        'employment_status': 'active',
      },
      {
        'id': 'active-employee',
        'full_name': 'Active Employee',
        'employee_number': 2,
        'is_active': true,
        'employment_status': 'active',
      },
    ];
    legacyList = false;
    prefillOnly = false;
    requests = [];
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          dynamic data;
          switch (options.path) {
            case '/api/employees':
              final list = prefillOnly ? <Map<String, dynamic>>[] : employees;
              data = legacyList
                  ? list
                  : {'employees': list, 'total': list.length};
              break;
            case '/api/employees/inactive-employee':
              data = employees.first;
              break;
            case '/api/assignments/context':
              data = {
                'official_date': '2026-09-15',
                'first_date': '2020-01-01',
                'last_date': '2030-12-31',
              };
              break;
            case '/api/assignments':
            case '/api/employee-other-positions':
            case '/api/departments':
            case '/api/positions':
            case '/api/shifts':
            case '/api/attendance-policies':
              data = <dynamic>[];
              break;
            default:
              handler.reject(
                DioException(
                  requestOptions: options,
                  message: 'Unexpected request: ${options.path}',
                ),
              );
              return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: data,
              statusCode: 200,
            ),
          );
        },
      ),
    );
  });

  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> openPage(WidgetTester tester, {String? employeeId}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1800, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManageAssignment(initialEmployeeId: employeeId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectAddEnabled(WidgetTester tester, bool enabled) {
    final primary = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add Primary'),
    );
    final other = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Add Other'),
    );
    expect(primary.onPressed != null, enabled);
    expect(other.onPressed != null, enabled);
    expect(
      find.byKey(const Key('assignment-inactive-employee')),
      enabled ? findsNothing : findsOneWidget,
    );
  }

  for (final useLegacyList in [false, true]) {
    testWidgets(
      'inactive employee cannot add; switching to active enables both (legacy=$useLegacyList)',
      (tester) async {
        legacyList = useLegacyList;
        await openPage(tester);
        await tester.tap(find.text('Inactive Employee'));
        await tester.pumpAndSettle();
        expectAddEnabled(tester, false);
        expect(requests.where((r) => r.path == '/api/assignments'), isNotEmpty);
        expect(
          requests.where((r) => r.path == '/api/employee-other-positions'),
          isNotEmpty,
        );
        await tester.tap(find.text('Add Primary'));
        await tester.tap(find.text('Add Other'));
        await tester.pumpAndSettle();
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
        await tester.tap(find.text('Active Employee'));
        await tester.pumpAndSettle();
        expectAddEnabled(tester, true);
        await tester.tap(find.text('Inactive Employee'));
        await tester.pumpAndSettle();
        expectAddEnabled(tester, false);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('non-active employment status blocks an enabled account', (
    tester,
  ) async {
    employees.first['is_active'] = true;
    employees.first['employment_status'] = 'resigned';
    await openPage(tester, employeeId: 'inactive-employee');
    expectAddEnabled(tester, false);
  });

  testWidgets(
    'employee deep link outside the loaded page retains inactive status',
    (tester) async {
      prefillOnly = true;
      await openPage(tester, employeeId: 'inactive-employee');
      expectAddEnabled(tester, false);
      expect(
        requests.where((r) => r.path == '/api/employees/inactive-employee'),
        hasLength(1),
      );
    },
  );
}
