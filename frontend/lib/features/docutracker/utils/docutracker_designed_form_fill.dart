import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_designed_print.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_print_layout.dart';

/// Whether this document should try the admin Printed Form fill surface.
///
/// Opens fill mode when a published printed-form layout exists (including
/// Memorandum / Purchase Request overrides). Source-linked rows stay on their
/// source screens. Navigation still falls back to the official/editor page
/// when no custom layout is saved.
bool docuTrackerShouldAttemptDesignedFormFill(DocuTrackerDocument document) {
  if (document.sourceOnly) return false;
  final id = document.id?.trim() ?? '';
  return id.isNotEmpty;
}

/// Field sources employees may type into. Others stay read-only on the form.
const docuTrackerFillWritableSources = <String>{
  'title',
  'subject',
  'description',
  'body',
  'to',
  'date',
  'cc',
};

bool docuTrackerFillSourceIsWritable(String source) =>
    docuTrackerFillWritableSources.contains(source.trim());

/// Maps a layout field source to the document column that stores its value.
///
/// Memo-specific sources (`to` / `cc` / `date`) live in builder memo metadata
/// and return null here — the fill screen persists them via the builder.
String? docuTrackerFillStorageKey(String source) {
  switch (source.trim()) {
    case 'title':
      return 'title';
    case 'subject':
      return 'title';
    case 'description':
    case 'body':
      return 'description';
    default:
      return null;
  }
}

bool docuTrackerDocumentIsMemo(DocuTrackerDocument document) =>
    DocumentType.fromValue(document.documentType) == DocumentType.memo;

/// Values shown in fill mode / designed print, from the live document.
Map<String, String> docuTrackerFillValuesFromDocument(
  DocuTrackerDocument document, {
  DocuTrackerMemoTemplate? memo,
}) {
  final form = docuTrackerPrintFormFromDocument(document, memo: memo);
  return {
    for (final key in docuTrackerPrintLayoutFields(
      documentType: document.documentType,
    ).keys)
      key: '${form[key] ?? ''}',
  };
}
