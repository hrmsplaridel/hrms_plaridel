import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Hero: Title, subtitle, and primary CTAs. No registration link.
/// Apply for Job → pre-application form; Track Application Status; View Job Vacancies.
class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    this.onApplyForJobTap,
    this.onTrackApplicationTap,
    this.onViewJobVacanciesTap,
  });

  final VoidCallback? onApplyForJobTap;
  final VoidCallback? onTrackApplicationTap;
  final VoidCallback? onViewJobVacanciesTap;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      color: AppTheme.lightGray,
      child: SectionContainer(
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 80 : 24,
          vertical: isWide ? 72 : 48,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Human Resource Management System (HRMS)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: isNarrow ? 22 : (isWide ? 36 : 28),
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                'A Digital Platform for Recruitment, Employee Management, and HR Services of the Municipality of Plaridel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: isNarrow ? 14 : (isWide ? 18 : 16),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onApplyForJobTap,
                  icon: const Icon(Icons.how_to_reg, size: 20),
                  label: const Text('Apply for Job'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    minimumSize: const Size(0, 48),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onTrackApplicationTap,
                  icon: const Icon(Icons.find_in_page_outlined, size: 20),
                  label: const Text('Track Application Status'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: const BorderSide(color: AppTheme.primaryNavy),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    minimumSize: const Size(0, 48),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onViewJobVacanciesTap,
                  icon: const Icon(Icons.work_outline, size: 20),
                  label: const Text('View Job Vacancies'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: const BorderSide(color: AppTheme.primaryNavy),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
