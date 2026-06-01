import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_record.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';

/// Relationship-scoped document visibility (client-side).
///
/// Does not use role-level `view` on `*` — that permission can mean "module
/// access" on the server but must not expose every document in the list UI.
abstract final class DocuTrackerDocumentVisibility {
  DocuTrackerDocumentVisibility._();

  static bool _sameId(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = a.trim();
    final y = b.trim();
    return x.isNotEmpty && x == y;
  }

  /// WIP draft: pending, not yet in workflow (no holder / step).
  static bool isWorkInProgressDraft(DocuTrackerDocument doc) {
    final holder = doc.currentHolderId?.trim();
    final hasHolder = holder != null && holder.isNotEmpty;
    final step = doc.currentStep;
    final hasStep = step != null && step > 0;
    return doc.status == DocumentStatus.pending && !hasHolder && !hasStep;
  }

  /// Whether [userId] may see [doc] in lists or open its detail screen.
  static bool isVisible({
    required DocuTrackerDocument doc,
    required String userId,
    List<DocumentRoutingRecord>? routingForDocument,
  }) {
    final uid = userId.trim();
    if (uid.isEmpty) return false;

    if (_sameId(doc.createdBy, uid)) return true;
    if (_sameId(doc.currentHolderId, uid)) return true;

    final step = doc.currentStep;
    if (routingForDocument != null && step != null && step > 0) {
      for (final record in routingForDocument) {
        if (record.stepOrder != step) continue;
        if (record.assigneeIds.any((id) => _sameId(id, uid))) return true;
        if (_sameId(record.assigneeId, uid)) return true;
      }
    }

    if (isWorkInProgressDraft(doc)) {
      return _sameId(doc.createdBy, uid);
    }

    return false;
  }

  static List<DocuTrackerDocument> filterForUser(
    List<DocuTrackerDocument> documents, {
    required String userId,
  }) {
    return documents.where((d) => isVisible(doc: d, userId: userId)).toList();
  }
}
