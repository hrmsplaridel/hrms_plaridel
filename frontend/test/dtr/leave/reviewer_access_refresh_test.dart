import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/reviewer_access_notice.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ApiClient.instance.init());
  for (final kind in ['leave', 'locator']) {
    for (final outcome in ['allowed', 'revoked', 'failed']) {
      testWidgets(
        '$kind background reviewer check keeps queue until $outcome result',
        (tester) async {
          ApiClient.instance.dio.interceptors.clear();
          LocatorSlipDataCache.instance.invalidateAll();
          addTearDown(() => ApiClient.instance.dio.interceptors.clear());
          final first = Completer<void>(), refresh = Completer<void>();
          var checks = 0;
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                if (o.path.endsWith('/final-reviewer/me')) {
                  final initial = ++checks == 1;
                  (initial ? first.future : refresh.future).then((_) {
                    if (!initial && outcome == 'failed') {
                      h.reject(DioException(requestOptions: o));
                      return;
                    }
                    h.resolve(
                      Response(
                        requestOptions: o,
                        statusCode: 200,
                        data: {'can_review': initial || outcome == 'allowed'},
                      ),
                    );
                  });
                  return;
                }
                dynamic data = <dynamic>[];
                if (o.uri.path == '/api/employees') {
                  data = {'employees': <dynamic>[], 'total': 0};
                }
                if (o.uri.path == '/api/locator-slips/admin') {
                  data = [
                    {
                      'id': 'request',
                      'employee_id': 'other',
                      'employee_name': 'Queue Employee',
                      'status': 'pending_hr',
                      'slip_date': '2026-10-12',
                      'reason': 'Test',
                      'am_in': true,
                    },
                  ];
                }
                if (o.uri.path == '/api/locator-slips/context') {
                  data = {'official_date': '2026-10-11'};
                }
                h.resolve(
                  Response(requestOptions: o, statusCode: 200, data: data),
                );
              },
            ),
          );
          final auth = AuthProvider()
            ..replaceUser(
              const AppUser(
                id: 'reviewer',
                email: 'reviewer@test.com',
                role: 'admin',
              ),
            );
          final realtime = _Realtime();
          final leave = LeaveProvider(repository: MockLeaveRepository());
          addTearDown(auth.dispose);
          addTearDown(realtime.dispose);
          addTearDown(leave.dispose);
          tester.view.physicalSize = const Size(1600, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AppRealtimeProvider>.value(
                  value: realtime,
                ),
                ChangeNotifierProvider<LeaveProvider>.value(value: leave),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: kind == 'leave'
                        ? const AdminLeaveScreen()
                        : const AdminLocatorManagementScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Checking reviewer access…'), findsOneWidget);
          first.complete();
          await tester.pumpAndSettle();
          expect(find.byType(ReviewerAccessNotice), findsNothing);
          realtime.eventsController.add(
            AppRealtimeEvent(name: '${kind}_updated'),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(checks, 2);
          expect(
            find.byType(ReviewerAccessNotice),
            findsNothing,
            reason:
                'Confirmed queue must remain visible during background checks',
          );
          if (kind == 'locator') {
            expect(find.text('Queue Employee'), findsOneWidget);
          }
          refresh.complete();
          await tester.pumpAndSettle();
          if (outcome == 'allowed') {
            expect(find.byType(ReviewerAccessNotice), findsNothing);
          } else {
            expect(find.byType(ReviewerAccessNotice), findsOneWidget);
            expect(
              find.text(
                outcome == 'failed'
                    ? 'Unable to check reviewer access. Please retry.'
                    : 'Assigned $kind reviewer access required.',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

class _Realtime extends AppRealtimeProvider {
  final eventsController = StreamController<AppRealtimeEvent>.broadcast();
  @override
  Stream<AppRealtimeEvent> get events => eventsController.stream;
  @override
  void dispose() {
    eventsController.close();
    super.dispose();
  }
}
