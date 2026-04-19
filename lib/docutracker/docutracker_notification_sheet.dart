import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../landingpage/constants/app_theme.dart';
import 'docutracker_notification_navigation.dart';
import 'docutracker_provider.dart';
import 'widgets/docutracker_notifications_panel.dart';

/// Draggable bottom sheet listing DocuTracker notifications (same panel as dashboard).
Future<void> showDocuTrackerNotificationSheet(
  BuildContext context, {
  required bool isAdmin,
}) async {
  final provider = context.read<DocuTrackerProvider>();
  await provider.loadNotifications(forceRefresh: true);
  if (!context.mounted) return;

  Future<void> afterNav() async {
    if (context.mounted) {
      await refreshDocuTrackerAfterNotificationNav(context, isAdmin: isAdmin);
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.48,
        minChildSize: 0.28,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Material(
              color: AppTheme.white,
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      child: Consumer<DocuTrackerProvider>(
                        builder: (_, p, __) {
                          final list = p.notifications;
                          if (list.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(
                                child: Text('No notifications yet.'),
                              ),
                            );
                          }
                          return DocuTrackerNotificationPanel(
                            notifications: list,
                            unreadCount: p.unreadNotificationsCount,
                            onMarkAllRead: () => p.markAllNotificationsRead(),
                            onNotificationTap: (n) async {
                              Navigator.of(sheetContext).pop();
                              if (!context.mounted) return;
                              await navigateFromDocuTrackerNotification(
                                context,
                                notification: n,
                                isAdmin: isAdmin,
                                afterNavigation: afterNav,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Opens [showDocuTrackerNotificationSheet]. Distinct from HR [NotificationProvider] bell.
class DocuTrackerBellIconButton extends StatelessWidget {
  const DocuTrackerBellIconButton({
    super.key,
    required this.isAdmin,
    this.adminChrome = false,
    this.compact = false,
  });

  final bool isAdmin;
  final bool adminChrome;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 22.0 : 24.0;
    return Selector<DocuTrackerProvider, int>(
      selector: (_, p) => p.unreadNotificationsCount,
      builder: (context, unread, __) {
        final label = unread > 99 ? '99+' : '$unread';
        return IconButton(
          tooltip: 'DocuTracker notifications',
          onPressed: () =>
              showDocuTrackerNotificationSheet(context, isAdmin: isAdmin),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            child: Icon(
              Icons.article_outlined,
              color: AppTheme.textPrimary,
              size: adminChrome ? (compact ? 24 : 26) : iconSize,
            ),
          ),
          style: adminChrome
              ? IconButton.styleFrom(
                  backgroundColor: AppTheme.offWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                )
              : null,
        );
      },
    );
  }
}
