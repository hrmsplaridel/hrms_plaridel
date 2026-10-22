import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';

void main() {
  for (final width in [1400.0, 390.0]) {
    for (final status in ['approved', 'revoked', 'rejected_by_hr']) {
      testWidgets(
        'Admin $status workflow history reuses Locator details at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ApiClient.instance.init();
          LocatorSlipDataCache.instance.invalidateAll();
          ApiClient.instance.dio.interceptors.clear();
          final calls = <RequestOptions>[];
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                calls.add(o);
                dynamic data = <dynamic>[];
                if (o.path.endsWith('/final-reviewer/me')) {
                  data = {'can_review': true};
                }
                if (o.uri.path.endsWith('/admin')) {
                  data = [
                    {
                      'id': 'completed',
                      'employee_id': 'applicant',
                      'employee_name': 'Workflow Applicant',
                      'department_name': 'Accounting',
                      'status': status,
                      'slip_date': '2026-10-20',
                      'request_type': 'visit',
                      'request_type_label': 'Official visit',
                      'office': 'Municipal hall',
                      'reason': 'Inspection',
                      'am_in': true,
                      'hr_reviewed_at': DateTime.now().toIso8601String(),
                      'hr_remarks': 'Review completed with remarks',
                      'revoked_by_name': status == 'revoked'
                          ? 'Records Officer'
                          : null,
                      'month_end_reconciliation_required': status == 'revoked',
                      'revocation_reason': status == 'revoked'
                          ? 'Incorrect requested date'
                          : null,
                      'employee_detail_schema_snapshot': [
                        {
                          'key': 'purpose',
                          'label': 'Visit purpose',
                          'type': 'text',
                        },
                      ],
                      'additional_details': {'purpose': 'Office audit'},
                      'workflow_snapshot': {
                        'name': 'Department → HR → Mayor',
                        'version': 1,
                        'current_step': 3,
                        'steps': [
                          {'label': 'Department Review'},
                          {'label': 'HR Review'},
                          {'label': 'Mayor Approval'},
                        ],
                        'decisions': [
                          {
                            'step': 0,
                            'action': 'approve',
                            'actor_id': 'head',
                            'reviewer': {'name': 'Department Reviewer'},
                          },
                          {
                            'step': 1,
                            'action': 'approve',
                            'actor_id': 'hr',
                            'signature': {
                              'signer_name_snapshot': 'HR Reviewer',
                            },
                          },
                          {
                            'step': 2,
                            'action': 'approve',
                            'actor_id': 'mayor',
                            'reviewer': {'name': 'Current Mayor'},
                          },
                        ],
                      },
                    },
                  ];
                }
                if (o.path.contains('source-signatures')) {
                  data = {
                    'source_module': 'dtr',
                    'source_table': 'locator_slips',
                    'source_record_id': 'completed',
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
              const AppUser(
                id: 'reviewer',
                email: 'reviewer@test.local',
                role: 'admin',
              ),
            );
          final realtime = AppRealtimeProvider();
          final documents = DocuTrackerProvider();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ApiClient.instance.dio.interceptors.clear();
            auth.dispose();
            realtime.dispose();
            documents.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: auth),
                ChangeNotifierProvider.value(value: realtime),
                ChangeNotifierProvider.value(value: documents),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: AdminLocatorManagementScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Workflow Applicant'));
          await tester.tap(find.text('Workflow Applicant'));
          await tester.pumpAndSettle();
          expect(
            find.byType(EmployeeLocatorMobileDetailsDialog),
            findsOneWidget,
          );
          expect(find.text('Request Details'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('Slip Information'), findsOneWidget);
          expect(find.text('Visit purpose: Office audit'), findsOneWidget);
          expect(find.text('Approval History'), findsOneWidget);
          expect(find.text('History'), findsNothing);
          expect(find.text('Department Review · Approved'), findsOneWidget);
          expect(find.text('HR Review · Approved'), findsOneWidget);
          expect(find.text('Mayor Approval · Approved'), findsOneWidget);
          expect(find.text('Review completed with remarks'), findsOneWidget);
          expect(find.text('Approve'), findsNothing);
          expect(find.text('Return'), findsNothing);
          expect(find.text('Review remarks'), findsNothing);
          if (status == 'approved') {
            expect(find.text('Preview'), findsOneWidget);
            expect(find.text('Print'), findsOneWidget);
            expect(find.text('Revoke Approval'), findsOneWidget);
            await tester.ensureVisible(find.text('Revoke Approval'));
            await tester.tap(find.text('Revoke Approval'));
            await tester.pumpAndSettle();
            expect(find.text('Revoke Locator Approval'), findsOneWidget);
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          } else {
            expect(find.text('Preview'), findsNothing);
            expect(find.text('Print'), findsNothing);
            if (status == 'revoked') {
              expect(find.text('Incorrect requested date'), findsOneWidget);
              expect(find.text('Records Officer'), findsOneWidget);
              expect(
                find.textContaining('Re-run month-end processing'),
                findsOneWidget,
              );
            }
          }
          expect(calls.where((o) => o.method != 'GET'), isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
