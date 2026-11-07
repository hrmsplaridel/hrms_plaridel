import 'dart:ui' show Rect;

/// Signature lines on a Purchase Request.
///
/// These replace the old typed "Signature: ____" sentences. The editor and
/// the PDF paint the same two boxes, and Approve writes into the empty one.
abstract final class DocuTrackerPurchaseLayout {
  static const String requestedLabel = 'Requested by';
  static const String approvedLabel = 'Approved by';

  /// Ink area for the person who requests the purchase.
  static const Rect requestedField = Rect.fromLTWH(0.11, 0.69, 0.34, 0.085);

  /// Ink area for the person who gives final approval.
  static const Rect approvedField = Rect.fromLTWH(0.54, 0.69, 0.34, 0.085);

  /// Sentences the first purchase-request drafts typed instead of a field.
  static const Set<String> legacySignatureLines = <String>{
    'Requested by:',
    'Approved by:',
    'Signature: ____________________',
    'Printed name: [Requesting official]',
    'Printed name: [Approving official]',
    'Designation: [Designation]',
  };

  static bool isSlotLabel(String label) =>
      label == requestedLabel || label == approvedLabel;
}

/// Drops the old typed signature sentences from a purchase-request page.
///
/// Stored pages keep those sentences until the draft is saved again. The
/// editor and PDF use this cleaned copy so the real fields are not repeated
/// as text.
List<Map<String, dynamic>> docuTrackerWithoutLegacyPurchaseSignatures(
  List<Map<String, dynamic>> delta,
) {
  final cleaned = <Map<String, dynamic>>[];
  for (final operation in delta) {
    final insert = operation['insert'];
    if (insert is String && _isLegacySignatureText(insert)) continue;
    cleaned.add(operation);
  }
  if (cleaned.isEmpty || cleaned.last['insert'] != '\n') {
    cleaned.add({'insert': '\n'});
  }
  return cleaned;
}

bool _isLegacySignatureText(String insert) {
  final lines = insert
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return false;
  return lines.every(DocuTrackerPurchaseLayout.legacySignatureLines.contains);
}
