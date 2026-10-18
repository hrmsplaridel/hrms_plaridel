import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

LeaveBalance _proratedBalance() => LeaveBalance.fromJson({
  'user_id': 'employee',
  'leave_type': 'wellnessLeave',
  'leave_type_display_name': 'Wellness Leave',
  'record_kind': 'annual_entitlement',
  'entitlement_basis': 'annual',
  'earned_days': 1,
  'full_limit_days': 5,
  'calculated_days': 1.25,
  'prorated': true,
  'entitlement_year': 2026,
});

class _ProratedRepository extends MockLeaveRepository {
  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async => [
    _proratedBalance(),
  ];
}

void main() {
  test(
    'annual limit survives JSON and copies while availability uses the prorated allowance',
    () {
      final balance = _proratedBalance();
      expect(balance.toJson()['full_limit_days'], 5);
      expect(balance.copyWith(usedDays: 1).toJson()['full_limit_days'], 5);
      expect(balance.availableDays, 1);
      expect(balance.copyWith(usedDays: 1).availableDays, 0);
      expect(balance.copyWith(pendingDays: 1).availableDays, 0);
    },
  );

  testWidgets('mobile separates full entitlement from prorated usable days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LeaveDaysCard(balance: _proratedBalance())),
      ),
    );
    final text = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .toList();
    expect(text, contains('Entitlement: 5'));
    expect(text, contains('Prorated: 1'));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('day available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shows Entitled 5, Prorated 1 and Available 1', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(
          id: 'employee',
          email: 'employee@test',
          role: 'employee',
          fullName: 'Employee',
        ),
      );
    final realtime = AppRealtimeProvider();
    final leave = LeaveProvider(repository: _ProratedRepository());
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
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EmployeeLeaveScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final row = find.byKey(const ValueKey('leave-balance-row-wellnessLeave'));
    expect(
      find.descendant(of: row, matching: find.text('Entitled')),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text('5')), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Prorated')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('1')),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile annual card explains service eligibility and rounded first-year days',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final balance = LeaveBalance.fromJson({
        'user_id': 'employee',
        'leave_type': 'wellnessLeave',
        'leave_type_display_name': 'Wellness Leave',
        'record_kind': 'annual_entitlement',
        'entitlement_basis': 'annual',
        'earned_days': 1,
        'eligible': false,
        'eligibility_message': 'You become eligible on 2027-04-01.',
        'prorated': true,
        'calculated_days': 1.25,
        'entitlement_year': 2026,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LeaveDaysCard(balance: balance)),
        ),
      );
      expect(find.text('You become eligible on 2027-04-01.'), findsOneWidget);
      expect(find.textContaining('rounded down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
