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

void main() {
  for (final scenario in [
    'department',
    'hr',
    'mayor',
    'expired',
    'missing',
    'paper',
    'paper-expired',
    'paper-own',
  ]) {
    testWidgets('Shared Locator revoke uses final approval time: $scenario', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiClient.instance.init();
      LocatorSlipDataCache.instance.invalidateAll();
      ApiClient.instance.dio.interceptors.clear();
      final approvedAt = scenario == 'missing'
          ? null
          : DateTime.now()
                .subtract(Duration(days: scenario == 'expired' ? 4 : 0))
                .toIso8601String();
      final paper = scenario.startsWith('paper');
      final record = <String, dynamic>{
        'id': 'completed',
        'employee_id': scenario == 'paper-own' ? 'reviewer' : 'applicant',
        'employee_name': 'Workflow Applicant',
        'status': 'approved',
        'slip_date': '2026-10-22',
        'request_type': 'locator',
        'office': 'Municipal hall',
        'reason': 'Inspection',
        'hr_reviewed_at': paper ? '2020-01-01T00:00:00Z' : approvedAt,
        if (paper)
          'paper_approval_record': {
            'source': 'approved_paper',
            'approval_date': '2020-01-01',
            'encoded_at': DateTime.now()
                .subtract(Duration(days: scenario == 'paper-expired' ? 4 : 0))
                .toIso8601String(),
          },
        'workflow_snapshot': paper
            ? null
            : {
                'name': 'Approval route',
                'version': 1,
                'current_step': 1,
                'steps': [
                  {
                    'label': scenario,
                    'assignee_source': switch (scenario) {
                      'hr' => 'final_hr_reviewers',
                      'mayor' => 'active_mayor',
                      _ => 'submitter_department_reviewers',
                    },
                  },
                ],
                'decisions': [
                  {
                    'step': 0,
                    'action': 'approve',
                    'actor_id': 'reviewer',
                    'reviewer': {'name': 'Reviewer'},
                  },
                ],
              },
      };
      final calls = <RequestOptions>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            calls.add(o);
            if (o.method == 'PATCH') {
              record['status'] = 'revoked';
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: record),
              );
              return;
            }
            dynamic data = <dynamic>[];
            if (o.path.endsWith('/final-reviewer/me')) {
              data = {'can_review': true};
            }
            if (o.uri.path.endsWith('/admin')) data = [record];
            if (o.path.endsWith('/inbox')) {
              data = [
                {
                  'id': 'completed',
                  'kind': 'locator',
                  'can_review': false,
                  'request_data': record,
                  'allowed_actions': [],
                },
              ];
            }
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
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
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        ApiClient.instance.dio.interceptors.clear();
        LocatorSlipDataCache.instance.invalidateAll();
        auth.dispose();
        realtime.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: realtime),
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
      await tester.tap(find.text('Workflow Applicant'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(OutlinedButton, 'Revoke Approval');
      expect(button, findsOneWidget);
      final enabled =
          scenario != 'missing' &&
          scenario != 'expired' &&
          scenario != 'paper-expired' &&
          scenario != 'paper-own';
      expect(
        tester.widget<OutlinedButton>(button).onPressed,
        enabled ? isNotNull : isNull,
      );
      if (scenario == 'missing') {
        expect(
          find.byTooltip('The approval time is unavailable.'),
          findsOneWidget,
        );
      }
      if (scenario == 'expired') {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                (widget.message?.startsWith(
                      'The three-day revoke period expired',
                    ) ??
                    false),
          ),
          findsOneWidget,
        );
      }
      if (enabled) {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('Revoke Locator Approval'), findsOneWidget);
        if (paper) {
          expect(find.textContaining('original signed paper'), findsOneWidget);
          await tester.tap(find.text('Revoke Approval').last);
          await tester.pumpAndSettle();
          expect(calls.where((o) => o.method == 'PATCH'), isEmpty);
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            ),
            'Duplicate approved paper entry.',
          );
          await tester.tap(find.text('Revoke Approval').last);
          await tester.pumpAndSettle();
          expect(calls.where((o) => o.method == 'PATCH').single.data, {
            'revocation_reason': 'Duplicate approved paper entry.',
          });
        }
      }
      expect(
        calls.where((o) => o.method != 'GET').length,
        scenario == 'paper' ? 1 : 0,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
