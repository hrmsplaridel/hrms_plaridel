import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/employee_locator_slip_screen.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  for (final size in [const Size(390, 844), const Size(740, 390)]) {
    for (final correction in [false, true]) {
      testWidgets(
        'Locator form covers dashboard: $size correction=$correction',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          LocatorSlipDataCache.instance.invalidateAll();
          ApiClient.instance.dio.interceptors.clear();
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final dynamic data = switch (options.uri.path) {
                  '/api/locator-slips/context' => {
                    'official_date': '2026-11-12',
                  },
                  '/api/locator-slips/submission-availability' => {
                    'can_submit': true,
                  },
                  '/api/locator-slips/types' => [
                    {
                      'code': 'locator',
                      'label': 'Locator / Official Business',
                      'is_active': true,
                    },
                  ],
                  '/api/locator-slips/shift-coverage' => {
                    'single_session': true,
                    'can_file': true,
                  },
                  '/api/locator-slips/department-head/check' => {
                    'isDeptHead': false,
                  },
                  '/api/locator-slips/my' => {
                    'items': correction
                        ? [
                            {
                              'id': 'locator',
                              'user_id': 'employee',
                              'employee_name': 'Employee One',
                              'slip_date': '2026-11-12',
                              'request_type': 'locator',
                              'office': 'Unique destination',
                              'reason': 'Meeting at barangay',
                              'am_in': true,
                              'status': 'returned_for_correction',
                            },
                          ]
                        : <dynamic>[],
                    'pagination': {
                      'page': 1,
                      'page_size': 50,
                      'total': correction ? 1 : 0,
                      'page_count': 1,
                    },
                  },
                  _ => <dynamic>[],
                };
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: data,
                  ),
                );
              },
            ),
          );
          final auth = AuthProvider()
            ..replaceUser(
              const AppUser(
                id: 'employee',
                email: 'employee@test.local',
                role: 'employee',
                fullName: 'Employee One',
              ),
            );
          final realtime = AppRealtimeProvider();
          final page = GlobalKey<EmployeeLocatorSlipScreenState>();
          final nested = GlobalKey<NavigatorState>();
          const launcher = ValueKey('dashboard-file-locator');
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ApiClient.instance.dio.interceptors.clear();
            LocatorSlipDataCache.instance.invalidateAll();
            auth.dispose();
            realtime.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: auth),
                ChangeNotifierProvider.value(value: realtime),
              ],
              child: MaterialApp(
                home: Scaffold(
                  bottomNavigationBar: const SizedBox(
                    height: 80,
                    child: Text('Dashboard navigation'),
                  ),
                  body: Stack(
                    children: [
                      Navigator(
                        key: nested,
                        onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => SingleChildScrollView(
                            child: EmployeeLocatorSlipScreen(key: page),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton.extended(
                          key: launcher,
                          onPressed: () => page.currentState!.openCreateForm(),
                          label: const Text('File Request'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (correction) {
            await tester.ensureVisible(find.text('Unique destination'));
            await tester.tap(find.text('Unique destination'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Correct & Resubmit'));
          } else {
            await tester.tap(find.byKey(launcher));
          }
          // The assistant greeting animates independently of the form route.
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            find.text(correction ? 'Correct Locator Request' : 'File Request'),
            findsOneWidget,
          );
          expect(find.byKey(launcher), findsNothing);
          expect(find.text('Dashboard navigation'), findsNothing);
          expect(nested.currentState!.canPop(), isFalse);
          expect(
            find.text(correction ? 'Save & Resubmit' : 'Submit').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Cancel').hitTestable(), findsOneWidget);
          if (correction) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.text('Cancel'));
          }
          await tester.pumpAndSettle();
          expect(find.byKey(launcher), findsOneWidget);
          expect(find.text('Dashboard navigation'), findsOneWidget);
          expect(nested.currentState!.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
