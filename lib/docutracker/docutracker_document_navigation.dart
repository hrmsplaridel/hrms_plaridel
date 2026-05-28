import 'package:flutter/material.dart';

import 'docutracker_repository.dart';
import 'models/document.dart';
import 'screens/docutracker_document_detail_screen.dart';
import 'services/docutracker_document_visibility.dart';

/// Documents safe to show in list UIs for non-admins (relationship-scoped).
List<DocuTrackerDocument> docuTrackerDocumentsForDisplay({
  required List<DocuTrackerDocument> documents,
  required bool isAdmin,
  required String userId,
}) {
  if (isAdmin || userId.trim().isEmpty) return documents;
  return DocuTrackerDocumentVisibility.filterForUser(
    documents,
    userId: userId,
  );
}

/// Opens document detail after verifying the user may access it.
Future<bool> openDocuTrackerDocumentDetail(
  BuildContext context, {
  required DocuTrackerDocument document,
  required bool isAdmin,
  required String userId,
  VoidCallback? onReturned,
}) async {
  final docId = document.id?.trim();
  if (docId == null || docId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document is missing an identifier.')),
      );
    }
    return false;
  }

  if (!isAdmin && !document.sourceOnly) {
    final allowed = await DocuTrackerRepository.instance.canAccessDocument(
      userId: userId,
      documentId: docId,
      isAdmin: false,
      document: document,
    );
    if (!allowed) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You do not have access to this document. '
              'Only the creator, current assignee, or step reviewers can open it.',
            ),
          ),
        );
      }
      return false;
    }
  }

  if (!context.mounted) return false;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => DocuTrackerDocumentDetailScreen(
        document: document,
        isAdmin: isAdmin,
      ),
    ),
  );
  onReturned?.call();
  return true;
}
