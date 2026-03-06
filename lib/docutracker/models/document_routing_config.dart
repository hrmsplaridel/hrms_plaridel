import 'document_type.dart';
import 'workflow_step.dart';

/// Predefined workflow for a document type (Step 1 & 3).
/// Example: Memo → HR Staff → Department Head → Selected Employees
/// Example: Purchase Request → Requesting Dept → Procurement → Accounting → Approving Officer
class DocumentRoutingConfig {
  const DocumentRoutingConfig({
    required this.documentType,
    required this.steps,
    this.reviewDeadlineHours = 1,
  });

  final DocumentType documentType;
  final List<WorkflowStep> steps;

  /// Default review deadline in hours (Step 5: Review Time Limit).
  final int reviewDeadlineHours;

  factory DocumentRoutingConfig.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json['steps'];
    return DocumentRoutingConfig(
      documentType: documentTypeFromString(json['document_type']?.toString()),
      steps: stepsRaw is List
          ? (stepsRaw)
              .map((e) => WorkflowStep.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : [],
      reviewDeadlineHours:
          (json['review_deadline_hours'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'document_type': documentType.value,
        'steps': steps.map((s) => s.toJson()).toList(),
        'review_deadline_hours': reviewDeadlineHours,
      };

  /// Default configs for built-in document types.
  static List<DocumentRoutingConfig> get defaults => [
        DocumentRoutingConfig(
          documentType: DocumentType.memo,
          steps: [
            const WorkflowStep(
              stepOrder: 1,
              assigneeType: 'role',
              label: 'HR Staff',
            ),
            const WorkflowStep(
              stepOrder: 2,
              assigneeType: 'department',
              label: 'Department Head',
            ),
            const WorkflowStep(
              stepOrder: 3,
              assigneeType: 'user',
              label: 'Selected Employees',
            ),
          ],
          reviewDeadlineHours: 1,
        ),
        DocumentRoutingConfig(
          documentType: DocumentType.purchaseRequest,
          steps: [
            const WorkflowStep(
              stepOrder: 1,
              assigneeType: 'department',
              label: 'Requesting Department',
            ),
            const WorkflowStep(
              stepOrder: 2,
              assigneeType: 'department',
              label: 'Procurement',
            ),
            const WorkflowStep(
              stepOrder: 3,
              assigneeType: 'department',
              label: 'Accounting',
            ),
            const WorkflowStep(
              stepOrder: 4,
              assigneeType: 'role',
              label: 'Approving Officer',
            ),
          ],
          reviewDeadlineHours: 1,
        ),
      ];
}
