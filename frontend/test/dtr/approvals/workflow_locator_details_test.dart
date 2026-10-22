import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';

void main() {
  for (final width in [1400.0, 390.0]) {
    for (final stage in [0, 1, 2, 3]) {
      testWidgets(
        'Locator reuses existing details at stage $stage, width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
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
                      'source_table': 'locator_slips',
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
                role: ['employee', 'hr', 'mayor', 'hr'][stage],
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
            'Mayor Approval',
          ][stage];
          final request = <String, dynamic>{
            'kind': 'locator',
            'id': 'request',
            'employee_name': 'Applicant',
            'step_label': label,
            'workflow_name': 'Department → HR → Mayor',
            'current_step': stage,
            'step_count': 3,
            'signature_revision': 1,
            'allowed_actions': ['approve', 'return', 'reject'],
            'can_review': stage != 3,
            'date': '2026-10-20T00:00:00.000Z',
            'reason': 'Official visit',
            'office': 'Municipal hall',
            'additional_details': {'purpose': 'Inspection', 'empty': null},
            'detail_schema': [
              {'key': 'purpose', 'label': 'Visit purpose', 'type': 'text'},
            ],
            'request_data': {
              'id': 'request',
              'employee_name': 'Applicant',
              'department_name': 'Accounting',
              'slip_date': '2026-10-20',
              'request_type': 'locator',
              'am_in': true,
              'status': stage == 3 ? 'approved' : 'pending_hr',
            },
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
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.byType(EmployeeLocatorMobileDetailsDialog),
            findsOneWidget,
          );
          expect(find.text('Request Details'), findsOneWidget);
          expect(find.text('Approval History'), findsOneWidget);
          expect(find.text('History'), findsNothing);
          expect(find.text('Submitted'), findsOneWidget);
          expect(find.text('Slip Information'), findsOneWidget);
          expect(find.text('Oct 20, 2026'), findsWidgets);
          expect(find.textContaining('2026-10-20T'), findsNothing);
          expect(
            find.text(stage == 3 ? 'Approved' : 'Pending $label'),
            findsOneWidget,
          );
          expect(find.textContaining('Step 4 of 3'), findsNothing);
          expect(find.text('Applicant'), findsWidgets);
          expect(find.text('Accounting'), findsOneWidget);
          expect(find.text('Municipal hall'), findsOneWidget);
          expect(find.text('AM IN'), findsOneWidget);
          expect(find.text('Visit purpose: Inspection'), findsOneWidget);
          expect(find.textContaining('empty:'), findsNothing);
          if (stage == 3) {
            expect(find.text('Approve'), findsNothing);
            expect(find.text('Review remarks'), findsNothing);
            expect(find.text('Preview'), findsOneWidget);
            expect(find.text('Print'), findsOneWidget);
          } else {
            expect(find.text('$label signature'), findsOneWidget);
            expect(find.text('Approve'), findsOneWidget);
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Approve'),
                  )
                  .onPressed,
              isNull,
            );
          }
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
