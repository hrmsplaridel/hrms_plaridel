import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';

void main() {
  Map<String, dynamic>? submitted;
  bool returned = false;
  String employmentStatus = 'resigned';
  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    submitted = null;
    returned = false;
    employmentStatus = 'resigned';
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data = <dynamic>[];
          if (options.path == '/api/employees/employee/return-to-service') {
            submitted = Map<String, dynamic>.from(options.data as Map);
            returned = true;
            data = {
              'id': 'employee',
              'employment_status': 'active',
              'is_active': true,
            };
          } else if (options.path == '/api/employees') {
            data = [
              {
                'id': 'employee',
                'employee_number': 1,
                'full_name': 'Returning Employee',
                'role': 'employee',
                'is_active': returned || employmentStatus == 'active',
                'employment_status': returned ? 'active' : employmentStatus,
                'date_hired': '2025-01-01',
                'separation_date': returned || employmentStatus == 'active'
                    ? null
                    : '2026-09-15',
                'employment_type': 'permanent',
                'leave_credit_eligible': false,
              },
            ];
          } else if (options.path == '/api/departments') {
            data = [
              {'id': 'department', 'name': 'Accounting', 'is_active': true},
            ];
          } else if (options.path == '/api/positions') {
            data = [
              {
                'id': 'position',
                'name': 'Accounting Staff',
                'department_id': 'department',
                'is_active': true,
              },
            ];
          } else if (options.path == '/api/shifts') {
            data = [
              {'id': 'shift', 'name': 'Office hours', 'is_active': true},
            ];
          } else if (options.path == '/api/attendance-policies') {
            data = [
              {'id': 'policy', 'name': 'Standard policy', 'is_active': true},
            ];
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> open(
    WidgetTester tester,
    double width, {
    bool openReturn = true,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManageEmployee(canCreateAccount: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Returning Employee').first);
    await tester.pumpAndSettle();
    if (!openReturn) return;
    await tester.ensureVisible(find.text('Return to service'));
    await tester.tap(find.text('Return to service'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'deceased employee has no return, login-enable or end-employment action',
    (tester) async {
      employmentStatus = 'deceased';
      await open(tester, 390, openReturn: false);
      expect(find.text('Return to service'), findsNothing);
      expect(find.text('Enable login'), findsNothing);
      expect(find.text('End employment'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expired contract retains the return-to-service action', (
    tester,
  ) async {
    employmentStatus = 'contract_expired';
    await open(tester, 390, openReturn: false);
    expect(find.text('Return to service'), findsOneWidget);
    expect(find.text('End employment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('end employment offers deceased and contract-expired reasons', (
    tester,
  ) async {
    employmentStatus = 'active';
    await open(tester, 390, openReturn: false);
    await tester.ensureVisible(find.text('End employment'));
    await tester.tap(find.text('End employment'));
    await tester.pumpAndSettle();
    final reason = find.byKey(const Key('end_employment_reason'));
    await tester.tap(reason);
    await tester.pumpAndSettle();
    expect(find.text('Deceased'), findsOneWidget);
    expect(find.text('Contract expired'), findsOneWidget);
    await tester.tap(find.text('Deceased'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1366.0]) {
    testWidgets(
      'return to service validates and submits a new assignment at width $width',
      (tester) async {
        await open(tester, width);
        expect(find.textContaining('Login will be enabled'), findsOneWidget);
        final submit = find.widgetWithText(FilledButton, 'Confirm return');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(submitted, isNull);
        expect(find.text('Reason is required'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('return_reason')));
        await tester.enterText(
          find.byKey(const Key('return_reason')),
          'Approved return to municipal service',
        );
        for (final (key, label) in [
          ('return_department', 'Accounting'),
          ('return_position', 'Accounting Staff'),
          ('return_shift', 'Office hours'),
        ]) {
          final field = find.byKey(Key(key));
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(submitted, isNotNull);
        expect(submitted!['assignment'], {
          'department_id': 'department',
          'position_id': 'position',
          'shift_id': 'shift',
        });
        expect(submitted!['leave_credit_eligible'], false);
        expect(
          submitted!['returned_on'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
        expect(find.text('Confirm return'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
