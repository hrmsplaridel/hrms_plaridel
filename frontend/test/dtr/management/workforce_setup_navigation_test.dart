import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/widgets/workforce_setup_navigation.dart';

void main() {
  for (final width in [600.0, 720.0, 1040.0, 1400.0]) {
    testWidgets(
      'all workforce tabs stay visible and selectable at width $width',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        int? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: WorkforceSetupNavigation(
                    selectedIndex: 4,
                    onSelected: (v) => selected = v,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final label in [
          'Assignments',
          'Departments',
          'Positions',
          'Shifts',
          'Weekly Schedule',
          'Holidays',
          'Attendance Policies',
        ]) {
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          await tester.tap(find.text(label));
        }
        expect(selected, 10);
        if (width < 1100) {
          expect(
            tester.getTopLeft(find.text('Attendance Policies')).dy,
            greaterThan(tester.getTopLeft(find.text('Assignments')).dy),
          );
        }
      },
    );
  }
}
