import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

Future<void> createDesignerField(
  WidgetTester tester,
  String label, {
  LeaveCustomFieldType type = LeaveCustomFieldType.date,
}) async {
  await tester.tap(find.byTooltip('Insert field'));
  await tester.pumpAndSettle();
  expect(find.text('Create new field'), findsOneWidget);
  await tester.ensureVisible(find.text('Create new field'));
  await tester.tap(find.text('Create new field'));
  await tester.pumpAndSettle();
  final dialog = find.byType(AlertDialog);
  final labelInput = find.descendant(
    of: dialog,
    matching: find.ancestor(
      of: find.text('Field label'),
      matching: find.byType(TextFormField),
    ),
  );
  await tester.enterText(labelInput, label);
  final dropdown = find.descendant(
    of: dialog,
    matching: find.byType(DropdownButtonFormField<LeaveCustomFieldType>),
  );
  tester
      .widget<DropdownButtonFormField<LeaveCustomFieldType>>(dropdown)
      .onChanged!(type);
  await tester.pumpAndSettle();
  if (type == LeaveCustomFieldType.select) {
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.ancestor(
          of: find.text('Options (one per line)'),
          matching: find.byType(TextFormField),
        ),
      ),
      'Local\nOverseas',
    );
  }
  await tester.tap(
    find.descendant(of: dialog, matching: find.text('Required')),
  );
  await tester.tap(
    find.descendant(of: dialog, matching: find.text('Create field')),
  );
  await tester.pumpAndSettle();
}
