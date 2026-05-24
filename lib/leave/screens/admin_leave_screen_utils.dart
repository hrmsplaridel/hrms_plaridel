import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_request.dart';

InputDecoration adminLeaveInputDecoration(BuildContext context, String label) {
  return AppTheme.dashInputDecoration(context, labelText: label, radius: 12);
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

String formatAdminLeaveDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '${formatAdminLeaveDate(value)} $hour:$minute $suffix';
}

const adminLeaveRevokeWindow = Duration(days: 3);

DateTime? adminLeaveRevokeDeadline(LeaveRequest request) {
  final reviewedAt = request.reviewedAt;
  if (reviewedAt == null) return null;
  return reviewedAt.add(adminLeaveRevokeWindow);
}

String? adminLeaveRevokeDisabledReason(LeaveRequest request, {DateTime? now}) {
  if (request.status != LeaveRequestStatus.approved) return null;
  final deadline = adminLeaveRevokeDeadline(request);
  if (deadline == null) {
    return 'Cannot determine the HR approval date for this request.';
  }
  final effectiveNow = now ?? DateTime.now();
  if (effectiveNow.isAfter(deadline)) {
    return 'Revoke period expired on ${formatAdminLeaveDateTime(deadline)}.';
  }
  return null;
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
