import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';

/// Read-only usage summaries; wrapping cards keep long names and larger text visible.
class LeaveUsageGrid extends StatelessWidget {
  const LeaveUsageGrid({super.key, required this.balances});
  final List<LeaveBalance> balances;

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
            .clamp(1.0, 1.5);
        final columns =
            balances.length > 1 &&
                constraints.maxWidth >= 340 * textScale * 2 + 16
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          key: const ValueKey('leave-usage-grid'),
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final balance in balances)
              SizedBox(
                width: width,
                child: _LeaveUsageCard(balance: balance),
              ),
          ],
        );
      },
    );
  }
}

class _LeaveUsageCard extends StatelessWidget {
  const _LeaveUsageCard({required this.balance});
  final LeaveBalance balance;
  String _days(double value) => value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final values = <String, String>{
      balance.isComplianceProgress ? 'Required' : 'Limit': _days(
        balance.annualEntitlementDays,
      ),
      if (balance.prorated) 'Prorated': _days(balance.earnedDays),
      'Taken': _days(balance.usedDays),
      balance.isComplianceProgress
          ? 'Still required'
          : 'Remaining': balance.historyVerificationRequired
          ? '—'
          : _days(balance.usageRemainingDays),
    };
    return Container(
      key: ValueKey('leave-balance-row-${balance.effectiveLeaveTypeName}'),
      constraints: const BoxConstraints(minHeight: 152),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            balance.leaveTypeLabel,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (balance.entitlementYear != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${balance.entitlementYear}',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, size) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
              final columns = size.maxWidth >= 340 && !largeText
                  ? values.length
                  : 2;
              final width = (size.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in values.entries)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: entry.key == values.keys.last
                                    ? AppTheme.primaryNavy
                                    : AppTheme.dashTextPrimaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          if (balance.prorated ||
              balance.eligibilityMessage != null ||
              balance.isComplianceProgress ||
              balance.usageStatusLabel != null) ...[
            const SizedBox(height: 12),
            if (balance.prorated)
              _note(context, 'First year: rounded down to whole days'),
            if (balance.eligibilityMessage != null)
              _note(context, balance.eligibilityMessage!),
            if (balance.isComplianceProgress)
              _note(
                context,
                'Includes approved Forced and Vacation Leave. Charged to VL credits.',
              ),
            if (balance.usageStatusLabel != null)
              _note(context, balance.usageStatusLabel!, emphasized: true),
          ],
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: emphasized
                ? AppTheme.dashTextPrimaryOf(context)
                : AppTheme.dashTextSecondaryOf(context),
            fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
}
