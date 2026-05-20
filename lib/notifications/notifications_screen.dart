import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../landingpage/constants/app_theme.dart';
import '../providers/auth_provider.dart';
import 'app_notification.dart';
import 'notification_provider.dart';
import 'notification_tap_result.dart';

/// In-app notifications (leave, future DTR, etc.) with HR-themed cards and clear read/unread states.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final np = context.watch<NotificationProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppTheme.sectionAlt,
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppTheme.textPrimary),
          tooltip: 'Close',
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.offWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          if (np.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => np.markAllRead(),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
                child: const Text('Mark all read'),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      body: np.loading && np.items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading notifications…',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : np.loadError != null && np.items.isEmpty
          ? _ErrorState(message: np.loadError!)
          : np.items.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              color: AppTheme.primaryNavy,
              onRefresh: () => np.loadNotifications(),
              child: Builder(
                builder: (context) {
                  final nowLocal = DateTime.now().toLocal();
                  final todayDay = DateTime(
                    nowLocal.year,
                    nowLocal.month,
                    nowLocal.day,
                  );

                  String groupLabel(DateTime createdAt) {
                    final d = createdAt.toLocal();
                    final itemDay = DateTime(d.year, d.month, d.day);
                    final daysAgo = todayDay.difference(itemDay).inDays;
                    if (daysAgo == 0) return 'Today';
                    if (daysAgo == 1) return 'Yesterday';
                    return 'Earlier';
                  }

                  // Flatten list into: [header, card, card, header, card...]
                  final rows = <_NotificationListRow>[];
                  String? lastLabel;
                  for (final n in np.items) {
                    final label = groupLabel(n.createdAt);
                    if (lastLabel != label) {
                      rows.add(_NotificationListRow.header(label));
                      lastLabel = label;
                    }
                    rows.add(_NotificationListRow.item(n));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row.isHeader) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 8),
                          child: Text(
                            row.header!,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.5,
                              color: AppTheme.primaryNavy,
                            ),
                          ),
                        );
                      }

                      final n = row.notification!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NotificationCard(
                          notification: n,
                          onTap: () {
                            _handleNotificationTap(context, n, np);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    AppNotification n,
    NotificationProvider np,
  ) async {
    if (n.isUnread) {
      await np.markRead(n.id);
    }
    if (!context.mounted) return;
    final role = context.read<AuthProvider>().user?.role;
    final result = NotificationTapResult.fromNotification(n, role: role);
    Navigator.of(context).pop(result);
  }
}

class _NotificationListRow {
  const _NotificationListRow._({
    required this.kind,
    this.header,
    this.notification,
  });

  final _NotificationListRowKind kind;
  final String? header;
  final AppNotification? notification;

  bool get isHeader => kind == _NotificationListRowKind.header;

  factory _NotificationListRow.header(String header) {
    return _NotificationListRow._(
      kind: _NotificationListRowKind.header,
      header: header,
    );
  }

  factory _NotificationListRow.item(AppNotification notification) {
    return _NotificationListRow._(
      kind: _NotificationListRowKind.item,
      notification: notification,
    );
  }
}

enum _NotificationListRowKind { header, item }

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'You’re all caught up',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'New leave updates and alerts will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

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
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load notifications',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final visual = _visualForType(n.type, n.category);
    final unread = n.isUnread;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: unread ? const Color(0xFFFFFBF5) : AppTheme.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread
                  ? AppTheme.primaryNavy.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: unread ? 0.07 : 0.04),
                blurRadius: unread ? 12 : 8,
                offset: const Offset(0, 2),
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
                    color: unread ? AppTheme.primaryNavy : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(13),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: visual.accentBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            visual.icon,
                            color: visual.iconColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (n.category == 'leave' ||
                                  n.category == 'locator')
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _CategoryChip(
                                    label: n.category == 'locator'
                                        ? 'Locator'
                                        : 'Leave',
                                  ),
                                ),
                              Text(
                                n.title,
                                style: TextStyle(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: 15,
                                  height: 1.25,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (n.body != null &&
                                  n.body!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _prettifyBody(n.body!),
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatRelative(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    ' · ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatAbsolute(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (unread)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 2),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryNavy,
                                shape: BoxShape.circle,
                              ),
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppTheme.primaryNavy,
        ),
      ),
    );
  }
}

class _TypeVisual {
  const _TypeVisual({
    required this.icon,
    required this.iconColor,
    required this.accentBg,
  });

  final IconData icon;
  final Color iconColor;
  final Color accentBg;
}

_TypeVisual _visualForType(String type, String category) {
  final t = type.toLowerCase();
  final categoryLower = category.toLowerCase();
  if (categoryLower == 'locator') {
    if (t.contains('approved')) {
      return _TypeVisual(
        icon: Icons.check_circle_outline_rounded,
        iconColor: const Color(0xFF2E7D32),
        accentBg: const Color(0xFFE8F5E9),
      );
    }
    if (t.contains('reject')) {
      return _TypeVisual(
        icon: Icons.cancel_outlined,
        iconColor: const Color(0xFFC62828),
        accentBg: const Color(0xFFFFEBEE),
      );
    }
    return _TypeVisual(
      icon: Icons.pin_drop_rounded,
      iconColor: AppTheme.primaryNavy,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.12),
    );
  }
  if (categoryLower != 'leave') {
    return _TypeVisual(
      icon: Icons.notifications_rounded,
      iconColor: AppTheme.primaryNavy,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.1),
    );
  }
  if (t.contains('approved') && !t.contains('revoke')) {
    return _TypeVisual(
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF2E7D32),
      accentBg: const Color(0xFFE8F5E9),
    );
  }
  if (t.contains('reject')) {
    return _TypeVisual(
      icon: Icons.cancel_outlined,
      iconColor: const Color(0xFFC62828),
      accentBg: const Color(0xFFFFEBEE),
    );
  }
  if (t.contains('return')) {
    return _TypeVisual(
      icon: Icons.reply_rounded,
      iconColor: const Color(0xFFEF6C00),
      accentBg: const Color(0xFFFFF3E0),
    );
  }
  if (t.contains('revoke')) {
    return _TypeVisual(
      icon: Icons.undo_rounded,
      iconColor: const Color(0xFF6A1B9A),
      accentBg: const Color(0xFFF3E5F5),
    );
  }
  if (t.contains('cancel')) {
    return _TypeVisual(
      icon: Icons.event_busy_rounded,
      iconColor: const Color(0xFF546E7A),
      accentBg: const Color(0xFFECEFF1),
    );
  }
  if (t.contains('mandatory') || t.contains('assigned')) {
    return _TypeVisual(
      icon: Icons.assignment_ind_rounded,
      iconColor: AppTheme.primaryNavyDark,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.12),
    );
  }
  if (t.contains('pending') ||
      t.contains('forwarded') ||
      t.contains('department')) {
    return _TypeVisual(
      icon: Icons.event_note_rounded,
      iconColor: AppTheme.primaryNavy,
      accentBg: AppTheme.primaryNavy.withValues(alpha: 0.12),
    );
  }
  return _TypeVisual(
    icon: Icons.calendar_month_rounded,
    iconColor: AppTheme.primaryNavy,
    accentBg: AppTheme.primaryNavy.withValues(alpha: 0.1),
  );
}

String _formatAbsolute(DateTime dt) {
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

String _formatRelative(DateTime dt) {
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

/// Inserts spaces in camelCase tokens (e.g. `vacationLeave` → `vacation Leave`).
String _prettifyBody(String body) {
  return body.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
}
