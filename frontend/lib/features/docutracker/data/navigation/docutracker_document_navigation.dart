import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_detail_screen.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

/// Documents safe to show in list UIs for non-admins (relationship-scoped).
List<DocuTrackerDocument> docuTrackerDocumentsForDisplay({
  required List<DocuTrackerDocument> documents,
  required bool isAdmin,
  required String userId,
}) {
  if (isAdmin || userId.trim().isEmpty) return documents;
  return DocuTrackerDocumentVisibility.filterForUser(documents, userId: userId);
}

/// Documents for Required actions: only items that still need the viewer to act.
/// Completed / past-participant native docs stay in the Documents table instead.
List<DocuTrackerDocument> docuTrackerRequiredActionDocuments({
  required List<DocuTrackerDocument> documents,
  required String userId,
}) {
  final uid = userId.trim();
  return documents
      .where((document) {
        if (document.sourceOnly) {
          // Leave/DTR: only while a source action is still available.
          return (document.sourceAction ?? '').trim().isNotEmpty;
        }
        if (uid.isEmpty) return false;
        if (DocuTrackerDocumentVisibility.isWorkInProgressDraft(document)) {
          return false;
        }
        final status = document.status;
        if (status == DocumentStatus.approved ||
            status == DocumentStatus.rejected ||
            status == DocumentStatus.cancelled) {
          return false;
        }
        final isCurrentHolder = document.currentHolderId?.trim() == uid;
        final isActiveReview =
            status == DocumentStatus.pending ||
            status == DocumentStatus.inReview ||
            status == DocumentStatus.escalated ||
            status == DocumentStatus.overdue ||
            status == DocumentStatus.returned;
        final isRoutingOnActive =
            document.viewerIsRoutingAssignee && isActiveReview;
        final isSignatureAssignee = document.signatureSignerIds.any(
          (id) => id.trim() == uid,
        );
        return isCurrentHolder || isRoutingOnActive || isSignatureAssignee;
      })
      .toList(growable: false);
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
      builder: (_) =>
          DocuTrackerDocumentDetailScreen(document: document, isAdmin: isAdmin),
    ),
  );
  onReturned?.call();
  return true;
}
