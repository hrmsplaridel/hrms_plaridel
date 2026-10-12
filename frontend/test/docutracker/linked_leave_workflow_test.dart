import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/linked_leave_workflow.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';

void main() {
  test('parses mirrored DTR leave steps, reviewers, and history', () {
    final workflow = LinkedLeaveWorkflow.fromJson({
      'current_step': null,
      'steps': [
        {
          'step_order': 1,
          'label': 'Department Review',
          'indicator': {'kind': 'cancelled', 'label': 'CANCELLED'},
          'reviewers': [
            {'id': 'head-1', 'name': 'Dana Head', 'role': 'primary'},
            {'id': 'head-2', 'name': 'Ben Backup', 'role': 'backup'},
          ],
        },
        {
          'step_order': 2,
          'label': 'Final HR Review',
          'indicator': {'kind': 'upcoming', 'label': 'WAITING'},
          'reviewers': <Object>[],
        },
      ],
      'history': [
        {
          'id': 'h1',
          'document_id': 'source:dtr:leave-1',
          'action': 'saved_draft',
          'actor_name': 'Amy Applicant',
          'from_status': null,
          'to_status': 'draft',
          'created_at': '2026-09-15T06:49:39.595Z',
        },
        {
          'id': 'h2',
          'document_id': 'source:dtr:leave-1',
          'action': 'cancelled',
          'from_status': 'in_review',
          'to_status': 'cancelled',
          'created_at': '2026-09-15T06:52:37.249Z',
        },
      ],
    });

    expect(workflow.steps.map((s) => s.label), [
      'Department Review',
      'Final HR Review',
    ]);
    expect(
      workflow.steps.first.indicator.kind,
      DocuTrackerStepIndicatorKind.cancelled,
    );
    expect(workflow.steps.first.reviewers.last.isBackup, isTrue);
    expect(workflow.steps.last.reviewers, isEmpty);

    final draft = workflow.history.first;
    expect(draft.fromStatus, isNull);
    expect(draft.toStatus, isNull, reason: 'draft must not show as Pending');
    final cancelled = workflow.history.last;
    expect(cancelled.fromStatus, DocumentStatus.inReview);
    expect(cancelled.toStatus, DocumentStatus.cancelled);
    expect(cancelled.createdAt, isNotNull);
  });

  test('unknown indicator kinds fall back to upcoming', () {
    final step = LinkedLeaveWorkflowStep.fromJson({
      'step_order': 1,
      'label': 'Department Review',
      'indicator': {'kind': 'mystery', 'label': 'NOT REQUIRED'},
    });
    expect(step.indicator.kind, DocuTrackerStepIndicatorKind.upcoming);
    expect(step.indicator.label, 'NOT REQUIRED');
    expect(step.reviewers, isEmpty);
  });
}
