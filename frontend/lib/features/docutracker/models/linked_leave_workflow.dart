import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';

/// Read-only DTR leave workflow (Department Review → Final HR Review) and
/// leave history, as shown on a linked leave's DocuTracker detail page.
class LinkedLeaveWorkflow {
  const LinkedLeaveWorkflow({
    required this.steps,
    required this.history,
    this.currentStep,
  });

  final List<LinkedLeaveWorkflowStep> steps;
  final List<DocumentHistoryEntry> history;
  final int? currentStep;

  factory LinkedLeaveWorkflow.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final rawHistory = json['history'];
    return LinkedLeaveWorkflow(
      currentStep: (json['current_step'] as num?)?.toInt(),
      steps: rawSteps is List
          ? rawSteps
                .whereType<Map>()
                .map(
                  (e) => LinkedLeaveWorkflowStep.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
          : const [],
      history: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map((e) => _historyEntry(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
    );
  }

  /// Draft is not a DocuTracker status, so it is left blank rather than
  /// shown as "Pending".
  static DocumentStatus? _status(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || value == 'draft') return null;
    return documentStatusFromString(value);
  }

  static DocumentHistoryEntry _historyEntry(Map<String, dynamic> json) {
    final createdAt = json['created_at']?.toString();
    return DocumentHistoryEntry(
      id: json['id']?.toString(),
      documentId: json['document_id']?.toString() ?? '',
      action: json['action']?.toString(),
      actorId: json['actor_id']?.toString(),
      actorName: json['actor_name']?.toString(),
      fromStatus: _status(json['from_status']),
      toStatus: _status(json['to_status']),
      remarks: json['remarks']?.toString(),
      createdAt: createdAt == null ? null : DateTime.tryParse(createdAt),
    );
  }
}

class LinkedLeaveWorkflowStep {
  const LinkedLeaveWorkflowStep({
    required this.stepOrder,
    required this.label,
    required this.indicator,
    required this.reviewers,
  });

  final int stepOrder;
  final String label;
  final DocuTrackerStepIndicator indicator;
  final List<LinkedLeaveReviewer> reviewers;

  factory LinkedLeaveWorkflowStep.fromJson(Map<String, dynamic> json) {
    final rawIndicator = json['indicator'];
    final indicator = rawIndicator is Map ? rawIndicator : const {};
    final kindName = indicator['kind']?.toString();
    final kind = DocuTrackerStepIndicatorKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => DocuTrackerStepIndicatorKind.upcoming,
    );
    final rawReviewers = json['reviewers'];
    return LinkedLeaveWorkflowStep(
      stepOrder: (json['step_order'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? 'Step',
      indicator: DocuTrackerStepIndicator(
        kind: kind,
        label: indicator['label']?.toString() ?? kind.name.toUpperCase(),
      ),
      reviewers: rawReviewers is List
          ? rawReviewers
                .whereType<Map>()
                .map(
                  (e) => LinkedLeaveReviewer.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class LinkedLeaveReviewer {
  const LinkedLeaveReviewer({
    this.id,
    required this.name,
    this.isBackup = false,
  });

  final String? id;
  final String name;
  final bool isBackup;

  factory LinkedLeaveReviewer.fromJson(Map<String, dynamic> json) {
    return LinkedLeaveReviewer(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? 'Reviewer',
      isBackup: json['role']?.toString() == 'backup',
    );
  }
}
