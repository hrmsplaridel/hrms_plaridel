import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';

/// A compact card showing approved usage against a yearly limit or requirement.
/// Distinct from [LeaveBalanceCard] which is for accrual-based credits.
class LeaveDaysCard extends StatelessWidget {
  const LeaveDaysCard({super.key, required this.balance});

  final LeaveBalance balance;

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final remaining = balance.usageRemainingDays;
    final total = balance.earnedDays;
    final displayedRemaining = remaining.clamp(0, total).toDouble();

    // Color the remaining chip: green when plenty left, amber when low, red when zero
    Color accentColor;
    if (balance.isComplianceProgress) {
      accentColor = !balance.historyVerificationRequired && displayedRemaining <= 0 ? const Color(0xFF2E7D32) : const Color(0xFFF57C00);
    } else if (displayedRemaining <= 0) {
      accentColor = const Color(0xFFD32F2F);
    } else if (total > 0 && displayedRemaining / total <= 0.33) {
      accentColor = const Color(0xFFF57C00);
    } else {
      accentColor = const Color(0xFF2E7D32);
    }

    return Container(
      key: ValueKey('leave-balance-row-${balance.effectiveLeaveTypeName}'),
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
                  balance.leaveTypeLabel,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                if (balance.prorated)
                  Text(
                    'First-year allowance rounded down to whole days',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 10,
                    ),
                  ),
                if (balance.eligibilityMessage != null)
                  Text(
                    balance.eligibilityMessage!,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 10,
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Pip(
                      label: balance.isComplianceProgress ? 'Required' : 'Limit',
                      value: _fmt(balance.annualEntitlementDays),
                      context: context,
                    ),
                    if (balance.prorated)
                      _Pip(
                        label: 'Prorated',
                        value: _fmt(total),
                        context: context,
                      ),
                    _Pip(
                        label: 'Taken',
                        value: _fmt(balance.usedDays),
                        context: context,
                      ),
                  ],
                ),
                if (balance.entitlementYear != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Calendar year ${balance.entitlementYear}',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 10,
                    ),
                  ),
                ],
                if (balance.isComplianceProgress)
                  Text('Includes approved Forced and Vacation Leave. Charged to VL credits.',
                    style: TextStyle(color: AppTheme.dashTextSecondaryOf(context),fontSize:10)),
                if (balance.usageStatusLabel != null)
                  Text(balance.usageStatusLabel!,style:TextStyle(color:accentColor,fontSize:11,fontWeight:FontWeight.w600)),
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
                  balance.historyVerificationRequired ? '—' : _fmt(displayedRemaining),
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  balance.historyVerificationRequired ? 'Unverified' : balance.isComplianceProgress ? 'Still required' : 'Remaining',
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
