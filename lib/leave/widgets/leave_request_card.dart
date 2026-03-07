import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'leave_status_chip.dart';

class LeaveRequestCard extends StatelessWidget {
  const LeaveRequestCard({
    super.key,
    required this.request,
    this.selected = false,
    this.onTap,
    this.variant = LeaveRequestCardVariant.employee,
    this.showReason = true,
  });

  final LeaveRequest request;
  final bool selected;
  final VoidCallback? onTap;
  final LeaveRequestCardVariant variant;
  final bool showReason;

  @override
  Widget build(BuildContext context) {
    final title = variant == LeaveRequestCardVariant.adminQueue
        ? (request.employeeName ?? 'Unknown employee')
        : request.leaveType.displayName;
    final subtitle = variant == LeaveRequestCardVariant.adminQueue
        ? request.leaveType.displayName
        : _formatRange(request);

    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.primaryNavy.withOpacity(0.08)
            : AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppTheme.primaryNavy.withOpacity(0.22)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              LeaveStatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DetailPill(
                label: variant == LeaveRequestCardVariant.adminQueue
                    ? 'Filed'
                    : 'Days',
                value: variant == LeaveRequestCardVariant.adminQueue
                    ? (request.dateFiled != null
                          ? _formatDate(request.dateFiled!)
                          : '—')
                    : (request.workingDaysApplied?.toStringAsFixed(1) ?? '—'),
              ),
              _DetailPill(
                label: variant == LeaveRequestCardVariant.adminQueue
                    ? 'Days'
                    : 'Filed',
                value: variant == LeaveRequestCardVariant.adminQueue
                    ? (request.workingDaysApplied?.toStringAsFixed(1) ?? '—')
                    : (request.dateFiled != null
                          ? _formatDate(request.dateFiled!)
                          : '—'),
              ),
            ],
          ),
          if (showReason && (request.reason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              request.reason!.trim(),
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }

  String _formatRange(LeaveRequest request) {
    if (request.startDate == null || request.endDate == null) {
      return 'Date not set';
    }
    return '${_formatDate(request.startDate!)} to ${_formatDate(request.endDate!)}';
  }
}

enum LeaveRequestCardVariant {
  employee,
  adminQueue,
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
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
