import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_workflow_config_validator.dart';

void main() {
  test('workflow step round-trips primary, backup, and allowed actions', () {
    final step = WorkflowStep.fromJson({
      'step_order': 2,
      'assignee_type': 'user',
      'assignee_source': 'specific_users',
      'user_ids': ['primary-1', 'backup-1'],
      'label': 'Final Approval',
      'allowed_actions': ['approve', 'return', 'reject'],
    });

    expect(step.userIds, ['primary-1', 'backup-1']);
    expect(step.allowedActions, ['approve', 'return', 'reject']);
    expect(step.toJson()['allowed_actions'], ['approve', 'return', 'reject']);
  });

  test('validator requires a primary assignee and at least one action', () {
    const steps = [
      WorkflowStep(
        stepOrder: 1,
        assigneeType: 'user',
        assigneeSource: 'specific_users',
        userIds: [],
        label: 'Review',
        allowedActions: [],
      ),
    ];

    final messages = const DocuTrackerWorkflowConfigValidator()
        .validate(steps)
        .map((issue) => issue.message)
        .toList();

    expect(
      messages,
      contains('Choose a primary reviewer (and optional backups).'),
    );
    expect(messages, contains('Choose at least one allowed action.'));
  });

  test('automatic department reviewer steps remain backward compatible', () {
    const steps = [
      WorkflowStep(
        stepOrder: 1,
        assigneeType: 'user',
        assigneeSource: 'department_reviewers',
        departmentId: 'department-1',
        userIds: [],
        label: 'Department Review',
        allowedActions: ['approve', 'return'],
      ),
    ];

    expect(const DocuTrackerWorkflowConfigValidator().validate(steps), isEmpty);
  });
}
