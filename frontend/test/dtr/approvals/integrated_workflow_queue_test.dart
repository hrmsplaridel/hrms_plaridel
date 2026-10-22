import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';

import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';

void main() {
  for (final employee in [false, true]) {
    for (final kind in ['leave', 'locator']) {
      testWidgets(
        '$kind ${employee ? 'employee' : 'HR'} backup reviews from existing request queue',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ApiClient.instance.init();
          LocatorSlipDataCache.instance.invalidateAll();
          var decided = false;
          final calls = <RequestOptions>[];
          ApiClient.instance.dio.interceptors.clear();
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                calls.add(o);
                if (o.method == 'POST') {
                  decided = true;
                }
                dynamic data = <dynamic>[];
                if (o.path.endsWith('/final-reviewer/me')) {
                  data = {'can_review': kind == 'leave' && !employee};
                }
                if (o.path.endsWith('/inbox')) {
                  data = decided && kind == 'leave'
                      ? []
                      : [
                          {
                            'id': 'assigned',
                            'kind': kind,
                            'employee_name': 'Assigned Applicant',
                            'workflow_name': 'Travel approval',
                            'workflow_version': 2,
                            'current_step': 0,
                            'step_count': 2,
                            'step_label': 'Supervisor review',
                            'allowed_actions': ['approve', 'return', 'reject'],
                            'signature_revision': 3,
                            'can_review': !decided,
                            'date': '2026-10-20',
                            'days': 1,
                            'request_data': {
                              'id': 'assigned',
                              'user_id': 'applicant',
                              'employee_id': 'applicant',
                              'employee_name': 'Assigned Applicant',
                              'status': decided
                                  ? 'returned_for_correction'
                                  : 'pending_hr',
                              'workflow_snapshot': {
                                'steps': [
                                  {'label': 'Supervisor review'},
                                ],
                                'current_step': 0,
                              },
                              'leave_type': 'vacationLeave',
                              'start_date': '2026-10-20',
                              'end_date': '2026-10-20',
                              'working_days_applied': 1,
                              'slip_date': '2026-10-20',
                              'request_type': 'locator',
                              'office': 'Municipal hall',
                            },
                          },
                          {
                            'id': 'other-kind',
                            'kind': kind == 'leave' ? 'locator' : 'leave',
                            'employee_name': 'Other Module Applicant',
                          },
                        ];
                }
                if (o.path.contains('source-signatures')) {
                  data = {
                    'source_module': 'dtr',
                    'source_table': kind == 'leave'
                        ? 'leave_requests'
                        : 'locator_slips',
                    'source_record_id': 'assigned',
                    'signatures': [],
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
                id: 'backup',
                email: 'backup@test.local',
                role: employee ? 'employee' : 'hr',
              ),
            );
          final repository = MockLeaveRepository();
          if (kind == 'leave' && !employee) {
            await repository.updateRequest(LeaveRequest.fromJson({
              'id':'old-approved', 'user_id':'old-applicant', 'employee_name':'Old Approved Applicant',
              'status':'approved', 'start_date':'2026-10-01', 'end_date':'2026-10-01',
              'leave_type':'vacationLeave', 'working_days_applied':1,
            }));
          }
          final leave = LeaveProvider(repository: repository);
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
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: employee
                        ? kind == 'leave'
                              ? const LeaveMain(
                                  initialSection: LeaveSection.approvals,
                                )
                              : const EmployeeLocatorSlipContent()
                        : kind == 'leave'
                        ? const AdminLeaveScreen()
                        : const AdminLocatorManagementScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Workflow approvals'), findsNothing);
          expect(find.text('Assigned Applicant'), findsOneWidget);
          expect(find.text('Other Module Applicant'), findsNothing);
          expect(find.text('Pending Supervisor review'), findsOneWidget);
          if (kind == 'leave' && !employee) {
            expect(tester.getTopLeft(find.text('Assigned Applicant')).dy,
              lessThan(tester.getTopLeft(find.text('Old Approved Applicant')).dy),
              reason:'Active workflow approvals must precede older management history.');
          }
          // Assigned requests obey the existing queue's status filter.
          if (kind == 'locator' && employee) {
            await tester.tap(find.text('Pending'));
            await tester.pumpAndSettle();
            expect(find.text('Assigned Applicant'), findsOneWidget);
            await tester.tap(find.text('All'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Approved'));
            await tester.pumpAndSettle();
            expect(find.text('Assigned Applicant'), findsNothing);
            await tester.tap(find.text('All'));
          } else {
            await tester.tap(
              find.text(kind == 'leave' ? 'All statuses' : 'All').first,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Approved').last);
            await tester.pumpAndSettle();
            expect(find.text('Assigned Applicant'), findsNothing);
            await tester.tap(find.text('Reset Filters'));
          }
          await tester.pumpAndSettle();
          expect(find.text('Assigned Applicant'), findsOneWidget);
          await tester.tap(find.text('Assigned Applicant'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Supervisor review'), findsWidgets);
          expect(find.text('Approve'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Approve'),
                )
                .onPressed,
            isNull,
          );
          await tester.enterText(
            find.byType(TextField).last,
            'Please correct destination',
          );
          await tester.tap(find.text('Return'));
          await tester.pumpAndSettle();
          final decision = calls.singleWhere((o) => o.method == 'POST');
          expect(
            decision.path,
            '/api/approval-workflows/requests/$kind/assigned/return',
          );
          expect(decision.data['expected_step'], 0);
          expect(decision.data['signature_revision'], 3);
          expect(
            find.text('Assigned Applicant'),
            kind == 'locator' ? findsOneWidget : findsNothing,
          );
          if (kind == 'locator') {
            expect(find.text('Pending Supervisor review'), findsNothing);
            await tester.tap(find.text('Assigned Applicant'));
            await tester.pumpAndSettle();
            expect(find.text('Approve'), findsNothing);
            expect(find.text('Review remarks'), findsNothing);
            await tester.tap(find.byTooltip('Close'));
            await tester.pumpAndSettle();
            if (employee) {
              await tester.tap(find.text('Returned').last);
            } else {
              await tester.tap(find.text('All').first);
              await tester.pumpAndSettle();
              await tester.tap(find.text('Returned for Correction').last);
            }
            await tester.pumpAndSettle();
            expect(find.text('Assigned Applicant'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
