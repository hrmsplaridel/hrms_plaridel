import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/feature_card.dart';

class RspHubFeature {
  const RspHubFeature({
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

const _rspHubFeatures = <RspHubFeature>[
  RspHubFeature(
    title: 'Job Vacancies (Landing Page)',
    subtitle: 'Edit the announcement shown on the landing page.',
    icon: Icons.work_rounded,
    sectionIndex: 1,
  ),
  RspHubFeature(
    title: 'Applications',
    subtitle: 'View applicants, attachments, and document review status.',
    icon: Icons.assignment_rounded,
    sectionIndex: 2,
  ),
  RspHubFeature(
    title: 'Exam Results',
    subtitle: 'View screening exam scores, grade BEI, and pass/fail results.',
    icon: Icons.fact_check_rounded,
    sectionIndex: 16,
  ),
  RspHubFeature(
    title: 'Scheduling',
    subtitle:
        'Deliberation for exam passers and orientation after final requirements are approved.',
    icon: Icons.calendar_month_rounded,
    sectionIndex: 15,
  ),
  RspHubFeature(
    title: 'Final Requirements',
    subtitle:
        'Review medical certificate, drug test, and NBI clearance — then create account and email credentials.',
    icon: Icons.health_and_safety_rounded,
    sectionIndex: 19,
  ),
  RspHubFeature(
    title: 'Exams',
    subtitle:
        'View and edit BEI, General Exam, Mathematics Exam, and General Information Exam questions.',
    icon: Icons.quiz_rounded,
    sectionIndex: 20,
  ),
  RspHubFeature(
    title: 'Forms',
    subtitle:
        'View and edit BI Form, Applicants Profile, Selection Line-Up, Computation of Points, Work Experience Sheet, and Turn Around Time.',
    icon: Icons.description_rounded,
    sectionIndex: 21,
  ),
];

/// RSP hub: title, subtitle, and feature cards (same layout as DTR).
class RspAdminHub extends StatelessWidget {
  const RspAdminHub({super.key, required this.onOpenSection});

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
                  'RSP',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recruitment, Selection, and Placement. Choose a feature below.',
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
            for (final f in _rspHubFeatures)
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
