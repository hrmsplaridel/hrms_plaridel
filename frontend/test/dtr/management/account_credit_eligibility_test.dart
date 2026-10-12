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
  @override
  AppUser get user => AppUser(id: 'actor', email: 'actor@test', role: 'admin');
}

void main() {
  setUpAll(() => ApiClient.instance.init());
  for (final label in ['Job Order (JO)', 'Contract of Service (COS)']) {
    testWidgets('$label disables credit earning during account creation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiClient.instance.dio.interceptors.clear();
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
      final auth = _Auth();
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
      final employment = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Employment Type',
      );
      final credits = find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            widget.title is Text &&
            (widget.title as Text).data == 'Earn monthly VL/SL credits',
      );
      Future<void> select(String option) async {
        await tester.ensureVisible(employment);
        await tester.tap(employment);
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last);
        await tester.pumpAndSettle();
      }

      expect(tester.widget<SwitchListTile>(credits).value, isTrue);
      await select(label);
      expect(tester.widget<SwitchListTile>(credits).value, isFalse);
      expect(tester.widget<SwitchListTile>(credits).onChanged, isNull);
      await select('Permanent');
      expect(tester.widget<SwitchListTile>(credits).onChanged, isNotNull);
      await tester.ensureVisible(credits);
      await tester.tap(credits);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(credits).value, isTrue);
      await select(label);
      expect(tester.widget<SwitchListTile>(credits).value, isFalse);
      expect(tester.widget<SwitchListTile>(credits).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
