import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_purchase_layout.dart';

import 'docutracker_signature_placement_overlay.dart';

/// Requested by and Approved by, painted like the Memorandum signatory boxes.
class DocuTrackerPurchaseSignatureBand extends StatelessWidget {
  const DocuTrackerPurchaseSignatureBand({
    super.key,
    required this.fields,
    required this.onSign,
    this.placementPreviewFieldId,
    this.placementPreviewBytes,
  });

  final List<DocuTrackerSignatureField> fields;
  final ValueChanged<DocuTrackerSignatureField>? onSign;

  /// Unsaved ink for one stored slot. The slot's saved rectangle is unchanged.
  final String? placementPreviewFieldId;
  final Uint8List? placementPreviewBytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 132,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _PurchaseSignatureBox(
                label: DocuTrackerPurchaseLayout.requestedLabel,
                field: _fieldFor(DocuTrackerPurchaseLayout.requestedLabel),
                onSign: onSign,
                previewBytes: _previewFor(
                  DocuTrackerPurchaseLayout.requestedLabel,
                ),
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: _PurchaseSignatureBox(
                label: DocuTrackerPurchaseLayout.approvedLabel,
                field: _fieldFor(DocuTrackerPurchaseLayout.approvedLabel),
                onSign: onSign,
                previewBytes: _previewFor(
                  DocuTrackerPurchaseLayout.approvedLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DocuTrackerSignatureField? _fieldFor(String label) {
    DocuTrackerSignatureField? match;
    for (final field in fields) {
      if (field.pageNumber != 1 || field.label != label) continue;
      if (match == null || (field.isSigned && !match.isSigned)) match = field;
    }
    return match;
  }

  Uint8List? _previewFor(String label) {
    final field = _fieldFor(label);
    if (field == null || field.id != placementPreviewFieldId) return null;
    return placementPreviewBytes;
  }
}

class _PurchaseSignatureBox extends StatelessWidget {
  const _PurchaseSignatureBox({
    required this.label,
    required this.field,
    required this.onSign,
    required this.previewBytes,
  });

  final String label;
  final DocuTrackerSignatureField? field;
  final ValueChanged<DocuTrackerSignatureField>? onSign;
  final Uint8List? previewBytes;

  @override
  Widget build(BuildContext context) {
    final source = field;
    final preview = previewBytes;
    final signable =
        preview == null &&
        source != null &&
        source.canSign &&
        !source.isSigned &&
        onSign != null;
    final image = source != null && source.isSigned
        ? source.signatureImageBytes
        : null;
    final name = source == null
        ? null
        : (source.isSigned ? source.signerName : source.assignedSignerName);
    final position = source == null
        ? null
        : (source.isSigned
              ? source.signerPositionSnapshot
              : source.assignedSignerPosition);

    Widget area = preview != null
        ? DocuTrackerSignaturePlacementMark(bytes: preview)
        : image != null
        ? Image.memory(
            image,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          )
        : Center(
            child: Text(
              source == null ? 'Awaiting assignment' : 'Awaiting signature',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: source == null
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF64748B),
              ),
            ),
          );
    area = DecoratedBox(
      decoration: BoxDecoration(
        color: source == null
            ? const Color(0xFFF9FAFB)
            : const Color(0xFFF8FAFC),
        border: Border.all(
          color: source == null
              ? const Color(0xFFE5E7EB)
              : const Color(0xFFCBD5E1),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: area,
    );
    if (signable) {
      area = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSign!(source),
        child: area,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Expanded(child: area),
        Container(height: 1, color: const Color(0xFF111827)),
        const SizedBox(height: 2),
        Text(
          (name == null || name.trim().isEmpty)
              ? ''
              : name.trim().toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          position?.trim() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
