import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_entitlement_basis.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_usage_grid.dart';

void main() {
  LeaveBalance usage(int i) => LeaveBalance(
    userId: 'employee',
    leaveType: LeaveType.others,
    leaveTypeName: 'usage_$i',
    leaveTypeDisplayName: 'Leave type $i',
    recordKind: 'annual_entitlement',
    entitlementBasis: LeaveEntitlementBasis.annual,
    entitlementYear: 2026,
    earnedDays: 7,
    usedDays: 2,
  );
  Future<void> mount(
    WidgetTester tester, {
    required double width,
    required List<LeaveBalance> balances,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1600),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LeaveUsageGrid(balances: balances),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final count in [0, 1, 3, 4, 5]) {
    testWidgets(
      'wide usage grid fills the right panel with $count leave types',
      (tester) async {
        await mount(tester, width: 1120, balances: List.generate(count, usage));
        if (count == 0) {
          expect(find.textContaining('Leave type'), findsNothing);
          return;
        }
        final first = find.byKey(const ValueKey('leave-balance-row-usage_0'));
        expect(
          tester.getSize(first).width,
          closeTo(count == 1 ? 1120 : 552, 1),
        );
        if (count > 1) {
          final second = find.byKey(
            const ValueKey('leave-balance-row-usage_1'),
          );
          expect(
            tester.getTopLeft(second).dy,
            closeTo(tester.getTopLeft(first).dy, 1),
          );
          expect(tester.getTopRight(second).dx, closeTo(1120, 1));
        }
        if (count > 2) {
          expect(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('leave-balance-row-usage_2')),
                )
                .dy,
            greaterThan(tester.getBottomLeft(first).dy),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'usage cards stack at 320 pixels with large text in $brightness',
      (tester) async {
        final forced = LeaveBalance(
          userId: 'employee',
          leaveType: LeaveType.mandatoryForcedLeave,
          recordKind: 'compliance_progress',
          entitlementBasis: LeaveEntitlementBasis.compliance,
          entitlementYear: 2026,
          earnedDays: 5,
          usedDays: 1,
          historyVerificationRequired: true,
        );
        final annual = usage(1).copyWith(
          prorated: true,
          fullLimitDays: 7,
          earnedDays: 3,
          eligibilityMessage: 'Eligible from the verified service date',
          leaveTypeDisplayName: 'A longer custom leave type name',
        );
        await mount(
          tester,
          width: 320,
          balances: [forced, annual],
          scale: 1.6,
          brightness: brightness,
        );
        final first = find.byKey(
          const ValueKey('leave-balance-row-mandatoryForcedLeave'),
        );
        final second = find.byKey(const ValueKey('leave-balance-row-usage_1'));
        expect(
          tester.getTopLeft(second).dy,
          greaterThan(tester.getBottomLeft(first).dy),
        );
        expect(find.text('History verification required'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('Required'), findsOneWidget);
        expect(find.text('Prorated'), findsOneWidget);
        expect(find.text('Still required'), findsOneWidget);
        expect(find.text('Remaining'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
