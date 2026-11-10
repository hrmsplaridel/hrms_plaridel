import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// Ghost of a signature before it is saved. The outline is the final area.
class DocuTrackerSignaturePlacementMark extends StatelessWidget {
  const DocuTrackerSignaturePlacementMark({super.key, required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    return DecoratedBox(
      key: const Key('docutracker_signature_preview'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED).withValues(alpha: 0.72),
        border: Border.all(color: const Color(0xFFC2410C), width: 1.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null && image.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
              child: Opacity(
                opacity: 0.84,
                child: Image.memory(
                  image,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
              ),
            ),
          const Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                'Preview',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFC2410C),
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ring that stays visible on white paper. Drawn in paper coordinates.
class DocuTrackerSignaturePlacementCursor extends StatelessWidget {
  const DocuTrackerSignaturePlacementCursor({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: Key('docutracker_signature_cursor'),
      width: 22,
      height: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x33C2410C),
          border: Border.fromBorderSide(
            BorderSide(color: Color(0xFFFFFFFF), width: 2),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xFFC2410C), width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirm writes through the existing sign path. Cancel writes nothing.
class DocuTrackerSignaturePlacementBar extends StatelessWidget {
  const DocuTrackerSignaturePlacementBar({
    super.key,
    required this.onConfirm,
    required this.onCancel,
    required this.enabled,
    required this.free,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool enabled;
  final bool free;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Material(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: narrow ? 10 : 16,
          vertical: 8,
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              free ? Icons.near_me_outlined : Icons.draw_outlined,
              size: 18,
              color: const Color(0xFFC2410C),
            ),
            Text(
              free
                  ? 'Move the preview, then confirm. Nothing is saved yet.'
                  : 'Preview only. Confirm to sign this field.',
              style: TextStyle(
                fontSize: narrow ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
            TextButton(
              key: const Key('docutracker_signature_preview_cancel'),
              onPressed: enabled ? onCancel : null,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('docutracker_signature_preview_confirm'),
              onPressed: enabled ? onConfirm : null,
              style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
              child: const Text('Confirm placement'),
            ),
          ],
        ),
      ),
    );
  }
}
