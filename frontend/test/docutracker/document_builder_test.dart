import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_document_navigation.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

void main() {
  test('signature images decode PostgreSQL line-wrapped Base64', () {
    final imageBytes = List<int>.generate(90, (index) => index);
    final encoded = base64Encode(imageBytes);
    final wrapped = '${encoded.substring(0, 76)}\n${encoded.substring(76)}';

    final asset = DocuTrackerSignatureAsset.fromJson(<String, dynamic>{
      'id': 'asset-1',
      'owner_user_id': 'user-1',
      'mime_type': 'image/png',
      'source_type': 'drawn',
      'is_saved': true,
      'image_base64': wrapped,
    });
    final field = DocuTrackerSignatureField.fromJson(<String, dynamic>{
      'id': 'field-1',
      'page_number': 1,
      'assigned_signer_id': 'user-1',
      'label': 'Sign Here',
      'signature_image_base64': wrapped,
    });

    expect(asset.imageBytes, imageBytes);
    expect(field.signatureImageBytes, imageBytes);
  });

  test('builder preserves A4 pages and locked signature geometry', () {
    final data = DocuTrackerDocumentBuilderData.fromJson(<String, dynamic>{
      'document_id': 'document-1',
      'current_user_id': 'user-2',
      'pages': <dynamic>[
        <dynamic>[
          <String, dynamic>{'insert': 'Memo body\n'},
        ],
      ],
      'format_version': 2,
      'revision': 4,
      'can_edit_layout': false,
      'can_sign': false,
      'signature_fields': <dynamic>[
        <String, dynamic>{
          'id': 'field-1',
          'page_number': 1,
          'position_x': 0.55,
          'position_y': 0.72,
          'width': 0.3,
          'height': 0.12,
          'assigned_signer_id': 'user-2',
          'assigned_signer_name': 'Maria Santos',
          'label': 'Sign Here',
          'can_sign': false,
          'signature_asset_id': 'asset-1',
          'signature_image_base64': base64Encode(<int>[1, 2, 3]),
          'signed_by': 'user-2',
          'signer_name_snapshot': 'Maria Santos',
          'signed_at': '2026-08-28T08:30:00.000Z',
          'locked_at': '2026-08-28T08:30:00.000Z',
        },
      ],
    });

    expect(data.pages.single.delta.single['insert'], 'Memo body\n');
    expect(data.revision, 4);
    expect(data.formatVersion, 2);
    expect(data.currentUserId, 'user-2');
    expect(data.signatureFields.single.isSigned, isTrue);
    expect(data.signatureFields.single.pageNumber, 1);
    expect(data.signatureFields.single.x, 0.55);
    expect(data.signatureFields.single.signatureImageBytes, <int>[1, 2, 3]);
    expect(data.signatureFields.single.canSign, isFalse);
  });

  test('linked source signature decodes image and server capability', () {
    final bundle = DocuTrackerSourceSignatureBundle.fromJson(<String, dynamic>{
      'source_module': 'dtr',
      'source_table': 'leave_requests',
      'source_record_id': 'leave-1',
      'source_status': 'pending_department_head',
      'signatures': <dynamic>[
        <String, dynamic>{
          'id': 'signature-1',
          'slot_key': 'applicant',
          'label': 'Signature of Applicant',
          'assigned_signer_id': 'employee-1',
          'can_sign': true,
          'signature_asset_id': 'asset-1',
          'signature_image_base64': 'AQID\nBA==',
          'signed_by': 'employee-1',
          'signer_name_snapshot': 'Employee One',
          'signed_at': '2026-09-13T01:00:00.000Z',
        },
      ],
    });

    final signature = bundle.signatureFor('applicant');
    expect(signature, isNotNull);
    expect(signature!.isSigned, isTrue);
    expect(signature.canSign, isTrue);
    expect(signature.signatureImageBytes, <int>[1, 2, 3, 4]);
  });

  test(
    'RSP signature bundle keeps assignment and signer capabilities separate',
    () {
      final bundle = DocuTrackerSourceSignatureBundle.fromJson(
        <String, dynamic>{
          'source_module': 'rsp',
          'source_table': 'applicants_profile_entries',
          'source_record_id': 'profile-1',
          'source_status': 'saved',
          'can_assign': true,
          'signatures': <Map<String, dynamic>>[
            <String, dynamic>{
              'slot_key': 'prepared_by',
              'label': 'Prepared by',
              'assigned_signer_id': 'preparer-1',
              'assigned_signer_name': 'Prepared Person',
              'can_sign': false,
            },
            <String, dynamic>{
              'slot_key': 'checked_by',
              'label': 'Checked by',
              'assigned_signer_id': 'checker-1',
              'assigned_signer_name': 'Checking Person',
              'can_sign': true,
            },
          ],
        },
      );

      expect(bundle.canAssign, isTrue);
      expect(bundle.signatureFor('prepared_by')?.canSign, isFalse);
      expect(bundle.signatureFor('checked_by')?.canSign, isTrue);
      expect(
        bundle.signatureFor('checked_by')?.assignedSignerName,
        'Checking Person',
      );
    },
  );

  test('RSP signature request parses its protected form preview payload', () {
    final request = DocuTrackerRspSignatureRequest.fromJson(<String, dynamic>{
      'source_module': 'rsp',
      'source_table': 'selection_lineup_entries',
      'source_record_id': 'lineup-1',
      'form_name': 'Selection Line-Up',
      'title': 'Administrative Officer',
      'source_record': <String, dynamic>{
        'id': 'lineup-1',
        'vacant_position': 'Administrative Officer',
      },
      'signature_bundle': <String, dynamic>{
        'source_module': 'rsp',
        'source_table': 'selection_lineup_entries',
        'source_record_id': 'lineup-1',
        'source_status': 'saved',
        'signatures': <Map<String, dynamic>>[
          <String, dynamic>{
            'slot_key': 'prepared_by',
            'label': 'Prepared by',
            'assigned_signer_id': 'employee-1',
            'can_sign': true,
          },
        ],
      },
    });

    expect(request.formName, 'Selection Line-Up');
    expect(request.sourceModule, 'rsp');
    expect(request.sourceRecord['vacant_position'], 'Administrative Officer');
    expect(request.hasUnsignedAssignedSlot, isTrue);
  });

  test('L&D signature request exposes admin setup state', () {
    final request = DocuTrackerRspSignatureRequest.fromJson(<String, dynamic>{
      'source_module': 'ld',
      'source_table': 'idp_entries',
      'source_record_id': 'idp-1',
      'form_name': 'Individual Development Plan',
      'title': 'Juan Dela Cruz - Administrative Officer',
      'requires_setup': true,
      'source_record': <String, dynamic>{'id': 'idp-1'},
      'signature_bundle': <String, dynamic>{
        'source_module': 'ld',
        'source_table': 'idp_entries',
        'source_record_id': 'idp-1',
        'source_status': 'saved',
        'can_assign': true,
        'signatures': <Map<String, dynamic>>[
          <String, dynamic>{
            'slot_key': 'prepared_by',
            'label': 'Prepared by',
            'assigned_signer_id': '',
            'can_sign': false,
          },
        ],
      },
    });

    expect(request.sourceModule, 'ld');
    expect(request.requiresSetup, isTrue);
    expect(request.signatureBundle.canAssign, isTrue);
  });

  test('builder trusts server field-level signing capability', () {
    final data = DocuTrackerDocumentBuilderData.fromJson(<String, dynamic>{
      'document_id': 'document-1',
      'current_user_id': 'signer-1',
      'pages': <dynamic>[],
      'revision': 1,
      'can_edit_layout': false,
      'can_sign': true,
      'signature_fields': <dynamic>[
        <String, dynamic>{
          'id': 'field-1',
          'page_number': 1,
          'position_x': 0.1,
          'position_y': 0.7,
          'width': 0.3,
          'height': 0.12,
          'assigned_signer_id': 'signer-1',
          'assigned_signer_name': 'Assigned Signer',
          'label': 'Sign Here',
          'can_sign': true,
        },
      ],
    });

    expect(data.canSign, isTrue);
    expect(data.formatVersion, 1);
    expect(data.signatureFields.single.canSign, isTrue);
    expect(data.signatureFields.single.assignedSignerName, 'Assigned Signer');
  });

  test(
    'assigned signature user can see the document in frontend filtering',
    () {
      final document = DocuTrackerDocument.fromJson(<String, dynamic>{
        'id': 'document-1',
        'document_type': 'memo',
        'title': 'For signature',
        'created_by': 'creator-1',
        'status': 'pending',
        'signature_signer_ids': <String>['signer-1'],
      });

      expect(
        DocuTrackerDocumentVisibility.isVisible(
          doc: document,
          userId: 'signer-1',
        ),
        isTrue,
      );
      expect(
        DocuTrackerDocumentVisibility.isVisible(
          doc: document,
          userId: 'unrelated-user',
        ),
        isFalse,
      );
    },
  );

  test('routing assignee returned by backend can see the document', () {
    final document = DocuTrackerDocument.fromJson(<String, dynamic>{
      'id': 'document-1',
      'document_type': 'memo',
      'title': 'Assigned document',
      'created_by': 'creator-1',
      'status': 'in_review',
      'current_holder_id': 'primary-assignee',
      'current_step': 1,
      'viewer_is_routing_assignee': true,
    });

    expect(
      DocuTrackerDocumentVisibility.isVisible(
        doc: document,
        userId: 'backup-assignee',
      ),
      isTrue,
    );
  });

  test('frontend trusts backend filtering for source-only records', () {
    final document = DocuTrackerDocument.fromJson(<String, dynamic>{
      'id': 'source:dtr:leave-1',
      'document_type': 'dtr',
      'title': 'Leave request',
      'created_by': 'employee-1',
      'status': 'in_review',
      'source_module': 'dtr',
      'source_table': 'leave_requests',
      'source_record_id': 'leave-1',
      'source_only': true,
    });

    expect(
      DocuTrackerDocumentVisibility.isVisible(
        doc: document,
        userId: 'assigned-reviewer-returned-by-server',
      ),
      isTrue,
    );
  });

  test(
    'required actions use server source actions and current assignments',
    () {
      final sourceAction = DocuTrackerDocument.fromJson(<String, dynamic>{
        'id': 'source:dtr:leave-1',
        'document_type': 'dtr',
        'title': 'Leave request',
        'status': 'in_review',
        'source_module': 'dtr',
        'source_table': 'leave_requests',
        'source_record_id': 'leave-1',
        'source_status': 'pending_department_head',
        'source_action': 'department_review_in_dtr',
        'source_action_label': 'Sign here, then review in DTR',
        'source_only': true,
      });
      final assignedDocument = DocuTrackerDocument.fromJson(<String, dynamic>{
        'id': 'document-1',
        'document_type': 'memo',
        'title': 'Memo for review',
        'status': 'in_review',
        'current_holder_id': 'user-1',
        'current_step': 1,
      });
      final completedDocument = DocuTrackerDocument.fromJson(<String, dynamic>{
        'id': 'document-2',
        'document_type': 'memo',
        'title': 'Completed memo',
        'status': 'approved',
        'current_holder_id': 'user-1',
        'current_step': 2,
      });

      final actions = docuTrackerRequiredActionDocuments(
        documents: <DocuTrackerDocument>[
          sourceAction,
          assignedDocument,
          completedDocument,
        ],
        userId: 'user-1',
      );

      expect(actions, <DocuTrackerDocument>[sourceAction, assignedDocument]);
      expect(sourceAction.sourceStatus, 'pending_department_head');
      expect(sourceAction.sourceActionLabel, 'Sign here, then review in DTR');
    },
  );

  test('linked leave signatures parse applicant, department, and HR slots', () {
    final bundle = DocuTrackerSourceSignatureBundle.fromJson(<String, dynamic>{
      'source_module': 'dtr',
      'source_table': 'leave_requests',
      'source_record_id': 'leave-1',
      'source_status': 'pending_department_head',
      'signatures': <Map<String, dynamic>>[
        <String, dynamic>{
          'slot_key': 'applicant',
          'label': 'Signature of Applicant',
          'assigned_signer_id': 'employee-1',
          'can_sign': false,
        },
        <String, dynamic>{
          'slot_key': 'department_head',
          'label': 'Department Head Signature',
          'assigned_signer_id': 'head-1',
          'assigned_signer_name': 'Department Head One',
          'can_sign': true,
        },
        <String, dynamic>{
          'slot_key': 'hr_approver',
          'label': 'Final Approver Signature',
          'assigned_signer_id': 'hr-1',
          'assigned_signer_name': 'HR Officer One',
          'can_sign': false,
        },
      ],
    });

    expect(bundle.signatureFor('applicant'), isNotNull);
    expect(bundle.signatureFor('department_head')?.canSign, isTrue);
    expect(
      bundle.signatureFor('department_head')?.assignedSignerName,
      'Department Head One',
    );
    expect(
      bundle.signatureFor('hr_approver')?.assignedSignerName,
      'HR Officer One',
    );
  });
}
