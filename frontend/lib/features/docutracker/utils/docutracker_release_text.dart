import 'package:hrms_plaridel/features/docutracker/models/document.dart';

/// Status badge text for the release stage, or null when release does not
/// apply. The document status itself stays `approved` in both cases.
String? docuTrackerReleaseBadgeLabel(
  DocuTrackerDocument document, {
  bool short = false,
}) {
  if (document.isAwaitingRelease) {
    return short ? 'Awaiting release' : 'Approved · Awaiting release';
  }
  if (document.isReleased) return 'Released';
  return null;
}

/// Hero copy after workflow approval. Release-required docs that are not yet
/// released must not say the workflow lifecycle is finished.
String docuTrackerApprovedWorkflowMessage(DocuTrackerDocument document) {
  if (document.isAwaitingRelease) return 'Approved — awaiting release';
  return 'This workflow is complete.';
}

/// Optional supporting line under [docuTrackerApprovedWorkflowMessage].
String? docuTrackerApprovedWorkflowDetail(DocuTrackerDocument document) {
  if (!document.isAwaitingRelease) return null;
  return 'Approval is complete. This document must still be released before '
      'it is distributed to the receiving department.';
}

/// Final-step approve confirmation. [typeRequiresRelease] is the document
/// type policy, which is known before approval. The document's own
/// release flag is set only when final approval succeeds.
({String title, String message, String confirmLabel})
docuTrackerFinalApproveConfirmCopy({required bool? typeRequiresRelease}) {
  if (typeRequiresRelease == true) {
    return (
      title: 'Approve final step?',
      message:
          'This finishes workflow approval. Distribution still requires a '
          'release before the receiving department can receive it.',
      confirmLabel: 'Approve',
    );
  }
  if (typeRequiresRelease == false) {
    return (
      title: 'Approve and complete?',
      message:
          'This finishes workflow approval. This document type does not '
          'require a release.',
      confirmLabel: 'Approve and Complete',
    );
  }
  return (
    title: 'Approve final step?',
    message: 'This finishes workflow approval.',
    confirmLabel: 'Approve',
  );
}

/// Receiving-department view-only banner: released, access via release, and
/// no active review / sign / release authority for this viewer.
bool docuTrackerShowReleasedViewOnlyMessage({
  required DocuTrackerDocument document,
  required String userId,
  bool hasActiveAction = false,
}) {
  if (!document.isReleased) return false;
  if (!document.viewerReleaseAccess) return false;
  if (document.viewerCanRelease) return false;
  if (hasActiveAction) return false;
  final uid = userId.trim();
  if (uid.isEmpty) return false;
  if (document.currentHolderId?.trim() == uid) return false;
  if (document.viewerIsRoutingAssignee) return false;
  if (document.signatureSignerIds.any((id) => id.trim() == uid)) return false;
  return true;
}

const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// e.g. "October 9, 2026, 3:42 PM" in local time.
String docuTrackerReleaseTimestamp(DateTime value) {
  final local = value.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${_months[local.month - 1]} ${local.day}, ${local.year}, '
      '$hour12:$minute $period';
}

/// e.g. "Released by Maria Santos · October 9, 2026, 3:42 PM".
String? docuTrackerReleasedByLine(DocuTrackerDocument document) {
  final releasedAt = document.releasedAt;
  if (releasedAt == null) return null;
  final name = document.releasedByName?.trim();
  final by = name == null || name.isEmpty ? 'Released' : 'Released by $name';
  return '$by · ${docuTrackerReleaseTimestamp(releasedAt)}';
}
