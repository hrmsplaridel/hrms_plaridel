import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';

/// Confirms, deletes an unsubmitted draft, and reports whether it was removed.
Future<bool> confirmDeleteDocuTrackerDraft(
  BuildContext context,
  DocuTrackerDocument doc,
) async {
  final title = doc.title.trim().isEmpty ? 'this draft' : doc.title.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete draft?'),
      content: Text(
        'Delete "$title"? It will leave the document list. '
        'Submitted documents stay in the workflow and cannot be deleted here.',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete draft'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final provider = context.read<DocuTrackerProvider>();
  final deleted = await provider.deleteDraft(doc);
  if (!context.mounted) return deleted;
  if (!deleted) {
    final message = provider.error?.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message != null && message.isNotEmpty
              ? message
              : 'Could not delete the draft.',
        ),
      ),
    );
  }
  return deleted;
}

class DocuTrackerDeleteDraftButton extends StatelessWidget {
  const DocuTrackerDeleteDraftButton({
    super.key,
    required this.doc,
    required this.userId,
    this.isAdmin = false,
    this.onDeleted,
  });

  final DocuTrackerDocument doc;
  final String userId;
  final bool isAdmin;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    if (!DocuTrackerDocumentVisibility.canDeleteDraft(
      doc,
      userId: userId,
      isAdmin: isAdmin,
    )) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Delete draft',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.delete_outline_rounded, size: 20),
      color: const Color(0xFFDC2626),
      onPressed: () async {
        final deleted = await confirmDeleteDocuTrackerDraft(context, doc);
        if (deleted) onDeleted?.call();
      },
    );
  }
}
