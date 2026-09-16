import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/linked_source_document.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_linked_source_document_screen.dart';

class _LinkedSourceProvider extends DocuTrackerProvider {
  @override
  Future<DocuTrackerLinkedSourceDocument> loadLinkedSourceDocument({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async {
    return DocuTrackerLinkedSourceDocument(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
      title: 'Administrative Aide',
      status: 'submitted',
      fields: const [
        DocuTrackerLinkedSourceField(
          label: 'Applicant',
          value: 'Juan Dela Cruz',
        ),
        DocuTrackerLinkedSourceField(
          label: 'Position applied for',
          value: 'Administrative Aide',
        ),
      ],
      attachments: const [],
      printData: const {
        'id': 'record-1',
        'full_name': 'Juan Dela Cruz',
        'email': 'juan@example.test',
        'status': 'submitted',
      },
    );
  }
}

void main() {
  test('linked source model ignores empty and invalid presentation rows', () {
    final source = DocuTrackerLinkedSourceDocument.fromJson({
      'source_module': 'ld',
      'source_table': 'training_daily_reports',
      'source_record_id': 'report-1',
      'title': 'Training report',
      'status': 'seen',
      'fields': [
        {'label': 'Employee', 'value': 'Maria Santos'},
        {'label': '', 'value': 'Hidden'},
      ],
      'attachments': [
        {'label': 'Proof', 'name': 'proof.pdf', 'url': '/proof'},
        {'label': 'Missing', 'name': 'missing.pdf', 'url': ''},
      ],
    });

    expect(source.fields, hasLength(1));
    expect(source.attachments, hasLength(1));
    expect(source.attachments.single.name, 'proof.pdf');
    expect(source.printData, isEmpty);
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('RSP linked document fits at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider<DocuTrackerProvider>.value(
          value: _LinkedSourceProvider(),
          child: const MaterialApp(
            home: DocuTrackerLinkedSourceDocumentScreen(
              document: DocuTrackerDocument(
                id: 'source:rsp:record-1',
                documentType: 'rsp',
                title: 'Administrative Aide',
                sourceModule: 'rsp',
                sourceTable: 'recruitment_applications',
                sourceRecordId: 'record-1',
                sourceOnly: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RECRUITMENT, SELECTION AND PLACEMENT'), findsOneWidget);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-print-source-document')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
