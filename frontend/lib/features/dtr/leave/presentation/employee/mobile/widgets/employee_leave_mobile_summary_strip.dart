import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

class EmployeeLeaveMobileSummaryStrip extends StatelessWidget {
  const EmployeeLeaveMobileSummaryStrip({
    super.key,
    required this.pendingCount,
    required this.totalPendingDays,
    required this.nextApproved,
    required this.nextApprovedAvailable,
  });

  final int? pendingCount;
  final double? totalPendingDays;
  final LeaveRequest? nextApproved;
  final bool nextApprovedAvailable;

  @override
  Widget build(BuildContext context) {
    final nextLabel = nextApprovedAvailable
        ? nextApproved?.leaveTypeLabel ?? 'None'
        : 'Unavailable';

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = constraints.maxWidth >= 280 * scale ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _MobileSummaryCard(
                title: 'Pending Requests',
                value: pendingCount?.toString() ?? '--',
                icon: Icons.pending_actions_outlined,
                accent: const Color(0xFF795548),
                footer: (totalPendingDays ?? 0) > 0
                    ? '${totalPendingDays!.toStringAsFixed(1)} day(s)'
                    : null,
              ),
            ),
            SizedBox(
              width: width,
              child: _MobileSummaryCard(
                title: 'Next Approved',
                value: nextLabel,
                icon: Icons.event_available_outlined,
                accent: const Color(0xFF2E7D32),
              ),
            ),
          ],
        );
      },
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
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.045),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
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
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
