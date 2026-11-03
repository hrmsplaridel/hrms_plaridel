import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_workflow_labels.dart';

void main() {
  test('approval badges do not infer a reviewer role from the internal route', () {
    expect(locatorApprovedStatusLabel('hr'), 'Approved');
    expect(locatorApprovedStatusLabel('mayor_direct'), 'Approved');
    expect(locatorFinalRejectionLabel('hr'), 'Rejected');
    expect(locatorFinalRejectionLabel('mayor_direct'), 'Rejected');
  });

  test('next-step feedback uses the saved specific-reviewer step', () {
    expect(locatorDepartmentApprovalMessage({
      'status': 'pending_hr',
      'final_review_route': 'hr',
      'workflow_snapshot': {
        'current_step': 1,
        'steps': [
          {'label': 'First Step', 'assignee_source': 'specific_users'},
          {'label': 'Records verification', 'assignee_source': 'specific_users'},
        ],
      },
    }), 'Step approved. Forwarded to Records verification.');
  });

  test('legacy pending feedback stays neutral when no saved step is available', () {
    expect(locatorDepartmentApprovalMessage({
      'status': 'pending_hr', 'final_review_route': 'hr',
    }), 'Step approved. Forwarded for further review.');
  });

  test('manual signing still tells the user to obtain the paper signature', () {
    expect(locatorApprovedStatusLabel('mayor'), 'Approved for manual Mayor signing');
    expect(locatorDepartmentApprovalMessage({
      'status': 'approved', 'final_review_route': 'mayor',
    }), 'Approved. Obtain the Mayor’s signature on the printed form.');
  });

  test('a saved custom step overrides the legacy manual route hint', () {
    expect(locatorApprovedStatusLabel('mayor', workflowSnapshot: {
      'steps': [{'label': 'Records verification', 'assignee_source': 'specific_users'}],
    }), 'Approved');
  });

  test('submission feedback follows saved steps for shared and legacy workflows', () {
    expect(locatorSubmissionMessage({
      'workflow_snapshot': {
        'current_step': 0,
        'steps': [{'label': 'Records verification', 'assignee_source': 'specific_users'}],
      },
    }), 'Request submitted. Awaiting Records verification.');
    expect(locatorSubmissionMessage({
      'workflow_snapshot': {'current_step': 0, 'steps': ['department', 'hr']},
    }), 'Request submitted. Awaiting Department Review.');
    expect(locatorSubmissionMessage(null), 'Request submitted successfully.');
  });

  test('completed and invalid snapshots do not invent a pending step', () {
    for (final snapshot in [
      {'current_step': -1, 'steps': ['hr']},
      {'current_step': 1, 'steps': ['hr']},
      {'current_step': 0, 'steps': ['hr'], 'outcome': 'approved'},
    ]) {
      expect(locatorPendingStepLabel(snapshot), isNull);
    }
  });
}
