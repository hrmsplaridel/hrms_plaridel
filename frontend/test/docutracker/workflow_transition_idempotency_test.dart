import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_workflow_service.dart';

class _CapturingWorkflowService extends DocuTrackerWorkflowService {
  _CapturingWorkflowService() : super(DocuTrackerRepository.instance);

  final List<String> idempotencyKeys = <String>[];

  @override
  Future<DocuTrackerResult<DocuTrackerDocument>> transitionDocument({
    required String documentId,
    required String action,
    String? remarks,
    String? targetHolderId,
    String? idempotencyKey,
  }) async {
    idempotencyKeys.add(idempotencyKey ?? '');
    return const DocuTrackerFailure<DocuTrackerDocument>(
      'Expected test failure',
    );
  }
}

DocuTrackerDocument _document({
  required DocumentStatus status,
  required DateTime updatedAt,
}) {
  return DocuTrackerDocument(
    id: 'doc-1',
    documentType: 'memo',
    title: 'Routing test',
    currentStep: 1,
    currentHolderId: 'reviewer-1',
    status: status,
    updatedAt: updatedAt,
  );
}

void main() {
  test('same workflow state reuses the transition idempotency key', () async {
    final service = _CapturingWorkflowService();
    final provider = DocuTrackerProvider(workflowService: service);
    addTearDown(provider.dispose);
    final document = _document(
      status: DocumentStatus.inReview,
      updatedAt: DateTime.utc(2026, 9, 18, 1),
    );

    await provider.approveDocument(document, actionBy: 'reviewer-1');
    await provider.approveDocument(document, actionBy: 'reviewer-1');

    expect(service.idempotencyKeys, hasLength(2));
    expect(service.idempotencyKeys[0], service.idempotencyKeys[1]);
  });

  test(
    'returned workflow cycle receives a new transition idempotency key',
    () async {
      final service = _CapturingWorkflowService();
      final provider = DocuTrackerProvider(workflowService: service);
      addTearDown(provider.dispose);
      final firstReview = _document(
        status: DocumentStatus.inReview,
        updatedAt: DateTime.utc(2026, 9, 18, 1),
      );
      final returnedReview = _document(
        status: DocumentStatus.returned,
        updatedAt: DateTime.utc(2026, 9, 18, 2),
      );

      await provider.approveDocument(firstReview, actionBy: 'reviewer-1');
      await provider.approveDocument(returnedReview, actionBy: 'reviewer-1');

      expect(service.idempotencyKeys, hasLength(2));
      expect(service.idempotencyKeys[0], isNot(service.idempotencyKeys[1]));
    },
  );
}
