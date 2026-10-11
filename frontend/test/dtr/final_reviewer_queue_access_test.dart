import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';

void main() {
  setUpAll(() {
    ApiClient.instance.init();
  });
  for (final locator in [false, true]) {
    testWidgets(
      '${locator ? "locator" : "leave"} queue denies unassigned reviewer and retries',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var allowed = false;
        var failAccess = false;
        ApiClient.instance.dio.interceptors.clear();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.path.endsWith('/final-reviewer/me')) {
                if (failAccess) {
                  h.reject(DioException(requestOptions: o));
                  return;
                }
                h.resolve(
                  Response(
                    requestOptions: o,
                    data: <String, dynamic>{'can_review': allowed},
                    statusCode: 200,
                  ),
                );
              } else {
                h.resolve(
                  Response(
                    requestOptions: o,
                    data: <dynamic>[],
                    statusCode: 200,
                  ),
                );
              }
            },
          ),
        );
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(
              id: 'test-reviewer',
              email: 'hr@test.local',
              role: 'hr',
            ),
          );
        final leave = LeaveProvider(repository: MockLeaveRepository());
        final realtime = AppRealtimeProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: leave),
              ChangeNotifierProvider.value(value: realtime),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: locator
                      ? const AdminLocatorManagementScreen()
                      : const AdminLeaveScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final message =
            'Assigned ${locator ? "locator" : "leave"} reviewer access required.';
        expect(find.text(message), findsOneWidget);
        failAccess = true;
        await tester.tap(find.text('Check reviewer access'));
        await tester.pumpAndSettle();
        expect(
          find.text('Unable to check reviewer access. Please retry.'),
          findsOneWidget,
        );
        expect(find.text(message), findsNothing);
        failAccess = false;
        allowed = true;
        await tester.tap(find.text('Check reviewer access'));
        await tester.pumpAndSettle();
        expect(find.text(message), findsNothing);
        expect(
          find.text('Unable to check reviewer access. Please retry.'),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        leave.dispose();
        realtime.dispose();
      },
    );
  }
}
