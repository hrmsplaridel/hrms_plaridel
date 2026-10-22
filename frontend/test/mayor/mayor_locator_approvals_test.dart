import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/mayor/presentation/pages/mayor_dashboard_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';

void main() {
  for (final module in ['Locator', 'Leave']) {
  testWidgets('Mayor can open $module approvals without staff filing actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    LocatorSlipDataCache.instance.invalidateRequests();
    LocatorSlipDataCache.instance.invalidateTypes();
    final requests = <String>[];
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add(o.path);
      final dynamic data = o.path.startsWith('/api/locator-slips/types')
              ? []
              : o.path == '/api/approval-workflows/inbox'
              ? []
              : o.path == '/api/leave/types' || o.path.startsWith('/api/leave/balances/')
              ? []
              : o.path.endsWith('/final-reviewer/me')
              ? {'can_review': true}
              : <String, dynamic>{};
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(
          id: 'mayor',
          email: 'mayor@test.local',
          role: 'mayor',
          fullName: 'Mayor',
        ),
      );
    final realtime = AppRealtimeProvider();
    final documents = DocuTrackerProvider();
    final leave = LeaveProvider(repository: ApiLeaveRepository());
    final notifications = NotificationProvider();
    final theme = ThemeModeNotifier(initial: ThemeMode.light);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: realtime),
          ChangeNotifierProvider.value(value: documents),
          ChangeNotifierProvider.value(value: leave),
          ChangeNotifierProvider.value(value: notifications),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: const MaterialApp(home: MayorDashboardPage()),
      ),
    );
    for (var i=0;i<10;i++) { await tester.pump(const Duration(milliseconds:100)); }
    await tester.tap(find.text('$module approvals'));
    for (var i=0;i<10;i++) { await tester.pump(const Duration(milliseconds:100)); }
    expect(requests.any((path)=>module=='Locator'?path.startsWith('/api/locator-slips/admin'):path=='/api/leave'),isTrue);
    expect(find.text('Leave Type Rules'), findsNothing);
    if (find.byTooltip('More actions').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('More actions'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Leave Type Rules'), findsNothing);
      expect(find.text('Forced Leave Deduction'), findsNothing);
      expect(find.text('Run Month End'), findsNothing);
      expect(find.text('Manual balance adjustment'), findsNothing);
      expect(find.text('Leave Ledger'), findsNothing);
      expect(find.text('Year-End Forced Leave Deduction'), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    realtime.dispose();
    documents.dispose();
    leave.dispose();
    notifications.dispose();
    theme.dispose();
    ApiClient.instance.dio.interceptors.clear();
  });
  }
}
