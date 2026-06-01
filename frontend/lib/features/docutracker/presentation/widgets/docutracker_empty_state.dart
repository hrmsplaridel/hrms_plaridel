import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

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
    final dark = DocuTrackerTokens.isDark(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: dark
                  ? DocuTrackerTokens.surfaceDark
                  : DocuTrackerTokens.surfaceCream,
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DocuTrackerTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: DocuTrackerTokens.subtitleStyle(context),
          ),
        ],
      ),
    );
  }
}
