import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';
import 'package:provider/provider.dart';

class _SourceSignatureProvider extends DocuTrackerProvider {
  _SourceSignatureProvider(this.bundle);

  final DocuTrackerSourceSignatureBundle bundle;

  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async => bundle;
}

DocuTrackerSourceSignatureBundle _bundle({
  required bool canAssign,
  required String assignedSignerId,
  required bool canSign,
  bool? fieldCanAssign,
  String assignmentSource = 'manual',
  String? assignedSignerName,
}) {
  return DocuTrackerSourceSignatureBundle(
    sourceModule: 'ld',
    sourceTable: 'idp_entries',
    sourceRecordId: 'idp-1',
    sourceStatus: 'active',
    canAssign: canAssign,
    signatures: [
      DocuTrackerSourceSignature(
        slotKey: 'prepared_by',
        label: 'Prepared by',
        assignedSignerId: assignedSignerId,
        assignedSignerName: assignedSignerName,
        canAssign: fieldCanAssign,
        assignmentSource: assignmentSource,
        canSign: canSign,
      ),
    ],
  );
}

Widget _subject(DocuTrackerSourceSignatureBundle bundle) {
  return ChangeNotifierProvider<DocuTrackerProvider>.value(
    value: _SourceSignatureProvider(bundle),
    child: const MaterialApp(
      home: Scaffold(
        body: DocuTrackerSourceSignatureCard(
          sourceModule: 'ld',
          sourceTable: 'idp_entries',
          sourceRecordId: 'idp-1',
          slotKey: 'prepared_by',
          title: 'Prepared by signature',
          unsignedMessage: 'Your signature is required',
          waitingMessage: 'Only the assigned account can sign.',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('admin sees assignment guidance for an unassigned field', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(_bundle(canAssign: true, assignedSignerId: '', canSign: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No signer assigned yet'), findsOneWidget);
    expect(
      find.text('Assign an account before this field can be signed.'),
      findsOneWidget,
    );
    expect(find.text('Your signature is required'), findsNothing);
    expect(find.text('Assign signer'), findsOneWidget);
  });

  testWidgets('assigned signer still sees the signing prompt', (tester) async {
    await tester.pumpWidget(
      _subject(
        _bundle(
          canAssign: false,
          assignedSignerId: 'employee-1',
          canSign: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your signature is required'), findsOneWidget);
    expect(find.text('Add Signature'), findsOneWidget);
    expect(find.text('No signer assigned yet'), findsNothing);
  });

  testWidgets(
    'creator-owned Prepared by shows the creator and no assignment button',
    (tester) async {
      await tester.pumpWidget(
        _subject(
          _bundle(
            canAssign: true,
            fieldCanAssign: false,
            assignmentSource: 'creator',
            assignedSignerId: 'employee-1',
            assignedSignerName: 'Maria Santos',
            canSign: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prepared by Maria Santos'), findsOneWidget);
      expect(
        find.text('This field belongs to the person who created the form.'),
        findsOneWidget,
      );
      expect(find.text('Change signer'), findsNothing);
      expect(find.text('Add Signature'), findsOneWidget);
    },
  );

  testWidgets('automatic assignment shows recovery-capable change control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        _bundle(
          canAssign: true,
          assignedSignerId: 'head-1',
          assignedSignerName: 'Department Head',
          canSign: false,
          fieldCanAssign: true,
          assignmentSource: 'automatic',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Automatically assigned to Department Head'),
      findsOneWidget,
    );
    expect(find.text('Change signer'), findsOneWidget);
  });
}
