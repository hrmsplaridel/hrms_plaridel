import 'dart:convert';
import 'dart:typed_data';

/// Signature ink sent with a signature-required Approve or Forward.
///
/// The server saves it in the same transaction as the workflow step. A failed
/// step leaves this signature uncommitted.
class DocuTrackerTransitionSignature {
  const DocuTrackerTransitionSignature({
    this.fieldId,
    this.pageNumber,
    this.x,
    this.y,
    this.width,
    this.height,
    this.label,
    this.signatureAssetId,
    this.imageBytes,
    this.mimeType = 'image/png',
    this.sourceType = 'drawn',
    this.saveForReuse = false,
  });

  final String? fieldId;
  final int? pageNumber;
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  final String? label;
  final String? signatureAssetId;
  final Uint8List? imageBytes;
  final String mimeType;
  final String sourceType;
  final bool saveForReuse;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (fieldId != null) 'field_id': fieldId,
      if (pageNumber != null) 'page_number': pageNumber,
      if (x != null) 'position_x': x,
      if (y != null) 'position_y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (label != null) 'label': label,
      if (signatureAssetId != null)
        'signature_asset_id': signatureAssetId
      else ...<String, dynamic>{
        'image_base64': base64Encode(imageBytes ?? Uint8List(0)),
        'mime_type': mimeType,
        'source_type': sourceType,
        'is_saved': saveForReuse,
      },
    };
  }
}
