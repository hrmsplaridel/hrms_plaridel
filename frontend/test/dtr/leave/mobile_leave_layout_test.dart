import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_summary_strip.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_request_information.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_overlay.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_fab.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';

const _balance = LeaveBalance(
  userId: 'employee',
  leaveType: LeaveType.sickLeave,
  earnedDays: 8.8,
  usedDays: 5,
);
final _request = LeaveRequest(
  id: 'request',
  userId: 'employee',
  employeeName: 'Earl D Bala',
  officeDepartment: 'Human Resources',
  positionTitle: 'Department Head',
  leaveType: LeaveType.sickLeave,
  dateFiled: DateTime(2026, 10, 5),
  startDate: DateTime(2026, 9, 23),
  endDate: DateTime(2026, 9, 23),
  workingDaysApplied: 1,
  status: LeaveRequestStatus.approved,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget balances() => EmployeeLeaveMobileBalancesPanel(
    balances: const [_balance],
    loading: false,
    error: null,
    onRetry: () {},
    onBalanceHistory: () {},
  );

  testWidgets(
    'mobile credit card keeps the original appearance and readable totals',
    (tester) async {
      await mount(tester, balances());
      expect(
        tester.getSize(find.byType(LeaveBalanceCard)).height,
        greaterThan(190),
      );
      for (final label in [
        'Sick Leave',
        '3.8',
        'Earned',
        '8.8',
        'Used',
        '5',
        'Pending',
        '0',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.text('3.8')).dy,
        greaterThan(tester.getBottomLeft(find.text('Sick Leave')).dy + 20),
      );
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('days'), findsOneWidget);
      expect(
        tester
            .getSize(find.widgetWithText(TextButton, 'Credit History'))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile switches one original card at a time, starting with Sick Leave',
    (tester) async {
      const vacation = LeaveBalance(
        userId: 'employee',
        leaveType: LeaveType.vacationLeave,
        earnedDays: 23.8,
        usedDays: 23.8,
      );
      await mount(
        tester,
        EmployeeLeaveMobileBalancesPanel(
          balances: const [vacation, _balance],
          loading: false,
          error: null,
          onRetry: () {},
          onBalanceHistory: () {},
        ),
      );
      expect(find.byType(LeaveBalanceCard), findsOneWidget);
      expect(find.text('Sick Leave'), findsOneWidget);
      expect(find.text('Vacation Leave'), findsNothing);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
      final swap = find.byTooltip('Show Vacation Leave');
      expect(tester.getSize(swap).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(swap);
      await tester.pumpAndSettle();
      expect(find.byType(LeaveBalanceCard), findsOneWidget);
      expect(find.text('Sick Leave'), findsNothing);
      expect(find.text('Vacation Leave'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('23.8'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show Sick Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Sick Leave'), findsOneWidget);
      expect(find.text('3.8'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one available balance has no switch or multi-card indicator', (
    tester,
  ) async {
    await mount(tester, balances());
    expect(find.byType(LeaveBalanceCard), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
    expect(find.text('1 of 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switcher preserves selection on refresh and recovers when a balance disappears',
    (tester) async {
      var current = const [
        _balance,
        LeaveBalance(
          userId: 'employee',
          leaveType: LeaveType.vacationLeave,
          earnedDays: 23.8,
        ),
      ];
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return EmployeeLeaveMobileBalancesPanel(
              balances: current,
              loading: false,
              error: null,
              onRetry: () {},
              onBalanceHistory: () {},
            );
          },
        ),
      );
      await tester.tap(find.byTooltip('Show Vacation Leave'));
      await tester.pumpAndSettle();
      update(
        () => current = const [
          _balance,
          LeaveBalance(
            userId: 'employee',
            leaveType: LeaveType.vacationLeave,
            earnedDays: 25,
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Vacation Leave'), findsOneWidget);
      expect(find.text('25'), findsNWidgets(2));
      update(() => current = const [_balance]);
      await tester.pumpAndSettle();
      expect(find.text('Sick Leave'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
      update(() => current = const []);
      await tester.pumpAndSettle();
      expect(find.byType(LeaveBalanceCard), findsNothing);
      expect(find.text('No leave credits available yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'summary has two wrapping tiles without repeating available credits',
    (tester) async {
      await mount(
        tester,
        const EmployeeLeaveMobileSummaryStrip(
          pendingCount: 0,
          totalPendingDays: 0,
          nextApproved: null,
          nextApprovedAvailable: true,
        ),
        size: const Size(320, 844),
        scale: 1.6,
      );
      expect(find.text('Available Credits'), findsNothing);
      expect(find.text('Pending Requests'), findsOneWidget);
      expect(find.text('Next Approved'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 844), const Size(740, 360)]) {
      testWidgets('mobile balances fit $size with large text in $brightness', (
        tester,
      ) async {
        await mount(
          tester,
          EmployeeLeaveMobileBalancesPanel(
            balances: const [
              _balance,
              LeaveBalance(
                userId: 'employee',
                leaveType: LeaveType.vacationLeave,
                earnedDays: 23.8,
                usedDays: 23.8,
              ),
            ],
            loading: false,
            error: null,
            onRetry: () {},
            onBalanceHistory: () {},
          ),
          size: size,
          scale: 1.6,
          brightness: brightness,
        );
        expect(find.text('3.8'), findsOneWidget);
        await tester.tap(find.byTooltip('Show Vacation Leave'));
        await tester.pumpAndSettle();
        expect(find.byType(LeaveBalanceCard), findsOneWidget);
        expect(find.text('Vacation Leave'), findsOneWidget);
        expect(find.text('2 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'mobile details put leave facts first and use plain label/value rows',
    (tester) async {
      await mount(
        tester,
        LeaveRequestInformation(request: _request),
        size: const Size(320, 844),
        scale: 1.6,
      );
      expect(find.text('Leave Type'), findsOneWidget);
      expect(find.text('Sick Leave'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Leave Details')).dy,
        lessThan(tester.getTopLeft(find.text('Employee Information')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final config in [
    (size: const Size(390, 844), scale: 1.0, keyboard: 0.0),
    (size: const Size(320, 844), scale: 1.6, keyboard: 0.0),
    (size: const Size(740, 390), scale: 1.0, keyboard: 0.0),
    (size: const Size(390, 844), scale: 1.0, keyboard: 260.0),
  ]) {
    testWidgets('details cover shell controls and restore the list: $config', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = config.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var previews = 0;
      var prints = 0;
      final innerNav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(config.scale),
              padding: const EdgeInsets.only(bottom: 24),
              viewInsets: EdgeInsets.only(bottom: config.keyboard),
            ),
            child: child!,
          ),
          home: Scaffold(
            bottomNavigationBar: const SizedBox(
              height: 80,
              child: Text('Dashboard navigation'),
            ),
            body: Stack(
              children: [
                Navigator(
                  key: innerNav,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => SingleChildScrollView(
                      child: EmployeeLeaveRequestsPanel(
                        requests: [_request],
                        loading: false,
                        error: null,
                        onRetry: () {},
                        totalRequests: 1,
                        hasMore: false,
                        loadingMore: false,
                        loadMoreError: null,
                        onLoadMore: () {},
                        onEdit: (_) {},
                        onCancel: (_) {},
                        onPrint: (_) => prints++,
                        onPreview: (_) => previews++,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () {},
                    label: const Text('File Leave'),
                  ),
                ),
                const Positioned(
                  right: 16,
                  bottom: 90,
                  child: Text('Chatbot launcher'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sick Leave'));
      await tester.tap(find.text('Sick Leave'));
      await tester.pumpAndSettle();
      expect(find.text('File Leave'), findsNothing);
      expect(find.text('Dashboard navigation'), findsNothing);
      expect(find.text('Chatbot launcher'), findsNothing);
      expect(innerNav.currentState!.canPop(), isFalse);
      expect(
        tester.getRect(find.byKey(const Key('employee-leave-details-panel'))),
        Rect.fromLTWH(0, 0, config.size.width, config.size.height),
      );
      final preview = find.widgetWithText(FilledButton, 'Preview Form');
      expect(preview, findsOneWidget);
      expect(tester.getSize(preview).height, greaterThanOrEqualTo(48));
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(preview).dy,
        lessThanOrEqualTo(config.size.height - config.keyboard - 24),
      );
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(previews, 1);
      expect(prints, 0);
      expect(find.text('File Leave'), findsOneWidget);
      expect(find.text('Dashboard navigation'), findsOneWidget);
      await tester.tap(find.text('Sick Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Print'));
      await tester.pumpAndSettle();
      expect(prints, 1);
      expect(previews, 1);
      await tester.tap(find.text('Sick Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('File Leave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('History still loads after closing the mobile details route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = LeaveProvider(repository: MockLeaveRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EmployeeLeaveRequestsPanel(
                requests: [_request],
                loading: false,
                error: null,
                onRetry: () {},
                totalRequests: 1,
                hasMore: false,
                loadingMore: false,
                loadMoreError: null,
                onLoadMore: () {},
                onEdit: (_) {},
                onCancel: (_) {},
                onPrint: (_) {},
                onPreview: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sick Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'History'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Request History'), findsOneWidget);
    expect(find.byKey(const Key('employee-leave-details-panel')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('mobile leave forms cover the nested shell and return results', (
    tester,
  ) async {
    String? result;
    await mount(
      tester,
      SizedBox(
        height: 600,
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await openResponsiveLeaveFormHost<String>(
                    context: context,
                    builder: (context) => Scaffold(
                      body: Center(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop('draft'),
                          child: const Text('Close mobile form'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    final form = find
        .ancestor(
          of: find.text('Close mobile form'),
          matching: find.byType(Scaffold),
        )
        .first;
    expect(tester.getSize(form), const Size(390, 844));
    await tester.tap(find.text('Close mobile form'));
    await tester.pumpAndSettle();
    expect(result, 'draft');
    expect(find.text('Open form'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leave form launcher is hidden on mobile and retained on desktop',
    (tester) async {
      for (final width in [390.0, 1280.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          const MaterialApp(
            home: EmployeeHrmsAssistantOverlay(
              hideLauncherOnMobile: true,
              child: Scaffold(body: Text('Leave form')),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byType(DraggableDtrAssistantLauncher),
          width < 900 ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      expect(tester.takeException(), isNull);
    },
  );
}
