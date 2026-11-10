import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';

/// Shared credit cards for desktop and mobile leave balances.
/// Optional [compact] mode keeps balances and totals together.
class LeaveBalanceCards extends StatelessWidget {
  const LeaveBalanceCards({
    super.key,
    required this.balances,
    this.compact = false,
  });
  final List<LeaveBalance> balances;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final minimumWidth = 280 * textScale.clamp(1.0, 1.5);
        final columns =
            balances.length > 1 && constraints.maxWidth >= minimumWidth * 2 + 16
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: balances
              .map(
                (balance) => SizedBox(
                  width: width,
                  child: LeaveBalanceCard(
                    key: ValueKey(
                      'leave-credit-card-${balance.effectiveLeaveTypeName}',
                    ),
                    balance: balance,
                    compact: compact,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({
    super.key,
    required this.balance,
    this.compact = false,
    this.headerAction,
  });
  final LeaveBalance balance;
  final bool compact;
  final Widget? headerAction;

  String _days(double value) => value == 0
      ? '0'
      : value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavyDark;
    final availableColor = balance.availableDays < 0
        ? Theme.of(context).colorScheme.error
        : balance.availableDays == 0
        ? AppTheme.dashTextSecondaryOf(context)
        : accent;
    if (compact) return _compactCard(context, accent, availableColor);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.dashPanelOf(context),
            Color.alphaBlend(
              AppTheme.primaryNavy.withValues(alpha: dark ? 0.07 : 0.045),
              AppTheme.dashPanelOf(context),
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: dark ? 0.25 : 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.12 : 0.025),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -44,
            top: -50,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.05),
                    width: 22,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        balance.effectiveLeaveTypeName == 'sickLeave'
                            ? Icons.medical_services_outlined
                            : Icons.beach_access_outlined,
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        balance.leaveTypeLabel,
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (headerAction != null) ...[
                      const SizedBox(width: 8),
                      headerAction!,
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Available',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _days(balance.availableDays),
                          style: TextStyle(
                            color: availableColor,
                            fontSize: 38,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'days',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CreditStat(
                        label: 'Earned',
                        value: _days(balance.earnedDays),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CreditStat(
                        label: 'Used',
                        value: _days(balance.usedDays),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CreditStat(
                        label: 'Pending',
                        value: _days(balance.pendingDays),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactCard(
    BuildContext context,
    Color accent,
    Color availableColor,
  ) {
    final heading = Text(
      balance.leaveTypeLabel,
      style: TextStyle(
        color: AppTheme.dashTextPrimaryOf(context),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    final available = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Available days',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
          ),
        ),
        Text(
          _days(balance.availableDays),
          style: TextStyle(
            color: availableColor,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
              if (largeText && constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: available),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  Flexible(child: available),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CreditStat(
                  label: 'Earned',
                  value: _days(balance.earnedDays),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CreditStat(
                  label: 'Used',
                  value: _days(balance.usedDays),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CreditStat(
                  label: 'Pending',
                  value: _days(balance.pendingDays),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditStat extends StatelessWidget {
  const _CreditStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
