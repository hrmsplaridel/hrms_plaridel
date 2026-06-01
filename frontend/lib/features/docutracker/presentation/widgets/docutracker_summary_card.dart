import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

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
    this.compact = false,
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
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final displayValue = padValue && value.length < 2
        ? value.padLeft(2, '0')
        : value;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompact = compact || constraints.maxWidth < 165;
        final iconSize = useCompact ? 17.0 : 22.0;
        final iconPad = useCompact ? 7.0 : 10.0;

        return Container(
          padding: useCompact
              ? const EdgeInsets.all(12)
              : const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1F2937) : backgroundColor,
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
            border: Border.all(
              color: dark
                  ? const Color(0xFF374151)
                  : DocuTrackerTokens.borderSubtle,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (useCompact)
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(iconPad),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: iconSize, color: iconColor),
                    ),
                    const Spacer(),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
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
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: badgeColor ?? DocuTrackerTokens.alertOrange,
                          ),
                        ),
                      ),
                  ],
                )
              else
                Container(
                  padding: EdgeInsets.all(iconPad),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: iconSize, color: iconColor),
                ),
              SizedBox(height: useCompact ? 9 : 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DocuTrackerStyles.cardLabelStyle(
                  color: dark ? Colors.white : DocuTrackerTokens.textPrimary,
                ).copyWith(fontSize: useCompact ? 10.5 : 11.5),
              ),
              SizedBox(height: useCompact ? 4 : 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayValue,
                    style: DocuTrackerStyles.cardValueStyle(
                      color: dark
                          ? Colors.white
                          : DocuTrackerTokens.textPrimary,
                    ).copyWith(fontSize: useCompact ? 23 : 28),
                  ),
                  if (!useCompact && badge != null) ...[
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
              SizedBox(height: useCompact ? 3 : 6),
              Text(
                subtitle,
                maxLines: useCompact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: DocuTrackerStyles.cardMetaStyle(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.7)
                      : DocuTrackerTokens.textMuted,
                ).copyWith(fontSize: useCompact ? 10.5 : 11.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
