import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_request_information.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';

void main() {
  for (final width in [1400.0, 390.0]) {
    for (final stepCount in [2, 3]) {
      for (var stage = 0; stage < stepCount; stage++) {
        testWidgets(
          '$stepCount-step workflow leave uses the old details layout at stage $stage, width $width',
          (tester) async {
            tester.view.physicalSize = Size(width, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            ApiClient.instance.init();
            ApiClient.instance.dio.interceptors.clear();
            ApiClient.instance.dio.interceptors.add(
              InterceptorsWrapper(
                onRequest: (o, h) {
                  h.resolve(
                    Response(
                      requestOptions: o,
                      statusCode: 200,
                      data: {
                        'source_module': 'dtr',
                        'source_table': 'leave_requests',
                        'source_record_id': 'request',
                        'signatures': [],
                      },
                    ),
                  );
                },
              ),
            );
            final auth = AuthProvider()
              ..replaceUser(
                AppUser(
                  id: 'reviewer',
                  email: 'reviewer@test.local',
                  role: ['employee', 'hr', 'mayor'][stage],
                ),
              );
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              ApiClient.instance.dio.interceptors.clear();
              auth.dispose();
            });
            final label = [
              'Department Review',
              'HR Review',
              'Mayor Approval',
            ][stage];
            final snapshot = {
              'name': stepCount == 2
                  ? 'Department → HR'
                  : 'Department → HR → Mayor',
              'version': 1,
              'current_step': stage,
              'steps': [
                {'label': 'Department Review'},
                {'label': 'HR Review'},
                if (stepCount == 3) {'label': 'Mayor Approval'},
              ],
            };
            final request = <String, dynamic>{
              'kind': 'leave',
              'id': 'request',
              'employee_name': 'Applicant',
              'step_label': label,
              'workflow_name': snapshot['name'],
              'current_step': stage,
              'step_count': stepCount,
              'allowed_actions': ['approve', 'return', 'reject'],
              'days': 1,
              'signature_revision': 1,
              'created_at': '2026-10-16T01:00:00Z',
              'additional_details': {
                'location_details': null,
                'sick_leave_nature': null,
                'destination': 'Cebu',
              },
              'request_data': {
                'id': 'request',
                'user_id': 'applicant',
                'employee_name': 'Applicant',
                'status': stage == 2 ? 'pending_mayor' : 'pending_hr',
                'workflow_snapshot': snapshot,
                'office_department': 'Accounting',
                'position_title': 'Accountant',
                'salary': 25000,
                'date_filed': '2026-10-16',
                'start_date': '2026-10-20',
                'end_date': '2026-10-20',
                'working_days_applied': 1,
                'leave_type': 'others',
                'custom_leave_type_text': 'Earl leave',
                'reason': 'Family appointment',
                'custom_details': {'destination': 'Cebu'},
                'employee_detail_schema_snapshot': [
                  {
                    'key': 'destination',
                    'label': 'Destination',
                    'type': 'text',
                  },
                ],
              },
              'decisions': stage == 0
                  ? []
                  : [
                      {
                        'step_label': 'Department Review',
                        'action': 'approve',
                        'reviewer_name': 'Department Reviewer',
                        'acted_at': '2026-10-16T02:00:00Z',
                      },
                    ],
            };
            await tester.pumpWidget(
              ChangeNotifierProvider.value(
                value: auth,
                child: MaterialApp(
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () =>
                            reviewAssignedWorkflowRequest(context, request),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            expect(find.text('Request Details'), findsOneWidget);
            expect(find.byType(AdminLeaveDetailsFrame), findsOneWidget);
            expect(find.byType(AdminLeaveRequestDetailsPanel), findsOneWidget);
            expect(find.byType(LeaveRequestInformation), findsOneWidget);
            expect(find.text('Employee Information'), findsOneWidget);
            expect(find.text('Accounting'), findsOneWidget);
            expect(find.text('Accountant'), findsOneWidget);
            expect(find.text('Pending $label'), findsOneWidget);
            expect(find.text('Family appointment'), findsNWidgets(2));
            expect(find.text('Destination'), findsOneWidget);
            expect(find.text('Cebu'), findsOneWidget);
            expect(find.text('Approval History'), findsOneWidget);
            expect(find.text('Actions'), findsOneWidget);
            expect(find.text('Current review cycle'), findsNothing);
            expect(
              find.ancestor(
                of: find.text('Approve'),
                matching: find.byType(SingleChildScrollView),
              ),
              findsOneWidget,
              reason:
                  'Workflow actions must use the existing scrollable Actions section.',
            );
            expect(find.text('Submitted'), findsOneWidget);
            expect(find.textContaining('location_details:'), findsNothing);
            expect(find.textContaining('sick_leave_nature:'), findsNothing);
            expect(find.text('No applicant signature yet'), findsNothing);
            expect(find.text('No reviewer signature yet'), findsOneWidget);
            expect(find.text('Approve'), findsOneWidget);
            await tester.tap(find.byTooltip('Close'));
            await tester.pumpAndSettle();
            expect(find.text('Request Details'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
