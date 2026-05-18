import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'leave_status_chip.dart';

class LeaveCard extends StatelessWidget {
  const LeaveCard({
    super.key,
    required this.request,
    required this.onViewDetails,
    required this.onViewHistory,
    this.onCancel,
    this.onTap,
    this.showActions = true,
    this.isSelected = false,
  });

  final LeaveRequest request;
  final VoidCallback onViewDetails;
  final VoidCallback onViewHistory;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;
  final bool showActions;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
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
                          request.leaveTypeLabel,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatRange(request),
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showActions)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: isSelected ? onViewDetails : null,
                              child: const Text('View Details'),
                            ),
                            OutlinedButton(
                              onPressed: isSelected ? onViewHistory : null,
                              child: const Text('View History'),
                            ),
                          ],
                        ),
                      if (showActions) const SizedBox(height: 10),
                      LeaveStatusChip(status: request.status),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaChip(
                    label: 'Days',
                    value:
                        request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
                  ),
                  _MetaChip(
                    label: 'Submitted',
                    value: request.dateFiled != null
                        ? _formatDate(request.dateFiled!)
                        : '—',
                  ),
                ],
              ),
              if (onCancel != null && showActions) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: isSelected ? onCancel : null,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatRange(LeaveRequest request) {
  if (request.startDate == null || request.endDate == null) {
    return 'Date not set';
  }
  return '${_formatDate(request.startDate!)} – ${_formatDate(request.endDate!)}';
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
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
