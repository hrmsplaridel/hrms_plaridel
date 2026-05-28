import 'package:flutter/material.dart';
import '../theme/docutracker_tokens.dart';

/// Top-of-module title + optional one-line description (dashboard-style).
class DocuTrackerModuleHeader extends StatelessWidget {
  const DocuTrackerModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTrailingBelow =
            trailing != null && constraints.maxWidth < 780;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: DocuTrackerTokens.textPrimaryOf(context),
                          fontSize: 22,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: DocuTrackerTokens.subtitleStyle(context),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null && !stackTrailingBelow) ...[
                  const SizedBox(width: 16),
                  trailing!,
                ],
              ],
            ),
            if (trailing != null && stackTrailingBelow) ...[
              const SizedBox(height: 12),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}
