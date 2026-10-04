import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';

DocuTrackerSourceSignature _slot(
  String key, {
  String signerId = 'someone',
  bool mine = false,
  bool signed = false,
  String? waitingOn,
}) {
  return DocuTrackerSourceSignature(
    slotKey: key,
    label: key,
    assignedSignerId: signerId,
    assignedSignerName: signerId.isEmpty ? null : 'Signer $key',
    canSign: mine,
    signatureAssetId: signed ? 'asset-$key' : null,
    signatureImageBytes: signed ? Uint8List.fromList([1, 2, 3]) : null,
    signedAt: signed ? DateTime(2026, 9, 1) : null,
    waitingOnLabel: waitingOn,
  );
}

DocuTrackerRspSignatureRequest _request(
  List<DocuTrackerSourceSignature> slots, {
  bool requiresSetup = false,
}) {
  return DocuTrackerRspSignatureRequest(
    sourceModule: 'rsp',
    sourceTable: 'turn_around_time_entries',
    sourceRecordId: 'form-1',
    formName: 'Turn Around Time',
    title: 'Administrative Aide',
    sourceRecord: const {},
    requiresSetup: requiresSetup,
    signatureBundle: DocuTrackerSourceSignatureBundle(
      sourceModule: 'rsp',
      sourceTable: 'turn_around_time_entries',
      sourceRecordId: 'form-1',
      sourceStatus: 'awaiting_signatures',
      signatures: slots,
    ),
  );
}

void main() {
  test('forms with unassigned slots need setup', () {
    final request = _request([
      _slot('prepared_by'),
      _slot('noted_by', signerId: ''),
    ], requiresSetup: true);
    expect(request.signatureState, DocuTrackerSourceSignatureState.needsSetup);
  });

  test('a slot the viewer can sign now needs their signature', () {
    final request = _request([
      _slot('prepared_by', mine: true),
      _slot('noted_by'),
    ]);
    expect(
      request.signatureState,
      DocuTrackerSourceSignatureState.needsYourSignature,
    );
  });

  test('a viewer blocked by signing order waits on other signers', () {
    final request = _request([
      _slot('prepared_by'),
      _slot('noted_by', mine: true, waitingOn: 'prepared_by'),
    ]);
    expect(
      request.signatureState,
      DocuTrackerSourceSignatureState.waitingOnOthers,
    );
  });

  test('partially signed forms wait on other signers', () {
    final request = _request([
      _slot('prepared_by', mine: true, signed: true),
      _slot('noted_by'),
    ]);
    expect(request.signedCount, 1);
    expect(
      request.signatureState,
      DocuTrackerSourceSignatureState.waitingOnOthers,
    );
  });

  test('fully signed forms are completed even for a non-signer admin', () {
    final request = _request([
      _slot('prepared_by', signed: true),
      _slot('noted_by', signed: true),
    ]);
    expect(request.isAssignedToViewer, isFalse);
    expect(request.signedCount, 2);
    expect(request.signatureState, DocuTrackerSourceSignatureState.fullySigned);
  });
}
