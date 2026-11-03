import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_opening_balances_form.dart';

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });
  for (final legacy in [false, true]) {
    testWidgets(
      '${legacy ? 'verification' : 'opening'} uses hire date and the actual cutoff for usage limits',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
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
                          'employment_type': 'permanent',
                          'date_hired': '2020-01-01',
                        },
                      ],
                      'total': 1,
                    }
                  : o.path == '/api/leave/admin/opening-balances'
                  ? {
                      'setups': legacy
                          ? [
                              {
                                'user_id': 'employee',
                                'cutoff_date': '2026-01-31',
                              },
                            ]
                          : [],
                    }
                  : {
                      'setup': legacy
                          ? {
                              'cutoff_date': '2026-01-31',
                              'qualifying_leave_days': null,
                            }
                          : null,
                      'balances': [],
                      'date_hired': '2026-01-16',
                      'official_date': legacy ? '2026-11-01' : '2026-02-01',
                    };
              h.resolve(
                Response<dynamic>(
                  requestOptions: o,
                  statusCode: 200,
                  data: data,
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminLeaveOpeningBalancesForm(onSavingChanged: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test Employee'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextFormField>(
          find.byKey(const ValueKey('opening-qualifying-days')),
        );
        expect(
          field.validator!('17'),
          isNotNull,
          reason: 'Jan 16 through Jan 31 contains only 16 days',
        );
        expect(field.validator!('16.001'), isNotNull);
        expect(field.validator!('16'), isNull);
        expect(field.validator!('0.5'), isNull);
        expect(field.validator!('0'), isNull);
        expect(find.textContaining('2026-01-16'), findsOneWidget);
        if (!legacy) {
          final credits = tester.widget<TextFormField>(
            find.byKey(const ValueKey('opening-vl')),
          );
          expect(
            credits.validator!('30'),
            isNull,
            reason:
                'Carried-over credits do not use the historical usage ceiling',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
