import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';

class _Realtime extends AppRealtimeProvider {
  final controller = StreamController<AppRealtimeEvent>.broadcast();
  @override
  Stream<AppRealtimeEvent> get events => controller.stream;
  void forwardToHr() =>
      controller.add(const AppRealtimeEvent(name: 'locator_updated'));
  @override
  void dispose() {
    controller.close();
    super.dispose();
  }
}

void main() {
  for (final arrivesWhileOpen in [false, true]) {
    testWidgets(
      'HR workflow approval is visible before older records, realtime=$arrivesWhileOpen',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ApiClient.instance.init();
        LocatorSlipDataCache.instance.invalidateAll();
        ApiClient.instance.dio.interceptors.clear();
        var reachedHr = !arrivesWhileOpen;
        final calls = <RequestOptions>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              calls.add(o);
              dynamic data = <dynamic>[];
              if (o.path.endsWith('/final-reviewer/me')) {
                data = {'can_review': true};
              }
              if (o.path.endsWith('/inbox')) {
                data = reachedHr
                    ? [
                        {
                          'id': 'awaiting-hr',
                          'kind': 'locator',
                          'employee_name': 'Current HR Applicant',
                          'can_review': true,
                          'current_step': 1,
                          'step_label': 'HR Review',
                          'workflow_name': 'Department → HR → Mayor',
                          'step_count': 3,
                          'allowed_actions': ['approve', 'return', 'reject'],
                          'signature_revision': 1,
                          'request_data': {
                            'id': 'awaiting-hr',
                            'employee_id': 'applicant',
                            'employee_name': 'Current HR Applicant',
                            'status': 'pending_hr',
                            'slip_date': '2026-10-19',
                            'office': 'Municipal hall',
                            'workflow_snapshot': {
                              'current_step': 1,
                              'steps': [
                                {'label': 'Department Review'},
                                {'label': 'HR Review'},
                                {'label': 'Mayor Approval'},
                              ],
                            },
                          },
                        },
                      ]
                    : [];
              }
              if (o.uri.path.endsWith('/admin')) {
                data = {
                  'items': List.generate(
                    10,
                    (index) => {
                      'id': 'old-$index',
                      'employee_id': 'old-applicant-$index',
                      'employee_name': 'Old Approved $index',
                      'status': 'approved',
                      'slip_date': '2026-10-01',
                      'office': 'Old destination',
                    },
                  ),
                  'pagination': {
                    'page': 1,
                    'page_size': 10,
                    'total': 20,
                    'page_count': 2,
                  },
                };
              }
              if (o.path.endsWith('/signatures')) {
                data = {
                  'source_module': 'dtr',
                  'source_table': 'locator_slips',
                  'source_record_id': 'awaiting-hr',
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
              id: 'hr-reviewer',
              email: 'hr@test.local',
              role: 'admin',
            ),
          );
        final realtime = _Realtime();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          ApiClient.instance.dio.interceptors.clear();
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
        if (arrivesWhileOpen) {
          expect(find.text('Current HR Applicant'), findsNothing);
          final previousInboxCalls = calls
              .where((o) => o.path.endsWith('/inbox'))
              .length;
          reachedHr = true;
          realtime.forwardToHr();
          await tester.pumpAndSettle();
          expect(
            calls.where((o) => o.path.endsWith('/inbox')).length,
            greaterThan(previousInboxCalls),
          );
        }
        expect(find.text('Current HR Applicant'), findsOneWidget);
        expect(
          find.text('Current HR Applicant').hitTestable(),
          findsOneWidget,
          reason:
              'The active HR approval must be visible without scrolling past historical records.',
        );
        expect(
          tester.getTopLeft(find.text('Current HR Applicant')).dy,
          lessThan(tester.getTopLeft(find.text('Old Approved 0')).dy),
        );
        await tester.tap(find.text('Current HR Applicant'));
        await tester.pumpAndSettle();
        expect(find.text('HR Review signature'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
