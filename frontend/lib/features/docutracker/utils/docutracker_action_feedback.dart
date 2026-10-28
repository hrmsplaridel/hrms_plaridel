import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_return_text.dart';

/// Success text after the server accepts a workflow action. Release is named
/// only when the updated document is actually awaiting release.
String docuTrackerWorkflowActionMessage({
  required String action,
  required DocuTrackerDocument document,
}) {
  final reviewer = document.assigneeName?.trim();
  final namedReviewer = reviewer == null || reviewer.isEmpty ? null : reviewer;
  switch (action) {
    case 'approve':
      if (document.isAwaitingRelease) return 'Approved — awaiting release';
      if (document.status == DocumentStatus.approved) {
        return 'Final approval completed';
      }
      if (namedReviewer != null) {
        return 'Approved and moved to the next reviewer: $namedReviewer';
      }
      return 'Approved and moved to the next reviewer';
    case 'forward':
      if (namedReviewer != null) {
        return 'Forwarded to next workflow step: $namedReviewer';
      }
      return 'Forwarded to next workflow step';
    case 'return':
      if (namedReviewer != null) {
        return '$docuTrackerReturnSuccessMessage $namedReviewer is now responsible.';
      }
      return docuTrackerReturnSuccessMessage;
    case 'reject':
      return 'Rejected';
    case 'submit':
      if (namedReviewer != null) {
        return 'Submitted for review: $namedReviewer';
      }
      return 'Submitted for review';
    default:
      return 'Workflow updated';
  }
}
