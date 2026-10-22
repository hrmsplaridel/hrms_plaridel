import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/shared/widgets/locator_custom_fields.dart';

void main() {
  test('locator type keeps additional field definitions through JSON', () {
    final type = LocatorRequestType.fromJson({
      'code': 'visit',
      'employee_detail_schema': [
        {
          'key': 'contact',
          'label': 'Contact person',
          'type': 'text',
          'required': true,
        },
      ],
    });
    expect(type.employeeDetailSchema.single.label, 'Contact person');
    expect(type.toJson()['employee_detail_schema'], isNotEmpty);
  });
  testWidgets(
    'required field validates, dropdown stores only a valid option, and details preserve false',
    (t) async {
      final key = GlobalKey<FormState>();
      final values = <String, dynamic>{};
      const fields = [
        LeaveCustomFieldDefinition(
          key: 'contact',
          label: 'Contact person',
          required: true,
        ),
        LeaveCustomFieldDefinition(
          key: 'vehicle',
          label: 'Vehicle',
          type: LeaveCustomFieldType.select,
          options: ['Car', 'Bus'],
        ),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: key,
              child: LocatorCustomFieldInputs(fields: fields, values: values),
            ),
          ),
        ),
      );
      expect(key.currentState!.validate(), false);
      await t.pump();
      expect(find.text('Contact person is required.'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'Alice');
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Bus').last);
      await t.pumpAndSettle();
      expect(key.currentState!.validate(), true);
      expect(values, {'contact': 'Alice', 'vehicle': 'Bus'});
      expect(
        locatorAdditionalFieldLines(
          [
            const LeaveCustomFieldDefinition(
              key: 'answer',
              label: 'Transport provided',
              type: LeaveCustomFieldType.boolean,
            ),
          ],
          {'answer': false},
        ),
        ['Transport provided: No'],
      );
    },
  );
  testWidgets('field editor adds required dropdown choices', (t) async {
    var fields = <LeaveCustomFieldDefinition>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: LocatorCustomFieldEditor(
                fields: fields,
                onChanged: (next) => setState(() => fields = next),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Add field'));
    await t.pump();
    expect(fields.length, 1);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Field label'),
      'Transport',
    );
    await t.tap(find.byType(DropdownButtonFormField<LeaveCustomFieldType>));
    await t.pumpAndSettle();
    await t.tap(find.text('Select').last);
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Options (one per line)'),
      'Car\nBus',
    );
    expect(fields.single.label, 'Transport');
    expect(fields.single.options, ['Car', 'Bus']);
    await t.ensureVisible(find.widgetWithText(TextFormField, 'Field instruction'));
    await t.enterText(find.widgetWithText(TextFormField, 'Field instruction'), 'Select your actual transport.');
    await t.pump();
    await t.ensureVisible(find.widgetWithText(TextFormField, 'Example input'));
    await t.enterText(find.widgetWithText(TextFormField, 'Example input'), 'Bus (example only).');
    await t.pump();
    final saved = fields.single.toJson();
    expect(saved['instruction'], 'Select your actual transport.');
    expect(saved['example'], 'Bus (example only).');
    expect(saved['options'], ['Car', 'Bus']);
  });
}
