// Compatibility statuses identify API routes, not the reviewer's office.
String? leavePendingStepLabel(Map<String, dynamic>? snapshot) {
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

String leaveApprovedStatusLabel(
  String? finalReviewRoute, {
  Map<String, dynamic>? workflowSnapshot,
}) {
  final steps = workflowSnapshot?['steps'];
  final last = steps is List && steps.isNotEmpty ? steps.last : null;
  final source = last is Map ? last['assignee_source'] : last;
  final manual =
      source == 'manual_mayor' ||
      (source == null && finalReviewRoute == 'mayor');
  return manual ? 'Approved for manual Mayor signing' : 'Approved';
}

String leaveDepartmentApprovalMessage({
  required String status,
  String? finalReviewRoute,
  Map<String, dynamic>? workflowSnapshot,
}) {
  if (status == 'approved') {
    final label = leaveApprovedStatusLabel(
      finalReviewRoute,
      workflowSnapshot: workflowSnapshot,
    );
    return label == 'Approved for manual Mayor signing'
        ? 'Approved. The Mayor signs the printed form manually.'
        : 'Request approved.';
  }
  final next = leavePendingStepLabel(workflowSnapshot);
  if (status.startsWith('pending') && next != null) {
    return 'Step approved. Forwarded to $next.';
  }
  return switch (status) {
    'pending_mayor' => 'Step approved. Awaiting Mayor approval.',
    'pending_hr' || 'pending' => 'Step approved. Forwarded for further review.',
    _ => 'Request updated successfully.',
  };
}
