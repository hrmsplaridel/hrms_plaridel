import 'package:flutter/material.dart';
import '../theme/docutracker_tokens.dart';

/// Centered empty placeholder for DocuTracker lists and panels.
class DocuTrackerEmptyState extends StatelessWidget {
  const DocuTrackerEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: DocuTrackerTokens.surfaceCream,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 36,
              color: DocuTrackerTokens.terracotta.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DocuTrackerTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: DocuTrackerTokens.subtitleStyle(),
          ),
        ],
      ),
    );
  }
}
