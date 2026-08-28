import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

void main() {
  test('builder preserves A4 pages and locked signature geometry', () {
    final data = DocuTrackerDocumentBuilderData.fromJson(<String, dynamic>{
      'document_id': 'document-1',
      'current_user_id': 'user-2',
      'pages': <dynamic>[
        <dynamic>[
          <String, dynamic>{'insert': 'Memo body\n'},
        ],
      ],
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
    expect(data.currentUserId, 'user-2');
    expect(data.signatureFields.single.isSigned, isTrue);
    expect(data.signatureFields.single.pageNumber, 1);
    expect(data.signatureFields.single.x, 0.55);
    expect(data.signatureFields.single.signatureImageBytes, <int>[1, 2, 3]);
    expect(data.signatureFields.single.canSign, isFalse);
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
}
