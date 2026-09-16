import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/feature_card.dart';

class LdHubFeature {
  const LdHubFeature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sectionIndex,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int sectionIndex;
}

const _ldHubFeatures = <LdHubFeature>[
  LdHubFeature(
    title: 'Forms',
    subtitle:
        'Encode forms and print backgrounds.',
    icon: Icons.description_rounded,
    sectionIndex: 1,
  ),
  LdHubFeature(
    title: 'Training Daily Reports',
    subtitle:
        'Review daily training submissions from employees, open attachments, and mark as seen.',
    icon: Icons.assignment_turned_in_outlined,
    sectionIndex: 3,
  ),
  LdHubFeature(
    title: 'Training Requirements',
    subtitle:
        'Monitor pre-training (invitation letter) and post-training (LAP, certificates) submissions.',
    icon: Icons.fact_check_outlined,
    sectionIndex: 5,
  ),
];

/// L&D hub: title, subtitle, and feature cards (same layout as DTR).
class LdAdminHub extends StatelessWidget {
  const LdAdminHub({super.key, required this.onOpenSection});

  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'L&D',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Learning and Development. Choose a feature below.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        FeatureCardGrid(
          children: [
            for (final f in _ldHubFeatures)
              FeatureCard(
                title: f.title,
                subtitle: f.subtitle,
                icon: f.icon,
                onTap: () => onOpenSection(f.sectionIndex),
              ),
          ],
        ),
      ],
    );
  }
}
