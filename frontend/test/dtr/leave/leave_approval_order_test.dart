import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_request_queue.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

Map<String, dynamic> _row(String id, String filed, {bool actionable = false}) =>
    {
      'id': id,
      'user_id': 'employee-$id',
      'employee_name': 'Employee $id',
      'leave_type': 'sickLeave',
      'office_department': 'Human Resources',
      'start_date': '2026-11-01',
      'end_date': '2026-11-01',
      'date_filed': '2026-09-01',
      'working_days_applied': 1,
      'status': actionable ? 'pending_hr' : 'approved',
      'created_at': filed,
      'updated_at': '2026-10-30T10:00:00Z',
    };
final _old = _row('old', '2026-10-20T10:00:00Z');
final _duplicate = _row('duplicate', '2026-10-25T10:00:00Z');
final _tieA = _row('tie-a', '2026-10-25T10:00:00Z');
final _tieZ = _row('tie-z', '2026-10-25T10:00:00Z');
final _newest = _row('newest', '2026-10-27T10:00:00Z');
final _actionable = _row(
  'actionable',
  '2026-10-19T10:00:00Z',
  actionable: true,
);
final _olderPage = _row('older-page', '2026-10-18T10:00:00Z');
final _workflowPage = _row('workflow-page', '2026-10-28T10:00:00Z');
Map<String, dynamic> _assigned(Map<String, dynamic> row) => {
  'id': row['id'],
  'kind': 'leave',
  'can_review': row['id'] == 'actionable',
  'request_data': row,
};

class _Repository extends MockLeaveRepository {
  final calls = <({bool departmentHead, int offset})>[];
  @override
  Future<LeaveRequestPage> listReviewRequestsPage({
    required LeaveRequestQuery query,
    bool departmentHead = false,
  }) async {
    final offset = query.offset ?? 0;
    calls.add((departmentHead: departmentHead, offset: offset));
    return LeaveRequestPage(
      items: (offset == 0 ? [_old, _duplicate, _tieA] : [_olderPage])
          .map(LeaveRequest.fromJson)
          .toList(),
      total: 4,
      limit: 3,
      offset: offset,
    );
  }
}

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });
  for (final departmentHead in [false, true]) {
    for (final width in [1500.0, 390.0]) {
      testWidgets(
        'Leave approvals sort filing times across sources and pages: head=$departmentHead width=$width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ApiClient.instance.dio.interceptors.clear();
          WorkflowInboxCache.instance.invalidate();
          var moreCalls = 0;
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                dynamic data = <dynamic>[];
                if (o.uri.path.endsWith('/final-reviewer/me')) {
                  data = {'can_review': true};
                }
                if (o.uri.path.endsWith('/inbox')) {
                  final more = o.uri.queryParameters['cursor'] != null;
                  if (more) {
                    moreCalls++;
                    expect(o.uri.queryParameters['cursor'], 'leave-next');
                  }
                  data = {
                    'items': more
                        ? [_assigned(_workflowPage)]
                        : [
                            _assigned(_actionable),
                            _assigned(_newest),
                            _assigned(_duplicate),
                            _assigned(_tieZ),
                          ],
                    'has_more': {'leave': !more, 'locator': false},
                    'next_cursor': {
                      'leave': more ? null : 'leave-next',
                      'locator': null,
                    },
                  };
                }
                h.resolve(
                  Response(requestOptions: o, statusCode: 200, data: data),
                );
              },
            ),
          );
          final repository = _Repository();
          final leave = LeaveProvider(repository: repository);
          final auth = AuthProvider()
            ..replaceUser(
              AppUser(
                id: 'reviewer',
                email: 'reviewer@test.local',
                role: departmentHead ? 'employee' : 'hr',
              ),
            );
          final realtime = AppRealtimeProvider();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ApiClient.instance.dio.interceptors.clear();
            WorkflowInboxCache.instance.invalidate();
            leave.dispose();
            auth.dispose();
            realtime.dispose();
          });
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
                    child: AdminLeaveScreen(isDepartmentHead: departmentHead),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          AdminLeaveRequestQueuePanel queue() =>
              tester.widget(find.byType(AdminLeaveRequestQueuePanel));
          final initial = [
            'newest',
            'tie-z',
            'tie-a',
            'duplicate',
            'old',
            'actionable',
          ];
          expect(queue().requests.map((r) => r.id), initial);
          expect(queue().totalCount, 7);
          expect(find.text('Employee newest'), findsOneWidget);
          await tester.ensureVisible(find.text('Refresh'));
          await tester.tap(find.text('Refresh'));
          await tester.pumpAndSettle();
          expect(queue().requests.map((r) => r.id), initial);
          await tester.ensureVisible(find.text('Load More'));
          await tester.tap(find.text('Load More'));
          await tester.pumpAndSettle();
          expect(queue().requests.map((r) => r.id), [...initial, 'older-page']);
          expect(queue().totalCount, 7);
          expect(
            repository.calls.every((c) => c.departmentHead == departmentHead),
            isTrue,
          );
          expect(repository.calls.any((c) => c.offset == 3), isTrue);
          await tester.ensureVisible(find.text('Load more workflow requests'));
          await tester.tap(find.text('Load more workflow requests'));
          await tester.pumpAndSettle();
          expect(queue().requests.map((r) => r.id), [
            'workflow-page',
            ...initial,
            'older-page',
          ]);
          expect(queue().totalCount, 8);
          expect(moreCalls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
