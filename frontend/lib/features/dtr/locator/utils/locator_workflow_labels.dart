// Use the request's saved route, never the type's current routing settings.
String locatorApprovedStatusLabel(String? finalReviewRoute) =>
    switch (finalReviewRoute?.trim().toLowerCase()) {
      'mayor_direct' => 'Approved by Mayor',
      'mayor' => 'Approved for manual Mayor signing',
      'hr' => 'Approved by HR',
      _ => 'Approved',
    };

String locatorFinalRejectionLabel(String? finalReviewRoute) =>
    switch (finalReviewRoute?.trim().toLowerCase()) {
      'mayor_direct' => 'Rejected by Mayor',
      'hr' => 'Rejected by HR',
      _ => 'Rejected',
    };

String locatorDepartmentApprovalMessage(Map<String, dynamic>? result) {
  final status = result?['status']?.toString().trim().toLowerCase();
  final route = result?['final_review_route']?.toString().trim().toLowerCase();
  return switch (status) {
    'pending_hr' || 'pending' => 'Approved and sent to HR for final approval.',
    'pending_mayor' => 'Department approved. Awaiting Mayor approval.',
    'approved' when route == 'mayor' =>
      'Department approved. Obtain the Mayor’s signature on the printed form.',
    'approved' => '${locatorApprovedStatusLabel(route)}.',
    _ => 'Request updated successfully.',
  };
}
