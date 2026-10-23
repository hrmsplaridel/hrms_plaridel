import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';

/// Return sends a native document back to the previous workflow step. The
/// reviewer of that step becomes responsible. Content stays locked, and the
/// author does not receive a correction task.
const String docuTrackerReturnButtonLabel = 'Return to Previous Step';

const String docuTrackerReturnTooltip =
    'Send this document back to the previous workflow step. '
    'That step\u2019s reviewer becomes responsible.';

const String docuTrackerReturnDialogTitle = 'Return to previous step';

/// Admin workflow-editor label for the stored `return` action.
const String docuTrackerReturnActionLabel = 'Return to previous step';

const String docuTrackerReturnActionExplanation =
    'Returns the document to the previous workflow reviewer. Document content '
    'remains read-only.';

const String docuTrackerReturnDialogExplanation =
    'The reviewer of the previous workflow step becomes responsible for this '
    'document. Its content stays read-only, and no correction task is created '
    'for the author.';

const String docuTrackerReturnReasonLabel = 'Reason for return (optional)';

const String docuTrackerReturnSuccessMessage =
    'Document returned to the previous step.';

const String docuTrackerReturnNoReason = 'No reason provided.';

const String docuTrackerReturnNotRecorded = 'Not recorded in Activity History';

/// Most recent `returned` event, or null when none is loaded.
DocumentHistoryEntry? docuTrackerLatestReturnEntry(
  Iterable<DocumentHistoryEntry> history,
) {
  DocumentHistoryEntry? latest;
  for (final entry in history) {
    if (entry.action != 'returned') continue;
    final at = entry.createdAt;
    if (latest == null) {
      latest = entry;
      continue;
    }
    final latestAt = latest.createdAt;
    if (at != null && (latestAt == null || at.isAfter(latestAt))) {
      latest = entry;
    }
  }
  return latest;
}

/// Reason recorded on a return, or a neutral message when none was entered.
String docuTrackerReturnReasonText(DocumentHistoryEntry? entry) {
  if (entry == null) return docuTrackerReturnNotRecorded;
  final reason = entry.remarks?.trim();
  if (reason == null || reason.isEmpty) return docuTrackerReturnNoReason;
  return reason;
}

/// Next action for the viewer of a returned document.
String docuTrackerReturnedNextAction({
  required bool isResponsibleReviewer,
  required bool isCreator,
}) {
  if (isResponsibleReviewer) {
    return 'This document was returned to your review step. Review it and '
        'choose the next workflow action.';
  }
  if (isCreator) {
    return 'Your document is still read-only. It is waiting for the reviewer '
        'of this step to act.';
  }
  return 'This document is read-only and is waiting for the reviewer of this '
      'step to act.';
}
