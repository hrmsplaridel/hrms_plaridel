import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';

class EmployeeLeaveMobileBalancesPanel extends StatelessWidget {
  const EmployeeLeaveMobileBalancesPanel({
    super.key,
    required this.balances,
    required this.loading,
    required this.onBalanceHistory,
  });

  final List<LeaveBalance> balances;
  final bool loading;
  final VoidCallback onBalanceHistory;

  static const _creditTypes = {'vacationLeave', 'sickLeave'};

  @override
  Widget build(BuildContext context) {
    final creditBalances = balances
        .where((b) => _creditTypes.contains(b.effectiveLeaveTypeName))
        .toList();
    final dayBalances = balances;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Credits section (Sick + Vacation) ────────────────────────────
        Row(
          children: [
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        if (loading && creditBalances.isEmpty)
          const _MobileCenteredState(message: 'Loading leave credits...')
        else if (creditBalances.isEmpty)
          const _MobileCenteredState(
            message: 'No leave credits available yet.',
          )
        else
          Column(
            children: List.generate(creditBalances.length, (index) {
              final balance = creditBalances[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == creditBalances.length - 1 ? 0 : 12,
                ),
                child: _MobileLeaveBalanceCard(balance: balance),
              );
            }),
          ),

        // ── Leave Remaining Days section ──────────────────────────────────
        if (dayBalances.isNotEmpty || loading) ...[  
          const SizedBox(height: 24),
          Text(
            'Leave Remaining Days',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Annual quota days remaining per leave type.',
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
              children: List.generate(dayBalances.length, (index) {
                final balance = dayBalances[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == dayBalances.length - 1 ? 0 : 12,
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

class _MobileLeaveBalanceCard extends StatelessWidget {
  const _MobileLeaveBalanceCard({required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final accent = _leaveBalanceAccent(balance.leaveType);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.dashIsDark(context) ? 0.28 : 0.035,
            ),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  balance.leaveTypeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 18) / 4;
              return Row(
                children: [
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Earned',
                    value: balance.earnedDays.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 6),
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Used',
                    value: balance.usedDays.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 6),
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Pending',
                    value: balance.pendingDays.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 6),
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Available',
                    value: balance.availableDays.toStringAsFixed(1),
                    accent: accent,
                    emphasized: true,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MobileBalanceStatTile extends StatelessWidget {
  const _MobileBalanceStatTile({
    required this.width,
    required this.label,
    required this.value,
    this.accent,
    this.emphasized = false,
  });

  final double width;
  final String label;
  final String value;
  final Color? accent;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? AppTheme.dashTextPrimaryOf(context);
    return SizedBox(
      width: width,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: emphasized
              ? effectiveAccent.withValues(
                  alpha: AppTheme.dashIsDark(context) ? 0.18 : 0.10,
                )
              : AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: emphasized
                      ? effectiveAccent
                      : AppTheme.dashTextSecondaryOf(context),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: emphasized
                      ? effectiveAccent
                      : AppTheme.dashTextPrimaryOf(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
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

Color _leaveBalanceAccent(LeaveType type) {
  return switch (type) {
    LeaveType.sickLeave => const Color(0xFFE53935),
    LeaveType.vacationLeave => AppTheme.primaryNavyLight,
    LeaveType.maternityLeave => const Color(0xFFD81B60),
    LeaveType.paternityLeave => const Color(0xFF5E35B1),
    LeaveType.specialPrivilegeLeave => const Color(0xFF00897B),
    LeaveType.soloParentLeave => const Color(0xFF3949AB),
    LeaveType.studyLeave => const Color(0xFF1E88E5),
    LeaveType.tenDayVawcLeave => const Color(0xFF8E24AA),
    LeaveType.rehabilitationPrivilege => const Color(0xFF43A047),
    LeaveType.specialLeaveBenefitsForWomen => const Color(0xFFC2185B),
    LeaveType.specialEmergencyCalamityLeave => const Color(0xFFF4511E),
    LeaveType.adoptionLeave => const Color(0xFF6D4C41),
    LeaveType.mandatoryForcedLeave => const Color(0xFFFB8C00),
    LeaveType.others => AppTheme.primaryNavy,
  };
}
