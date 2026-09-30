import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/shared/widgets/locator_signature_section.dart';

class _Signatures extends DocuTrackerProvider {
  _Signatures(this.isPrimary);
  final bool isPrimary;

  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async {
    expect(sourceModule, 'dtr');
    expect(sourceTable, 'locator_slips');
    expect(sourceRecordId, 'locator-1');
    return DocuTrackerSourceSignatureBundle(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
      sourceStatus: 'pending_department_head',
      signatures: [
        for (final slot in ['applicant', 'department_head', 'hr_approver'])
          DocuTrackerSourceSignature(
            slotKey: slot,
            label: slot,
            assignedSignerId: slot,
            assignedSignerName: slot == 'department_head'
                ? 'Official Head'
                : slot,
            assignmentSource: 'automatic',
            canAssign: false,
            canSign: slot == 'department_head' && isPrimary,
          ),
      ],
    );
  }
}

void main() {
  for (final primary in [true, false]) {
    testWidgets('locator signatures use official names, primary=$primary', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<DocuTrackerProvider>(
          create: (_) => _Signatures(primary),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LocatorSignatureSection(requestId: 'locator-1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Automatically assigned to Official Head'),
        findsOneWidget,
      );
      expect(
        find.text('Add Signature'),
        primary ? findsOneWidget : findsNothing,
      );
      expect(find.text('Change signer'), findsNothing);
      expect(find.text('Noted / Final Approver'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
