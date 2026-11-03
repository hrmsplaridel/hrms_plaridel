import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';

Map<String, dynamic> entry(String kind, String id, String name) => {
  'id': id,
  'kind': kind,
  'employee_name': name,
  'status': 'pending_hr',
  'workflow_name': 'Department Review',
  'workflow_version': 1,
  'current_step': 0,
  'step_label': 'Department Review',
  'can_review': true,
  'allowed_actions': ['approve'],
  'days': 1,
  'signature_revision': 1,
  'created_at': '2026-10-23',
  'request_data': {
    'id': id,
    'user_id': 'applicant',
    'employee_id': 'applicant',
    'employee_name': name,
    'status': 'pending_hr',
    'leave_type': 'wellnessLeave',
    'start_date': '2026-10-23',
    'end_date': '2026-10-23',
    'working_days_applied': 1,
    'slip_date': '2026-10-23',
    'request_type': 'locator',
    'office': 'Office',
    'reason': 'Test',
    'am_in': true,
    'workflow_snapshot': {
      'name': 'Department Review',
      'version': 1,
      'current_step': 0,
      'steps': [
        {'label': 'Department Review', 'assignee_source': 'specific_users'},
      ],
      'decisions': [],
    },
  },
};

void main() {
  for (final screen in ['leave', 'locator', 'personal locator']) {
    testWidgets(
      '$screen loads older assigned requests and keeps current rows',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ApiClient.instance.init();
        WorkflowInboxCache.instance.clearSession();
        LocatorSlipDataCache.instance.invalidateAll();
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        final kind = screen == 'leave' ? 'leave' : 'locator';
        var pages = 0, targets = 0;
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data = <dynamic>[];
              if (o.path.endsWith('/final-reviewer/me')) {
                data = {'can_review': true};
              }
              if (o.path.endsWith('/department-head/check')) {
                data = {'canReviewPending': false, 'hasReviewHistory': false};
              }
              if (o.path.endsWith('/context')) {
                data = {'official_date': '2026-10-23'};
              }
              if (o.uri.path == '/api/employees') {
                data = {'employees': [], 'total': 0};
              }
              if (o.path.endsWith('/inbox')) {
                final more = o.queryParameters['cursor'] != null;
                final target = o.queryParameters['request_id'] != null;
                if (target) {
                  targets++;
                } else {
                  pages++;
                }
                data = {
                  'items': [
                    entry(
                      kind,
                      more || target ? 'older' : 'newest',
                      more || target ? 'Older Applicant' : 'Newest Applicant',
                    ),
                  ],
                  'has_more': {kind: !more && !target},
                  'next_cursor': {kind: more || target ? null : 'page-two'},
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
              email: 'reviewer@test.invalid',
              role: screen == 'personal locator' ? 'employee' : 'admin',
            ),
          );
        final leave = LeaveProvider(repository: MockLeaveRepository());
        final realtime = _Realtime();
        addTearDown(auth.dispose);
        addTearDown(leave.dispose);
        addTearDown(realtime.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<LeaveProvider>.value(value: leave),
              ChangeNotifierProvider<AppRealtimeProvider>.value(
                value: realtime,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: screen == 'leave'
                      ? const AdminLeaveScreen()
                      : screen == 'locator'
                      ? const AdminLocatorManagementScreen()
                      : const EmployeeLocatorSlipContent(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (screen == 'personal locator') {
          await tester.tap(find.text('Approvals / History'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Newest Applicant'), findsOneWidget);
        expect(find.text('Older Applicant'), findsNothing);
        final loadMore = find.text('Load more workflow requests');
        await tester.ensureVisible(loadMore);
        await tester.tap(loadMore);
        await tester.pumpAndSettle();
        expect(find.text('Newest Applicant'), findsOneWidget);
        expect(find.text('Older Applicant'), findsOneWidget);
        expect(loadMore, findsNothing);
        expect(pages, 2);
        if (screen == 'leave') {
          await tester.tap(find.text('Older Applicant'));
          await tester.pumpAndSettle();
          expect(targets, 1);
          expect(find.text('Approve'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Realtime extends AppRealtimeProvider {
  final controller = StreamController<AppRealtimeEvent>.broadcast();
  @override
  Stream<AppRealtimeEvent> get events => controller.stream;
  @override
  void dispose() {
    controller.close();
    super.dispose();
  }
}
