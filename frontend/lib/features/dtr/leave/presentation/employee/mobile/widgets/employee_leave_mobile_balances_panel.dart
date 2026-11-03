import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_usage_details_panel.dart';

class EmployeeLeaveMobileBalancesPanel extends StatelessWidget {
  const EmployeeLeaveMobileBalancesPanel({
    super.key,
    this.showCredits = true,
    required this.balances,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onBalanceHistory,
  });

  final bool showCredits;
  final List<LeaveBalance> balances;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onBalanceHistory;

  static const _creditTypes = {'vacationLeave', 'sickLeave'};
  @override
  Widget build(BuildContext context) {
    final creditBalances = balances
        .where((b) => _creditTypes.contains(b.effectiveLeaveTypeName))
        .toList();
    final dayBalances = balances
        .where((balance) => balance.isUsageSummary)
        .toList();
    final previewBalances = dayBalances.take(leaveUsagePreviewLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Credits section (Sick + Vacation) ────────────────────────────
        if (showCredits) ...[
          Row(
            children: [
              if (showCredits)
                Expanded(
                  child: Text(
                    'Leave Credits',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
              TextButton(
                onPressed: onBalanceHistory,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavyDark,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Credit History',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (error != null) ...[
          _MobileBalanceLoadError(message: error!, onRetry: onRetry),
          if (balances.isNotEmpty) const SizedBox(height: 12),
        ],
        if (showCredits && loading && creditBalances.isEmpty)
          const _MobileCenteredState(message: 'Loading leave credits...')
        else if (showCredits && error == null && creditBalances.isEmpty)
          const _MobileCenteredState(message: 'No leave credits available yet.')
        else if (showCredits && creditBalances.isNotEmpty)
          LeaveBalanceCards(balances: creditBalances),

        // ── Leave Remaining Days section ──────────────────────────────────
        if (dayBalances.isNotEmpty || loading) ...[
          if (showCredits) const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Leave Usage & Limits',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              if (dayBalances.length > leaveUsagePreviewLimit)
                TextButton(
                  onPressed: () => showLeaveUsageDetails(
                    context: context,
                    balances: dayBalances,
                  ),
                  child: Text('View all (${dayBalances.length})'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Approved days taken toward your yearly limits and requirements.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          if (loading && dayBalances.isEmpty)
            const _MobileCenteredState(message: 'Loading leave days...')
          else
            Column(
              children: List.generate(previewBalances.length, (index) {
                final balance = previewBalances[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == previewBalances.length - 1 ? 0 : 12,
                  ),
                  child: LeaveDaysCard(balance: balance),
                );
              }),
            ),
        ],
      ],
    );
  }
}

class _MobileBalanceLoadError extends StatelessWidget {
  const _MobileBalanceLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Retry',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _MobileCenteredState extends StatelessWidget {
  const _MobileCenteredState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
