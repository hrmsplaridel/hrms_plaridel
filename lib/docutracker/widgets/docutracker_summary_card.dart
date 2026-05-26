import 'package:flutter/material.dart';
import '../docutracker_styles.dart';
import '../theme/docutracker_tokens.dart';

/// Summary metric card for the DocuTracker dashboard (mockup-style).
class DocuTrackerSummaryCard extends StatelessWidget {
  const DocuTrackerSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.badge,
    this.badgeColor,
    this.padValue = false,
  });

  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final String? badge;
  final Color? badgeColor;
  final bool padValue;

  @override
  Widget build(BuildContext context) {
    final displayValue = padValue && value.length < 2
        ? value.padLeft(2, '0')
        : value;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
        border: Border.all(color: DocuTrackerTokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: DocuTrackerStyles.cardLabelStyle(
              color: DocuTrackerTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                displayValue,
                style: DocuTrackerStyles.cardValueStyle(
                  color: DocuTrackerTokens.textPrimary,
                ).copyWith(fontSize: 28),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? DocuTrackerTokens.alertOrange)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: badgeColor ?? DocuTrackerTokens.alertOrange,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: DocuTrackerStyles.cardMetaStyle(
              color: DocuTrackerTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
