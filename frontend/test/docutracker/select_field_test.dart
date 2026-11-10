import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_select_field.dart';

void main() {
  testWidgets('select menu marks the choice and filters a long list', (
    tester,
  ) async {
    var selected = 'memo';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return DocuTrackerSelectField<String>(
                label: 'Document scope',
                value: selected,
                searchable: true,
                searchHint: 'Search types',
                options: const [
                  DocuTrackerSelectOption(
                    value: '*',
                    label: 'All document types',
                    subtitle: 'Used when a type has no setting of its own',
                  ),
                  DocuTrackerSelectOption(
                    value: 'memo',
                    label: 'Memo',
                    subtitle: 'Only this document type',
                  ),
                  DocuTrackerSelectOption(
                    value: 'purchaseRequest',
                    label: 'Purchase Request',
                    fieldLabel: 'Purchase Request',
                    subtitle: 'Accounting',
                  ),
                ],
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Memo'), findsOneWidget);
    await tester.tap(find.text('Memo'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase Request'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-select-search')),
      'account',
    );
    await tester.pump();
    expect(find.text('All document types'), findsNothing);
    expect(find.text('Purchase Request'), findsOneWidget);

    await tester.tap(find.text('Purchase Request'));
    await tester.pumpAndSettle();
    expect(selected, 'purchaseRequest');
    expect(find.text('Accounting'), findsNothing);
  });
}
