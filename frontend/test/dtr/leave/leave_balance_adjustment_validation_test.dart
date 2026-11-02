import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';

void main() {
  for (final text in [
    '',
    '0',
    'NaN',
    'Infinity',
    '-Infinity',
    '0x10',
    '1e2',
    '1.0001',
    '10000000',
    '-10000000',
  ]) {
    test('adjustment field rejects invalid decimal $text', () {
      expect(validateAdminLeaveAdjustment(text), isNotNull);
    });
  }
  for (final text in [
    '+2.000',
    '-1.250',
    ' 0.001 ',
    '9999999.999',
    '-9999999.999',
  ]) {
    test('adjustment field accepts valid signed decimal $text', () {
      expect(validateAdminLeaveAdjustment(text), isNull);
    });
  }
  test(
    'adjustment field checks the resulting signed bucket at exact boundaries',
    () {
      expect(
        validateAdminLeaveAdjustment('0.001', currentAdjustedDays: 9999999.999),
        isNotNull,
      );
      expect(
        validateAdminLeaveAdjustment(
          '-0.001',
          currentAdjustedDays: -9999999.999,
        ),
        isNotNull,
      );
      expect(
        validateAdminLeaveAdjustment('0.001', currentAdjustedDays: 9999999.998),
        isNull,
      );
      expect(
        validateAdminLeaveAdjustment(
          '-0.001',
          currentAdjustedDays: -9999999.998,
        ),
        isNull,
      );
      expect(
        validateAdminLeaveAdjustment('-2.500'),
        isNull,
        reason: 'Negative available balance is not forbidden',
      );
      expect(
        validateAdminLeaveAdjustment('1', currentAdjustedDays: double.nan),
        isNotNull,
      );
      expect(
        validateAdminLeaveAdjustment('1', currentAdjustedDays: double.infinity),
        isNotNull,
      );
    },
  );

  testWidgets(
    'actual adjustment field rejects finite and nonfinite oversized amounts',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      ApiClient.instance.init();
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiClient.instance.dio.interceptors.clear();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            final dynamic data = o.path == '/api/employees'
                ? {
                    'employees': [
                      {
                        'id': 'employee',
                        'full_name': 'Test Employee',
                        'current_department_name': 'HR',
                        'employment_type': 'permanent',
                        'leave_credit_eligible': true,
                      },
                    ],
                    'total': 1,
                  }
                : o.path == '/api/departments'
                ? [
                    {'name': 'HR'},
                  ]
                : o.path == '/api/leave/types'
                ? []
                : o.path == '/api/leave/final-reviewer/me'
                ? {'can_review': true}
                : {'items': []};
            h.resolve(
              Response<dynamic>(requestOptions: o, statusCode: 200, data: data),
            );
          },
        ),
      );
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(id: 'hr', email: 'hr@test.local', role: 'hr'),
        );
      final leave = LeaveProvider(repository: MockLeaveRepository());
      final realtime = AppRealtimeProvider();
      addTearDown(auth.dispose);
      addTearDown(leave.dispose);
      addTearDown(realtime.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<LeaveProvider>.value(value: leave),
            ChangeNotifierProvider<AppRealtimeProvider>.value(value: realtime),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: AdminLeaveScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual balance adjustment'));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Example: +2.000 or -1.250',
      );
      final field = tester.widget<TextFormField>(
        find.ancestor(of: input, matching: find.byType(TextFormField)),
      );
      for (final text in [
        '10000000',
        '-10000000',
        List.filled(400, '9').join(),
      ]) {
        expect(
          field.validator!(text),
          isNotNull,
          reason: 'Out-of-range input must not pass form validation',
        );
      }
      expect(field.validator!('-1.250'), isNull);
      expect(field.validator!('+2.000'), isNull);
    },
  );
}
