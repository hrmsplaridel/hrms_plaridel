import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';

class _Auth extends AuthProvider {
  _Auth(this.role);
  final String role;
  @override
  AppUser get user =>
      AppUser(id: 'actor', email: 'actor@example.test', role: role);
}

void main() {
  setUpAll(() => ApiClient.instance.init());
  setUp(() => ApiClient.instance.dio.interceptors.clear());
  testWidgets('Mayor profiles display and retain their role during editing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: options.path == '/api/employees'
                ? [
                    {
                      'id': 'mayor-user',
                      'employee_number': 123,
                      'full_name': 'Mayor Example',
                      'first_name': 'Mayor',
                      'last_name': 'Example',
                      'email': 'mayor@example.test',
                      'role': 'mayor',
                      'is_active': true,
                      'date_hired': '2026-10-08',
                      'employment_status': 'active',
                    },
                  ]
                : <dynamic>[],
          ),
        ),
      ),
    );
    addTearDown(() => ApiClient.instance.dio.interceptors.clear());
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ManageEmployee(canCreateAccount: false)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mayor'), findsOneWidget);
    await tester.tap(find.text('Mayor Example').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.initialValue == 'Mayor',
      ),
    );
    expect(field.initialValue, 'Mayor');
    expect(field.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
  for (final role in ['admin', 'super_admin']) {
    testWidgets('Mayor account option is restricted for $role', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: <dynamic>[],
            ),
          ),
        ),
      );
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      final auth = _Auth(role);
      final hire = RecruitmentHirePrefill();
      addTearDown(auth.dispose);
      addTearDown(hire.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<RecruitmentHirePrefill>.value(value: hire),
          ],
          child: const MaterialApp(home: Scaffold(body: AddEmployeeForm())),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Role',
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(
        find.text('Mayor'),
        role == 'super_admin' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
