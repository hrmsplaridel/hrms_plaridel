import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employee_details_view.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    ApiClient.instance.init();
  });
  tearDownAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        ),
  );
  setUp(() => ApiClient.instance.dio.interceptors.clear());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  for (final scenario in ['eligible', 'ineligible', 'historical']) {
    testWidgets('employee details show available credits for $scenario', (
      tester,
    ) async {
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'full_name': 'Balance Employee',
                  'leave_credit_eligible': scenario == 'eligible',
                  'assignment_history': [],
                  'credit_balances': scenario == 'ineligible'
                      ? []
                      : [
                          {
                            'user_id': 'employee',
                            'leave_type': 'vacationLeave',
                            'earned_days': '10',
                            'used_days': '2',
                            'pending_days': '1',
                            'adjusted_days': '0.5',
                          },
                        ],
                },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: EmployeeDetailsView(employeeId: 'employee')),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Leave credits'),
        250,
        scrollable: scrollable,
      );
      if (scenario == 'ineligible') {
        expect(
          find.text('This employee does not earn monthly VL/SL credits.'),
          findsOneWidget,
        );
        expect(find.text('Vacation Leave'), findsNothing);
      } else {
        expect(find.text('Vacation Leave'), findsOneWidget);
        expect(find.text('7.50 days'), findsOneWidget);
        expect(find.text('Pending'), findsWidgets);
      }
    });
  }
  for (final width in [420.0, 900.0]) {
    testWidgets('employee details are read-only and fit $width pixels', (
      tester,
    ) async {
      var writes = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            expect(o.path, '/api/employees/employee/details');
            if (o.method != 'GET') writes++;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'full_name': 'Employee Example',
                  'employee_number': 11,
                  'email': 'example@test.com',
                  'role': 'admin',
                  'is_active': false,
                  'civil_status': 'Single',
                  'nationality': 'Filipino',
                  'employment_type': 'contract_of_service',
                  'leave_credit_eligible': false,
                  'address': 'Purok 1|Bato|Plaridel|Misamis Occidental',
                  'date_of_birth': '1990-05-10',
                  'date_hired': '2026-01-01',
                  'assignment_history': [
                    {
                      'department_name': 'Human Resources',
                      'position_name': 'Staff',
                      'shift_name': 'Regular shift',
                      'effective_from': '2026-01-01',
                      'effective_to': null,
                      'status': 'Current',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: EmployeeDetailsView(employeeId: 'employee')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Employee Example'), findsOneWidget);
      expect(find.text('Contract of Service (COS)'), findsOneWidget);
      expect(
        find.text('Purok 1, Bato, Plaridel, Misamis Occidental'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Regular shift'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Regular shift'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed details fetch offers a retry', (tester) async {
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          calls++;
          if (calls == 1) {
            h.reject(
              DioException(
                requestOptions: o,
                response: Response(
                  requestOptions: o,
                  statusCode: 403,
                  data: {'error': 'Employee access disabled'},
                ),
              ),
            );
          } else {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'full_name': 'Recovered Employee',
                  'assignment_history': [],
                },
              ),
            );
          }
        },
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: EmployeeDetailsView(employeeId: 'employee')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Employee access disabled'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered Employee'), findsOneWidget);
    expect(calls, 2);
  });
}
