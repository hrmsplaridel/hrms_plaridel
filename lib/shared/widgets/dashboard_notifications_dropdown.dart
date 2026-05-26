import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../docutracker/docutracker_notification_navigation.dart';
import '../../docutracker/docutracker_provider.dart';
import '../../docutracker/models/document_notification.dart';
import '../../docutracker/theme/docutracker_tokens.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../notifications/app_notification.dart';
import '../../notifications/notification_provider.dart';
import '../../notifications/notification_tap_result.dart';
import '../../notifications/open_notifications_panel.dart';
import '../../providers/auth_provider.dart';

bool dashboardDocuTrackerAdminFromAuth(BuildContext context) {
  final role = context.read<AuthProvider>().user?.role?.toLowerCase();
  return role == 'admin' || role == 'hr';
}

/// Single global header bell — HRMS + DocuTracker notifications in one dropdown.
class DashboardNotificationBellButton extends StatefulWidget {
  const DashboardNotificationBellButton({
    super.key,
    this.compact = false,
    this.onViewAll,
    this.onNotificationTap,
  });

  final bool compact;
  final VoidCallback? onViewAll;
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

  void _onHrmsTap(NotificationTapResult? result) {
    widget.onNotificationTap?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.compact ? 20.0 : 22.0;
    final pad = widget.compact ? 8.0 : 10.0;
    final hrmsUnread = context.select<NotificationProvider, int>(
      (p) => p.unreadCount,
    );
    final docUnread = context.select<DocuTrackerProvider, int>(
      (p) => p.unreadNotificationsCount,
    );
    final unread = hrmsUnread + docUnread;
    final isAdmin = dashboardDocuTrackerAdminFromAuth(context);

    return PopupMenuButton<void>(
      offset: const Offset(0, 48),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      constraints: const BoxConstraints(minWidth: 380, maxWidth: 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: EdgeInsets.zero,
      color: DocuTrackerTokens.surface,
      onOpened: () {
        context.read<NotificationProvider>().loadNotifications();
        context.read<DocuTrackerProvider>().loadNotifications(
          forceRefresh: true,
        );
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: DashboardNotificationsDropdownPanel(
            isAdmin: isAdmin,
            onViewAll: () => _openViewAll(menuContext),
            onHrmsTap: (result) {
              Navigator.of(menuContext).pop();
              _onHrmsTap(result);
            },
            onDocuTrackerTap: (n) async {
              Navigator.of(menuContext).pop();
              if (!context.mounted) return;
              await navigateFromDocuTrackerNotification(
                context,
                notification: n,
                isAdmin: isAdmin,
                afterNavigation: () => refreshDocuTrackerAfterNotificationNav(
                  context,
                  isAdmin: isAdmin,
                ),
              );
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
              color: DocuTrackerTokens.surfaceCream,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Icon(
                  Icons.notifications_outlined,
                  color: DocuTrackerTokens.brand,
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
                    color: DocuTrackerTokens.overdueAccent,
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

enum _UnifiedSource { hrms, docuTracker }

class _UnifiedNotification {
  const _UnifiedNotification.hrms(this.hrms)
    : source = _UnifiedSource.hrms,
      docu = null;

  const _UnifiedNotification.docu(this.docu)
    : source = _UnifiedSource.docuTracker,
      hrms = null;

  final _UnifiedSource source;
  final AppNotification? hrms;
  final DocumentNotification? docu;

  DateTime get sortAt {
    return switch (source) {
      _UnifiedSource.hrms => hrms!.createdAt,
      _UnifiedSource.docuTracker =>
        docu!.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    };
  }

  bool get isUnread {
    return switch (source) {
      _UnifiedSource.hrms => hrms!.isUnread,
      _UnifiedSource.docuTracker => !docu!.read,
    };
  }
}

/// Dropdown body: header, merged notification list, footer.
class DashboardNotificationsDropdownPanel extends StatelessWidget {
  const DashboardNotificationsDropdownPanel({
    super.key,
    required this.isAdmin,
    required this.onViewAll,
    required this.onHrmsTap,
    required this.onDocuTrackerTap,
  });

  final bool isAdmin;
  final VoidCallback onViewAll;
  final void Function(NotificationTapResult? result) onHrmsTap;
  final Future<void> Function(DocumentNotification n) onDocuTrackerTap;

  static const int _maxPreviewItems = 8;

  static List<_UnifiedNotification> _merge(
    List<AppNotification> hrms,
    List<DocumentNotification> docu,
  ) {
    final merged = <_UnifiedNotification>[
      ...hrms.map(_UnifiedNotification.hrms),
      ...docu.map(_UnifiedNotification.docu),
    ]..sort((a, b) => b.sortAt.compareTo(a.sortAt));
    return merged.take(_maxPreviewItems).toList();
  }

  @override
  Widget build(BuildContext context) {
    final np = context.watch<NotificationProvider>();
    final doc = context.watch<DocuTrackerProvider>();
    final merged = _merge(np.items, doc.notifications);
    final unread = np.unreadCount + doc.unreadNotificationsCount;
    final loading =
        (np.loading && np.items.isEmpty) ||
        (doc.loading && doc.notifications.isEmpty);
    Future<void> markAllRead() async {
      if (np.unreadCount > 0) await np.markAllRead();
      if (doc.unreadNotificationsCount > 0) {
        await doc.markAllNotificationsRead();
      }
    }

    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DropdownHeader(
            unreadCount: unread,
            onMarkAllRead: unread > 0 ? () => markAllRead() : null,
          ),
          SizedBox(
            height: 240,
            child: _DropdownBody(
              loading: loading,
              hrmsError: np.loadError,
              docError: doc.error,
              items: merged,
              onHrmsTap: onHrmsTap,
              onDocuTrackerTap: onDocuTrackerTap,
            ),
          ),
          _DropdownFooter(
            onClearAll: unread > 0 ? () => markAllRead() : null,
            onViewAll: onViewAll,
          ),
        ],
      ),
    );
  }
}

class _DropdownBody extends StatelessWidget {
  const _DropdownBody({
    required this.loading,
    required this.hrmsError,
    required this.docError,
    required this.items,
    required this.onHrmsTap,
    required this.onDocuTrackerTap,
  });

  final bool loading;
  final String? hrmsError;
  final String? docError;
  final List<_UnifiedNotification> items;
  final void Function(NotificationTapResult? result) onHrmsTap;
  final Future<void> Function(DocumentNotification n) onDocuTrackerTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: DocuTrackerTokens.brand,
          ),
        ),
      );
    }
    if (items.isEmpty) {
      final message = (hrmsError != null || docError != null)
          ? 'Could not load some notifications.'
          : 'You’re all caught up.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = items[index];
        return switch (item.source) {
          _UnifiedSource.hrms => _HrmsNotificationTile(
            notification: item.hrms!,
            onTap: () async {
              final np = context.read<NotificationProvider>();
              final n = item.hrms!;
              if (n.isUnread) await np.markRead(n.id);
              if (!context.mounted) return;
              final role = context.read<AuthProvider>().user?.role;
              onHrmsTap(NotificationTapResult.fromNotification(n, role: role));
            },
          ),
          _UnifiedSource.docuTracker => _DocuTrackerNotificationTile(
            notification: item.docu!,
            onTap: () => onDocuTrackerTap(item.docu!),
          ),
        };
      },
    );
  }
}

class _HrmsNotificationTile extends StatelessWidget {
  const _HrmsNotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = n.isUnread;

    return _NotificationTileShell(
      unread: unread,
      accentColor: AppTheme.primaryNavy,
      sourceLabel: 'HRMS',
      title: n.title,
      body: n.body,
      onTap: onTap,
    );
  }
}

class _DocuTrackerNotificationTile extends StatelessWidget {
  const _DocuTrackerNotificationTile({
    required this.notification,
    required this.onTap,
  });

  final DocumentNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.read;
    final title = n.title?.trim().isNotEmpty == true
        ? n.title!
        : n.displayType;

    return _NotificationTileShell(
      unread: unread,
      accentColor: DocuTrackerTokens.brand,
      sourceLabel: 'DocuTracker',
      title: title,
      body: n.body,
      onTap: onTap,
    );
  }
}

class _NotificationTileShell extends StatelessWidget {
  const _NotificationTileShell({
    required this.unread,
    required this.accentColor,
    required this.sourceLabel,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool unread;
  final Color accentColor;
  final String sourceLabel;
  final String title;
  final String? body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: unread
                ? DocuTrackerTokens.highlightPeach.withValues(alpha: 0.65)
                : DocuTrackerTokens.surfaceCream.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: unread
                  ? accentColor.withValues(alpha: 0.25)
                  : DocuTrackerTokens.borderSubtle,
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
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DocuTrackerTokens.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      if (body != null && body!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          body!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DocuTrackerTokens.metaStyle(),
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
        color: DocuTrackerTokens.brand,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_rounded, color: Colors.white, size: 22),
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
    this.onClearAll,
  });

  final VoidCallback onViewAll;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DocuTrackerTokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onClearAll,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clear All'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DocuTrackerTokens.brand,
                disabledForegroundColor: DocuTrackerTokens.textMuted,
                side: const BorderSide(color: DocuTrackerTokens.brand),
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
              style: DocuTrackerTokens.brandFilledStyle().copyWith(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(vertical: 12),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
