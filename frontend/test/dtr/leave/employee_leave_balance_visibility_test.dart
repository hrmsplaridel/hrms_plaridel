import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/pages/employee_leave_mobile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_entitlement_basis.dart';

class _Repository extends MockLeaveRepository {
  _Repository(this.hasHistory, this.annual);
  final bool annual;
  final bool hasHistory;
  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async => [
    LeaveBalance(
      userId: userId,
      leaveType: LeaveType.sickLeave,
      earnedDays: hasHistory ? 2 : 0,
      usedDays: hasHistory ? 2 : 0,
    ),
    if (annual)
      LeaveBalance(
        userId: userId,
        leaveType: LeaveType.others,
        leaveTypeName: 'wellnessLeave',
        recordKind: 'annual_entitlement',
        entitlementBasis: LeaveEntitlementBasis.annual,
        earnedDays: 5,
      ),
  ];
}

void main() {
  for (final width in [1600.0, 700.0, 400.0]) {
    for (final type in ['job_order', 'contract_of_service']) {
      for (final history in [false, true]) {
        testWidgets('$type credits history=$history at width=$width', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 1100));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final auth = AuthProvider()
            ..replaceUser(
              AppUser(
                id: 'employee-1',
                email: 'employee@test',
                role: 'employee',
                employmentType: type,
                leaveCreditEligible: false,
              ),
            );
          final realtime = AppRealtimeProvider();
          final annual = !history && width == 1600 && type == 'job_order';
          final leave = LeaveProvider(repository: _Repository(history, annual));
          addTearDown(auth.dispose);
          addTearDown(realtime.dispose);
          addTearDown(leave.dispose);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AppRealtimeProvider>.value(
                  value: realtime,
                ),
                ChangeNotifierProvider<LeaveProvider>.value(value: leave),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: width < 600
                        ? const EmployeeLeaveMobilePage()
                        : const EmployeeLeaveScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.text('Leave Credits'),
            history ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Available Credits'),
            history ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Annual Leave Entitlements'),
            annual ? findsOneWidget : findsNothing,
          );
          if (annual) {
            final row = find.byKey(
              const ValueKey('leave-balance-row-wellnessLeave'),
            );
            expect(tester.getSize(row).width, greaterThan(1200));
            expect(
              tester.getTopLeft(find.text('Annual Leave Entitlements')).dx,
              tester.getTopLeft(row).dx,
            );
          }
          expect(
            find.text('Credit History'),
            history ? findsOneWidget : findsNothing,
          );
          expect(find.text('My Requests'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
