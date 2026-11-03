import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';

/// Primary / secondary buckets for the Documents → Required actions panel.
enum DocuTrackerRequiredActionBucket {
  needsReview,
  needsSignature,
  needsSetup,
  waiting,
  completed,
}

/// Classifies a Required actions row without changing authorization.
///
/// - RSP/L&D source signature requests stay in signature / setup / waiting /
///   completed buckets from [DocuTrackerRspSignatureRequest.signatureState].
/// - Native DocuTracker workflow / department-review tasks → [needsReview].
/// - Native signature-only assignees (not the active reviewer) →
///   [needsSignature].
DocuTrackerRequiredActionBucket docuTrackerRequiredActionBucket({
  DocuTrackerDocument? document,
  DocuTrackerRspSignatureRequest? sourceRequest,
  String userId = '',
}) {
  if (sourceRequest != null) {
    return switch (sourceRequest.signatureState) {
      DocuTrackerSourceSignatureState.needsSetup =>
        DocuTrackerRequiredActionBucket.needsSetup,
      DocuTrackerSourceSignatureState.needsYourSignature =>
        DocuTrackerRequiredActionBucket.needsSignature,
      DocuTrackerSourceSignatureState.waitingOnOthers =>
        DocuTrackerRequiredActionBucket.waiting,
      DocuTrackerSourceSignatureState.fullySigned =>
        DocuTrackerRequiredActionBucket.completed,
    };
  }
  if (document == null) return DocuTrackerRequiredActionBucket.needsReview;
  if (_isNativeSignatureOnlyTask(document, userId)) {
    return DocuTrackerRequiredActionBucket.needsSignature;
  }
  return DocuTrackerRequiredActionBucket.needsReview;
}

bool _isNativeSignatureOnlyTask(DocuTrackerDocument document, String userId) {
  final action = (document.sourceAction ?? '').trim().toLowerCase();
  if (action.contains('sign')) return true;

  final uid = userId.trim();
  if (uid.isEmpty) return false;

  final status = document.status;
  final isActiveReview =
      status == DocumentStatus.pending ||
      status == DocumentStatus.inReview ||
      status == DocumentStatus.escalated ||
      status == DocumentStatus.overdue ||
      status == DocumentStatus.returned;
  final isHolder = document.currentHolderId?.trim() == uid;
  final isRouting = document.viewerIsRoutingAssignee && isActiveReview;
  if (isHolder || isRouting) return false;

  return document.signatureSignerIds.any((id) => id.trim() == uid);
}
