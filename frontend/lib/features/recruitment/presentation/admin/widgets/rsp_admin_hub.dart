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
    title: 'BEI / Exam Questions',
    subtitle:
        'View and edit the 8 Behavioral Event Interview questions applicants answer.',
    icon: Icons.quiz_rounded,
    sectionIndex: 3,
  ),
  RspHubFeature(
    title: 'General Exam (LGU-Plaridel)',
    subtitle:
        'View and edit the General Exam multiple-choice questions for applicants.',
    icon: Icons.assignment_turned_in_rounded,
    sectionIndex: 4,
  ),
  RspHubFeature(
    title: 'Mathematics Exam',
    subtitle: 'View and edit the Mathematics exam questions for applicants.',
    icon: Icons.calculate_rounded,
    sectionIndex: 5,
  ),
  RspHubFeature(
    title: 'General Information Exam',
    subtitle:
        'View and edit the General Information exam questions for applicants.',
    icon: Icons.info_outline_rounded,
    sectionIndex: 6,
  ),
  RspHubFeature(
    title: 'Background Investigation (BI Form)',
    subtitle:
        'Record BI form entries: applicant, respondent, and competency ratings.',
    icon: Icons.verified_user_rounded,
    sectionIndex: 7,
  ),
  RspHubFeature(
    title: 'Applicants Profile',
    subtitle:
        'Job vacancy details and list of applicants (name, course, address, sex, age, civil status, remark).',
    icon: Icons.people_alt_rounded,
    sectionIndex: 10,
  ),
  RspHubFeature(
    title: 'Selection Line-Up',
    subtitle:
        'Date, agency/office, vacant position, item no., and applicants table.',
    icon: Icons.format_list_numbered_rounded,
    sectionIndex: 13,
  ),
  RspHubFeature(
    title: 'Computation of Points',
    subtitle:
        'Personnel Selection Board scoring: education, eligibility, experience, training, and ranking.',
    icon: Icons.calculate_rounded,
    sectionIndex: 17,
  ),
  RspHubFeature(
    title: 'Work Experience Sheet',
    subtitle:
        'Position, department, minimum standards, job description of last work, and applicant signature.',
    icon: Icons.work_history_rounded,
    sectionIndex: 18,
  ),
  RspHubFeature(
    title: 'Turn Around Time',
    subtitle:
        'Position, office, dates, and applicant tracking through hiring milestones.',
    icon: Icons.schedule_rounded,
    sectionIndex: 14,
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
