import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_request_queue.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

class _Realtime extends AppRealtimeProvider {
  final controller = StreamController<AppRealtimeEvent>.broadcast();
  @override
  Stream<AppRealtimeEvent> get events => controller.stream;
  void refresh() =>
      controller.add(const AppRealtimeEvent(name: 'locator_updated'));
  @override
  void dispose() {
    controller.close();
    super.dispose();
  }
}

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets('Leave shimmer preserves loaded rows at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var loading = true;
      var loaded = false;
      var requests = <LeaveRequest>[];
      late StateSetter update;
      final request = LeaveRequest.fromJson({
        'id': 'request',
        'user_id': 'employee',
        'employee_name': 'Queue Employee',
        'leave_type': 'sickLeave',
        'status': 'pending_department_head',
        'start_date': '2026-10-22',
        'end_date': '2026-10-22',
        'working_days_applied': 1,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return AdminLeaveRequestQueuePanel(
                    requests: requests,
                    filterKey: '',
                    isDepartmentHead: true,
                    loading: loading,
                    initialLoadComplete: loaded,
                    initialLoadAttempted: loaded,
                    onRetry: () {},
                    totalCount: requests.length,
                    hasMore: false,
                    loadingMore: false,
                    loadMoreError: null,
                    onLoadMore: () {},
                    selectedRequest: null,
                    filterBar: const Text('Queue filters'),
                    onSelect: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byType(WorkforceRowsSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      update(() {
        loading = false;
        loaded = true;
        requests = [request];
      });
      await tester.pumpAndSettle();
      expect(find.text('Queue Employee'), findsOneWidget);
      update(() => loading = true);
      await flush(tester);
      expect(find.text('Queue Employee'), findsOneWidget);
      expect(find.text('Queue filters'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Refreshing leave requests'),
        findsOneWidget,
      );
      expect(find.byType(WorkforceRowsSkeleton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      update(() => loading = false);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Refreshing leave requests'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final admin in [false, true]) {
      testWidgets(
        'Locator ${admin ? 'management' : 'personal approvals'} shimmer at width $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1200);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          ApiClient.instance.init();
          LocatorSlipDataCache.instance.invalidateAll();
          ApiClient.instance.dio.interceptors.clear();
          RequestOptions? pendingOptions;
          RequestInterceptorHandler? pendingHandler;
          final queuePath = admin
              ? '/api/locator-slips/admin'
              : '/api/locator-slips/department-head';
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                if (o.uri.path == queuePath) {
                  pendingOptions = o;
                  pendingHandler = h;
                  return;
                }
                dynamic data = <dynamic>[];
                if (o.path.endsWith('/final-reviewer/me')) {
                  data = {'can_review': true};
                }
                if (o.path.endsWith('/department-head/check')) {
                  data = {
                    'isDeptHead': true,
                    'canReviewPending': true,
                    'hasReviewHistory': true,
                  };
                }
                if (o.path.endsWith('/context')) {
                  data = {'official_date': '2026-10-22'};
                }
                if (o.path.endsWith('/types')) {
                  data = [
                    {'code': 'locator', 'label': 'Locator', 'is_active': true},
                  ];
                }
                if (o.path.endsWith('/my')) {
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
          void succeed(String? name) {
            final handler = pendingHandler!;
            pendingHandler = null;
            handler.resolve(
              Response(
                requestOptions: pendingOptions!,
                statusCode: 200,
                data: {
                  'items': [
                    if (name != null)
                      {
                        'id': 'request',
                        'employee_id': 'employee',
                        'employee_name': name,
                        'status': admin
                            ? 'pending_hr'
                            : 'pending_department_head',
                        'slip_date': '2026-10-22',
                        'request_type': 'locator',
                        'office': 'Municipal hall',
                        'reason': 'Official business',
                        'am_in': true,
                      },
                  ],
                  'pagination': {
                    'page': 1,
                    'page_size': 50,
                    'total': name == null ? 0 : 1,
                    'page_count': 1,
                  },
                },
              ),
            );
          }

          final auth = AuthProvider()
            ..replaceUser(
              const AppUser(
                id: 'reviewer',
                email: 'reviewer@test.local',
                role: 'admin',
              ),
            );
          final realtime = _Realtime();
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
                ChangeNotifierProvider<AppRealtimeProvider>.value(
                  value: realtime,
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: admin
                        ? const AdminLocatorManagementScreen()
                        : const EmployeeLocatorSlipContent(),
                  ),
                ),
              ),
            ),
          );
          await flush(tester);
          expect(pendingHandler, isNotNull);
          expect(find.byType(WorkforceRowsSkeleton), findsWidgets);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          succeed('Queue Employee');
          await tester.pumpAndSettle();
          expect(find.text('Queue Employee'), findsOneWidget);

          realtime.refresh();
          await flush(tester);
          expect(pendingHandler, isNotNull);
          expect(find.text('Queue Employee'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Refreshing locator requests'),
            findsOneWidget,
          );
          expect(find.byType(WorkforceRowsSkeleton), findsNothing);
          succeed('Updated Employee');
          await tester.pumpAndSettle();
          expect(find.text('Queue Employee'), findsNothing);
          expect(find.text('Updated Employee'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Refreshing locator requests'),
            findsNothing,
          );

          realtime.refresh();
          await flush(tester);
          final handler = pendingHandler!;
          pendingHandler = null;
          handler.reject(
            DioException(
              requestOptions: pendingOptions!,
              response: Response(
                requestOptions: pendingOptions!,
                statusCode: 503,
                data: {'error': 'Temporarily unavailable'},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Updated Employee'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Refreshing locator requests'),
            findsNothing,
          );

          realtime.refresh();
          await flush(tester);
          succeed(null);
          await tester.pumpAndSettle();
          expect(find.text('Updated Employee'), findsNothing);
          realtime.refresh();
          await flush(tester);
          expect(
            find.bySemanticsLabel('Refreshing locator requests'),
            findsOneWidget,
          );
          expect(find.byType(WorkforceRowsSkeleton), findsNothing);
          succeed(null);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
