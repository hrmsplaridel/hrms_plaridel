import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_notification_navigation.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_notifications_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_slide_in_panel.dart';

/// Slide-in panel listing DocuTracker notifications (grouped, scannable).
///
/// Opens immediately and refreshes in the background so a slow API call cannot
/// block the first paint (a prior cause of “bell does nothing” during testing).
Future<void> showDocuTrackerNotificationPanel(
  BuildContext context, {
  required bool isAdmin,
}) async {
  final provider = context.read<DocuTrackerProvider>();

  // Kick off refresh without awaiting — panel shows cached data / loading.
  final refresh = provider.loadNotifications(forceRefresh: true);

  Future<void> afterNav() async {
    if (context.mounted) {
      await refreshDocuTrackerAfterNotificationNav(context, isAdmin: isAdmin);
    }
  }

  String? documentReferenceOf(DocumentNotification notification) {
    for (final doc in provider.documents) {
      if (doc.id == notification.documentId) {
        final number = doc.documentNumber?.trim();
        if (number != null && number.isNotEmpty) {
          return number;
        }
        final title = doc.title.trim();
        if (title.isNotEmpty) return title;
      }
    }
    return notification.inferredDocumentReference;
  }

  await showDocuTrackerSlideInPanel<void>(
    context: context,
    title: 'Notifications',
    width: 440,
    headerTrailing: Consumer<DocuTrackerProvider>(
      builder: (_, p, __) {
        if (p.unreadNotificationsCount == 0) return const SizedBox.shrink();
        return TextButton(
          onPressed: () => p.markAllNotificationsRead(),
          style: TextButton.styleFrom(
            foregroundColor: DocuTrackerTokens.brand,
            minimumSize: const Size(44, 40),
          ),
          child: const Text('Mark all read'),
        );
      },
    ),
    child: FutureBuilder<void>(
      future: refresh,
      builder: (context, snapshot) {
        return Consumer<DocuTrackerProvider>(
          builder: (_, p, __) {
            // loadNotifications catches failures into [p.error] (no rethrow).
            final waiting =
                snapshot.connectionState == ConnectionState.waiting &&
                p.notifications.isEmpty;
            final failed =
                snapshot.connectionState != ConnectionState.waiting &&
                p.notifications.isEmpty &&
                p.error != null;

            return LayoutBuilder(
              builder: (context, constraints) {
                final body = DocuTrackerNotificationPanel(
                  notifications: p.notifications,
                  unreadCount: p.unreadNotificationsCount,
                  showChrome: false,
                  loading: waiting,
                  errorMessage: failed ? p.error : null,
                  onRetry: () => p.loadNotifications(forceRefresh: true),
                  // Header already exposes mark-all; avoid a second control.
                  onMarkAllRead: null,
                  onMarkRead: (n) async {
                    final id = n.id;
                    if (id == null) return;
                    await p.markNotificationRead(id);
                  },
                  documentReferenceOf: documentReferenceOf,
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
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: body,
                  ),
                );
              },
            );
          },
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
