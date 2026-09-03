import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_fields_panel.dart';

void main() {
  const unsignedField = DocuTrackerSignatureField(
    id: 'unsigned-field',
    pageNumber: 2,
    x: 0.2,
    y: 0.4,
    width: 0.3,
    height: 0.12,
    assignedSignerId: 'employee-1',
    assignedSignerName: 'Juan Dela Cruz',
    label: 'Prepared by',
    canSign: true,
  );
  final signedField = DocuTrackerSignatureField(
    id: 'signed-field',
    pageNumber: 1,
    x: 0.5,
    y: 0.7,
    width: 0.3,
    height: 0.12,
    assignedSignerId: 'employee-1',
    assignedSignerName: 'Juan Dela Cruz',
    label: 'Approved by',
    canSign: true,
    signatureAssetId: 'signature-1',
    signedBy: 'employee-1',
    signerName: 'Juan Dela Cruz',
    signedAt: DateTime.utc(2026, 9, 3, 8),
    lockedAt: DateTime.utc(2026, 9, 3, 8),
  );

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<DocuTrackerSignatureField> fields,
    bool isBusy = false,
    ValueChanged<DocuTrackerSignatureField>? onSelect,
    ValueChanged<DocuTrackerSignatureField>? onSign,
    ValueChanged<DocuTrackerSignatureField>? onDelete,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 336,
              height: 640,
              child: DocuTrackerSignatureFieldsPanel(
                fields: fields,
                activePage: 2,
                selectedFieldId: 'unsigned-field',
                canEditLayout: true,
                isBusy: isBusy,
                onSelect: onSelect ?? (_) {},
                onSign: onSign ?? (_) {},
                onDelete: onDelete ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lists signature status and exposes permitted actions', (
    tester,
  ) async {
    String? selectedId;
    String? signedId;
    String? deletedId;
    await pumpPanel(
      tester,
      fields: [unsignedField, signedField],
      onSelect: (field) => selectedId = field.id,
      onSign: (field) => signedId = field.id,
      onDelete: (field) => deletedId = field.id,
    );

    expect(find.text('1 of 2 signed'), findsOneWidget);
    expect(find.text('Signed'), findsOneWidget);
    expect(find.text('Unsigned'), findsOneWidget);
    expect(find.text('Page 2 - Current page'), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-unsigned-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-signed-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-unsigned-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-signed-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('go-to-unsigned-field')));
    expect(selectedId, 'unsigned-field');
    await tester.tap(find.byKey(const ValueKey('sign-signed-field')));
    expect(signedId, 'signed-field');
    await tester.tap(find.byKey(const ValueKey('delete-unsigned-field')));
    expect(deletedId, 'unsigned-field');
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy panel blocks sign and delete actions', (tester) async {
    await pumpPanel(tester, fields: [unsignedField, signedField], isBusy: true);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-unsigned-field')), findsNothing);
    expect(find.byKey(const ValueKey('sign-signed-field')), findsNothing);
    expect(find.byKey(const ValueKey('delete-unsigned-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty state when there are no fields', (tester) async {
    await pumpPanel(tester, fields: const []);

    expect(find.text('No signature fields yet'), findsOneWidget);
    expect(
      find.text(
        'Add a signature field to assign a signer and place it on a page.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
