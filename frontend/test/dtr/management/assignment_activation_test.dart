import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';

void main() {
  late bool active, rejectActivation, unused;
  late List<RequestOptions> writes;

  setUp(() {
    active = false;
    rejectActivation = false;
    unused = false;
    writes = [];
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        dynamic data = <dynamic>[];
        if (options.method == 'PUT') {
          writes.add(options);
          if (rejectActivation) {
            handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 409,
                data: {'error': 'Assignment overlaps another active assignment.'}),
              type: DioExceptionType.badResponse,
            ));
            return;
          }
          active = (options.data as Map)['is_active'] == true;
          data = {'id': 'assignment', 'is_active': active};
        } else if (options.path == '/api/employees') {
          data = {'employees': [{'id': 'employee', 'full_name': 'Test Employee',
            'is_active': true, 'employment_status': 'active'}], 'total': 1};
        } else if (options.path == '/api/assignments/context') {
          data = {'official_date': '2026-11-08', 'first_date': '2020-01-01', 'last_date': '2030-12-31'};
        } else if (options.path == '/api/assignments') {
          data = [{
            'id': 'assignment', 'department_id': 'dept', 'department_name': 'Test Department',
            'position_id': 'position', 'position_name': 'Test Position',
            'shift_id': 'shift', 'shift_name': 'Day Shift',
            'attendance_policy_id': 'policy', 'attendance_policy_name': 'Test Policy',
            'effective_from': '2026-10-01', 'is_active': active,
            'computed_status': active ? 'Current' : 'Archived',
            'can_permanently_delete': unused,
          }];
        } else if (options.path == '/api/departments') {
          data = [{'id': 'dept', 'name': 'Test Department'}];
        } else if (options.path == '/api/positions') {
          data = [{'id': 'position', 'name': 'Test Position', 'department_id': 'dept'}];
        } else if (options.path == '/api/shifts') {
          data = [{'id': 'shift', 'name': 'Day Shift'}];
        } else if (options.path == '/api/attendance-policies') {
          data = [{'id': 'policy', 'policy_name': 'Test Policy'}];
        }
        handler.resolve(Response<dynamic>(requestOptions: options, data: data, statusCode: 200));
      },
    ));
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> openAssignment(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1800, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ManageAssignment(initialEmployeeId: 'employee'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Department').first);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(OutlinedButton, label));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), 'Correct assignment status');
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  for (final initialActive in [false, true]) {
    testWidgets('assignment lifecycle sends the opposite status (active=$initialActive)', (tester) async {
      active = initialActive;
      await openAssignment(tester);
      final label = active ? 'Deactivate' : 'Activate';
      expect(find.widgetWithText(OutlinedButton, active ? 'Activate' : 'Deactivate'), findsNothing);
      await confirm(tester, label);
      expect(writes, hasLength(1));
      expect(writes.single.path, '/api/assignments/assignment');
      expect(writes.single.data, {'is_active': !initialActive, 'change_reason': 'Correct assignment status'});
      expect(find.text('Edit Primary Assignment'), findsNothing);
      await tester.tap(find.text('Test Department').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, initialActive ? 'Activate' : 'Deactivate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed activation retains the inactive assignment and shows the backend conflict', (tester) async {
    rejectActivation = true;
    await openAssignment(tester);
    await confirm(tester, 'Activate');
    expect(active, false);
    expect(find.text('Edit Primary Assignment'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Activate'), findsOneWidget);
    expect(find.text('Assignment overlaps another active assignment.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive unused assignment can activate as well as be removed', (tester) async {
    unused = true;
    await openAssignment(tester);
    expect(find.widgetWithText(OutlinedButton, 'Activate'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Remove Unused Assignment'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Deactivate'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
