import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';

Map<String, dynamic> record(bool complete) => {
  'id': 'request',
  'user_id': 'applicant',
  'employee_name': 'Applicant',
  'leave_type': 'sickLeave',
  'working_days_applied': 1,
  'start_date': '2026-10-19',
  'end_date': '2026-10-19',
  'created_at': '2026-10-18T01:00:00Z',
  'updated_at': complete ? '2026-10-18T03:00:00Z' : '2026-10-18T02:00:00Z',
  'status': complete ? 'approved' : 'pending_hr',
  'final_review_route': 'mayor_direct',
  'workflow_snapshot': {
    'name': 'Complete Workflow',
    'version': 2,
    'current_step': complete ? 3 : 1,
    'steps': [
      {'label': 'Dept', 'assignee_source': 'submitter_department_reviewers'},
      {'label': 'Final HR', 'assignee_source': 'final_hr_reviewers'},
      {'label': 'Mayor', 'assignee_source': 'active_mayor'},
    ],
    'decisions': [
      for (var step = 0; step < (complete ? 3 : 1); step++)
        {
          'step': step,
          'action': 'approve',
          'actor_id': ['head', 'primary', 'mayor'][step],
          'acted_at': '2026-10-18T02:0$step:00Z',
          'reviewer': {
            'name': ['Head', 'Primary HR', 'Mayor Office'][step],
          },
        },
    ],
  },
};

class _Repository extends MockLeaveRepository {
  bool complete = false;
  @override
  Future<LeaveRequest?> getRequestById(String id) async =>
      LeaveRequest.fromJson(record(complete));
  @override
  Future<LeaveRequestPage> listReviewRequestsPage({
    required LeaveRequestQuery query,
    bool departmentHead = false,
  }) async => LeaveRequestPage(
    items: [LeaveRequest.fromJson(record(complete))],
    total: 1,
    limit: 200,
    offset: 0,
  );
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

void main() {
  testWidgets('ordinary history details show every saved workflow approval', (
    tester,
  ) async {
    final leave = LeaveProvider(repository: _Repository());
    addTearDown(leave.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: leave,
        child: MaterialApp(
          home: Scaffold(
            body: AdminLeaveDetailsSideSheet(
              initial: LeaveRequest.fromJson(record(true)),
              isDepartmentHead: false,
              onApprove: (_) async {},
              onReturn: (_) async {},
              onReject: (_) async {},
              onPrint: (_) async {},
            ),
          ),
        ),
      ),
    );
    for (final label in [
      'Dept · Approved',
      'Final HR · Approved',
      'Mayor · Approved',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Approved by HR'), findsNothing);
    expect(find.text('Approve'), findsNothing);
  });

  for (final completedBeforeOpening in [true, false]) {
    testWidgets(
      'backup cannot reapprove when completed ${completedBeforeOpening ? 'before opening' : 'with details open'}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository();
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(id: 'backup', email: 'backup@test', role: 'hr'),
          );
        final leave = LeaveProvider(repository: repository);
        final realtime = _Realtime();
        final posts = <String>[];
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data = <dynamic>[];
              if (o.method == 'POST') posts.add(o.path);
              if (o.path.endsWith('/final-reviewer/me')) {
                data = {'can_review': true};
              }
              if (o.path.endsWith('/inbox')) {
                data = repository.complete
                    ? []
                    : [
                        {
                          'id': 'request',
                          'kind': 'leave',
                          'can_review': true,
                          'allowed_actions': ['approve', 'return', 'reject'],
                          'days': 1,
                          'signature_revision': 1,
                          'current_step': 1,
                          'step_label': 'Final HR',
                          'request_data': record(false),
                        },
                      ];
              }
              if (o.path == '/api/leave/request') {
                data = record(repository.complete);
              }
              if (o.path.endsWith('/signatures')) {
                data = {
                  'source_module': 'dtr',
                  'source_table': 'leave_requests',
                  'source_record_id': 'request',
                  'signatures': [],
                };
              }
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: data),
              );
            },
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          ApiClient.instance.dio.interceptors.clear();
          auth.dispose();
          leave.dispose();
          realtime.dispose();
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: leave),
              ChangeNotifierProvider<AppRealtimeProvider>.value(
                value: realtime,
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: AdminLeaveScreen()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (completedBeforeOpening) repository.complete = true;
        await tester.tap(find.text('Applicant'));
        await tester.pumpAndSettle();
        if (!completedBeforeOpening) {
          expect(find.text('Approve'), findsOneWidget);
          repository.complete = true;
          realtime.controller.add(AppRealtimeEvent(name: 'leave_updated'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Request Details'), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Return'), findsNothing);
        expect(find.text('Reject'), findsNothing);
        for (final label in [
          'Dept · Approved',
          'Final HR · Approved',
          'Mayor · Approved',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(posts, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
