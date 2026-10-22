import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_content_lock_banner.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_content_lock.dart';

DocuTrackerDocument _document({
  DocumentStatus status = DocumentStatus.pending,
  int? currentStep,
  String? currentHolderId,
  DateTime? sentTime,
  DateTime? releasedAt,
  bool releaseRequired = false,
  String? sourceModule,
  bool sourceOnly = false,
}) {
  return DocuTrackerDocument(
    id: 'doc-1',
    documentType: 'memo',
    title: 'Memo',
    status: status,
    currentStep: currentStep,
    currentHolderId: currentHolderId,
    sentTime: sentTime,
    releasedAt: releasedAt,
    releaseRequired: releaseRequired,
    sourceModule: sourceModule,
    sourceOnly: sourceOnly,
  );
}

void main() {
  test('draft content stays editable and later stages lock', () {
    expect(docuTrackerNativeContentIsLocked(_document()), isFalse);
    expect(docuTrackerNativeContentLockMessage(_document()), isNull);

    final locked = [
      _document(status: DocumentStatus.inReview, currentStep: 1, currentHolderId: 'holder'),
      _document(status: DocumentStatus.overdue, currentStep: 1, currentHolderId: 'holder'),
      _document(
        status: DocumentStatus.approved,
        currentStep: 2,
        releaseRequired: true,
      ),
      _document(status: DocumentStatus.returned, currentStep: 1),
      _document(status: DocumentStatus.rejected),
      _document(status: DocumentStatus.cancelled),
      _document(status: DocumentStatus.escalated, currentStep: 1),
    ];
    for (final document in locked) {
      expect(docuTrackerNativeContentIsLocked(document), isTrue, reason: document.status.name);
      expect(
        docuTrackerNativeContentLockMessage(document),
        'This document is no longer a draft, so its content is read-only.',
      );
    }

    final released = _document(
      status: DocumentStatus.approved,
      releaseRequired: true,
      releasedAt: DateTime.utc(2026, 10, 19),
    );
    expect(
      docuTrackerNativeContentLockMessage(released),
      'This released document is finalized and read-only.',
    );
    expect(
      docuTrackerNativeContentIsLocked(_document(sourceModule: 'rsp', status: DocumentStatus.inReview)),
      isFalse,
    );
    expect(docuTrackerNativeContentIsLocked(_document(sourceOnly: true)), isFalse);
  });

  testWidgets('content lock banner names a released document as finalized', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocuTrackerContentLockBanner(
            message: 'This released document is finalized and read-only.',
          ),
        ),
      ),
    );

    expect(find.text('Finalized — read only'), findsOneWidget);
    expect(find.text('This released document is finalized and read-only.'), findsOneWidget);
  });

  testWidgets('content lock banner explains a document that left draft', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocuTrackerContentLockBanner(
            message: 'This document is no longer a draft, so its content is read-only.',
          ),
        ),
      ),
    );

    expect(find.text('Read only'), findsOneWidget);
    expect(
      find.text('This document is no longer a draft, so its content is read-only.'),
      findsOneWidget,
    );
  });
}
