import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_credit_switcher.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';

const sick = LeaveBalance(
  userId: 'employee',
  leaveType: LeaveType.sickLeave,
  earnedDays: 23.8,
  usedDays: 6,
);
const vacation = LeaveBalance(
  userId: 'employee',
  leaveType: LeaveType.vacationLeave,
  earnedDays: 23.8,
  usedDays: 23.8,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(20), child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('credit switcher cycles through custom wallets and handles refreshed balances', (tester) async {
    const custom = LeaveBalance(userId: 'employee', leaveType: LeaveType.others,
      leaveTypeName: 'wellness', leaveTypeDisplayName: 'Wellness Leave', earnedDays: 2.5);
    await mount(tester, const LeaveCreditSwitcher(balances: [custom, vacation, sick]), width: 800);
    expect(find.text('Sick Leave'), findsOneWidget);
    await tester.tap(find.byTooltip('Show Vacation Leave'));await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show Wellness Leave'));await tester.pumpAndSettle();
    expect(find.text('Wellness Leave'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.byType(LeaveBalanceCard), findsOneWidget);
    await mount(tester, LeaveCreditSwitcher(balances: [sick, vacation, custom.copyWith(earnedDays: 5)]), width: 800);
    expect(find.text('Wellness Leave'), findsOneWidget);
    expect(tester.widget<LeaveBalanceCard>(find.byType(LeaveBalanceCard)).balance.earnedDays, 5);
    await tester.tap(find.byTooltip('Show Sick Leave'));await tester.pumpAndSettle();
    expect(find.text('Sick Leave'), findsOneWidget);
    await mount(tester, const LeaveCreditSwitcher(balances: [custom]), width: 800);
    expect(find.text('Wellness Leave'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
    await mount(tester, const LeaveCreditSwitcher(balances: []), width: 800);
    expect(find.byType(LeaveBalanceCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'available credit is the main figure and other totals remain visible',
    (tester) async {
      await mount(tester, const LeaveBalanceCard(balance: sick));
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('days'), findsOneWidget);
      for (final label in ['Sick Leave', 'Earned', 'Used', 'Pending']) {
        expect(find.text(label), findsOneWidget);
      }
      final available = tester.widget<Text>(find.text('17.8'));
      final earned = tester.widget<Text>(find.text('23.8'));
      expect(available.style!.fontSize, greaterThan(earned.style!.fontSize!));
      expect(
        tester.getTopLeft(find.text('17.8')).dy,
        lessThan(tester.getTopLeft(find.text('Earned')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final balance in [
    vacation,
    const LeaveBalance(
      userId: 'employee',
      leaveType: LeaveType.sickLeave,
      earnedDays: 10,
      usedDays: 8,
      pendingDays: 4,
      adjustedDays: 0.5,
    ),
  ]) {
    testWidgets(
      'credit card preserves available value ${balance.availableDays}',
      (tester) async {
        await mount(tester, LeaveBalanceCard(balance: balance));
        final expected = balance.availableDays == 0 ? '0' : '-1.5';
        expect(find.text(expected), findsWidgets);
        expect(find.text('Available'), findsOneWidget);
        expect(find.text('days'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'card fits $brightness at $width with enlarged text and large balances',
        (tester) async {
          await mount(
            tester,
            const LeaveBalanceCard(
              balance: LeaveBalance(
                userId: 'employee',
                leaveType: LeaveType.vacationLeave,
                leaveTypeDisplayName: 'Vacation Leave — carried over credits',
                earnedDays: 9999999.999,
                pendingDays: 12.5,
              ),
            ),
            width: width,
            brightness: brightness,
            textScale: 1.6,
          );
          expect(find.text('days'), findsOneWidget);
          expect(find.text('Pending'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'mobile uses the shared cards, keeps history available, and preserves errors and retry',
    (tester) async {
      var history = 0;
      var retries = 0;
      await mount(
        tester,
        EmployeeLeaveMobileBalancesPanel(
          balances: const [sick, vacation],
          loading: false,
          error: 'Could not refresh balances',
          onRetry: () => retries++,
          onBalanceHistory: () => history++,
        ),
      );
      expect(find.byType(LeaveBalanceCard), findsOneWidget);
      expect(find.text('Sick Leave'), findsOneWidget);
      await tester.tap(find.byTooltip('Show Vacation Leave'));
      await tester.pumpAndSettle();
      expect(find.byType(LeaveBalanceCard), findsOneWidget);
      expect(find.text('Vacation Leave'), findsOneWidget);
      await tester.tap(find.text('Credit History'));
      await tester.tap(find.byTooltip('Retry'));
      expect(history, 1);
      expect(retries, 1);
      expect(find.text('Could not refresh balances'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
