import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request_history.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflows_panel.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';

void main() {
  const primary = '11111111-1111-4111-8111-111111111111';
  const backup = '22222222-2222-4222-8222-222222222222';
  final calls = <RequestOptions>[];
  setUp(() {
    ApiClient.instance.init();
    calls.clear();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          calls.add(o);
          final dynamic body = o.path == '/api/employees'
              ? {
                  'employees': [
                    {'id': primary, 'full_name': 'Maria Primary'},
                    {'id': backup, 'full_name': 'Juan Backup'},
                  ],
                }
              : o.method == 'GET'
              ? <dynamic>[]
              : {'id': 'workflow'};
          h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  test(
    'history identifies the configured review step without assuming HR or Mayor',
    () {
      final entry = LeaveRequestHistoryEntry.fromJson({
        'id': 'history',
        'action': 'workflow_step_approved',
        'to_status': 'pending_hr',
        'acted_at': '2026-10-16T03:00:00Z',
        'metadata_json': {
          'workflow_step': {'label': 'Municipal administrator'},
        },
      });
      expect(entry.actionLabel, 'Municipal administrator approved');
    },
  );
  test('shared approval notifications open existing module approval lists', () {
    for (final role in ['employee', 'hr', 'admin', 'mayor']) {
      final notification = AppNotification(
        id: 'notice',
        category: 'leave',
        type: 'leave_pending_hr',
        title: 'Review needed',
        createdAt: DateTime(2026, 10, 16),
        metadata: {'workflow_approval': true},
      );
      expect(
        NotificationTapResult.fromNotification(notification, role: role).kind,
        role == 'employee'
            ? NotificationTapKind.employeeLeaveApprovals
            : NotificationTapKind.adminDtrLeaveManagement,
      );
    }
  });

  testWidgets(
    'shared catalog uses DocuTracker primary/backup editor and publishes named steps',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ApprovalWorkflowsPanel())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New workflow'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Travel approval',
      );
      await tester.tap(find.text('Add approval step'));
      await tester.pumpAndSettle();
      expect(find.text('Primary Assignee'), findsOneWidget);
      expect(find.text('Backup Assignee (Optional)'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Example: Department Review'),
        'Municipal administrator',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Search by name, department, or position',
        ),
        'Maria',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maria Primary').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search optional backup'),
        'Juan',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juan Backup').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Step'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Primary: Maria Primary'), findsOneWidget);
      await tester.tap(find.text('Publish workflow'));
      await tester.pumpAndSettle();
      final request = calls.singleWhere((o) => o.method == 'POST');
      final step = (request.data['steps'] as List).single as Map;
      expect(step['label'], 'Municipal administrator');
      expect(step['user_ids'], [primary, backup]);
      expect(step['requires_signature'], true);
      expect(step['allowed_actions'], isNot(contains('forward')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assigned workflow inbox sends a guarded return decision', (
    tester,
  ) async {
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(
          id: backup,
          email: 'backup@test.local',
          role: 'employee',
          fullName: 'Backup',
        ),
      );
    addTearDown(auth.dispose);
    var returned = false;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          calls.add(o);
          if (o.method == 'POST') returned = true;
          final dynamic data = o.path.endsWith('/inbox')
              ? returned
                    ? []
                    : [
                        {
                          'id': primary,
                          'kind': 'leave',
                          'employee_name': 'Applicant',
                          'workflow_name': 'Travel approval',
                          'workflow_version': 2,
                          'current_step': 0,
                          'step_count': 2,
                          'step_label': 'Municipal administrator',
                          'allowed_actions': ['approve', 'return', 'reject'],
                          'signature_revision': 3,
                          'days': 1,
                          'date': '2026-10-20',
                        },
                      ]
              : {
                  'source_module': 'dtr',
                  'source_table': 'leave_requests',
                  'source_record_id': primary,
                  'signatures': [
                    {
                      'slot_key': 'hr_approver',
                      'can_sign': true,
                      'can_assign': false,
                    },
                  ],
                };
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final requests = await loadAssignedWorkflowRequests('leave');
                  if (context.mounted) {
                    await reviewAssignedWorkflowRequest(
                      context,
                      requests.values.first,
                    );
                  }
                },
                child: const Text('Applicant'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applicant'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Review remarks'),
      'Please correct the destination.',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Return'));
    await tester.pumpAndSettle();
    final write = calls.singleWhere((o) => o.method == 'POST');
    expect(
      write.path,
      '/api/approval-workflows/requests/leave/$primary/return',
    );
    expect(write.data['expected_step'], 0);
    expect(write.data['signature_revision'], 3);
    expect(find.text('Approve'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'shared catalog binds the same definition to a DocuTracker document type',
    (tester) async {
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            calls.add(o);
            final dynamic data = o.path.endsWith('/document-types')
                ? [
                    {'document_type': 'memo', 'display_name': 'Memo'},
                  ]
                : o.method == 'GET'
                ? [
                    {
                      'id': 'shared',
                      'name': 'Shared approval',
                      'current_version': 1,
                      'is_active': true,
                      'steps': [
                        {
                          'label': 'Final reviewer',
                          'assignee_source': 'specific_users',
                          'user_ids': [primary, backup],
                        },
                      ],
                    },
                  ]
                : {'version': 3};
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
          },
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ApprovalWorkflowsPanel(allowDocumentBinding: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Use Shared approval in DocuTracker'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Memo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use workflow'));
      await tester.pumpAndSettle();
      expect(
        calls.singleWhere((o) => o.method == 'POST').path,
        '/api/approval-workflows/shared/document-types/memo',
      );
      expect(
        find.text('Shared workflow linked to document type.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
