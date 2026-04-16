import 'package:flutter/material.dart';

import '../models/leave_request.dart';

class LeaveStatusChip extends StatelessWidget {
  const LeaveStatusChip({
    super.key,
    required this.status,
    this.label,
  });

  final LeaveRequestStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      LeaveRequestStatus.draft => (Colors.grey.shade200, Colors.grey.shade800),
      LeaveRequestStatus.pending => (
          Colors.orange.shade100,
          Colors.orange.shade900,
        ),
      LeaveRequestStatus.pendingDepartmentHead => (
          Colors.amber.shade100,
          Colors.amber.shade900,
        ),
      LeaveRequestStatus.pendingHr => (
          Colors.orange.shade100,
          Colors.orange.shade900,
        ),
      LeaveRequestStatus.rejectedByDepartmentHead => (
          Colors.red.shade50,
          Colors.red.shade800,
        ),
      LeaveRequestStatus.rejectedByHr => (
          Colors.red.shade100,
          Colors.red.shade900,
        ),
      LeaveRequestStatus.returned => (
          Colors.blue.shade100,
          Colors.blue.shade900,
        ),
      LeaveRequestStatus.approved => (
          Colors.green.shade100,
          Colors.green.shade900,
        ),
      LeaveRequestStatus.rejected => (
          Colors.red.shade100,
          Colors.red.shade900,
        ),
      LeaveRequestStatus.cancelled => (
          Colors.grey.shade300,
          Colors.grey.shade800,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? status.displayName,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
