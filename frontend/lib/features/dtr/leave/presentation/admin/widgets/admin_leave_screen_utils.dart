import 'package:hrms_plaridel/features/dtr/leave/utils/leave_workflow_labels.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

InputDecoration adminLeaveInputDecoration(BuildContext context, String label) {
  return AppTheme.dashInputDecoration(context, labelText: label, radius: 12);
}

double? parseAdminLeaveDouble(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

String? validateAdminLeaveAdjustment(
  String? value, {
  double currentAdjustedDays = 0,
}) {
  const maxDays = 9999999.999; // Backend leave_balances NUMERIC(10,3).
  final text = value?.trim() ?? '';
  final parsed = parseAdminLeaveDouble(text);
  if (parsed == null) return 'Enter the number of days to adjust';
  if (!parsed.isFinite || parsed.abs() > maxDays) {
    return 'Adjustment must be between -9,999,999.999 and 9,999,999.999 days';
  }
  if (parsed == 0) return 'Adjustment must not be zero';
  if (!RegExp(r'^[+-]?\d+(?:\.\d{1,3})?$').hasMatch(text)) {
    return 'Use up to 3 decimal places';
  }
  final currentUnits = currentAdjustedDays * 1000;
  if (!currentUnits.isFinite ||
      (currentUnits.round() + (parsed * 1000).round()).abs() > 9999999999) {
    return 'The resulting adjusted balance exceeds the supported range';
  }
  return null;
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
  final reviewedAt = request.isPaperRecord
      ? DateTime.tryParse(
              request.paperApprovalRecord?['encoded_at']?.toString() ?? '',
            ) ??
            request.createdAt
      : request.approvedAt ?? request.reviewedAt;
  if (reviewedAt == null) return null;
  return reviewedAt.add(adminLeaveRevokeWindow);
}

String? adminLeaveRevokeDisabledReason(LeaveRequest request, {DateTime? now}) {
  if (request.status != LeaveRequestStatus.approved) return null;
  final deadline = adminLeaveRevokeDeadline(request);
  if (deadline == null) {
    return request.isPaperRecord
        ? 'The paper recording time is unavailable.'
        : 'Cannot determine the final approval date for this request.';
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
  String finalReviewRoute = 'hr',
  Map<String, dynamic>? workflowSnapshot,
  bool paperRecorded = false,
}) {
  if (paperRecorded && status == LeaveRequestStatus.approved) {
    return 'Approved (paper record)';
  }
  if (paperRecorded && status == LeaveRequestStatus.cancelled) {
    return 'Revoked (paper record)';
  }
  final named = leavePendingStepLabel(workflowSnapshot);
  if (status.isPending && named != null) return 'Pending $named';
  if (status == LeaveRequestStatus.approved) {
    return leaveApprovedStatusLabel(
      finalReviewRoute,
      workflowSnapshot: workflowSnapshot,
    );
  }
  if (!isDepartmentHead) return status.displayName;
  return switch (status) {
    LeaveRequestStatus.pendingDepartmentHead => 'Pending',
    LeaveRequestStatus.pendingMayor => 'Forwarded to Mayor',
    LeaveRequestStatus.pendingHr => 'Forwarded for review',
    LeaveRequestStatus.rejectedByDepartmentHead => 'Rejected',
    LeaveRequestStatus.rejectedByHr => 'Rejected',
    LeaveRequestStatus.returned => 'Returned',
    LeaveRequestStatus.cancelled => 'Cancelled',
    _ => status.displayName,
  };
}
