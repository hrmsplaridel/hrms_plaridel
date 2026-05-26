import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../docutracker/docutracker_notification_navigation.dart';
import '../docutracker/docutracker_provider.dart';
import '../docutracker/widgets/docutracker_notifications_panel.dart';
import '../landingpage/constants/app_theme.dart';
import '../providers/auth_provider.dart';
import 'app_notification.dart';
import 'notification_provider.dart';
import 'notification_tap_result.dart';
import 'notifications_ui.dart';

/// Full notifications panel — HRMS (leave, locator, …) and DocuTracker in one place.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await Future.wait([
      context.read<NotificationProvider>().loadNotifications(),
      context.read<DocuTrackerProvider>().loadNotifications(forceRefresh: true),
    ]);
  }

  bool _docuTrackerAdmin(BuildContext context) {
    final role = context.read<AuthProvider>().user?.role?.toLowerCase();
    return role == 'admin' || role == 'hr';
  }

  Future<void> _markAllRead(
    NotificationProvider np,
    DocuTrackerProvider doc,
  ) async {
    if (np.unreadCount > 0) await np.markAllRead();
    if (doc.unreadNotificationsCount > 0) {
      await doc.markAllNotificationsRead();
    }
  }

  @override
  Widget build(BuildContext context) {
    final np = context.watch<NotificationProvider>();
    final doc = context.watch<DocuTrackerProvider>();
    final scheme = Theme.of(context).colorScheme;
    final hrmsEmpty = np.items.isEmpty;
    final docEmpty = doc.notifications.isEmpty;
    final allEmpty = hrmsEmpty && docEmpty;
    final loading =
        (np.loading && hrmsEmpty) || (doc.loading && docEmpty);
    final totalUnread = np.unreadCount + doc.unreadNotificationsCount;
    final isDocuAdmin = _docuTrackerAdmin(context);
    final loadError = np.loadError ?? doc.error;

    return Scaffold(
      backgroundColor: AppTheme.sectionAltOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
          tooltip: 'Close',
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.dashMutedSurfaceOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: NotificationsUi.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                size: 20,
                color: NotificationsUi.accent,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Notifications',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppTheme.dashTextPrimaryOf(context),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (totalUnread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _markAllRead(np, doc),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
                label: const Text('Mark all read'),
              ),
            ),
        ],
        bottom: NotificationsUi.appBarBottomDivider(),
      ),
      body: DecoratedBox(
        decoration: NotificationsUi.screenCanvas(context),
        child: loading
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
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : allEmpty && loadError != null
                ? NotificationErrorState(
                    message: loadError,
                    onRetry: _reload,
                  )
                : allEmpty
                    ? const NotificationEmptyState()
                    : RefreshIndicator(
                        color: AppTheme.primaryNavy,
                        onRefresh: _reload,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            if (!hrmsEmpty || !docEmpty)
                              NotificationsSummaryStrip(
                                totalCount:
                                    np.items.length + doc.notifications.length,
                                unreadCount: totalUnread,
                              ),
                            if (!docEmpty) ...[
                              const SizedBox(height: 8),
                              const _PanelSectionTitle(title: 'DocuTracker'),
                              const SizedBox(height: 8),
                              DocuTrackerNotificationPanel(
                                notifications: doc.notifications,
                                unreadCount: doc.unreadNotificationsCount,
                                initialVisiblePerGroup: 20,
                                onMarkAllRead:
                                    doc.unreadNotificationsCount > 0
                                        ? () => doc.markAllNotificationsRead()
                                        : null,
                                onNotificationTap: (n) =>
                                    navigateFromDocuTrackerNotification(
                                  context,
                                  notification: n,
                                  isAdmin: isDocuAdmin,
                                  afterNavigation: () =>
                                      refreshDocuTrackerAfterNotificationNav(
                                    context,
                                    isAdmin: isDocuAdmin,
                                  ),
                                ),
                              ),
                              if (!hrmsEmpty) const SizedBox(height: 20),
                            ],
                            if (!hrmsEmpty) ...[
                              if (!docEmpty)
                                const _PanelSectionTitle(title: 'Leave & HR'),
                              if (!docEmpty) const SizedBox(height: 8),
                              _HrmsNotificationList(
                                items: np.items,
                                onTap: (n) =>
                                    _handleNotificationTap(context, n, np),
                              ),
                            ],
                          ],
                        ),
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

class _PanelSectionTitle extends StatelessWidget {
  const _PanelSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        letterSpacing: 0.5,
        color: AppTheme.primaryNavy.withValues(alpha: 0.85),
      ),
    );
  }
}

class _HrmsNotificationList extends StatelessWidget {
  const _HrmsNotificationList({
    required this.items,
    required this.onTap,
  });

  final List<AppNotification> items;
  final void Function(AppNotification n) onTap;

  @override
  Widget build(BuildContext context) {
    final nowLocal = DateTime.now().toLocal();
    final todayDay = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);

    String groupLabel(DateTime createdAt) {
      final d = createdAt.toLocal();
      final itemDay = DateTime(d.year, d.month, d.day);
      final daysAgo = todayDay.difference(itemDay).inDays;
      if (daysAgo == 0) return 'Today';
      if (daysAgo == 1) return 'Yesterday';
      return 'Earlier';
    }

    final rows = <_NotificationListRow>[];
    String? lastLabel;
    for (final n in items) {
      final label = groupLabel(n.createdAt);
      if (lastLabel != label) {
        rows.add(_NotificationListRow.header(label));
        lastLabel = label;
      }
      rows.add(_NotificationListRow.item(n));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          if (row.isHeader)
            NotificationSectionHeader(label: row.header!)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NotificationListCard(
                notification: row.notification!,
                onTap: () => onTap(row.notification!),
              ),
            ),
      ],
    );
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
