import 'package:hrms_plaridel/features/docutracker/models/document_action.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permission_service.dart';

/// Maps backend `reason` codes from permission-explain to user-facing text.
String docuTrackerPermissionReasonLabel(
  DocuTrackerPermissionExplanation explanation, {
  required DocumentAction action,
}) {
  if (explanation.granted) {
    return switch (explanation.reason) {
      'admin_override' => 'Allowed (administrator).',
      'current_holder' => 'You are the current reviewer for this document.',
      'step_assignee' => 'You are assigned to the current workflow step.',
      'creator' => 'You created this document.',
      'explicit_permission' => 'Allowed by your assigned permissions.',
      'past_participant' => 'You participated earlier in this routing.',
      _ => 'You can perform this action.',
    };
  }

  final code = (explanation.reason ?? '').trim();
  final actionName = action.displayName.toLowerCase();

  return switch (code) {
    'not_assigned_to_step' =>
      'You are not the current reviewer or step assignee, so you cannot $actionName.',
    'assigned_but_action_not_allowed' =>
      'You are on this step, but your role is not allowed to $actionName.',
    'relationship_required' =>
      'You must be the creator, current reviewer, or a step assignee to $actionName.',
    'explicit_permission' => 'Your account is not permitted to $actionName.',
    'workflow_action_requires_document' =>
      'Open a specific document to check $actionName permission.',
    'explain_failed' => 'Could not verify permission. Try again or contact HR.',
    'fallback_rule' =>
      'No permission rule grants $actionName for this document type.',
    _ =>
      code.isNotEmpty
          ? 'Cannot $actionName ($code).'
          : 'Cannot $actionName with your current access.',
  };
}
