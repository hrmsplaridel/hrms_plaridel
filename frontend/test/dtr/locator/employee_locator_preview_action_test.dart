import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';

void main() {
  testWidgets('approved locator offers preview separately from print', (
    tester,
  ) async {
    var previews = 0;
    var prints = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmployeeLocatorMobileDetailActions(
            canCancel: false,
            canPrint: true,
            canOpenAttachment: false,
            onHistory: () {},
            onCancel: () {},
            onPreview: () => previews++,
            onPrint: () => prints++,
            onOpenAttachment: () {},
          ),
        ),
      ),
    );

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    expect(previews, 1);
    expect(prints, 0);
  });
}
