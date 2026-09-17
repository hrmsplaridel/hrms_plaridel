import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

enum RspApplicantBadgeKind {
  completed,
  approved,
  passed,
  ready,
  inProgress,
  submitted,
  underReview,
  waitingForHr,
  scheduled,
  needsAction,
  rejected,
  failed,
  locked,
}

class RspApplicantStatusBadge extends StatelessWidget {
  const RspApplicantStatusBadge({
    super.key,
    required this.kind,
    this.label,
  });

  final RspApplicantBadgeKind kind;
  final String? label;

  static String defaultLabel(RspApplicantBadgeKind kind) {
    switch (kind) {
      case RspApplicantBadgeKind.completed:
        return 'Completed';
      case RspApplicantBadgeKind.approved:
        return 'Approved';
      case RspApplicantBadgeKind.passed:
        return 'Passed';
      case RspApplicantBadgeKind.ready:
        return 'Ready';
      case RspApplicantBadgeKind.inProgress:
        return 'In Progress';
      case RspApplicantBadgeKind.submitted:
        return 'Submitted';
      case RspApplicantBadgeKind.underReview:
        return 'Under Review';
      case RspApplicantBadgeKind.waitingForHr:
        return 'Waiting for HR';
      case RspApplicantBadgeKind.scheduled:
        return 'Scheduled';
      case RspApplicantBadgeKind.needsAction:
        return 'Needs Action';
      case RspApplicantBadgeKind.rejected:
        return 'Rejected';
      case RspApplicantBadgeKind.failed:
        return 'Failed';
      case RspApplicantBadgeKind.locked:
        return 'Locked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec(kind);
    return Semantics(
      label: label ?? defaultLabel(kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: spec.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: spec.fg.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, size: 13, color: spec.fg),
            const SizedBox(width: 5),
            Text(
              label ?? defaultLabel(kind),
              style: TextStyle(
                color: spec.fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ({Color bg, Color fg, IconData icon}) _spec(RspApplicantBadgeKind k) {
    switch (k) {
      case RspApplicantBadgeKind.completed:
      case RspApplicantBadgeKind.approved:
      case RspApplicantBadgeKind.passed:
        return (
          bg: const Color(0xFFF3FAF4),
          fg: const Color(0xFF2E7D32),
          icon: Icons.check_circle_rounded,
        );
      case RspApplicantBadgeKind.ready:
      case RspApplicantBadgeKind.needsAction:
      case RspApplicantBadgeKind.inProgress:
        return (
          bg: const Color(0xFFFFF4EC),
          fg: AppTheme.primaryNavy,
          icon: k == RspApplicantBadgeKind.inProgress
              ? Icons.timelapse_rounded
              : Icons.play_circle_fill_rounded,
        );
      case RspApplicantBadgeKind.submitted:
      case RspApplicantBadgeKind.underReview:
      case RspApplicantBadgeKind.waitingForHr:
      case RspApplicantBadgeKind.scheduled:
        return (
          bg: const Color(0xFFF5F9FF),
          fg: const Color(0xFF1565C0),
          icon: Icons.info_rounded,
        );
      case RspApplicantBadgeKind.rejected:
      case RspApplicantBadgeKind.failed:
        return (
          bg: const Color(0xFFFFF6F6),
          fg: const Color(0xFFC62828),
          icon: Icons.cancel_rounded,
        );
      case RspApplicantBadgeKind.locked:
        return (
          bg: const Color(0xFFF4F5F7),
          fg: const Color(0xFF6B7280),
          icon: Icons.lock_rounded,
        );
    }
  }
}
