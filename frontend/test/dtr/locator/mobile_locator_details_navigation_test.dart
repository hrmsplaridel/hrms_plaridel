import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/employee_locator_slip_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

const _slip = <String, dynamic>{
  'id': 'locator',
  'user_id': 'employee',
  'employee_name': 'Employee One',
  'slip_date': '2026-11-07',
  'request_type': 'locator',
  'request_type_label': 'Locator / Official Business',
  'office': 'Unique destination',
  'reason': 'Meeting at barangay',
  'am_in': true,
  'am_out': true,
  'status': 'approved',
  'created_at': '2026-11-06T08:00:00Z',
  'updated_at': '2026-11-06T09:00:00Z',
};

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  for (final config in [
    (size: const Size(390, 844), scale: 1.0, mode: 'personal'),
    (size: const Size(320, 844), scale: 1.6, mode: 'personal'),
    (size: const Size(740, 390), scale: 1.0, mode: 'personal'),
    (size: const Size(390, 844), scale: 1.0, mode: 'history'),
    (size: const Size(390, 844), scale: 1.0, mode: 'assigned'),
  ]) {
    testWidgets('Locator details cover dashboard controls: $config', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = config.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LocatorSlipDataCache.instance.invalidateAll();
      WorkflowInboxCache.instance.clearSession();
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.uri.path;
            dynamic data = <dynamic>[];
            if (path.endsWith('/context')) {
              data = {'official_date': '2026-11-07'};
            }
            if (path.endsWith('/department-head/check')) {
              data = {
                'isDeptHead': true,
                'canReviewPending': true,
                'hasReviewHistory': true,
              };
            }
            if (path.endsWith('/my') || path.endsWith('/department-head')) {
              data = {
                'items': [_slip],
                'pagination': {
                  'page': 1,
                  'page_size': 50,
                  'total': 1,
                  'page_count': 1,
                },
              };
            }
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
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
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        ApiClient.instance.dio.interceptors.clear();
        LocatorSlipDataCache.instance.invalidateAll();
        WorkflowInboxCache.instance.clearSession();
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(config.scale),
                padding: const EdgeInsets.only(bottom: 24),
              ),
              child: child!,
            ),
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
                      builder: (context) => config.mode == 'assigned'
                          ? Center(
                              child: TextButton(
                                onPressed: () => reviewAssignedWorkflowRequest(
                                  context,
                                  {
                                    'kind': 'locator',
                                    'id': 'locator',
                                    'status': 'approved',
                                    'request_data': _slip,
                                    'allowed_actions': <String>[],
                                    'can_review': false,
                                    'decisions': <dynamic>[],
                                  },
                                  onPreview: () async {},
                                  onPrint: () async {},
                                ),
                                child: const Text('Open assigned locator'),
                              ),
                            )
                          : SingleChildScrollView(
                              child: EmployeeLocatorSlipScreen(key: page),
                            ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      onPressed: () {},
                      label: const Text('File Request'),
                    ),
                  ),
                  const Positioned(
                    right: 16,
                    bottom: 90,
                    child: Text('Chatbot launcher'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (config.mode != 'assigned') {
        page.currentState!.showSection(approvals: config.mode == 'history');
      }
      await tester.pumpAndSettle();
      final target = find.text(
        config.mode == 'assigned'
            ? 'Open assigned locator'
            : 'Unique destination',
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byType(EmployeeLocatorMobileDetailsDialog), findsOneWidget);
      expect(nested.currentState!.canPop(), isFalse);
      expect(find.text('File Request'), findsNothing);
      expect(find.text('Chatbot launcher'), findsNothing);
      expect(find.text('Dashboard navigation'), findsNothing);
      expect(
        tester.getSize(find.byType(EmployeeLocatorMobileDetailsDialog)).width,
        config.size.width,
      );
      final preview = find.widgetWithText(OutlinedButton, 'Preview');
      expect(preview.hitTestable(), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Print').hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(preview).dy,
        lessThanOrEqualTo(config.size.height - 24),
      );
      if (config.scale > 1) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('Close'));
      }
      await tester.pumpAndSettle();
      expect(find.text('File Request'), findsOneWidget);
      expect(find.text('Dashboard navigation'), findsOneWidget);
      expect(nested.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
