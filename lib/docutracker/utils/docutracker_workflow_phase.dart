import '../models/document.dart';
import '../models/document_status.dart';
import '../services/docutracker_document_visibility.dart';

/// Human-readable workflow phase for document detail and lists.
class DocuTrackerWorkflowPhase {
  const DocuTrackerWorkflowPhase({
    required this.label,
    this.detail,
  });

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
    if (step != null && step > 0) {
      final stepPart = totalEnabledSteps != null && totalEnabledSteps > 0
          ? 'Step $step of $totalEnabledSteps'
          : 'Step $step';
      final labelPart = (currentStepLabel != null && currentStepLabel.isNotEmpty)
          ? '$stepPart · $currentStepLabel'
          : stepPart;
      return DocuTrackerWorkflowPhase(
        label: 'In review',
        detail: labelPart,
      );
    }

    if (doc.status == DocumentStatus.escalated) {
      return const DocuTrackerWorkflowPhase(
        label: 'Escalated',
        detail: 'Past deadline — needs attention',
      );
    }

    return const DocuTrackerWorkflowPhase(
      label: 'In progress',
      detail: 'Routing in progress',
    );
  }
}
