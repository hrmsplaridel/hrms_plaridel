import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../notifications/app_notification.dart';
import '../../notifications/notification_provider.dart';
import '../../notifications/notification_tap_result.dart';
import '../../notifications/open_notifications_panel.dart';
import '../../providers/auth_provider.dart';

/// Header bell that opens an edusync-style notifications dropdown.
class DashboardNotificationBellButton extends StatefulWidget {
  const DashboardNotificationBellButton({
    super.key,
    this.compact = false,
    this.onViewAll,
    this.onNotificationTap,
  });

  final bool compact;
  final VoidCallback? onViewAll;

  /// Called after a dropdown item tap (menu already closed).
  final void Function(NotificationTapResult? result)? onNotificationTap;

  @override
  State<DashboardNotificationBellButton> createState() =>
      _DashboardNotificationBellButtonState();
}

class _DashboardNotificationBellButtonState
    extends State<DashboardNotificationBellButton> {
  void _openViewAll(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    if (widget.onViewAll != null) {
      widget.onViewAll!();
      return;
    }
    openNotificationsPanel(context).then((result) {
      if (!mounted) return;
      widget.onNotificationTap?.call(result);
    });
  }

  void _onDropdownTap(NotificationTapResult? result) {
    widget.onNotificationTap?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.compact ? 20.0 : 22.0;
    final pad = widget.compact ? 8.0 : 10.0;
    final unread = context.select<NotificationProvider, int>((p) => p.unreadCount);

    return PopupMenuButton<void>(
      offset: const Offset(0, 48),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      constraints: const BoxConstraints(minWidth: 380, maxWidth: 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: EdgeInsets.zero,
      color: AppTheme.dashPanelOf(context),
      onOpened: () {
        context.read<NotificationProvider>().loadNotifications();
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: DashboardNotificationsDropdownPanel(
            onViewAll: () => _openViewAll(menuContext),
            onNotificationTap: (result) {
              Navigator.of(menuContext).pop();
              _onDropdownTap(result);
            },
          ),
        ),
      ],
      child: Tooltip(
        message: 'Notifications',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: AppTheme.primaryNavy.withValues(alpha: 0.14),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.primaryNavy,
                  size: iconSize,
                ),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown body: header, notification list, footer.
class DashboardNotificationsDropdownPanel extends StatelessWidget {
  const DashboardNotificationsDropdownPanel({
    super.key,
    required this.onViewAll,
    this.onNotificationTap,
  });

  final VoidCallback onViewAll;
  final void Function(NotificationTapResult? result)? onNotificationTap;

  static const int _maxPreviewItems = 8;

  @override
  Widget build(BuildContext context) {
    final np = context.watch<NotificationProvider>();

    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DropdownHeader(
            unreadCount: np.unreadCount,
            onMarkAllRead: np.unreadCount > 0 ? () => np.markAllRead() : null,
          ),
          SizedBox(
            height: 240,
            child: _DropdownBody(
              loading: np.loading,
              loadError: np.loadError,
              items: np.items,
              onNotificationTap: onNotificationTap,
            ),
          ),
          _DropdownFooter(onViewAll: onViewAll),
        ],
      ),
    );
  }
}

class _DropdownBody extends StatelessWidget {
  const _DropdownBody({
    required this.loading,
    required this.loadError,
    required this.items,
    this.onNotificationTap,
  });

  final bool loading;
  final String? loadError;
  final List<AppNotification> items;
  final void Function(NotificationTapResult? result)? onNotificationTap;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (loadError != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Could not load notifications.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'You’re all caught up.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ),
      );
    }

    final preview = items.take(DashboardNotificationsDropdownPanel._maxPreviewItems).toList();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      itemCount: preview.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final n = preview[index];
        return _DropdownNotificationTile(
          notification: n,
          onTap: () async {
            final np = context.read<NotificationProvider>();
            if (n.isUnread) await np.markRead(n.id);
            if (!context.mounted) return;
            final role = context.read<AuthProvider>().user?.role;
            final result = NotificationTapResult.fromNotification(n, role: role);
            onNotificationTap?.call(result);
          },
        );
      },
    );
  }
}

class _DropdownNotificationTile extends StatelessWidget {
  const _DropdownNotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = n.isUnread;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: unread
                ? AppTheme.primaryNavy.withValues(alpha: 0.06)
                : AppTheme.dashMutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: unread
                  ? AppTheme.primaryNavy.withValues(alpha: 0.2)
                  : AppTheme.dashHairlineOf(context),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryNavy,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          color: AppTheme.dashTextPrimaryOf(context),
                          height: 1.25,
                        ),
                      ),
                      if (n.body != null && n.body!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          n.body!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: AppTheme.dashTextSecondaryOf(context),
                          ),
                        ),
                      ],
                    ],
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

class _DropdownHeader extends StatelessWidget {
  const _DropdownHeader({
    required this.unreadCount,
    this.onMarkAllRead,
  });

  final int unreadCount;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        color: AppTheme.primaryNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              unreadCount > 0 ? 'Notifications ($unreadCount)' : 'Notifications',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onMarkAllRead != null)
            TextButton(
              onPressed: onMarkAllRead,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _DropdownFooter extends StatelessWidget {
  const _DropdownFooter({
    required this.onViewAll,
  });

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clear All'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                side: const BorderSide(color: AppTheme.primaryNavy),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onViewAll,
              icon: const Icon(Icons.notifications_rounded, size: 18),
              label: const Text('View All'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
