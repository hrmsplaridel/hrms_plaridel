import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';

/// Backend workflow façade (all state transitions + remarks).
///
/// Kept intentionally small to improve testability and reduce Provider churn.
class DocuTrackerWorkflowService {
  DocuTrackerWorkflowService(this._repo);

  final DocuTrackerRepository _repo;

  Future<DocuTrackerResult<DocuTrackerDocument>> transitionDocument({
    required String documentId,
    required String action,
    String? remarks,
    String? targetHolderId,
    String? idempotencyKey,
  }) {
    return _repo.transitionDocument(
      documentId: documentId,
      action: action,
      remarks: remarks,
      targetHolderId: targetHolderId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<bool> addDocumentRemark({
    required String documentId,
    required String remarks,
  }) {
    return _repo.addDocumentRemark(documentId: documentId, remarks: remarks);
  }
}
