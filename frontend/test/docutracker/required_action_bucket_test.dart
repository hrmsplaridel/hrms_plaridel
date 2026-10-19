import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_required_action_bucket.dart';

DocuTrackerDocument _memo({
  String id = 'memo-1',
  String status = 'in_review',
  String? currentHolderId,
  List<String> signatureSignerIds = const [],
  bool viewerIsRoutingAssignee = false,
  String? sourceAction,
  bool sourceOnly = false,
}) => DocuTrackerDocument.fromJson({
  'id': id,
  'document_type': 'memo',
  'title': 'Memo',
  'status': status,
  if (currentHolderId != null) 'current_holder_id': currentHolderId,
  'signature_signer_ids': signatureSignerIds,
  'viewer_is_routing_assignee': viewerIsRoutingAssignee,
  if (sourceAction != null) 'source_action': sourceAction,
  'source_only': sourceOnly,
});

DocuTrackerRspSignatureRequest _signatureRequest({
  required DocuTrackerSourceSignatureState state,
}) {
  final slot = switch (state) {
    DocuTrackerSourceSignatureState.needsYourSignature => {
      'assigned_signer_id': 'me',
      'can_sign': true,
    },
    DocuTrackerSourceSignatureState.waitingOnOthers => {
      'assigned_signer_id': 'other',
      'can_sign': false,
    },
    DocuTrackerSourceSignatureState.fullySigned => {
      'assigned_signer_id': 'other',
      'can_sign': false,
      'signature_asset_id': 'asset-1',
      'signature_image_base64': 'AQ==',
      'signed_at': '2026-01-01T00:00:00Z',
    },
    DocuTrackerSourceSignatureState.needsSetup => {'assigned_signer_id': ''},
  };
  return DocuTrackerRspSignatureRequest.fromJson({
    'source_module': 'rsp',
    'source_table': 'turn_around_time_entries',
    'source_record_id': 'tat-1',
    'form_name': 'Turn Around Time',
    'title': 'TAT',
    'requires_setup': state == DocuTrackerSourceSignatureState.needsSetup,
    'signature_bundle': {
      'source_module': 'rsp',
      'source_table': 'turn_around_time_entries',
      'source_record_id': 'tat-1',
      'signatures': [slot],
    },
  });
}

void main() {
  group('docuTrackerRequiredActionBucket', () {
    test('native holder review is Needs your review', () {
      expect(
        docuTrackerRequiredActionBucket(
          document: _memo(currentHolderId: 'me'),
          userId: 'me',
        ),
        DocuTrackerRequiredActionBucket.needsReview,
      );
    });

    test('source signature request is Needs your signature', () {
      expect(
        docuTrackerRequiredActionBucket(
          sourceRequest: _signatureRequest(
            state: DocuTrackerSourceSignatureState.needsYourSignature,
          ),
        ),
        DocuTrackerRequiredActionBucket.needsSignature,
      );
    });

    test('signature-only native assignee is Needs your signature', () {
      expect(
        docuTrackerRequiredActionBucket(
          document: _memo(
            currentHolderId: 'other',
            signatureSignerIds: const ['me'],
          ),
          userId: 'me',
        ),
        DocuTrackerRequiredActionBucket.needsSignature,
      );
    });

    test('holder who is also a signer stays in review', () {
      expect(
        docuTrackerRequiredActionBucket(
          document: _memo(
            currentHolderId: 'me',
            signatureSignerIds: const ['me'],
          ),
          userId: 'me',
        ),
        DocuTrackerRequiredActionBucket.needsReview,
      );
    });

    test('source-only leave action is review, not signature', () {
      expect(
        docuTrackerRequiredActionBucket(
          document: _memo(
            sourceOnly: true,
            sourceAction: 'complete_in_dtr',
            status: 'pending',
          ),
        ),
        DocuTrackerRequiredActionBucket.needsReview,
      );
    });

    test('setup / waiting / completed signature states are preserved', () {
      expect(
        docuTrackerRequiredActionBucket(
          sourceRequest: _signatureRequest(
            state: DocuTrackerSourceSignatureState.needsSetup,
          ),
        ),
        DocuTrackerRequiredActionBucket.needsSetup,
      );
      expect(
        docuTrackerRequiredActionBucket(
          sourceRequest: _signatureRequest(
            state: DocuTrackerSourceSignatureState.waitingOnOthers,
          ),
        ),
        DocuTrackerRequiredActionBucket.waiting,
      );
      expect(
        docuTrackerRequiredActionBucket(
          sourceRequest: _signatureRequest(
            state: DocuTrackerSourceSignatureState.fullySigned,
          ),
        ),
        DocuTrackerRequiredActionBucket.completed,
      );
    });
  });
}
