// Internal routes also represent specific-person steps; they do not identify HR.
// Use the request's saved workflow, never the type's current configuration.
String locatorApprovedStatusLabel(
  String? finalReviewRoute, {
  Map<String, dynamic>? workflowSnapshot,
}) {
  final steps = workflowSnapshot?['steps'];
  final last = steps is List && steps.isNotEmpty ? steps.last : null;
  final source = last is Map ? last['assignee_source'] : last;
  final manual =
      source == 'manual_mayor' ||
      (source == null && finalReviewRoute?.trim().toLowerCase() == 'mayor');
  return manual ? 'Approved for manual Mayor signing' : 'Approved';
}

String locatorFinalRejectionLabel(String? finalReviewRoute) => 'Rejected';

String? locatorPendingStepLabel(Map<String, dynamic>? snapshot) {
  if (snapshot?['outcome'] != null) return null;
  final steps = snapshot?['steps'];
  final index = snapshot?['current_step'];
  if (steps is! List || index is! int || index < 0 || index >= steps.length) {
    return null;
  }
  final step = steps[index];
  final label = step is Map
      ? step['label']?.toString().trim()
      : switch (step) {
          'department' => 'Department Review',
          'hr' => 'HR Review',
          'mayor' => 'Mayor Approval',
          'manual_mayor' => 'Manual Mayor Signing',
          _ => null,
        };
  return label == null || label.isEmpty ? null : label;
}

String locatorSubmissionMessage(Map<String, dynamic>? result) {
  final snapshot = result?['workflow_snapshot'];
  final label = locatorPendingStepLabel(
    snapshot is Map ? Map<String, dynamic>.from(snapshot) : null,
  );
  return label == null
      ? 'Request submitted successfully.'
      : 'Request submitted. Awaiting $label.';
}

String locatorDepartmentApprovalMessage(Map<String, dynamic>? result) {
  final status = result?['status']?.toString().trim().toLowerCase();
  final route = result?['final_review_route']?.toString().trim().toLowerCase();
  final rawSnapshot = result?['workflow_snapshot'];
  final snapshot = rawSnapshot is Map
      ? Map<String, dynamic>.from(rawSnapshot)
      : null;
  final next = locatorPendingStepLabel(snapshot);
  if (status != null && status.startsWith('pending') && next != null) {
    return 'Step approved. Forwarded to $next.';
  }
  return switch (status) {
    'pending_hr' || 'pending' => 'Step approved. Forwarded for further review.',
    'pending_mayor' => 'Step approved. Awaiting Mayor approval.',
    'approved'
        when locatorApprovedStatusLabel(route, workflowSnapshot: snapshot) ==
            'Approved for manual Mayor signing' =>
      'Approved. Obtain the Mayor’s signature on the printed form.',
    'approved' => 'Request approved.',
    _ => 'Request updated successfully.',
  };
}
