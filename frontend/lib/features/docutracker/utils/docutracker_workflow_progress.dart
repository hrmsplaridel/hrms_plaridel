import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_history_presentation.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';

/// One enabled workflow step as shown on the strip and the full map.
class DocuTrackerStepProgress {
  const DocuTrackerStepProgress({
    required this.order,
    required this.name,
    required this.indicator,
    this.personName,
  });

  final int order;
  final String name;
  final DocuTrackerStepIndicator indicator;

  /// Recorded actor, or the current responsible reviewer on the open step.
  /// Null when nothing was recorded. Upcoming steps never receive a name.
  final String? personName;

  bool get isCurrent => indicator.kind == DocuTrackerStepIndicatorKind.current;
}

/// Progress for [steps] using the document status and the full activity history.
///
/// Pass the unpaged history list. A single Activity History page can omit an
/// older decision and would leave that step unlabeled.
List<DocuTrackerStepProgress> docuTrackerWorkflowProgress({
  required DocuTrackerDocument doc,
  required List<WorkflowStep> steps,
  List<DocumentHistoryEntry> history = const [],
  String? currentReviewerName,
}) {
  final enabled = steps.where((step) => step.enabled).toList()
    ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
  final decisions = _decisionsByStep(history);
  final current = doc.currentStep;
  final draft = DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
  final open =
      !draft && _isOpenReview(doc.status) && current != null && current > 0;
  final reviewer = _clean(currentReviewerName ?? doc.assigneeName);

  return [
    for (final step in enabled)
      _progressForStep(
        doc: doc,
        step: step,
        decisions: decisions[step.stepOrder] ?? const [],
        open: open && step.stepOrder == current,
        behind: !draft && current != null && step.stepOrder < current,
        reviewer: reviewer,
      ),
  ];
}

DocuTrackerStepProgress _progressForStep({
  required DocuTrackerDocument doc,
  required WorkflowStep step,
  required List<_StepDecision> decisions,
  required bool open,
  required bool behind,
  required String? reviewer,
}) {
  final name = _clean(step.label) ?? 'Step ${step.stepOrder}';
  final latest = decisions.isEmpty ? null : decisions.last;
  final earlier = decisions.length < 2 ? null : decisions[decisions.length - 2];

  if (open) {
    final state = switch (doc.status) {
      DocumentStatus.returned => 'Returned',
      DocumentStatus.overdue => 'Overdue',
      DocumentStatus.escalated => 'Escalated',
      _ => 'In review',
    };
    return DocuTrackerStepProgress(
      order: step.stepOrder,
      name: name,
      personName: reviewer,
      indicator: DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.current,
        label: 'Current step',
        detail: latest == null
            ? state
            : '$state · Previous visit: ${latest.label}',
      ),
    );
  }

  if (doc.status == DocumentStatus.approved &&
      step.stepOrder == doc.currentStep) {
    final release = doc.isReleased
        ? 'Released'
        : doc.isAwaitingRelease
        ? 'Awaiting release'
        : null;
    final earlierVisit = earlier == null
        ? null
        : 'Earlier visit: ${earlier.label}';
    final detail = [
      if (release != null) release,
      if (earlierVisit != null) earlierVisit,
    ].join(' · ');
    return DocuTrackerStepProgress(
      order: step.stepOrder,
      name: name,
      personName: latest?.actorName,
      indicator: DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.approved,
        label: 'Approved',
        detail: detail.isEmpty ? null : detail,
      ),
    );
  }

  if (doc.status == DocumentStatus.rejected &&
      step.stepOrder == doc.currentStep) {
    return DocuTrackerStepProgress(
      order: step.stepOrder,
      name: name,
      personName: latest?.actorName,
      indicator: const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.rejected,
        label: 'Rejected',
      ),
    );
  }

  if (doc.status == DocumentStatus.cancelled &&
      step.stepOrder == doc.currentStep) {
    return DocuTrackerStepProgress(
      order: step.stepOrder,
      name: name,
      indicator: const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.cancelled,
        label: 'Cancelled',
      ),
    );
  }

  if (latest != null) {
    return DocuTrackerStepProgress(
      order: step.stepOrder,
      name: name,
      personName: latest.actorName,
      indicator: DocuTrackerStepIndicator(
        kind: latest.kind,
        label: latest.label,
        detail: earlier == null ? null : 'Earlier visit: ${earlier.label}',
      ),
    );
  }

  if (behind) {
    return DocuTrackerStepProgress(
      order: step.stepOrder,
      name: name,
      indicator: const DocuTrackerStepIndicator(
        kind: DocuTrackerStepIndicatorKind.unrecorded,
        label: 'Decision not recorded',
      ),
    );
  }

  return DocuTrackerStepProgress(
    order: step.stepOrder,
    name: name,
    indicator: const DocuTrackerStepIndicator(
      kind: DocuTrackerStepIndicatorKind.upcoming,
      label: 'Pending',
    ),
  );
}

bool _isOpenReview(DocumentStatus status) {
  return status == DocumentStatus.inReview ||
      status == DocumentStatus.returned ||
      status == DocumentStatus.overdue ||
      status == DocumentStatus.escalated ||
      status == DocumentStatus.pending;
}

class _StepDecision {
  const _StepDecision({
    required this.action,
    required this.kind,
    required this.label,
    this.actorName,
  });

  final String action;
  final DocuTrackerStepIndicatorKind kind;
  final String label;
  final String? actorName;
}

/// Newest decision last. Untimed rows stay older than timed ones. Rows with
/// the same timestamp keep the newest-first history order.
Map<int, List<_StepDecision>> _decisionsByStep(
  List<DocumentHistoryEntry> history,
) {
  final indexed = <({int index, DocumentHistoryEntry entry})>[
    for (var i = 0; i < history.length; i++) (index: i, entry: history[i]),
  ];
  indexed.sort((a, b) {
    final at = a.entry.createdAt;
    final bt = b.entry.createdAt;
    if (at == null && bt != null) return -1;
    if (at != null && bt == null) return 1;
    if (at != null && bt != null) {
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
    }
    return b.index.compareTo(a.index);
  });

  final byStep = <int, List<_StepDecision>>{};
  for (final row in indexed) {
    final entry = row.entry;
    final step = entry.fromStep;
    final action = entry.action?.trim().toLowerCase();
    if (step == null || action == null) continue;
    final decision = switch (action) {
      'approved' => const _StepDecision(
        action: 'approved',
        kind: DocuTrackerStepIndicatorKind.approved,
        label: 'Approved',
      ),
      'forwarded' => const _StepDecision(
        action: 'forwarded',
        kind: DocuTrackerStepIndicatorKind.forwarded,
        label: 'Forwarded',
      ),
      'returned' => const _StepDecision(
        action: 'returned',
        kind: DocuTrackerStepIndicatorKind.returned,
        label: 'Returned',
      ),
      'rejected' => const _StepDecision(
        action: 'rejected',
        kind: DocuTrackerStepIndicatorKind.rejected,
        label: 'Rejected',
      ),
      _ => null,
    };
    if (decision == null) continue;
    byStep
        .putIfAbsent(step, () => [])
        .add(
          _StepDecision(
            action: decision.action,
            kind: decision.kind,
            label: decision.label,
            actorName: docuTrackerHistoryActorName(entry),
          ),
        );
  }
  return byStep;
}

/// Indicator for one step. Uses the same rules as [docuTrackerWorkflowProgress].
DocuTrackerStepIndicator docuTrackerIndicatorForStep({
  required DocuTrackerDocument doc,
  required int stepOrder,
  List<DocumentHistoryEntry> history = const [],
  String? currentReviewerName,
}) {
  return docuTrackerWorkflowProgress(
    doc: doc,
    steps: [
      WorkflowStep(
        stepOrder: stepOrder,
        assigneeType: 'user',
        label: 'Step $stepOrder',
      ),
    ],
    history: history,
    currentReviewerName: currentReviewerName,
  ).single.indicator;
}

String? _clean(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
