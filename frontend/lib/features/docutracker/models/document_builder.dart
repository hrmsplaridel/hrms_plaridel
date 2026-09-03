import 'dart:convert';
import 'dart:typed_data';

Uint8List _decodeBase64Image(String encoded) {
  final normalized = encoded.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList(base64Decode(normalized));
}

/// One A4 page stored as Quill Delta operations.
class DocuTrackerDocumentPage {
  const DocuTrackerDocumentPage({required this.delta});

  final List<Map<String, dynamic>> delta;

  factory DocuTrackerDocumentPage.empty() => const DocuTrackerDocumentPage(
    delta: <Map<String, dynamic>>[
      <String, dynamic>{'insert': '\n'},
    ],
  );

  factory DocuTrackerDocumentPage.fromJson(dynamic json) {
    if (json is! List) return DocuTrackerDocumentPage.empty();
    final operations = json
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    return DocuTrackerDocumentPage(
      delta: operations.isEmpty
          ? DocuTrackerDocumentPage.empty().delta
          : operations,
    );
  }

  List<Map<String, dynamic>> toJson() => delta;
}

class DocuTrackerSignatureAsset {
  const DocuTrackerSignatureAsset({
    required this.id,
    required this.ownerUserId,
    required this.mimeType,
    required this.sourceType,
    required this.isSaved,
    required this.imageBytes,
    this.displayName,
    this.createdAt,
  });

  final String id;
  final String ownerUserId;
  final String mimeType;
  final String sourceType;
  final bool isSaved;
  final Uint8List imageBytes;
  final String? displayName;
  final DateTime? createdAt;

  factory DocuTrackerSignatureAsset.fromJson(Map<String, dynamic> json) {
    final encoded = json['image_base64']?.toString() ?? '';
    return DocuTrackerSignatureAsset(
      id: json['id']?.toString() ?? '',
      ownerUserId: json['owner_user_id']?.toString() ?? '',
      mimeType: json['mime_type']?.toString() ?? 'image/png',
      sourceType: json['source_type']?.toString() ?? 'uploaded',
      isSaved: json['is_saved'] == true,
      imageBytes: encoded.isEmpty ? Uint8List(0) : _decodeBase64Image(encoded),
      displayName: json['display_name']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class DocuTrackerSignatureField {
  const DocuTrackerSignatureField({
    required this.id,
    required this.pageNumber,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.assignedSignerId,
    required this.label,
    this.canSign = false,
    this.assignedSignerName,
    this.signatureAssetId,
    this.signatureImageBytes,
    this.signedBy,
    this.signerName,
    this.signedAt,
    this.lockedAt,
  });

  final String id;
  final int pageNumber;
  final double x;
  final double y;
  final double width;
  final double height;
  final String assignedSignerId;
  final String label;
  final bool canSign;
  final String? assignedSignerName;
  final String? signatureAssetId;
  final Uint8List? signatureImageBytes;
  final String? signedBy;
  final String? signerName;
  final DateTime? signedAt;
  final DateTime? lockedAt;

  bool get isSigned => signedAt != null && lockedAt != null;

  factory DocuTrackerSignatureField.fromJson(Map<String, dynamic> json) {
    final encoded = json['signature_image_base64']?.toString();
    return DocuTrackerSignatureField(
      id: json['id']?.toString() ?? '',
      pageNumber: (json['page_number'] as num?)?.toInt() ?? 1,
      x: (json['position_x'] as num?)?.toDouble() ?? 0.1,
      y: (json['position_y'] as num?)?.toDouble() ?? 0.7,
      width: (json['width'] as num?)?.toDouble() ?? 0.25,
      height: (json['height'] as num?)?.toDouble() ?? 0.1,
      assignedSignerId: json['assigned_signer_id']?.toString() ?? '',
      assignedSignerName: json['assigned_signer_name']?.toString(),
      label: json['label']?.toString() ?? 'Sign Here',
      canSign: json['can_sign'] == true,
      signatureAssetId: json['signature_asset_id']?.toString(),
      signatureImageBytes: encoded == null || encoded.isEmpty
          ? null
          : _decodeBase64Image(encoded),
      signedBy: json['signed_by']?.toString(),
      signerName: json['signer_name_snapshot']?.toString(),
      signedAt: DateTime.tryParse(json['signed_at']?.toString() ?? ''),
      lockedAt: DateTime.tryParse(json['locked_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toLayoutJson() => <String, dynamic>{
    if (id.isNotEmpty) 'id': id,
    'page_number': pageNumber,
    'position_x': x,
    'position_y': y,
    'width': width,
    'height': height,
    'assigned_signer_id': assignedSignerId,
    'label': label,
  };

  DocuTrackerSignatureField copyWith({
    int? pageNumber,
    double? x,
    double? y,
    double? width,
    double? height,
    String? assignedSignerId,
    String? assignedSignerName,
    String? label,
  }) => DocuTrackerSignatureField(
    id: id,
    pageNumber: pageNumber ?? this.pageNumber,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    assignedSignerId: assignedSignerId ?? this.assignedSignerId,
    assignedSignerName: assignedSignerName ?? this.assignedSignerName,
    label: label ?? this.label,
    canSign: canSign,
    signatureAssetId: signatureAssetId,
    signatureImageBytes: signatureImageBytes,
    signedBy: signedBy,
    signerName: signerName,
    signedAt: signedAt,
    lockedAt: lockedAt,
  );
}

class DocuTrackerDocumentBuilderData {
  const DocuTrackerDocumentBuilderData({
    required this.documentId,
    required this.currentUserId,
    required this.pages,
    required this.signatureFields,
    required this.revision,
    required this.canEditLayout,
    required this.canSign,
  });

  final String documentId;
  final String currentUserId;
  final List<DocuTrackerDocumentPage> pages;
  final List<DocuTrackerSignatureField> signatureFields;
  final int revision;
  final bool canEditLayout;
  final bool canSign;

  factory DocuTrackerDocumentBuilderData.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final rawFields = json['signature_fields'];
    final pages = rawPages is List
        ? rawPages.map(DocuTrackerDocumentPage.fromJson).toList(growable: false)
        : <DocuTrackerDocumentPage>[];
    return DocuTrackerDocumentBuilderData(
      documentId: json['document_id']?.toString() ?? '',
      currentUserId: json['current_user_id']?.toString() ?? '',
      pages: pages.isEmpty
          ? <DocuTrackerDocumentPage>[DocuTrackerDocumentPage.empty()]
          : pages,
      signatureFields: rawFields is List
          ? rawFields
                .whereType<Map>()
                .map(
                  (item) => DocuTrackerSignatureField.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const <DocuTrackerSignatureField>[],
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      canEditLayout: json['can_edit_layout'] == true,
      canSign: json['can_sign'] == true,
    );
  }
}
