import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

enum DocuTrackerStepIndicatorKind {
  approved,
  forwarded,
  completed,
  current,
  upcoming,
  returned,
  rejected,
  overdue,
  escalated,
  cancelled,
}

class DocuTrackerStepIndicator {
  const DocuTrackerStepIndicator({required this.kind, required this.label});

  final DocuTrackerStepIndicatorKind kind;
  final String label;

  bool get isCompleted =>
      kind == DocuTrackerStepIndicatorKind.approved ||
      kind == DocuTrackerStepIndicatorKind.forwarded ||
      kind == DocuTrackerStepIndicatorKind.completed;
}

DocumentStatus docuTrackerStatusForDisplay(
  DocuTrackerDocument document, {
  DateTime? now,
}) {
  final terminal =
      document.status == DocumentStatus.approved ||
      document.status == DocumentStatus.rejected ||
      document.status == DocumentStatus.cancelled;
  if (terminal || document.status == DocumentStatus.overdue) {
    return document.status;
  }
  final deadline = document.deadlineTime;
  if (deadline != null && (now ?? DateTime.now()).isAfter(deadline)) {
    return DocumentStatus.overdue;
  }
  return document.status;
}

/// Human-readable workflow phase for document detail and lists.
class DocuTrackerWorkflowPhase {
  const DocuTrackerWorkflowPhase({required this.label, this.detail});

  final String label;
  final String? detail;

  static DocuTrackerWorkflowPhase forDocument({
    required DocuTrackerDocument doc,
    int? totalEnabledSteps,
    String? currentStepLabel,
  }) {
    if (doc.status == DocumentStatus.approved) {
      return const DocuTrackerWorkflowPhase(
        label: 'Completed',
        detail: 'Approved — workflow finished',
      );
    }
    if (doc.status == DocumentStatus.rejected) {
      return const DocuTrackerWorkflowPhase(
        label: 'Closed',
        detail: 'Rejected — workflow finished',
      );
    }
    if (doc.status == DocumentStatus.cancelled) {
      return const DocuTrackerWorkflowPhase(
        label: 'Cancelled',
        detail: 'Document was cancelled',
      );
    }

    if (DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc)) {
      return const DocuTrackerWorkflowPhase(
        label: 'Draft',
        detail: 'Not submitted — only you can edit until you submit',
      );
    }

    final step = doc.currentStep;
    String? activeStepDetail() {
      if (step == null || step <= 0) return null;
      final stepPart = totalEnabledSteps != null && totalEnabledSteps > 0
          ? 'Step $step of $totalEnabledSteps'
          : 'Step $step';
      return currentStepLabel != null && currentStepLabel.isNotEmpty
          ? '$stepPart - $currentStepLabel'
          : stepPart;
    }

    if (doc.status == DocumentStatus.returned) {
      final detail = activeStepDetail();
      return DocuTrackerWorkflowPhase(
        label: 'Returned for changes',
        detail: detail == null
            ? 'Changes are required'
            : '$detail - Changes are required',
      );
    }
    if (doc.status == DocumentStatus.escalated) {
      final detail = activeStepDetail();
      return DocuTrackerWorkflowPhase(
        label: 'Escalated',
        detail: detail == null
            ? 'Past deadline - needs attention'
            : '$detail - Past deadline - needs attention',
      );
    }
    if (doc.status == DocumentStatus.overdue) {
      final detail = activeStepDetail();
      return DocuTrackerWorkflowPhase(
        label: 'Overdue',
        detail: detail == null
            ? 'The current action is past its deadline'
            : '$detail - Past deadline',
      );
    }

    if (step != null && step > 0) {
      final stepPart = totalEnabledSteps != null && totalEnabledSteps > 0
          ? 'Step $step of $totalEnabledSteps'
          : 'Step $step';
      final labelPart =
          (currentStepLabel != null && currentStepLabel.isNotEmpty)
          ? '$stepPart · $currentStepLabel'
          : stepPart;
      return DocuTrackerWorkflowPhase(label: 'In review', detail: labelPart);
    }

    return const DocuTrackerWorkflowPhase(
      label: 'In progress',
      detail: 'Routing in progress',
    );
  }

  static DocuTrackerStepIndicator indicatorForStep({
    required DocuTrackerDocument doc,
    required int stepOrder,
    List<DocumentHistoryEntry> history = const <DocumentHistoryEntry>[],
  }) {
    final currentStep = doc.currentStep ?? 1;

    if (stepOrder > currentStep) {
      return const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.upcoming,
        label: 'WAITING',
      );
    }

    if (stepOrder == currentStep) {
      return switch (doc.status) {
        DocumentStatus.approved => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.approved,
          label: 'APPROVED',
        ),
        DocumentStatus.rejected => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.rejected,
          label: 'REJECTED',
        ),
        DocumentStatus.returned => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.returned,
          label: 'RETURNED',
        ),
        DocumentStatus.overdue => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.overdue,
          label: 'OVERDUE',
        ),
        DocumentStatus.escalated => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.escalated,
          label: 'ESCALATED',
        ),
        DocumentStatus.cancelled => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.cancelled,
          label: 'CANCELLED',
        ),
        _ => const DocuTrackerStepIndicator(
          kind: DocuTrackerStepIndicatorKind.current,
          label: 'CURRENT',
        ),
      };
    }

    DocumentHistoryEntry? latest;
    for (final entry in history) {
      if (entry.fromStep != stepOrder) continue;
      final action = entry.action?.trim().toLowerCase();
      if (action != 'approved' && action != 'forwarded') continue;
      final latestTime = latest?.createdAt;
      if (latest == null ||
          latestTime == null ||
          (entry.createdAt?.isAfter(latestTime) ?? false)) {
        latest = entry;
      }
    }

    return switch (latest?.action?.trim().toLowerCase()) {
      'approved' => const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.approved,
        label: 'APPROVED',
      ),
      'forwarded' => const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.forwarded,
        label: 'FORWARDED',
      ),
      _ => const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.completed,
        label: 'COMPLETED',
      ),
    };
  }
}
