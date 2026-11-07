import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_transition_signature.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_workflow_service.dart';

class _CapturingWorkflowService extends DocuTrackerWorkflowService {
  _CapturingWorkflowService() : super(DocuTrackerRepository.instance);

  final List<String> idempotencyKeys = <String>[];
  final List<String> actions = <String>[];
  final List<DocuTrackerTransitionSignature?> signatures =
      <DocuTrackerTransitionSignature?>[];
  Completer<void>? gate;

  @override
  Future<DocuTrackerResult<DocuTrackerDocument>> transitionDocument({
    required String documentId,
    required String action,
    String? remarks,
    String? targetHolderId,
    String? idempotencyKey,
    DocuTrackerTransitionSignature? signature,
  }) async {
    idempotencyKeys.add(idempotencyKey ?? '');
    actions.add(action);
    signatures.add(signature);
    final pending = gate;
    if (pending != null) await pending.future;
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

  test('a signature retry keeps the same idempotency key', () async {
    final service = _CapturingWorkflowService();
    final provider = DocuTrackerProvider(workflowService: service);
    addTearDown(provider.dispose);
    final document = _document(
      status: DocumentStatus.inReview,
      updatedAt: DateTime.utc(2026, 9, 18, 1),
    );
    final signature = DocuTrackerTransitionSignature(
      fieldId: '33333333-3333-4333-8333-333333333333',
      imageBytes: Uint8List.fromList(const [9, 9]),
    );

    await provider.approveDocument(
      document,
      actionBy: 'reviewer-1',
      signature: signature,
    );
    await provider.approveDocument(
      document,
      actionBy: 'reviewer-1',
      signature: signature,
    );

    expect(service.signatures, hasLength(2));
    expect(service.signatures[0]?.fieldId, signature.fieldId);
    expect(service.idempotencyKeys[0], service.idempotencyKeys[1]);
  });

  test('the first tap locks approve and forward until it finishes', () async {
    final service = _CapturingWorkflowService();
    final provider = DocuTrackerProvider(workflowService: service);
    addTearDown(provider.dispose);
    final document = _document(
      status: DocumentStatus.inReview,
      updatedAt: DateTime.utc(2026, 9, 18, 1),
    );
    service.gate = Completer<void>();

    expect(provider.tryBeginWorkflowAction('doc-1'), isTrue);
    expect(provider.tryBeginWorkflowAction('doc-1'), isFalse);
    expect(provider.isWorkflowActionLocked('doc-1'), isTrue);

    final first = provider.approveDocument(
      document,
      actionBy: 'reviewer-1',
      workflowLockHeld: true,
    );
    await Future<void>.delayed(Duration.zero);
    final second = await provider.forwardDocument(
      document,
      actionBy: 'reviewer-1',
      workflowLockHeld: true,
    );

    expect(second, isFalse);
    expect(provider.error, contains('already in progress'));
    expect(service.actions, ['approve']);

    service.gate!.complete();
    expect(await first, isFalse);
    provider.endWorkflowAction('doc-1');
    expect(provider.isWorkflowActionLocked('doc-1'), isFalse);
    expect(service.actions, ['approve']);
  });

  test('cancel releases the lock without a transition', () {
    final service = _CapturingWorkflowService();
    final provider = DocuTrackerProvider(workflowService: service);
    addTearDown(provider.dispose);

    expect(provider.tryBeginWorkflowAction('doc-1'), isTrue);
    provider.endWorkflowAction('doc-1');

    expect(provider.isWorkflowActionLocked('doc-1'), isFalse);
    expect(service.actions, isEmpty);
    expect(provider.tryBeginWorkflowAction('doc-1'), isTrue);
  });
}
