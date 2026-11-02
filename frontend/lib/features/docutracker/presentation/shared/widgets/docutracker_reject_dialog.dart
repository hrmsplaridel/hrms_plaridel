import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_return_text.dart';

typedef DocuTrackerRejectCallback = Future<bool> Function(String reason);

class DocuTrackerRejectDialog extends StatefulWidget {
  const DocuTrackerRejectDialog({super.key, required this.onConfirm});

  final DocuTrackerRejectCallback onConfirm;

  @override
  State<DocuTrackerRejectDialog> createState() =>
      _DocuTrackerRejectDialogState();
}

class _DocuTrackerRejectDialogState extends State<DocuTrackerRejectDialog> {
  final TextEditingController _reasonController = TextEditingController();
  bool _submitting = false;

  bool get _hasReason => _reasonController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting || !_hasReason) return;
    setState(() => _submitting = true);
    final confirmed = await widget.onConfirm(_reasonController.text.trim());
    if (!mounted) return;
    if (confirmed) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(docuTrackerRejectDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            docuTrackerRejectDialogExplanation,
            style: DocuTrackerTokens.subtitleStyle(
              context,
            ).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('docutracker-reject-reason'),
            controller: _reasonController,
            autofocus: true,
            enabled: !_submitting,
            onChanged: (_) => setState(() {}),
            decoration: DocuTrackerStyles.inputDecoration(
              context,
              'Reason for rejection (required)',
              Icons.cancel_rounded,
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const ValueKey('docutracker-reject-cancel'),
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          style: DocuTrackerStyles.outlinedButtonStyle(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('docutracker-reject-confirm'),
          onPressed: _submitting || !_hasReason ? null : _confirm,
          style: DocuTrackerStyles.destructiveButtonStyle(),
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reject'),
        ),
      ],
    );
  }
}
