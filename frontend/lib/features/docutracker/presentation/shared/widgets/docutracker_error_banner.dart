import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// Inline error banner matching the documents screen pattern.
class DocuTrackerErrorBanner extends StatelessWidget {
  const DocuTrackerErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
  });

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: DocuTrackerTokens.errorBannerDecoration(context),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: DocuTrackerTokens.errorBannerIcon(context),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: DocuTrackerTokens.errorBannerForeground(context),
                fontSize: 13,
              ),
            ),
          ),
          if (onDismiss != null)
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                foregroundColor: DocuTrackerTokens.brand,
              ),
              child: const Text('Dismiss'),
            ),
        ],
      ),
    );
  }
}

void showDocuTrackerProviderError(
  BuildContext context,
  DocuTrackerProvider provider, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (!context.mounted) return;
  final msg = provider.error?.trim();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg != null && msg.isNotEmpty ? msg : fallback)),
  );
}
