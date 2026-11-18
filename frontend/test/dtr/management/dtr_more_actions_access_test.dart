import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/management/shared/dtr_more_actions_access.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';

class _Events extends AppRealtimeProvider {
  final controller = StreamController<AppRealtimeEvent>.broadcast();
  @override
  Stream<AppRealtimeEvent> get events => controller.stream;
  @override
  void dispose() {
    controller.close();
    super.dispose();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
  });
  for (final kind in ['leave', 'locator']) {
    testWidgets(
      '$kind real menu only shows granted tools and keeps review access',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var allowed = true;
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(id: 'actor', email: 'a@test.com', role: 'admin'),
          );
        final events = _Events();
        final leave = LeaveProvider(repository: MockLeaveRepository());
        addTearDown(auth.dispose);
        addTearDown(events.dispose);
        addTearDown(leave.dispose);
        LocatorSlipDataCache.instance.invalidateAll();
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data = <dynamic>[];
              if (o.path == '/api/dtr-access/me') {
                data = {
                  'leave_allowed': true,
                  'locator_allowed': true,
                  'leave_balances_allowed': allowed,
                  'locator_corrections_allowed': allowed,
                };
              } else if (o.path.endsWith('/final-reviewer/me')) {
                data = {'can_review': true};
              } else if (o.uri.path == '/api/employees') {
                data = {'employees': <dynamic>[], 'total': 0};
              } else if (o.uri.path == '/api/locator-slips/context') {
                data = {'official_date': '2026-11-18'};
              }
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: data),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AppRealtimeProvider>.value(value: events),
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
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            kind == 'leave' ? 'Manual balance adjustment' : 'Record Correction',
          ),
          findsOneWidget,
        );
        expect(
          find.text(kind == 'leave' ? 'Run Month End' : 'Manage Types'),
          findsNothing,
        );
        expect(
          find.text(
            kind == 'leave'
                ? 'Record approved paper leave'
                : 'Record approved paper locator',
          ),
          findsNothing,
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        allowed = false;
        events.controller.add(
          const AppRealtimeEvent(name: 'admin_access_changed'),
        );
        await tester.pumpAndSettle();
        if (kind == 'locator') {
          expect(find.byTooltip('More actions'), findsNothing);
        } else {
          await tester.tap(find.byTooltip('More actions'));
          await tester.pumpAndSettle();
          expect(find.text('Manual balance adjustment'), findsNothing);
          expect(find.text('My Signatures'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final role in ['admin', 'hr', 'employee']) {
    testWidgets(
      'More actions fail closed and refresh after changes for $role',
      (tester) async {
        var access = <String, bool>{
          'leave_allowed': true,
          'leave_balances_allowed': true,
        };
        var failed = false;
        final auth = AuthProvider()
          ..replaceUser(AppUser(id: 'actor', email: 'a@test.com', role: role));
        final events = _Events();
        addTearDown(auth.dispose);
        addTearDown(events.dispose);
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              expect(o.path, '/api/dtr-access/me');
              if (failed) {
                h.reject(DioException(requestOptions: o));
                return;
              }
              h.resolve(Response(requestOptions: o, data: access));
            },
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AppRealtimeProvider>.value(value: events),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: DtrMoreActionsAccess(
                  builder: (context, allows) => Column(
                    children: [
                      if (allows('leave_balances_allowed'))
                        const Text('Balance tool'),
                      if (allows('locator_file_allowed'))
                        const Text('Locator filing'),
                      const Text('Existing review controls'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Balance tool'),
          role == 'employee' ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Locator filing'),
          role == 'hr' ? findsOneWidget : findsNothing,
        );
        access = {'leave_allowed': true, 'leave_balances_allowed': false};
        events.controller.add(
          const AppRealtimeEvent(name: 'admin_access_changed'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Balance tool'),
          role == 'hr' ? findsOneWidget : findsNothing,
        );
        access = {'leave_allowed': false, 'leave_balances_allowed': true};
        events.controller.add(
          const AppRealtimeEvent(name: 'admin_access_changed'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Balance tool'),
          role == 'hr' ? findsOneWidget : findsNothing,
        );
        failed = true;
        events.controller.add(
          const AppRealtimeEvent(name: 'admin_access_changed'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Balance tool'),
          role == 'hr' ? findsOneWidget : findsNothing,
        );
        expect(find.text('Existing review controls'), findsOneWidget);
      },
    );
  }
}
