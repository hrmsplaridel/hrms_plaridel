import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/employee_locator_slip_screen.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_shell.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });
  testWidgets('mobile Leave notifications reset the cached tab on every tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(
          id: 'reviewer',
          email: 'reviewer@test.local',
          role: 'employee',
        ),
      );
    final theme = ThemeModeNotifier(initial: ThemeMode.light);
    final notices = NotificationProvider();
    final docs = DocuTrackerProvider();
    final navKey = GlobalKey<NavigatorState>();
    var version = 0;
    var section = LeaveSection.approvals;
    Widget host() => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: notices),
        ChangeNotifierProvider.value(value: docs),
      ],
      child: MaterialApp(
        home: EmployeeDashboardMobileShell(
          width: 420,
          avatarPath: null,
          displayName: 'Reviewer',
          selectedIndex: 2,
          content: DashboardContentNavigator(
            navigatorKey: navKey,
            homeCacheKey: 2,
            homeRefreshKey: Object.hash(2, version, 'Reviewer'),
            homeBuilder: () => LeaveMain(
              key: ValueKey(version),
              isDepartmentHead: true,
              initialSection: section,
              employeeRequestsContent: const Text('Personal Leave Requests'),
              adminApprovalsContent: const Text('Leave Reviewer Queue'),
            ),
            settingsPanel: const SizedBox.shrink(),
            homeScrollPadding: EdgeInsets.zero,
            settingsScrollPadding: EdgeInsets.zero,
          ),
          onNavSelected: (_) {},
          onProfile: () {},
          onViewAllNotifications: () {},
          onNotificationTap: (_) {},
          onFileLeave: () {},
          onFileLocator: () {},
          onTutorial: () {},
          showMobileLeaveFab: false,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      notices.dispose();
      docs.dispose();
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Leave Reviewer Queue'), findsOneWidget);
    for (final type in [
      'leave_approved',
      'leave_pending_department_head',
      'leave_returned_hr',
      'leave_pending_department_head',
      'leave_approved',
    ]) {
      final tap = NotificationTapResult.fromNotification(
        AppNotification(
          id: 'notice',
          category: 'leave',
          type: type,
          title: 'Update',
          createdAt: DateTime(2026, 11, 1),
        ),
        role: 'employee',
      );
      section = tap.employeeLeaveSection!;
      version++;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(
        find.text(
          section == LeaveSection.requests
              ? 'Personal Leave Requests'
              : 'Leave Reviewer Queue',
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
  for (final width in [1400.0, 420.0]) {
    for (final role in ['employee', 'admin']) {
      testWidgets(
        '$role notification selects the Locator section on repeated taps at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          LocatorSlipDataCache.instance.invalidateAll();
          WorkflowInboxCache.instance.clearSession();
          ApiClient.instance.dio.interceptors.clear();
          final access = Completer<Response<dynamic>>();
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                if (o.path.endsWith('/department-head/check')) {
                  access.future.then(
                    (_) => h.resolve(
                      Response(
                        requestOptions: o,
                        statusCode: 200,
                        data: {'isDeptHead': true, 'canReviewPending': true},
                      ),
                    ),
                  );
                  return;
                }
                dynamic data = <dynamic>[];
                if (o.path.endsWith('/context')) {
                  data = {'official_date': '2026-11-01'};
                }
                if (o.path.endsWith('/my') ||
                    o.path.endsWith('/department-head')) {
                  data = {
                    'items': [],
                    'pagination': {
                      'page': 1,
                      'page_size': 50,
                      'total': 0,
                      'page_count': 1,
                    },
                  };
                }
                h.resolve(
                  Response(requestOptions: o, statusCode: 200, data: data),
                );
              },
            ),
          );
          final auth = AuthProvider()
            ..replaceUser(
              AppUser(
                id: 'reviewer',
                email: 'reviewer@test.local',
                role: role,
                fullName: 'Reviewer',
              ),
            );
          final realtime = AppRealtimeProvider();
          final key = GlobalKey<EmployeeLocatorSlipScreenState>();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ApiClient.instance.dio.interceptors.clear();
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
                  body: SingleChildScrollView(
                    child: EmployeeLocatorSlipScreen(key: key),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          // Explicit request navigation must survive a late reviewer access response.
          key.currentState!.showSection(approvals: false);
          access.complete(Response(requestOptions: RequestOptions()));
          await tester.pumpAndSettle();
          expect(find.text('My Locator Requests'), findsOneWidget);
          expect(find.text('Locator Requests & History'), findsNothing);
          for (final approvals in [true, false, true, false]) {
            key.currentState!.showSection(approvals: approvals);
            await tester.pumpAndSettle();
            expect(
              find.text(
                approvals
                    ? 'Locator Requests & History'
                    : 'My Locator Requests',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
