import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_request.dart';

InputDecoration adminLeaveInputDecoration(BuildContext context, String label) {
  return AppTheme.dashInputDecoration(
    context,
    labelText: label,
    radius: 12,
  );
}

double? parseAdminLeaveDouble(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

String? trimAdminLeaveOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String formatAdminLeaveDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String adminLeaveStatusLabel(
  LeaveRequestStatus status, {
  required bool isDepartmentHead,
}) {
  if (!isDepartmentHead) return status.displayName;
  return switch (status) {
    LeaveRequestStatus.pendingDepartmentHead => 'Pending',
    LeaveRequestStatus.pendingHr => 'Forwarded to HR',
    LeaveRequestStatus.approved => 'Approved by HR',
    LeaveRequestStatus.rejectedByDepartmentHead => 'Rejected',
    LeaveRequestStatus.rejectedByHr => 'Rejected by HR',
    LeaveRequestStatus.returned => 'Returned',
    LeaveRequestStatus.cancelled => 'Cancelled',
    _ => status.displayName,
  };
}
