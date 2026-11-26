import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/widgets/workforce_setup_navigation.dart';
import 'package:hrms_plaridel/features/dtr/dtr_routes.dart';

const _labels = [
  'Assignments',
  'Departments',
  'Positions',
  'Shifts',
  'Weekly Schedule',
  'Holidays',
  'Attendance Policies',
];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required DtrPage selected,
  required ValueChanged<DtrPage> onSelected,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WorkforceSetupNavigation(
              selected: selected,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [600.0, 720.0, 1040.0, 1400.0]) {
    testWidgets('tabs stay on one row and are all reachable at width $width', (
      tester,
    ) async {
      DtrPage? selected;
      await _pump(
        tester,
        width: width,
        selected: DtrPage.assignments,
        onSelected: (v) => selected = v,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButtonFormField<DtrPage>), findsNothing);

      final rowY = tester.getTopLeft(find.text('Assignments')).dy;
      for (final page in DtrPage.workforcePages) {
        final label = find.text(page.title);
        expect(tester.getTopLeft(label).dy, rowY, reason: page.title);
        // Center the tab, as the widget does for the selected tab, so the
        // floating scroll arrows never cover it.
        Scrollable.ensureVisible(tester.element(label), alignment: 0.5);
        await tester.pumpAndSettle();
        final rect = tester.getRect(label);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        await tester.tap(label);
        expect(selected, page, reason: 'tapping ${page.title}');
      }
    });
  }

  testWidgets('the selected tab is scrolled into view', (tester) async {
    await _pump(
      tester,
      width: 600,
      selected: DtrPage.attendancePolicies,
      onSelected: (_) {},
    );
    final rect = tester.getRect(find.text('Attendance Policies'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(600));
  });

  testWidgets('the selected tab is marked selected', (tester) async {
    await _pump(
      tester,
      width: 1400,
      selected: DtrPage.shifts,
      onSelected: (_) {},
    );
    expect(
      tester.getSemantics(find.text('Shifts')),
      isSemantics(isSelected: true, isButton: true),
    );
    expect(
      tester.getSemantics(find.text('Holidays')),
      isSemantics(isSelected: false, isButton: true),
    );
  });

  testWidgets('mobile width shows a labelled dropdown instead of tabs', (
    tester,
  ) async {
    DtrPage? selected;
    await _pump(
      tester,
      width: 360,
      selected: DtrPage.shifts,
      onSelected: (v) => selected = v,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<DtrPage>), findsOneWidget);
    expect(find.text('Section'), findsOneWidget);
    expect(find.text('Shifts'), findsWidgets);
    expect(find.byIcon(Icons.policy_rounded), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<DtrPage>));
    await tester.pumpAndSettle();
    for (final label in _labels) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.text('Holidays').last);
    await tester.pumpAndSettle();
    expect(selected, DtrPage.holidays);
  });
}
