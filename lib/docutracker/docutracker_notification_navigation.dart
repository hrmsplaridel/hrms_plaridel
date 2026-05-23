import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'docutracker_provider.dart';
import 'docutracker_api_result.dart';
import 'docutracker_repository.dart';
import 'models/document.dart';
import 'models/document_notification.dart';
import 'screens/docutracker_document_detail_screen.dart';

/// Opens the document for a notification after marking it read (when [notification.id] is set).
Future<void> navigateFromDocuTrackerNotification(
  BuildContext context, {
  required DocumentNotification notification,
  required bool isAdmin,
  Future<void> Function()? afterNavigation,
}) async {
  final provider = context.read<DocuTrackerProvider>();
  final nid = notification.id;
  if (nid != null) {
    await provider.markNotificationRead(nid);
  }
  DocuTrackerDocument? doc;
  for (final d in provider.documents) {
    if (d.id == notification.documentId) {
      doc = d;
      break;
    }
  }
  final fetch = await DocuTrackerRepository.instance.getDocument(
    notification.documentId,
  );
  if (fetch is DocuTrackerSuccess<DocuTrackerDocument>) {
    doc = fetch.value;
  }
  if (!context.mounted) return;
  if (doc == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Document could not be opened. It may have been removed.',
        ),
      ),
    );
    return;
  }
  final docOpen = doc;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          DocuTrackerDocumentDetailScreen(document: docOpen, isAdmin: isAdmin),
    ),
  );
  if (context.mounted) await afterNavigation?.call();
}

/// Reloads documents and notifications after returning from a document opened via notification.
Future<void> refreshDocuTrackerAfterNotificationNav(
  BuildContext context, {
  required bool isAdmin,
}) async {
  final auth = context.read<AuthProvider>();
  final provider = context.read<DocuTrackerProvider>();
  await provider.loadDocumentsForUser(
    userId: auth.user?.id ?? '',
    isAdmin: isAdmin,
  );
  await provider.loadNotifications(forceRefresh: true);
}
