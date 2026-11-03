import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

/// Shown when the employee inbox has no assigned work and no released
/// documents this viewer may open. It is not a claim that no documents exist.
const docuTrackerEmployeeDashboardEmptyTitle = 'No documents yet';

const docuTrackerEmployeeDashboardEmptyMessage =
    'This inbox lists work assigned to you and documents released to your department.';

/// True when this employee already appears in a personal inbox section
/// (created, holding, assigned, source participation, or signature).
bool docuTrackerEmployeeParticipated(
  DocuTrackerDocument document,
  String userId,
) {
  if (userId.isEmpty) return false;
  return document.createdBy == userId ||
      document.currentHolderId == userId ||
      document.viewerIsRoutingAssignee ||
      document.viewerParticipatedInSource ||
      document.signatureSignerIds.any((id) => id == userId);
}

/// Released documents this viewer may open, and that are not already listed
/// as their own work.
///
/// Membership uses the backend [DocuTrackerDocument.viewerReleaseAccess] flag
/// and [DocuTrackerDocumentVisibility]. A user-specific view denial leaves
/// that flag false. Being listed here does not grant edit, review, or release.
List<DocuTrackerDocument> docuTrackerReleasedViewDocuments({
  required List<DocuTrackerDocument> documents,
  required String userId,
}) {
  if (userId.isEmpty) return const [];
  return documents.where((document) {
    if (!DocuTrackerDocumentVisibility.isVisible(
      doc: document,
      userId: userId,
    )) {
      return false;
    }
    if (!docuTrackerShowReleasedViewOnlyMessage(
      document: document,
      userId: userId,
    )) {
      return false;
    }
    return !docuTrackerEmployeeParticipated(document, userId);
  }).toList();
}
