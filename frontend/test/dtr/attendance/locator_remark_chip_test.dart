import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';

void main() {
  test('only locator detail is compacted', () {
    expect(
      compactLocatorRemark('On Field (AM IN, AM OUT, PM IN, PM OUT)'),
      'On Field',
    );
    expect(compactLocatorRemark('Late + Undertime'), 'Late + Undertime');
    expect(
      compactLocatorRemark('No Electricity (AM IN, AM OUT, PM IN, PM OUT)'),
      'No Electricity',
    );
    expect(
      compactLocatorRemark('Custom Locator (PM IN, PM OUT)'),
      'Custom Locator',
    );
    expect(
      compactLocatorRemark('Medical Leave (Paid)'),
      'Medical Leave (Paid)',
    );
    expect(
      compactLocatorRemark('Field Work (AM IN, office visit)'),
      'Field Work (AM IN, office visit)',
    );
  });

  testWidgets('locator chip retains the covered slots in a tooltip', (
    tester,
  ) async {
    const remark = 'On Field (AM IN, AM OUT, PM IN, PM OUT)';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AttendanceRemarksChip(remark: remark)),
      ),
    );

    expect(find.text('On Field'), findsOneWidget);
    expect(find.text(remark), findsNothing);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, remark);
  });
}
