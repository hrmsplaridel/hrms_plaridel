import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/linked_source_document.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_linked_source_document_screen.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_source_status_text.dart';

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
      title: 'Records management training',
      status: 'submitted',
      fields: const [
        DocuTrackerLinkedSourceField(label: 'Employee', value: 'Maria Santos'),
      ],
      attachments: const [],
      printData: const {
        'id': 'record-1',
        'employee_name': 'Maria Santos',
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

  test(
    'L&D statuses use module wording; recruitment has no DocuTracker view',
    () {
      final ld = docuTrackerLinkedSourceStatusText(
        sourceModule: 'ld',
        status: 'needs_revision',
      );
      expect(ld.label, 'Needs revision');
      expect(ld.description, 'L&D asked the employee to revise this report.');

      final rsp = docuTrackerLinkedSourceStatusText(
        sourceModule: 'rsp',
        status: 'registered',
      );
      expect(rsp.description, 'Status is managed by the source module.');
    },
  );

  test('L&D "seen" reads as a finished review', () {
    final seen = docuTrackerLinkedSourceStatusText(
      sourceModule: 'ld',
      status: 'seen',
    );
    expect(seen.label, 'Reviewed');
    expect(seen.description, contains('No further action is needed'));
  });

  test('only reviewed L&D reports are kept out of approval counts', () {
    const ldRow = DocuTrackerDocument(
      documentType: 'ld',
      title: 'Daily report',
      status: DocumentStatus.approved,
      sourceModule: 'ld',
      sourceStatus: 'seen',
      sourceOnly: true,
    );
    expect(docuTrackerIsReviewedSourceCompletion(ldRow), isTrue);
    expect(
      docuTrackerIsReviewedSourceCompletion(
        ldRow.copyWith(sourceStatus: 'reviewed'),
      ),
      isTrue,
    );
    expect(
      docuTrackerIsReviewedSourceCompletion(
        ldRow.copyWith(sourceStatus: 'approved'),
      ),
      isFalse,
    );
    expect(
      docuTrackerIsReviewedSourceCompletion(
        ldRow.copyWith(sourceModule: 'rsp', sourceStatus: 'registered'),
      ),
      isFalse,
    );
    expect(
      docuTrackerIsReviewedSourceCompletion(
        const DocuTrackerDocument(
          documentType: 'memo',
          title: 'Memo',
          status: DocumentStatus.approved,
        ),
      ),
      isFalse,
    );
  });

  test('source badge label uses L&D wording only for L&D source rows', () {
    const ldRow = DocuTrackerDocument(
      documentType: 'ld',
      title: 'Daily report',
      sourceModule: 'ld',
      sourceStatus: 'seen',
      sourceOnly: true,
    );
    expect(docuTrackerSourceBadgeLabel(ldRow), 'Reviewed');
    expect(
      docuTrackerSourceBadgeLabel(ldRow.copyWith(sourceStatus: 'submitted')),
      'Submitted',
    );
    expect(
      docuTrackerSourceBadgeLabel(
        ldRow.copyWith(sourceModule: 'rsp', sourceStatus: 'registered'),
      ),
      isNull,
    );
    expect(
      docuTrackerSourceBadgeLabel(ldRow.copyWith(sourceOnly: false)),
      isNull,
    );
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('L&D linked document fits at $width', (tester) async {
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
                id: 'source:ld:record-1',
                documentType: 'ld',
                title: 'Records management training',
                sourceModule: 'ld',
                sourceTable: 'training_daily_reports',
                sourceRecordId: 'record-1',
                sourceOnly: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LEARNING AND DEVELOPMENT'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Status: Submitted'), findsOneWidget);
      expect(
        find.text('The report was submitted and is waiting for L&D review.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('docutracker-print-source-document')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
