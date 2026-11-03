import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

/// Native DocuTracker content stays editable only while the document is a draft.
///
/// RSP and Learning & Development records keep their source-module rules.
bool docuTrackerNativeContentIsLocked(DocuTrackerDocument document) {
  if (document.sourceOnly) return false;
  final source = document.sourceModule?.trim();
  if (source != null && source.isNotEmpty) return false;
  if (document.sentTime != null) return true;
  return !DocuTrackerDocumentVisibility.isWorkInProgressDraft(document);
}

/// Message shown when ordinary content edits are blocked, or null for a draft.
String? docuTrackerNativeContentLockMessage(DocuTrackerDocument document) {
  if (!docuTrackerNativeContentIsLocked(document)) return null;
  if (document.releasedAt != null) {
    return 'This released document is finalized and read-only.';
  }
  return 'This document is no longer a draft, so its content is read-only.';
}
