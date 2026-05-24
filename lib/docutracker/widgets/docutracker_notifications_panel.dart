import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../docutracker_provider.dart';
import '../models/document.dart';
import '../models/document_notification.dart';
import '../screens/docutracker_document_detail_screen.dart';

/// In-module alerts for DocuTracker (Option B — not shown in the global header bell).
class DocuTrackerNotificationsPanel extends StatelessWidget {
  const DocuTrackerNotificationsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final unread = provider.unreadNotificationCount;
    final items = provider.notifications;

    if (items.isEmpty && unread == 0) {
      return const SizedBox.shrink();
    }

    final preview = items.take(5).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 20,
                color: AppTheme.primaryNavy,
              ),
              const SizedBox(width: 8),
              Text(
                unread > 0
                    ? 'DocuTracker alerts ($unread unread)'
                    : 'DocuTracker alerts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Document alerts appear here only — not in the main notification bell.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...preview.map((n) => _NotificationRow(notification: n)),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification});

  final DocumentNotification notification;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final title = (n.title?.trim().isNotEmpty == true)
        ? n.title!.trim()
        : n.displayType;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final provider = context.read<DocuTrackerProvider>();
          if (n.id != null && !n.read) {
            await provider.markNotificationRead(n.id!);
          }
          if (!context.mounted || n.documentId.isEmpty) return;
          DocuTrackerDocument? doc;
          for (final d in provider.documents) {
            if (d.id == n.documentId) {
              doc = d;
              break;
            }
          }
          final document = doc;
          if (document == null) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  DocuTrackerDocumentDetailScreen(document: document),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!n.read)
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
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            n.read ? FontWeight.w600 : FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (n.body != null && n.body!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        n.body!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
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
    );
  }
}
