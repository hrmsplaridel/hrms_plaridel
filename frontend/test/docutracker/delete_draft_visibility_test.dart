import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

DocuTrackerDocument _doc({
  String? id = 'doc-1',
  String? createdBy = 'me',
  DocumentStatus status = DocumentStatus.pending,
  String? holder,
  int? step,
  DateTime? sentTime,
  bool sourceOnly = false,
}) => DocuTrackerDocument(
  id: id,
  documentType: 'memo',
  title: 'Draft memo',
  createdBy: createdBy,
  status: status,
  currentHolderId: holder,
  currentStep: step,
  sentTime: sentTime,
  sourceOnly: sourceOnly,
);

void main() {
  test('the creator can delete an unsubmitted draft', () {
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(_doc(), userId: 'me'),
      isTrue,
    );
  });

  test('a submitted or someone else\'s document cannot be deleted', () {
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(_doc(), userId: 'other'),
      isFalse,
    );
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(
        _doc(step: 1, holder: 'reviewer'),
        userId: 'me',
      ),
      isFalse,
    );
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(
        _doc(sentTime: DateTime.utc(2026, 11, 3)),
        userId: 'me',
      ),
      isFalse,
    );
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(
        _doc(status: DocumentStatus.approved),
        userId: 'me',
      ),
      isFalse,
    );
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(
        _doc(sourceOnly: true),
        userId: 'me',
        isAdmin: true,
      ),
      isFalse,
    );
  });

  test('an admin can delete another person\'s unsubmitted draft', () {
    expect(
      DocuTrackerDocumentVisibility.canDeleteDraft(
        _doc(createdBy: 'someone'),
        userId: 'admin',
        isAdmin: true,
      ),
      isTrue,
    );
  });
}
