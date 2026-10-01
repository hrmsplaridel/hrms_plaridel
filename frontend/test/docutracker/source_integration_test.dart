import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_document_navigation.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_source_status_text.dart';

DocuTrackerDocument _sourceDocument({
  required String module,
  required String table,
  required String status,
  String? action,
  String? actionLabel,
}) => DocuTrackerDocument.fromJson({
  'id': 'source:$module:11111111-1111-4111-8111-111111111111',
  'document_type': module,
  'title': 'Source record',
  'status': 'pending',
  'source_module': module,
  'source_table': table,
  'source_record_id': '11111111-1111-4111-8111-111111111111',
  'source_status': status,
  if (action != null) 'source_action': action,
  if (actionLabel != null) 'source_action_label': actionLabel,
  'source_only': true,
});

Map<String, dynamic> _slot(
  String slot, {
  String signerId = '',
  String? signerName,
  bool signed = false,
}) => {
  'slot_key': slot,
  'label': slot == 'prepared_by' ? 'Prepared by' : 'Noted by',
  'assigned_signer_id': signerId,
  if (signerName != null) 'assigned_signer_name': signerName,
  if (signed) 'signature_asset_id': 'asset-$slot',
  if (signed) 'signed_at': '2026-09-30T01:00:00.000Z',
  if (signed) 'signature_image_base64': 'c2lnbmF0dXJl',
};

DocuTrackerRspSignatureRequest _request(List<Map<String, dynamic>> slots) =>
    DocuTrackerRspSignatureRequest.fromJson({
      'source_module': 'rsp',
      'source_table': 'turn_around_time_entries',
      'source_record_id': '22222222-2222-4222-8222-222222222222',
      'form_name': 'Turn Around Time',
      'title': 'Administrative Aide',
      'signature_bundle': {
        'source_module': 'rsp',
        'source_table': 'turn_around_time_entries',
        'source_record_id': '22222222-2222-4222-8222-222222222222',
        'signatures': slots,
      },
    });

void main() {
  test('source rows keep server-owned RSP/L&D status and next step', () {
    final doc = _sourceDocument(
      module: 'rsp',
      table: 'recruitment_applications',
      status: 'exam_taken',
      action: 'grade_exam_in_rsp',
      actionLabel: 'Complete exam grading in RSP',
    );
    expect(doc.sourceOnly, isTrue);
    expect(doc.status, DocumentStatus.pending);
    expect(doc.sourceStatus, 'exam_taken');
    expect(doc.sourceActionLabel, 'Complete exam grading in RSP');
  });

  test('Required actions only lists RSP/L&D rows with a module action', () {
    final actionable = _sourceDocument(
      module: 'ld',
      table: 'training_daily_reports',
      status: 'submitted',
      action: 'review_report_in_ld',
      actionLabel: 'Review training report in L&D',
    );
    final informational = _sourceDocument(
      module: 'rsp',
      table: 'recruitment_applications',
      status: 'document_declined',
    );

    final required = docuTrackerRequiredActionDocuments(
      documents: [actionable, informational],
      userId: 'admin-1',
    );

    expect(required, [actionable]);
  });

  test('source module labels cover only RSP and L&D', () {
    expect(docuTrackerSourceModuleLabel('rsp'), 'RSP');
    expect(docuTrackerSourceModuleLabel('LD'), 'L&D');
    expect(docuTrackerSourceModuleLabel('dtr'), isNull);
    expect(docuTrackerSourceModuleLabel(null), isNull);
  });

  test('signature requests report completion and who still has to sign', () {
    final waiting = _request([
      _slot('prepared_by', signerId: 'u-1', signerName: 'Ana', signed: true),
      _slot('noted_by', signerId: 'u-2', signerName: 'Ben'),
    ]);
    expect(waiting.isFullySigned, isFalse);
    expect(waiting.pendingSignerNames, ['Ben']);

    final unassigned = _request([
      _slot('prepared_by', signerId: 'u-1', signed: true),
      _slot('noted_by'),
    ]);
    expect(unassigned.isFullySigned, isFalse);
    expect(unassigned.pendingSignerNames, isEmpty);

    final waitingTurn = _request([
      _slot('prepared_by', signerId: 'u-1', signerName: 'Ana'),
      {
        ..._slot('noted_by', signerId: 'u-2', signerName: 'Ben'),
        'can_sign': true,
        'waiting_on_label': 'Prepared by',
      },
    ]);
    expect(waitingTurn.hasUnsignedAssignedSlot, isFalse);
    expect(waitingTurn.viewerWaitingOnLabel, 'Prepared by');
    expect(waitingTurn.isAssignedToViewer, isTrue);

    final myTurn = _request([
      _slot('prepared_by', signerId: 'u-1', signed: true),
      {..._slot('noted_by', signerId: 'u-2'), 'can_sign': true},
    ]);
    expect(myTurn.hasUnsignedAssignedSlot, isTrue);
    expect(myTurn.viewerWaitingOnLabel, isNull);

    final complete = _request([
      _slot('prepared_by', signerId: 'u-1', signed: true),
      _slot('noted_by', signerId: 'u-2', signed: true),
    ]);
    expect(complete.isFullySigned, isTrue);
    expect(complete.pendingSignerNames, isEmpty);
  });
}
