import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'docutracker_notification_navigation.dart';
import 'docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/widgets/docutracker_notifications_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/widgets/docutracker_slide_in_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/widgets/docutracker_empty_state.dart';

/// Slide-in panel listing DocuTracker notifications (grouped, scannable).
Future<void> showDocuTrackerNotificationPanel(
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

  await showDocuTrackerSlideInPanel<void>(
    context: context,
    title: 'Notifications',
    width: 420,
    headerTrailing: Consumer<DocuTrackerProvider>(
      builder: (_, p, __) {
        if (p.unreadNotificationsCount == 0) return const SizedBox.shrink();
        return TextButton(
          onPressed: () => p.markAllNotificationsRead(),
          style: TextButton.styleFrom(
            foregroundColor: DocuTrackerTokens.terracotta,
          ),
          child: const Text('Mark all read'),
        );
      },
    ),
    child: Consumer<DocuTrackerProvider>(
      builder: (_, p, __) {
        final list = p.notifications;
        if (list.isEmpty) {
          return const Center(
            child: DocuTrackerEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'All caught up',
              message:
                  'Deadline reminders and routing assignments will appear here.',
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: DocuTrackerNotificationPanel(
            notifications: list,
            unreadCount: p.unreadNotificationsCount,
            onMarkAllRead: () => p.markAllNotificationsRead(),
            onNotificationTap: (n) async {
              Navigator.of(context).pop();
              if (!context.mounted) return;
              await navigateFromDocuTrackerNotification(
                context,
                notification: n,
                isAdmin: isAdmin,
                afterNavigation: afterNav,
              );
            },
            initialVisiblePerGroup: 8,
          ),
        );
      },
    ),
  );
}

/// @deprecated Use [showDocuTrackerNotificationPanel] — kept for call-site compatibility.
Future<void> showDocuTrackerNotificationSheet(
  BuildContext context, {
  required bool isAdmin,
}) => showDocuTrackerNotificationPanel(context, isAdmin: isAdmin);
