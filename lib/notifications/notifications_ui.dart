import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';
import 'app_notification.dart';

/// Shared visual system for in-app notification list (bell dropdown + full screen).
class NotificationsUi {
  NotificationsUi._();

  static const double radiusLg = 18;
  static const double radiusMd = 14;
  static const Color accent = Color(0xFFE85D04);

  static BoxDecoration screenCanvas(BuildContext context) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.dashIsDark(context)
              ? const Color(0xFF1A2030)
              : const Color(0xFFF4F6FA),
          AppTheme.dashIsDark(context)
              ? const Color(0xFF151A24)
              : const Color(0xFFECEFF4),
        ],
      ),
    );
  }

  static PreferredSizeWidget appBarBottomDivider() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(
        height: 1,
        color: Colors.black.withValues(alpha: 0.06),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(NotificationsUi.radiusMd),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_rounded, size: 20, color: NotificationsUi.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              unreadCount > 0
                  ? '$unreadCount unread · $totalCount total'
                  : '$totalCount notification${totalCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: NotificationsUi.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: NotificationsUi.accent,
                ),
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
        'Today' => Icons.today_rounded,
        'Yesterday' => Icons.history_rounded,
        _ => Icons.calendar_view_week_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  NotificationsUi.accent.withValues(alpha: 0.18),
                  AppTheme.primaryNavy.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: NotificationsUi.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: 16, color: NotificationsUi.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NotificationsUi.radiusMd),
        child: Ink(
          decoration: BoxDecoration(
            color: unread
                ? (AppTheme.dashIsDark(context)
                    ? const Color(0xFF252D3D)
                    : const Color(0xFFFFFBF8))
                : AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(NotificationsUi.radiusMd),
            border: Border.all(
              color: unread
                  ? NotificationsUi.accent.withValues(alpha: 0.4)
                  : AppTheme.dashHairlineOf(context),
              width: unread ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: unread ? 0.08 : 0.04),
                blurRadius: unread ? 14 : 8,
                offset: const Offset(0, 3),
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
                          ? [NotificationsUi.accent, AppTheme.primaryNavy]
                          : [Colors.transparent, Colors.transparent],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 12 : 14,
                      14,
                      compact ? 12 : 14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: compact ? 40 : 48,
                          height: compact ? 40 : 48,
                          decoration: BoxDecoration(
                            color: visual.accentBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: visual.iconColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Icon(
                            visual.icon,
                            color: visual.iconColor,
                            size: compact ? 20 : 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (categoryLabel != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: NotificationCategoryChip(
                                    label: categoryLabel,
                                    color: visual.iconColor,
                                  ),
                                ),
                              Text(
                                n.title,
                                style: TextStyle(
                                  fontWeight:
                                      unread ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: compact ? 14 : 15,
                                  height: 1.25,
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
                                    color: AppTheme.dashTextSecondaryOf(context),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: AppTheme.dashTextSecondaryOf(context)
                                        .withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${formatNotificationRelative(n.createdAt)} · ${formatNotificationAbsolute(n.createdAt)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: BoxDecoration(
                              color: NotificationsUi.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: NotificationsUi.accent
                                      .withValues(alpha: 0.4),
                                  blurRadius: 4,
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.dashPanelOf(context),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_active_outlined,
                size: 52,
                color: NotificationsUi.accent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'You’re all caught up',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave, recruitment, training, and other HR alerts will show here.',
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
  switch (category.toLowerCase()) {
    case 'leave':
      return 'Leave';
    case 'locator':
      return 'Locator';
    case 'recruitment':
      return 'Recruitment';
    case 'training':
      return 'Training';
    case 'overtime':
      return 'Overtime';
    case 'dtr':
      return 'DTR';
    default:
      return null;
  }
}

NotificationTypeVisual notificationVisualFor(String type, String category) {
  final t = type.toLowerCase();
  final cat = category.toLowerCase();

  if (cat == 'recruitment') {
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
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

String formatNotificationRelative(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);

  if (diff.isNegative) return 'Just now';
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${local.month}/${local.day}/${local.year}';
}

String prettifyNotificationBody(String body) {
  return body.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
}
