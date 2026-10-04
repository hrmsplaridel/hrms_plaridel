import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_action.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permission_service.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_permission_reason_label.dart';

DocuTrackerPermissionExplanation _denied(String reason) =>
    DocuTrackerPermissionExplanation(
      granted: false,
      source: DocuTrackerPermissionSource.stepAssignee,
      matchedDocumentType: 'memo',
      matchedRoleId: null,
      reason: reason,
    );

void main() {
  test(
    'a step assignee blocked by a workflow rule is not told they are unassigned',
    () {
      final label = docuTrackerPermissionReasonLabel(
        _denied('blocked_by_workflow_rule'),
        action: DocumentAction.approve,
      );
      expect(label, startsWith('You are on this step'));
      expect(label, isNot(contains('not the current reviewer')));
    },
  );

  test('an unassigned user is told they are not on the step', () {
    final label = docuTrackerPermissionReasonLabel(
      _denied('not_assigned_to_step'),
      action: DocumentAction.approve,
    );
    expect(label, contains('not the current reviewer or step assignee'));
  });
}
