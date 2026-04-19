import '../models/workflow_step.dart';

class DocuTrackerWorkflowValidationIssue {
  const DocuTrackerWorkflowValidationIssue({
    required this.message,
    this.stepOrder,
    this.isWarning = false,
  });

  final String message;
  final int? stepOrder;
  final bool isWarning;
}

class DocuTrackerWorkflowConfigValidator {
  const DocuTrackerWorkflowConfigValidator();

  List<DocuTrackerWorkflowValidationIssue> validate(List<WorkflowStep> steps) {
    final issues = <DocuTrackerWorkflowValidationIssue>[];
    if (steps.isEmpty) {
      issues.add(const DocuTrackerWorkflowValidationIssue(
        message: 'Workflow must have at least 1 step.',
      ));
      return issues;
    }

    final orders = steps.map((s) => s.stepOrder).toList()..sort();
    // Check duplicates
    final seen = <int>{};
    for (final o in orders) {
      if (!seen.add(o)) {
        issues.add(DocuTrackerWorkflowValidationIssue(
          message: 'Duplicate step number $o.',
          stepOrder: o,
        ));
      }
    }

    if (orders.first != 1) {
      issues.add(const DocuTrackerWorkflowValidationIssue(
        message: 'Workflow must start at step 1.',
        stepOrder: 1,
      ));
    }

    for (var i = 1; i < orders.length; i++) {
      if (orders[i] != orders[i - 1] + 1) {
        issues.add(const DocuTrackerWorkflowValidationIssue(
          message: 'Step numbers must be contiguous (no gaps).',
        ));
        break;
      }
    }

    // At least one enabled step.
    if (!steps.any((s) => s.enabled)) {
      issues.add(const DocuTrackerWorkflowValidationIssue(
        message: 'At least one step must be enabled.',
      ));
    }

    // Per-step validation.
    for (final step in steps) {
      final type = step.assigneeType.trim().toLowerCase();
      if (!const {'user', 'role', 'department', 'office'}.contains(type)) {
        issues.add(DocuTrackerWorkflowValidationIssue(
          message: 'Invalid assignee type "$type".',
          stepOrder: step.stepOrder,
        ));
      }

      if (step.deadlineHours != null && step.deadlineHours! <= 0) {
        issues.add(DocuTrackerWorkflowValidationIssue(
          message: 'Deadline hours must be greater than 0.',
          stepOrder: step.stepOrder,
        ));
      }

      if (!step.enabled) {
        // Disabled steps are allowed, but warn if it’s the only enabled path.
        continue;
      }

      if (type == 'user') {
        final ids = step.userIds ?? const [];
        final hasUsers = ids.where((e) => e.trim().isNotEmpty).isNotEmpty;
        if ((step.departmentId ?? '').trim().isEmpty) {
          issues.add(DocuTrackerWorkflowValidationIssue(
            message:
                'For “selected people” steps, choose a department so reviewers are scoped correctly.',
            stepOrder: step.stepOrder,
          ));
        }
        if (!hasUsers) {
          issues.add(DocuTrackerWorkflowValidationIssue(
            message: 'Choose a primary reviewer (and optional backups).',
            stepOrder: step.stepOrder,
          ));
        }
      } else if (type == 'role') {
        if ((step.roleId ?? '').trim().isEmpty) {
          issues.add(DocuTrackerWorkflowValidationIssue(
            message: 'Role step requires a role.',
            stepOrder: step.stepOrder,
          ));
        }
      } else if (type == 'department') {
        if ((step.departmentId ?? '').trim().isEmpty) {
          issues.add(DocuTrackerWorkflowValidationIssue(
            message: 'Department step requires a department.',
            stepOrder: step.stepOrder,
          ));
        }
      } else if (type == 'office') {
        if ((step.officeId ?? '').trim().isEmpty) {
          issues.add(DocuTrackerWorkflowValidationIssue(
            message: 'Office step requires an office.',
            stepOrder: step.stepOrder,
          ));
        }
      }
    }

    return issues;
  }
}

