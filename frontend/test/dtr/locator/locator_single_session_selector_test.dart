import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_form_widgets.dart';

void main() {
  for (final single in [true, false]) {
    testWidgets('locator selector uses single-session=$single', (tester) async {
      var starts = 0, ends = 0, middle = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: EmployeeLocatorMobileSegmentSelector(
                singleSession: single,
                amIn: false,
                amOut: false,
                pmIn: false,
                pmOut: false,
                locked: false,
                onAmIn: () => starts++,
                onAmOut: () => middle++,
                onPmIn: () => middle++,
                onPmOut: () => ends++,
              ),
            ),
          ),
        ),
      );
      if (single) {
        expect(find.text('AM OUT'), findsNothing);
        expect(find.text('PM IN'), findsNothing);
      }
      await tester.tap(find.text(single ? 'IN' : 'AM IN'));
      await tester.tap(find.text(single ? 'OUT' : 'PM OUT'));
      expect(starts, 1);
      expect(ends, 1);
      expect(middle, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
