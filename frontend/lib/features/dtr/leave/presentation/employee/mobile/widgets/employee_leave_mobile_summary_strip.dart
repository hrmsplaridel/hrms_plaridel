import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

class EmployeeLeaveMobileSummaryStrip extends StatelessWidget {
  const EmployeeLeaveMobileSummaryStrip({
    super.key,
    required this.totalAvailable,
    required this.pendingCount,
    required this.totalPendingDays,
    required this.nextApproved,
  });

  final double totalAvailable;
  final int pendingCount;
  final double totalPendingDays;
  final LeaveRequest? nextApproved;

  @override
  Widget build(BuildContext context) {
    final nextLabel = nextApproved?.leaveTypeLabel ?? 'None';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _MobileSummaryCard(
            title: 'Available Credits',
            value: totalAvailable.toStringAsFixed(1),
            icon: Icons.account_balance_wallet_outlined,
            accent: AppTheme.primaryNavy,
          ),
          const SizedBox(width: 12),
          _MobileSummaryCard(
            title: 'Pending Requests',
            value: '$pendingCount',
            icon: Icons.pending_actions_outlined,
            accent: const Color(0xFF795548),
            footer: totalPendingDays > 0
                ? '${totalPendingDays.toStringAsFixed(1)} day(s)'
                : null,
          ),
          const SizedBox(width: 12),
          _MobileSummaryCard(
            title: 'Next Approved',
            value: nextLabel,
            icon: Icons.event_available_outlined,
            accent: const Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }
}

class _MobileSummaryCard extends StatelessWidget {
  const _MobileSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.footer,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: 138,
      height: 96,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.045),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: value.length > 6 ? 18 : 25,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 3),
            Text(
              footer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
