import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

List<LeaveBalance> _balances(int count, bool credits) => [
  if (credits)
    const LeaveBalance(
      userId: 'employee',
      leaveType: LeaveType.sickLeave,
      earnedDays: 25,
    ),
  for (var i = 0; i < count; i++)
    LeaveBalance.fromJson({
      'user_id': 'employee',
      'leave_type': i == 0 ? 'mandatoryForcedLeave' : 'customAnnual$i',
      'leave_type_display_name': i == 0
          ? 'Mandatory/Forced Leave'
          : 'Annual Leave $i',
      'record_kind': i == 0 ? 'compliance_progress' : 'annual_entitlement',
      'entitlement_basis': i == 0 ? 'compliance' : 'annual',
      'entitlement_year': 2026,
      'earned_days': 5,
      'used_days': 1,
      'pending_days': 2,
    }),
];

class _Repository extends MockLeaveRepository {
  _Repository(this.rows);
  final List<LeaveBalance> rows;
  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async => rows;
}

Future<void> _open(
  WidgetTester tester, {
  required double width,
  required bool credits,
  int count = 6,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = _balances(count, credits);
  final auth = AuthProvider()
    ..replaceUser(
      AppUser(
        id: 'employee',
        email: 'employee@test.local',
        role: 'employee',
        employmentType: credits ? 'permanent' : 'job_order',
        leaveCreditEligible: credits,
      ),
    );
  final realtime = AppRealtimeProvider();
  final leave = LeaveProvider(repository: _Repository(rows));
  addTearDown(auth.dispose);
  addTearDown(realtime.dispose);
  addTearDown(leave.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AppRealtimeProvider>.value(value: realtime),
        ChangeNotifierProvider<LeaveProvider>.value(value: leave),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: width < 600
                ? EmployeeLeaveMobileBalancesPanel(
                    showCredits: credits,
                    balances: rows,
                    loading: false,
                    error: null,
                    onRetry: () {},
                    onBalanceHistory: () {},
                  )
                : const EmployeeLeaveScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final width in [1600.0, 900.0, 390.0]) {
    for (final credits in [true, false]) {
      testWidgets(
        'view all opens separate usage details at $width, credits=$credits',
        (tester) async {
          await _open(tester, width: width, credits: credits);
          expect(find.text('View all (6)'), findsOneWidget);
          expect(find.text('Annual Leave 3'), findsOneWidget);
          expect(find.text('Annual Leave 4'), findsNothing);
          expect(find.text('Annual Leave 5'), findsNothing);
          final dashboardHeight = tester
              .getSize(find.byType(SingleChildScrollView).first)
              .height;
          await tester.ensureVisible(find.text('View all (6)'));
          await tester.tap(find.text('View all (6)'));
          await tester.pumpAndSettle();

          final panel = find.byKey(const ValueKey('leave-usage-details-panel'));
          expect(panel, findsOneWidget);
          expect(
            tester.getSize(panel).width,
            width >= 1100 ? lessThan(width) : closeTo(width, 1),
          );
          if (width >= 1100) {
            expect(tester.getTopLeft(panel).dx, greaterThan(0));
          }
          expect(
            find.descendant(of: panel, matching: find.byType(LeaveBalanceCard)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.text('Mandatory/Forced Leave'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: panel, matching: find.text('Still required')),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.descendant(of: panel, matching: find.text('Annual Leave 5')),
            200,
            scrollable: find
                .descendant(of: panel, matching: find.byType(Scrollable))
                .first,
          );
          expect(
            find.descendant(of: panel, matching: find.text('Annual Leave 5')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Close leave usage details'));
          await tester.pumpAndSettle();
          expect(panel, findsNothing);
          expect(find.text('Annual Leave 4'), findsNothing);
          expect(find.text('View all (6)'), findsOneWidget);
          expect(
            tester.getSize(find.byType(SingleChildScrollView).first).height,
            dashboardHeight,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final width in [1600.0, 390.0]) {
    testWidgets('four usage rows do not need view all at $width', (
      tester,
    ) async {
      await _open(tester, width: width, credits: true, count: 4);
      expect(find.text('Annual Leave 3'), findsOneWidget);
      expect(find.textContaining('View all'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
