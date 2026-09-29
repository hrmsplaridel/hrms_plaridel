import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('desktop balances use side-by-side rows and stack when narrow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(
          id: 'employee-1',
          email: 'employee@example.com',
          role: 'employee',
          fullName: 'Employee One',
        ),
      );
    final realtime = AppRealtimeProvider();
    final leave = LeaveProvider(repository: MockLeaveRepository());
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

    final credits = find.text('Leave Credits');
    final entitlements = find.text('Annual Leave Entitlements');
    final requests = find.text('My Requests');
    expect(
      tester.getTopLeft(credits).dy,
      closeTo(tester.getTopLeft(entitlements).dy, 1),
    );
    expect(
      tester.getTopLeft(requests).dy,
      greaterThan(tester.getTopLeft(entitlements).dy),
    );
    expect(find.byType(LeaveBalanceCard), findsNothing);
    expect(find.byType(LeaveDaysCard), findsNothing);
    final sickRow = find.byKey(const ValueKey('leave-balance-row-sickLeave'));
    final annualRow = find.byKey(
      const ValueKey('leave-balance-row-soloParentLeave'),
    );
    expect(sickRow, findsOneWidget);
    expect(annualRow, findsOneWidget);
    expect(tester.getSize(sickRow).width, lessThanOrEqualTo(560));
    expect(tester.getSize(annualRow).width, lessThanOrEqualTo(560));

    await tester.binding.setSurfaceSize(const Size(1120, 1100));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(sickRow).width, lessThanOrEqualTo(560));
    expect(tester.getSize(annualRow).width, lessThanOrEqualTo(560));
    expect(
      tester.getTopLeft(credits).dy,
      closeTo(tester.getTopLeft(entitlements).dy, 1),
    );

    await tester.binding.setSurfaceSize(const Size(900, 1100));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(entitlements).dy,
      greaterThan(tester.getTopLeft(credits).dy),
    );
    expect(
      tester.getTopLeft(requests).dy,
      greaterThan(tester.getTopLeft(entitlements).dy),
    );
  });
}
