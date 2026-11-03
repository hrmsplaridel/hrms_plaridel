import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_document_detail_ui.dart';

/// Read-only notice for native document content that has left draft.
class DocuTrackerContentLockBanner extends StatelessWidget {
  const DocuTrackerContentLockBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final finalized = message.contains('finalized');
    return DocuTrackerDetailActionBanner(
      key: const ValueKey('docutracker-content-lock-banner'),
      icon: finalized ? Icons.lock_rounded : Icons.visibility_outlined,
      title: finalized ? 'Finalized — read only' : 'Read only',
      subtitle: message,
    );
  }
}
