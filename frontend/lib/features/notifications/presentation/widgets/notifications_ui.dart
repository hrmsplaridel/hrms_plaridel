import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';

/// Shared visual system for in-app notification list (bell dropdown + full screen).
class NotificationsUi {
  NotificationsUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;
  static const Color accent = Color(0xFFE85D04);
  static const Color accentSoft = Color(0xFFFFF4EC);

  static BoxDecoration screenCanvas(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF171C28), Color(0xFF12161F), Color(0xFF1A1520)]
            : const [Color(0xFFF7F8FC), Color(0xFFF0F2F7), Color(0xFFFFF8F3)],
        stops: const [0.0, 0.55, 1.0],
      ),
    );
  }

  static PreferredSizeWidget appBarBottomDivider() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              NotificationsUi.accent.withValues(alpha: 0.35),
              AppTheme.primaryNavy.withValues(alpha: 0.2),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact stats row under the app bar.
class NotificationsSummaryStrip extends StatelessWidget {
  const NotificationsSummaryStrip({
    super.key,
    required this.totalCount,
    required this.unreadCount,
  });

  final int totalCount;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final readCount = (totalCount - unreadCount).clamp(0, totalCount);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(NotificationsUi.radiusMd),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  NotificationsUi.accent.withValues(alpha: 0.2),
                  AppTheme.primaryNavy.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: NotificationsUi.accent.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              unreadCount > 0
                  ? Icons.mark_email_unread_rounded
                  : Icons.mark_email_read_outlined,
              color: NotificationsUi.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unreadCount > 0 ? 'You have new updates' : 'Inbox is clear',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: primary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unreadCount > 0
                      ? '$unreadCount unread · $totalCount total'
                      : '$totalCount notification${totalCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: secondary,
                  ),
                ),
              ],
            ),
          ),
          _MetricPill(
            label: 'Unread',
            value: '$unreadCount',
            emphasize: unreadCount > 0,
          ),
          const SizedBox(width: 8),
          _MetricPill(label: 'Read', value: '$readCount', emphasize: false),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.emphasize,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final color = emphasize
        ? NotificationsUi.accent
        : AppTheme.dashTextSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: emphasize
            ? NotificationsUi.accent.withValues(alpha: 0.12)
            : AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize
              ? NotificationsUi.accent.withValues(alpha: 0.28)
              : AppTheme.dashHairlineOf(context),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationSectionHeader extends StatelessWidget {
  const NotificationSectionHeader({super.key, required this.label});

  final String label;

  IconData get _icon => switch (label) {
    'Today' => Icons.wb_sunny_outlined,
    'Yesterday' => Icons.history_rounded,
    _ => Icons.calendar_month_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: NotificationsUi.accent.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: 15, color: NotificationsUi.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.2,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationListCard extends StatelessWidget {
  const NotificationListCard({
    super.key,
    required this.notification,
    required this.onTap,
    this.compact = false,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final visual = notificationVisualFor(n.type, n.category);
    final unread = n.isUnread;
    final categoryLabel = notificationCategoryLabel(n.category);
    final dark = AppTheme.dashIsDark(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NotificationsUi.radiusMd),
        child: Ink(
          decoration: BoxDecoration(
            color: unread
                ? (dark ? const Color(0xFF252D3D) : NotificationsUi.accentSoft)
                : AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(NotificationsUi.radiusMd),
            border: Border.all(
              color: unread
                  ? NotificationsUi.accent.withValues(alpha: 0.42)
                  : AppTheme.dashHairlineOf(context),
              width: unread ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: unread ? 0.08 : 0.035),
                blurRadius: unread ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: unread
                          ? const [
                              NotificationsUi.accent,
                              Color(0xFFFF8A3D),
                              AppTheme.primaryNavy,
                            ]
                          : [Colors.transparent, Colors.transparent],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 12 : 14,
                      12,
                      compact ? 12 : 14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: compact ? 42 : 48,
                          height: compact ? 42 : 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                visual.accentBg,
                                visual.iconColor.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: visual.iconColor.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Icon(
                            visual.icon,
                            color: visual.iconColor,
                            size: compact ? 20 : 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (categoryLabel != null) ...[
                                    NotificationCategoryChip(
                                      label: categoryLabel,
                                      color: visual.iconColor,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (unread)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: NotificationsUi.accent
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                          color: NotificationsUi.accent,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  if (unread)
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: NotificationsUi.accent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: NotificationsUi.accent
                                                .withValues(alpha: 0.45),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                n.title,
                                style: TextStyle(
                                  fontWeight: unread
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: compact ? 14 : 15,
                                  height: 1.25,
                                  letterSpacing: -0.15,
                                  color: AppTheme.dashTextPrimaryOf(context),
                                ),
                              ),
                              if (n.body != null &&
                                  n.body!.trim().isNotEmpty &&
                                  !compact) ...[
                                const SizedBox(height: 6),
                                Text(
                                  prettifyNotificationBody(n.body!),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: AppTheme.dashTextSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: AppTheme.dashTextSecondaryOf(
                                      context,
                                    ).withValues(alpha: 0.85),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      formatNotificationTimestamp(n.createdAt),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'Open',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: NotificationsUi.accent
                                            .withValues(alpha: 0.9),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: NotificationsUi.accent.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationCategoryChip extends StatelessWidget {
  const NotificationCategoryChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.45,
          color: color,
        ),
      ),
    );
  }
}

class NotificationEmptyState extends StatelessWidget {
  const NotificationEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    NotificationsUi.accent.withValues(alpha: 0.14),
                    AppTheme.primaryNavy.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                size: 48,
                color: NotificationsUi.accent.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'You’re all caught up',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave, recruitment, training, endorsements, and other HR alerts will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationErrorState extends StatelessWidget {
  const NotificationErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load notifications',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NotificationTypeVisual {
  const NotificationTypeVisual({
    required this.icon,
    required this.iconColor,
    required this.accentBg,
  });

  final IconData icon;
  final Color iconColor;
  final Color accentBg;
}

String? notificationCategoryLabel(String category) {
  final c = category.toLowerCase();
  if (c == 'leave') return 'Leave';
  if (c == 'locator') return 'Locator';
  if (c == 'recruitment') return 'Recruitment';
  if (c.contains('mayor') || c.contains('endorsement')) return 'Endorsement';
  if (c == 'training') return 'Training';
  if (c == 'overtime') return 'Overtime';
  if (c == 'dtr') return 'DTR';
  return null;
}

NotificationTypeVisual notificationVisualFor(String type, String category) {
  final t = type.toLowerCase();
  final cat = category.toLowerCase();

  if (cat.contains('mayor') ||
      cat.contains('endorsement') ||
      t.contains('endorsement') ||
      t.contains('mayor')) {
    return NotificationTypeVisual(
      icon: Icons.assured_workload_rounded,
      iconColor: const Color(0xFFB45309),
      accentBg: const Color(0xFFFFF7ED),
    );
  }
  if (cat == 'recruitment') {
    if (t.contains('endorsement')) {
      return NotificationTypeVisual(
        icon: Icons.assured_workload_rounded,
        iconColor: const Color(0xFFB45309),
        accentBg: const Color(0xFFFFF7ED),
      );
    }
    return NotificationTypeVisual(
      icon: Icons.person_add_alt_1_rounded,
      iconColor: NotificationsUi.accent,
      accentBg: NotificationsUi.accent.withValues(alpha: 0.14),
    );
  }
  if (cat == 'training') {
    return NotificationTypeVisual(
      icon: Icons.school_rounded,
      iconColor: const Color(0xFF1565C0),
      accentBg: const Color(0xFFE3F2FD),
    );
  }
  if (cat == 'overtime') {
    if (t.contains('approved')) {
      return NotificationTypeVisual(
        icon: Icons.check_circle_outline_rounded,
        iconColor: const Color(0xFF2E7D32),
        accentBg: const Color(0xFFE8F5E9),
      );
    }
    if (t.contains('reject')) {
      return NotificationTypeVisual(
        icon: Icons.cancel_outlined,
        iconColor: const Color(0xFFC62828),
        accentBg: const Color(0xFFFFEBEE),
      );
    }
    return NotificationTypeVisual(
      icon: Icons.more_time_rounded,
      iconColor: const Color(0xFF6A1B9A),
      accentBg: const Color(0xFFF3E5F5),
    );
  }
  if (cat == 'locator') {
    if (t.contains('approved')) {
      return NotificationTypeVisual(
        icon: Icons.check_circle_outline_rounded,
        iconColor: const Color(0xFF2E7D32),
        accentBg: const Color(0xFFE8F5E9),
      );
    }
    if (t.contains('reject')) {
      return NotificationTypeVisual(
        icon: Icons.cancel_outlined,
        iconColor: const Color(0xFFC62828),
        accentBg: const Color(0xFFFFEBEE),
      );
    }
    return NotificationTypeVisual(
      icon: Icons.pin_drop_rounded,
      iconColor: AppTheme.primaryNavy,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.12),
    );
  }
  if (cat != 'leave') {
    return NotificationTypeVisual(
      icon: Icons.notifications_rounded,
      iconColor: AppTheme.primaryNavy,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.1),
    );
  }
  if (t.contains('approved') && !t.contains('revoke')) {
    return NotificationTypeVisual(
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF2E7D32),
      accentBg: const Color(0xFFE8F5E9),
    );
  }
  if (t.contains('reject')) {
    return NotificationTypeVisual(
      icon: Icons.cancel_outlined,
      iconColor: const Color(0xFFC62828),
      accentBg: const Color(0xFFFFEBEE),
    );
  }
  if (t.contains('return')) {
    return NotificationTypeVisual(
      icon: Icons.reply_rounded,
      iconColor: const Color(0xFFEF6C00),
      accentBg: const Color(0xFFFFF3E0),
    );
  }
  if (t.contains('revoke')) {
    return NotificationTypeVisual(
      icon: Icons.undo_rounded,
      iconColor: const Color(0xFF6A1B9A),
      accentBg: const Color(0xFFF3E5F5),
    );
  }
  if (t.contains('cancel')) {
    return NotificationTypeVisual(
      icon: Icons.event_busy_rounded,
      iconColor: const Color(0xFF546E7A),
      accentBg: const Color(0xFFECEFF1),
    );
  }
  if (t.contains('mandatory') || t.contains('assigned')) {
    return NotificationTypeVisual(
      icon: Icons.assignment_ind_rounded,
      iconColor: AppTheme.primaryNavyDark,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.12),
    );
  }
  if (t.contains('pending') ||
      t.contains('forwarded') ||
      t.contains('department')) {
    return NotificationTypeVisual(
      icon: Icons.event_note_rounded,
      iconColor: AppTheme.primaryNavy,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.12),
    );
  }
  return NotificationTypeVisual(
    icon: Icons.calendar_month_rounded,
    iconColor: AppTheme.primaryNavy,
    accentBg: AppTheme.primaryNavy.withValues(alpha: 0.1),
  );
}

String formatNotificationAbsolute(DateTime dt) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = dt.toLocal();
  final h24 = local.hour;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 >= 12 ? 'PM' : 'AM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day} · $h12:$min $ampm';
}

String formatNotificationRelative(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);

  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatNotificationAbsolute(local);
}

/// Single clean timestamp line (no duplicate date formats).
String formatNotificationTimestamp(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  final absolute = formatNotificationAbsolute(local);

  if (diff.isNegative || diff.inSeconds < 60) return 'Just now · $absolute';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago · $absolute';
  if (diff.inHours < 24) return '${diff.inHours}h ago · $absolute';
  if (diff.inDays == 1) return 'Yesterday · $absolute';
  if (diff.inDays < 7) return '${diff.inDays}d ago · $absolute';
  return absolute;
}

String prettifyNotificationBody(String body) {
  return body.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
}
