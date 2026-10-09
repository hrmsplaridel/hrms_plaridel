import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employment_type_field.dart';

void main() {
  testWidgets(
    'employment type dropdown has seven named options and separate COS',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmploymentTypeField(
              value: null,
              decoration: const InputDecoration(labelText: 'Employment Type'),
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      for (final label in [
        'Permanent',
        'Temporary',
        'Casual',
        'Contractual appointment',
        'Coterminous',
        'Job Order (JO)',
        'Contract of Service (COS)',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Regular (legacy)'), findsNothing);
      await tester.tap(find.text('Contract of Service (COS)').last);
      await tester.pumpAndSettle();
      expect(selected, 'contract_of_service');
    },
  );
  testWidgets(
    'editing preserves legacy Regular without mapping it to Permanent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmploymentTypeField(
              value: 'regular',
              decoration: const InputDecoration(),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Regular (legacy)'), findsOneWidget);
    },
  );
}
