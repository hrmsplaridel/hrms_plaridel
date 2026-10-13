import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_print_settings.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  testWidgets('new leave type can design, apply and retain a custom layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    LeavePrintDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LeavePrintSettings(onChanged: (v) => draft = v)),
      ),
    );
    await tester.tap(find.text('Design layout'));
    await tester.pumpAndSettle();
    expect(find.byType(LocatorPrintLayoutEditor), findsOneWidget);
    expect(find.text('Working days applied'), findsWidgets);
    await tester.tap(find.byTooltip('Insert field'));
    await tester.pumpAndSettle();
    expect(find.text('Certification signature'), findsWidgets);
    await tester.ensureVisible(find.text('Certification signature').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Certification signature').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use layout'));
    await tester.pumpAndSettle();
    expect(draft!.layout, 'custom');
    expect(draft!.hasChanges, isTrue);
    expect(find.text('Edit layout'), findsOneWidget);
  });
}
