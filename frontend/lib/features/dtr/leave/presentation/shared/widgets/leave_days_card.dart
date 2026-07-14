import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';

/// A compact card that shows remaining days for an annual-quota leave type.
/// Distinct from [LeaveBalanceCard] which is for accrual-based credits.
class LeaveDaysCard extends StatelessWidget {
  const LeaveDaysCard({super.key, required this.balance});

  final LeaveBalance balance;

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final remaining = balance.availableDays;
    final total = balance.earnedDays;
    final isMandatory =
        balance.effectiveLeaveTypeName == 'mandatoryForcedLeave';
    final isCalamity =
        balance.effectiveLeaveTypeName == 'specialEmergencyCalamityLeave';
    final displayedRemaining = isMandatory
        ? (total - balance.usedDays).clamp(0, total).toDouble()
        : remaining;

    // Color the remaining chip: green when plenty left, amber when low, red when zero
    Color accentColor;
    if (displayedRemaining <= 0) {
      accentColor = const Color(0xFFD32F2F);
    } else if (total > 0 && displayedRemaining / total <= 0.33) {
      accentColor = const Color(0xFFF57C00);
    } else {
      accentColor = const Color(0xFF2E7D32);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Leave type name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMandatory
                      ? 'Mandatory/Forced Leave Compliance'
                      : balance.leaveTypeLabel,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Pip(
                      label: isMandatory
                          ? 'Required'
                          : (isCalamity ? 'Maximum' : 'Entitlement'),
                      value: _fmt(total),
                      context: context,
                    ),
                    const SizedBox(width: 8),
                    if (balance.usedDays > 0) ...[
                      _Pip(
                        label: isMandatory ? 'Taken' : 'Used',
                        value: _fmt(balance.usedDays),
                        context: context,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (balance.pendingDays > 0)
                      _Pip(
                        label: isMandatory ? 'Scheduled' : 'Pending',
                        value: _fmt(balance.pendingDays),
                        context: context,
                      ),
                  ],
                ),
                if (isMandatory) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Charged against Vacation Leave credits.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 10,
                    ),
                  ),
                ],
                if (isCalamity) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Subject to a qualifying calamity, supporting documents, and approval.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Prominent remaining days chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: dark ? 0.22 : 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  isCalamity
                      ? 'Up to ${_fmt(total)}'
                      : _fmt(displayedRemaining),
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isMandatory
                      ? (displayedRemaining == 1
                            ? 'day required'
                            : 'days required')
                      : isCalamity
                      ? (total == 1 ? 'day' : 'days')
                      : (remaining == 1 ? 'day available' : 'days available'),
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({required this.label, required this.value, required this.context});

  final String label;
  final String value;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(ctx),
          fontSize: 11,
        ),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
