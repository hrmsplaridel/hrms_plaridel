import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_balance.dart';
import '../models/leave_type.dart';

class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({
    super.key,
    required this.balance,
  });

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            balance.leaveType.displayName,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniStatChip(
                label: 'Earned',
                value: balance.earnedDays.toStringAsFixed(1),
              ),
              _MiniStatChip(
                label: 'Used',
                value: balance.usedDays.toStringAsFixed(1),
              ),
              _MiniStatChip(
                label: 'Pending',
                value: balance.pendingDays.toStringAsFixed(1),
              ),
              _MiniStatChip(
                label: 'Available',
                value: balance.availableDays.toStringAsFixed(1),
                emphasize: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasize
            ? AppTheme.primaryNavy.withOpacity(0.10)
            : AppTheme.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasize
              ? AppTheme.primaryNavy.withOpacity(0.25)
              : Colors.black.withOpacity(0.06),
        ),
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
              color: emphasize ? AppTheme.primaryNavyDark : AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
