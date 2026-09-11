import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/attendance_policies/pages/manage_attendance_policy.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/attendance-policies') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: [
                  {
                    'id': 'policy-used',
                    'policy_name': 'Used policy',
                    'description': 'Historical policy',
                    'work_hours_per_day': 8,
                    'use_equivalent_day_conversion': true,
                    'deduct_late': false,
                    'convert_late_to_equivalent_day': true,
                    'deduct_undertime': true,
                    'convert_undertime_to_equivalent_day': true,
                    'absent_equals_full_day_deduction': true,
                    'combine_late_and_undertime': false,
                    'deduction_multiplier': 1,
                    'is_default': false,
                    'is_active': true,
                    'is_used': true,
                  },
                  {
                    'id': 'policy-inactive',
                    'policy_name': 'Inactive policy',
                    'description': 'Inactive historical policy',
                    'work_hours_per_day': 8,
                    'use_equivalent_day_conversion': true,
                    'deduct_late': false,
                    'convert_late_to_equivalent_day': true,
                    'deduct_undertime': true,
                    'convert_undertime_to_equivalent_day': true,
                    'absent_equals_full_day_deduction': true,
                    'combine_late_and_undertime': false,
                    'deduction_multiplier': 1,
                    'is_default': false,
                    'is_active': false,
                    'is_used': true,
                  },
                ],
              ),
            );
            return;
          }
          if (options.path == '/api/shifts') {
            handler.resolve(
              Response<List<dynamic>>(requestOptions: options, data: const []),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );
  });

  tearDownAll(() {
    ApiClient.instance.dio.interceptors.clear();
  });

  testWidgets(
    'used policy locks computation controls but keeps metadata editable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ManageAttendancePolicy())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Used policy'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('attendance-policy-computation-lock')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('attendance-policy-work-hours')),
            )
            .enabled,
        false,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('attendance-policy-deduction-multiplier')),
            )
            .enabled,
        false,
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(
                const ValueKey('attendance-policy-switch-Deduct Late'),
              ),
            )
            .onChanged,
        isNull,
      );
      expect(find.text('Convert Late to Equivalent Day'), findsNothing);
      expect(find.text('Convert Undertime to Equivalent Day'), findsNothing);

      final metadataFields = tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      );
      expect(metadataFields.where((field) => field.enabled != false).length, 2);
    },
  );

  testWidgets('inactive policy shows Reactivate instead of Deactivate', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ManageAttendancePolicy())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inactive policy'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reactivate-attendance-policy')),
      findsOneWidget,
    );
    expect(find.text('Reactivate'), findsOneWidget);
    expect(find.text('Deactivate'), findsNothing);
  });
}
