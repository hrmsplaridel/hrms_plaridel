import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';

class DocuTrackerSignatureFieldVisual extends StatelessWidget {
  const DocuTrackerSignatureFieldVisual({
    super.key,
    required this.field,
    required this.signable,
    this.exportMode = false,
  });

  final DocuTrackerSignatureField field;
  final bool signable;
  final bool exportMode;

  @override
  Widget build(BuildContext context) =>
      field.isSigned ? _buildSignedField() : _buildUnsignedField();

  Widget _buildUnsignedField() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            signable ? Icons.edit_rounded : Icons.draw_outlined,
            color: const Color(0xFFB45309),
            size: 20,
          ),
          Text(
            field.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          Text(
            field.assignedSignerName ?? field.assignedSignerId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF92400E)),
          ),
          if (signable && !exportMode)
            const Text(
              'Click to sign',
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSignedField() {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: [
          Expanded(
            child: field.signatureImageBytes == null
                ? const Icon(Icons.verified_rounded, color: Color(0xFF15803D))
                : Image.memory(field.signatureImageBytes!, fit: BoxFit.contain),
          ),
          Text(
            field.signerName ?? field.assignedSignerName ?? 'Signed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9),
          ),
          Text(
            _formatSignedDate(field.signedAt),
            maxLines: 1,
            style: const TextStyle(fontSize: 8, color: Color(0xFF4B5563)),
          ),
          if (field.canSign && !exportMode)
            const Text(
              'Drag to move • Click to change',
              maxLines: 1,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF15803D),
              ),
            ),
        ],
      ),
    );
  }

  String _formatSignedDate(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
