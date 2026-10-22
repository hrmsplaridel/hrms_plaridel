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
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_shared_widgets.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

void main() {
  for (final label in ['Preview Form', 'Print Form']) {
    testWidgets(
      'approved workflow history restores $label through the existing form handler',
      (tester) async {
        final repository = _PrintTrackingRepository();
        final calls = await mountQueue(
          tester,
          approved: true,
          repository: repository,
        );
        await tester.tap(find.text('Applicant'));
        await tester.pumpAndSettle();
        expect(find.text('Request Details'), findsOneWidget);
        expect(find.text('Preview Form'), findsOneWidget);
        expect(find.text('Print Form'), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Actions'), findsNothing);
        expect(find.text('Close'), findsNothing);
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('leave-request-actions-footer')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(repository.refreshedIds, ['request']);
        expect(calls.where((o) => o.method == 'POST'), isEmpty);
        expect(find.text('Request Details'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'approval shows confirmation, retains history, and prevents a second review',
    (tester) async {
      final calls = await mountQueue(tester);
      await tester.tap(find.text('Applicant'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNotNull,
        reason: calls.map((o) => o.path).join(', '),
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Approve'));
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Request Details'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('Department Review approved successfully'),
        findsOneWidget,
      );
      expect(find.text('Applicant'), findsOneWidget);
      expect(find.text('Pending HR Review'), findsOneWidget);
      expect(
        tester
            .widget<AdminLeaveHeaderChip>(
              find.byWidgetPredicate(
                (w) => w is AdminLeaveHeaderChip && w.label == 'Pending',
              ),
            )
            .value,
        '0',
      );
      expect(
        calls
            .where((o) => o.path.endsWith('/inbox'))
            .every((o) => o.queryParameters['include_history'] == true),
        isTrue,
      );
      await tester.tap(find.text('Applicant'));
      await tester.pumpAndSettle();
      expect(find.text('Request Details'), findsOneWidget);
      expect(find.text('Department Review · Approved'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
      expect(find.text('Return'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.widgetWithText(TextField, 'Review remarks'), findsNothing);
      expect(calls.where((o) => o.method == 'POST').length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed approval shows snackbar and keeps the request open', (
    tester,
  ) async {
    await mountQueue(tester, failDecision: true);
    await tester.tap(find.text('Applicant'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Approve'));
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Request Details'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('This request changed. Refresh before reviewing.'),
      findsWidgets,
    );
    expect(find.textContaining('approved successfully'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<List<RequestOptions>> mountQueue(
  WidgetTester tester, {
  bool failDecision = false,
  bool approved = false,
  MockLeaveRepository? repository,
}) async {
  tester.view.physicalSize = const Size(1600, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  ApiClient.instance.init();
  final calls = <RequestOptions>[];
  var decided = false;
  final snapshot = {
    'name': 'Department → HR → Mayor',
    'version': 1,
    'steps': [
      {'label': 'Department Review'},
      {'label': 'HR Review'},
      {'label': 'Mayor Approval'},
    ],
  };
  ApiClient.instance.dio.interceptors.clear();
  ApiClient.instance.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        calls.add(o);
        dynamic body = <dynamic>[];
        if (o.method == 'POST') {
          if (failDecision) {
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: o,
                  statusCode: 409,
                  data: {
                    'error': 'This request changed. Refresh before reviewing.',
                  },
                ),
              ),
            );
            return;
          }
          decided = true;
          body = {
            'status': 'pending_hr',
            'workflow_snapshot': {...snapshot, 'current_step': 1},
          };
        } else if (o.path.endsWith('/inbox')) {
          body = [
            {
              'kind': 'leave',
              'id': 'request',
              'employee_name': 'Applicant',
              'workflow_name': snapshot['name'],
              'current_step': approved
                  ? 3
                  : decided
                  ? 1
                  : 0,
              'step_label': decided ? 'HR Review' : 'Department Review',
              'step_count': 3,
              'can_review': !decided && !approved,
              'allowed_actions': decided || approved
                  ? []
                  : ['approve', 'return', 'reject'],
              'signature_revision': 1,
              'days': 1,
              'created_at': '2026-10-16',
              'request_data': {
                'id': 'request',
                'user_id': 'applicant',
                'employee_name': 'Applicant',
                'status': approved ? 'approved' : 'pending_hr',
                'leave_type': 'vacationLeave',
                'start_date': '2026-10-20',
                'end_date': '2026-10-20',
                'working_days_applied': 1,
                'workflow_snapshot': {
                  ...snapshot,
                  'current_step': approved
                      ? 3
                      : decided
                      ? 1
                      : 0,
                  if (approved) 'outcome': 'approved',
                },
              },
              'decisions': decided
                  ? [
                      {
                        'step_label': 'Department Review',
                        'action': 'approve',
                        'reviewer_name': 'Reviewer',
                        'acted_at': '2026-10-16',
                      },
                    ]
                  : [],
            },
          ];
        } else if (o.path.endsWith('/signatures')) {
          body = {
            'source_module': 'dtr',
            'source_table': 'leave_requests',
            'source_record_id': 'request',
            'signatures': [
              {
                'slot_key': 'hr_approver',
                'assigned_signer_id': 'reviewer',
                'signed_by': 'reviewer',
                'signature_asset_id': 'asset',
                'signed_at': '2026-10-16T00:00:00Z',
                'signature_image_base64':
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              },
            ],
          };
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      },
    ),
  );
  final auth = AuthProvider()
    ..replaceUser(
      const AppUser(
        id: 'reviewer',
        email: 'reviewer@test.local',
        role: 'employee',
      ),
    );
  final leave = LeaveProvider(repository: repository ?? MockLeaveRepository());
  final realtime = AppRealtimeProvider();
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
        ChangeNotifierProvider.value(value: realtime),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AdminLeaveScreen())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

class _PrintTrackingRepository extends MockLeaveRepository {
  final refreshedIds = <String>[];
  @override
  Future<LeaveRequest?> getRequestById(String requestId) async {
    refreshedIds.add(requestId);
    // Stop before native printing: existing handlers must verify fresh data.
    return null;
  }
}
