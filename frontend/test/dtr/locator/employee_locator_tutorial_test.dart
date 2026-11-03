import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/tutorial/employee_locator_tutorial.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/tutorial/employee_tutorial_controller.dart';

void main() {
  test(
    'employees without review access have no approval-only tutorial steps',
    () {
      final targets = EmployeeLocatorTutorial.targets(
        isDepartmentHead: false,
        headerKey: GlobalKey(),
        requestsKey: GlobalKey(),
        tabsKey: GlobalKey(),
        approvalFiltersKey: GlobalKey(),
      );
      expect(targets.length, 2);
      expect(
        targets.any((target) => target.title.contains('Approvals')),
        isFalse,
      );
    },
  );

  for (final width in [390.0, 1500.0]) {
    testWidgets(
      'locator tour opens the right tab before highlighting at $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'employee_tutorial_v2:reviewer:locator': true,
        });
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final header = GlobalKey();
        final tabs = GlobalKey();
        final requests = GlobalKey();
        final filters = GlobalKey();
        var approvals = true;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, update) => Scaffold(
                body: Column(
                  children: [
                    SizedBox(
                      key: header,
                      height: 80,
                      child: const Text('Locator header'),
                    ),
                    SizedBox(
                      key: tabs,
                      height: 50,
                      child: const Text('Locator tabs'),
                    ),
                    if (approvals)
                      SizedBox(
                        key: filters,
                        height: 70,
                        child: const Text('Approval filters'),
                      ),
                    SizedBox(
                      key: requests,
                      height: 100,
                      child: Text(
                        approvals ? 'Approval rows' : 'My request rows',
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        EmployeeTutorialController.showCoachIfNeeded(
                          context,
                          userId: 'reviewer',
                          section: EmployeeTutorialSection.locator,
                          targets: EmployeeLocatorTutorial.targets(
                            isDepartmentHead: true,
                            headerKey: header,
                            requestsKey: requests,
                            tabsKey: tabs,
                            approvalFiltersKey: filters,
                            showMyRequests: () =>
                                update(() => approvals = false),
                            showApprovals: () => update(() => approvals = true),
                          ),
                        ),
                      ),
                      child: const Text('Start tour'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        Future<void> settleStep() async {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 150));
          }
        }

        await tester.tap(find.text('Start tour'));
        await settleStep();
        expect(EmployeeTutorialController.coachActive.value, isTrue);
        await tester.tap(find.text('Next'));
        await settleStep();
        expect(
          find.text('My Requests and Approvals / History'),
          findsOneWidget,
        );
        await tester.tap(find.text('Next'));
        await settleStep();
        expect(approvals, isFalse);
        expect(find.text('Find and track your requests'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await settleStep();
        expect(approvals, isTrue);
        expect(filters.currentContext, isNotNull);
        expect(find.text('Filter Approvals / History'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await settleStep();
        expect(find.text('Review a request and its history'), findsOneWidget);
        await tester.tap(find.text('Finish'));
        await settleStep();
        expect(EmployeeTutorialController.coachActive.value, isFalse);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'employee_tutorial_v3:reviewer:locator',
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
