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
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';

class _Repository extends MockLeaveRepository {
  bool authorized = true;
  bool revoked = false;
  bool expired = false;
  bool missingDate = false;
  String leaveTypeName = 'sickLeave';
  String creditPolicy = 'sickLeave';
  double? paidDays = 1;
  int writes = 0;
  Map<String, dynamic> get record => {
    'id': 'request', 'user_id': 'applicant', 'employee_name': 'Applicant', 'leave_type': leaveTypeName,
    'approved_days_with_pay': paidDays,
    'start_date': '2026-10-19', 'end_date': '2026-10-19', 'working_days_applied': 1,
    'status': revoked ? 'returned' : 'approved', 'can_revoke_approval': authorized && !revoked,
    if (!missingDate) 'approved_at': DateTime.now().subtract(Duration(days: expired ? 4 : 1)).toIso8601String(),
    // An older HR timestamp must not replace the final Mayor approval date.
    if (!missingDate) 'reviewed_at': DateTime.now().subtract(const Duration(days: 7)).toIso8601String(),
    'workflow_snapshot': {
      'name': 'Complete Workflow', 'version': 2, 'current_step': 3,
      'steps': [
        {'label': 'Dept', 'assignee_source': 'submitter_department_reviewers'},
        {'label': 'Final HR', 'assignee_source': 'final_hr_reviewers'},
        {'label': 'Mayor', 'assignee_source': 'active_mayor'},
      ],
      'decisions': [],
    },
  };
  @override
  Future<LeaveRequest?> getRequestById(String id) async => LeaveRequest.fromJson(record);
  @override
  Future<LeaveRequestPage> listReviewRequestsPage({required LeaveRequestQuery query, bool departmentHead = false}) async =>
    LeaveRequestPage(items: [LeaveRequest.fromJson(record)], total: 1, limit: 200, offset: 0);
  @override
  Future<LeaveRequest> revokeApproval(LeaveReviewDecisionInput input) async {
    writes++;
    revoked = true;
    return LeaveRequest.fromJson(record);
  }
}

void main() {
  for (final example in [
    ('wellnessLeave', 'none', 1.0, false),
    ('specialPrivilegeLeave', 'none', 1.0, false),
    ('vacationLeave', 'vacationLeave', 0.0, false),
    ('sickLeave', 'sickLeave', 1.0, true),
    ('mandatoryForcedLeave', 'vacationLeave', 1.0, true),
    ('customCreditLeave', 'ownBalance', 1.0, true),
  ]) {
    testWidgets('revoke message reflects credits for ${example.$1}, paid days=${example.$3}', (tester) async {
      final repository = _Repository()
        ..leaveTypeName = example.$1
        ..creditPolicy = example.$2
        ..paidDays = example.$3;
      await _mount(tester, repository);
      await tester.tap(find.text('Applicant').first);
      await tester.pumpAndSettle();
      final revoke = find.widgetWithText(OutlinedButton, 'Revoke Approval');
      await tester.ensureVisible(revoke);
      await tester.tap(revoke);
      await tester.pumpAndSettle();
      final confirmation = tester.widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text)))
          .map((text) => text.data ?? '').join(' ');
      expect(confirmation.contains('Leave credits will be restored.'), example.$4);
      expect(confirmation.contains('balance will be restored'), false);
      await tester.tap(find.text('Revoke Approval').last);
      await tester.pumpAndSettle();
      expect(find.text(example.$4 ? 'Approval revoked. Leave credits restored.' : 'Approval revoked. The request was returned to the employee.'), findsOneWidget);
      expect(repository.writes, 1);
      expect(tester.takeException(), isNull);
    });
  }
  test('revoke deadline uses final approval time and preserves it through model copies', () {
    final finalApproval = DateTime.utc(2026, 10, 18, 2);
    final request = LeaveRequest.fromJson({
      'user_id': 'applicant', 'leave_type': 'sickLeave', 'status': 'approved',
      'approved_at': finalApproval.toIso8601String(), 'reviewed_at': '2026-10-10T02:00:00Z', 'can_revoke_approval': true,
    });
    expect(adminLeaveRevokeDeadline(request), finalApproval.add(const Duration(days: 3)));
    expect(adminLeaveRevokeDisabledReason(request, now: finalApproval.add(const Duration(days: 1))), isNull);
    expect(request.copyWith().toJson()['approved_at'], finalApproval.toIso8601String());
    expect(request.copyWith().toJson()['can_revoke_approval'], true);
  });

  for (final scenario in ['confirm', 'cancel', 'unauthorized', 'expired', 'missing-date', 'changed-permission']) {
    testWidgets('shared leave Revoke Approval: $scenario', (tester) async {
      final repository = _Repository()
        ..authorized = scenario != 'unauthorized'
        ..expired = scenario == 'expired'
        ..missingDate = scenario == 'missing-date';
      await _mount(tester, repository);
      await tester.tap(find.text('Applicant').first);
      await tester.pumpAndSettle();
      final revoke = find.widgetWithText(OutlinedButton, 'Revoke Approval');
      if (scenario == 'unauthorized') {
        expect(revoke, findsNothing);
      } else if (scenario == 'expired' || scenario == 'missing-date') {
        expect(revoke, findsNothing);
        expect(find.textContaining(scenario == 'expired' ? 'Revoke period expired' : 'Cannot determine'), findsOneWidget);
      } else {
        expect(revoke, findsOneWidget);
        if (scenario == 'changed-permission') repository.authorized = false;
        await tester.ensureVisible(revoke);
        await tester.tap(revoke);
        await tester.pumpAndSettle();
        if (scenario == 'changed-permission') {
          expect(find.byType(AlertDialog), findsNothing);
        } else if (scenario == 'cancel') {
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Revoke Approval').last);
          await tester.pumpAndSettle();
          expect(repository.revoked, true);
          expect(find.textContaining('Approval revoked.'), findsOneWidget);
          await tester.tap(find.text('Applicant').first);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(OutlinedButton, 'Revoke Approval'), findsNothing);
        }
      }
      expect(repository.writes, scenario == 'confirm' ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _mount(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1600, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  ApiClient.instance.init();
  LeaveTypeDefinitionCache.instance.invalidate();
  ApiClient.instance.dio.interceptors.clear();
  ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    dynamic data = <dynamic>[];
    if (o.path.endsWith('/final-reviewer/me')) data = {'can_review': true};
    if (o.path.endsWith('/types')) {
      data = [{
        'name': repository.leaveTypeName,
        'display_name': repository.leaveTypeName,
        'balance_ledger_type': repository.creditPolicy,
      }];
    }
    if (o.path.endsWith('/inbox')) {
      data = repository.revoked ? [] : [{
      'id': 'request', 'kind': 'leave', 'employee_name': 'Applicant', 'days': 1,
      'current_step': 3, 'step_count': 3, 'signature_revision': 1, 'allowed_actions': [],
      'can_review': false, 'request_data': repository.record,
      }];
    }
    h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
  }));
  final auth = AuthProvider()..replaceUser(const AppUser(id: 'mayor', email: 'mayor@test.local', role: 'mayor'));
  final leave = LeaveProvider(repository: repository);
  final realtime = AppRealtimeProvider();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    ApiClient.instance.dio.interceptors.clear();
    LeaveTypeDefinitionCache.instance.invalidate();
    auth.dispose(); leave.dispose(); realtime.dispose();
  });
  await tester.pumpWidget(MultiProvider(providers: [
    ChangeNotifierProvider.value(value: auth), ChangeNotifierProvider.value(value: leave),
    ChangeNotifierProvider.value(value: realtime),
  ], child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AdminLeaveScreen())))));
  await tester.pumpAndSettle();
}
