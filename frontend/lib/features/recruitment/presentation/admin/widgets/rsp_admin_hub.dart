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
    title: 'Recruitment Management',
    subtitle:
        'Applications, exam results, scheduling, and final requirements.',
    icon: Icons.groups_rounded,
    sectionIndex: RspAdminHub.recruitmentManagementSection,
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
    subtitle: 'Encode forms and print backgrounds.',
    icon: Icons.description_rounded,
    sectionIndex: 21,
  ),
];

/// RSP hub: title, subtitle, and feature cards (same layout as DTR).
class RspAdminHub extends StatelessWidget {
  const RspAdminHub({super.key, required this.onOpenSection});

  /// Opens Recruitment Management. Internal tabs keep the original section tools.
  static const int recruitmentManagementSection = 22;

  static const recruitmentTabs = <({String label, IconData icon})>[
    (label: 'Applications', icon: Icons.assignment_rounded),
    (label: 'Exam Results', icon: Icons.fact_check_rounded),
    (label: 'Scheduling', icon: Icons.calendar_month_rounded),
    (label: 'Final Requirements', icon: Icons.health_and_safety_rounded),
  ];

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

/// Applications, exam results, scheduling, and final requirements in one page.
///
/// [IndexedStack] keeps each existing section mounted so switching tabs does
/// not drop its state.
class RspRecruitmentManagement extends StatelessWidget {
  const RspRecruitmentManagement({
    super.key,
    required this.tabIndex,
    required this.onTabChanged,
    required this.applications,
    required this.examResults,
    required this.scheduling,
    required this.finalRequirements,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final Widget applications;
  final Widget examResults;
  final Widget scheduling;
  final Widget finalRequirements;

  @override
  Widget build(BuildContext context) {
    final selected = tabIndex.clamp(0, RspAdminHub.recruitmentTabs.length - 1);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final accent = AppTheme.primaryNavy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: muted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < RspAdminHub.recruitmentTabs.length; i++)
                  _RecruitmentTab(
                    label: RspAdminHub.recruitmentTabs[i].label,
                    icon: RspAdminHub.recruitmentTabs[i].icon,
                    selected: i == selected,
                    accent: accent,
                    onTap: () => onTabChanged(i),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        IndexedStack(
          index: selected,
          sizing: StackFit.loose,
          children: [
            applications,
            examResults,
            scheduling,
            finalRequirements,
          ],
        ),
      ],
    );
  }
}

class _RecruitmentTab extends StatelessWidget {
  const _RecruitmentTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected
                      ? Colors.white
                      : AppTheme.dashTextSecondaryOf(context),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: selected
                        ? Colors.white
                        : AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
