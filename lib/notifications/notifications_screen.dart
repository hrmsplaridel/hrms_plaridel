import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../landingpage/constants/app_theme.dart';
import '../providers/auth_provider.dart';
import 'app_notification.dart';
import 'notification_provider.dart';
import 'notification_tap_result.dart';
import 'notifications_ui.dart';

/// Full-screen notifications list (leave, recruitment, training, etc.).
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
          if (np.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => np.markAllRead(),
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
        child: np.loading && np.items.isEmpty
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
            : np.loadError != null && np.items.isEmpty
                ? NotificationErrorState(
                    message: np.loadError!,
                    onRetry: () => np.loadNotifications(),
                  )
                : np.items.isEmpty
                    ? const NotificationEmptyState()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NotificationsSummaryStrip(
                            totalCount: np.items.length,
                            unreadCount: np.unreadCount,
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              color: AppTheme.primaryNavy,
                              onRefresh: () => np.loadNotifications(),
                              child: _NotificationList(
                                items: np.items,
                                onTap: (n) =>
                                    _handleNotificationTap(context, n, np),
                              ),
                            ),
                          ),
                        ],
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

class _NotificationList extends StatelessWidget {
  const _NotificationList({
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isHeader) {
          return NotificationSectionHeader(label: row.header!);
        }

        final n = row.notification!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NotificationListCard(
            notification: n,
            onTap: () => onTap(n),
          ),
        );
      },
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
