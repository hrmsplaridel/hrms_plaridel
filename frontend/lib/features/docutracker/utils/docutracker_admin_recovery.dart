import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permission_service.dart';

/// A reviewer the existing recovery check can accept for the current step.
class DocuTrackerRecoveryCandidate {
  const DocuTrackerRecoveryCandidate({
    required this.userId,
    required this.name,
    required this.roleLabel,
  });

  final String userId;
  final String name;
  final String roleLabel;
}

/// Reviewers returned for the current step, or an explanation when none exist.
class DocuTrackerRecoveryOptions {
  const DocuTrackerRecoveryOptions({
    required this.candidates,
    this.message,
    this.departmentName,
    this.currentStep,
    this.stepLabel,
    this.currentReviewerName,
  });

  final List<DocuTrackerRecoveryCandidate> candidates;

  /// Shown instead of a reviewer list. Null when [candidates] can be chosen.
  final String? message;

  /// Submitter or fixed department resolved by the backend, when this step has one.
  final String? departmentName;

  /// Current step number from the candidate payload, when the backend sent one.
  final int? currentStep;

  /// Current step name from the candidate payload.
  final String? stepLabel;

  /// Current holder name from the candidate payload.
  final String? currentReviewerName;

  bool get canSelect => message == null && candidates.isNotEmpty;
}

/// Shown when permission-explain reports `reassignment_required` (holder ineligible).
const docuTrackerAdminRecoveryNoticeBlocking =
    'The assigned reviewer can no longer act on this step. An administrator '
    'must reassign this document through Admin Recovery before the workflow '
    'can continue.';

/// Shown when the document is flagged but the server still allows the holder to act.
const docuTrackerAdminRecoveryNoticeAdvisory =
    'This document is flagged for administrator attention. The current '
    'reviewer may still complete their step, or an administrator can reassign '
    'it through Admin Recovery.';

/// Legacy combined string kept for older tests/call sites.
const docuTrackerAdminRecoveryNotice =
    'Admin attention required. $docuTrackerAdminRecoveryNoticeBlocking';

const docuTrackerNoReplacementReviewerMessage =
    'No eligible replacement reviewer is configured for this step.';

const docuTrackerRecoveryRemarksRequired =
    'Enter a reason for this reassignment.';

bool docuTrackerIsNativeDocument(DocuTrackerDocument doc) {
  if (doc.sourceOnly) return false;
  final source = doc.sourceModule?.trim();
  return source == null || source.isEmpty;
}

bool docuTrackerRecoveryStatusOpen(DocumentStatus status) {
  return status == DocumentStatus.inReview ||
      status == DocumentStatus.returned ||
      status == DocumentStatus.escalated ||
      status == DocumentStatus.overdue;
}

/// The attention message is for anyone who can open a flagged native document.
bool docuTrackerShowAdminRecoveryNotice(DocuTrackerDocument doc) {
  return doc.needsAdminIntervention && docuTrackerIsNativeDocument(doc);
}

/// The action stays with administrators, and only while recovery can apply.
bool docuTrackerShowAdminRecoveryAction({
  required DocuTrackerDocument doc,
  required bool isAdmin,
}) {
  return isAdmin &&
      docuTrackerShowAdminRecoveryNotice(doc) &&
      docuTrackerRecoveryStatusOpen(doc.status);
}

/// True when permission-explain says workflow step actions need Admin Recovery.
///
/// Mirrors backend `getDepartmentReviewHolderStatus` / `reassignment_required`:
/// `needs_admin_intervention` alone does not block an eligible holder.
bool docuTrackerReassignmentRequired(
  Map<String, DocuTrackerPermissionExplanation> explanations,
) {
  for (final explanation in explanations.values) {
    if (explanation.reason == 'reassignment_required') return true;
  }
  return false;
}

/// Body copy for the admin attention card, aligned with server decisions.
String docuTrackerAdminRecoveryBody({required bool workflowBlocked}) {
  return workflowBlocked
      ? docuTrackerAdminRecoveryNoticeBlocking
      : docuTrackerAdminRecoveryNoticeAdvisory;
}

/// Newest recorded reason, when history actually explains the intervention.
String? docuTrackerAdminRecoveryReason(Iterable<DocumentHistoryEntry> history) {
  final rows = history.toList()
    ..sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  for (final entry in rows) {
    final remarks = entry.remarks?.trim();
    if (remarks == null || remarks.isEmpty) continue;
    final lower = remarks.toLowerCase();
    if (lower.contains('admin recovery') ||
        lower.contains('admin intervention')) {
      return remarks;
    }
  }
  return null;
}

/// Displays the admin recovery candidate payload without deciding eligibility.
DocuTrackerRecoveryOptions docuTrackerRecoveryOptionsFromJson(
  Map<String, dynamic> json,
) {
  final raw = json['candidates'];
  final candidates = <DocuTrackerRecoveryCandidate>[];
  if (raw is List) {
    for (final row in raw.whereType<Map>()) {
      final id = row['user_id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final name = row['name']?.toString().trim() ?? '';
      final role = row['role_label']?.toString().trim() ?? '';
      candidates.add(
        DocuTrackerRecoveryCandidate(
          userId: id,
          name: name.isEmpty ? 'Name not recorded' : name,
          roleLabel: role.isEmpty ? 'Reviewer' : role,
        ),
      );
    }
  }
  final department = json['department_name']?.toString().trim() ?? '';
  final message = json['message']?.toString().trim() ?? '';
  final stepLabel = json['step_label']?.toString().trim() ?? '';
  final reviewer = json['current_holder_name']?.toString().trim() ?? '';
  final step = json['current_step'];
  return DocuTrackerRecoveryOptions(
    candidates: candidates,
    departmentName: department.isEmpty ? null : department,
    currentStep: step is num ? step.toInt() : int.tryParse('$step'),
    stepLabel: stepLabel.isEmpty ? null : stepLabel,
    currentReviewerName: reviewer.isEmpty ? null : reviewer,
    message: candidates.isEmpty
        ? (message.isEmpty ? docuTrackerNoReplacementReviewerMessage : message)
        : null,
  );
}
