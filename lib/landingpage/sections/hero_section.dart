import 'package:flutter/material.dart';
import 'dart:math' as math;
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
    final viewportHeight = MediaQuery.sizeOf(context).height;
    // Make the hero tall enough that "Job Vacancies" is not visible on initial open.
    // Background should be visible only in this hero area (not in the scroll-down content).
    final minHeight = isWide
        ? math.max(760.0, viewportHeight * 0.92)
        : math.max(660.0, viewportHeight * 0.86);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Keep a light overlay so background image is still visible.
        color: Colors.transparent,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/Building.jpg'),
                    // Use `contain` so the image isn't cropped (users asked for fully visible background).
                    // Fill the full width so there are no left/right gaps.
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                // Stronger overlay + gradient to keep title/buttons readable.
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xBFFFFFFF), // more contrast at top
                      Color(0x80FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
            SectionContainer(
              backgroundColor: Colors.transparent,
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 80 : 24,
                // Taller hero so Job Vacancies stays below the fold at open.
                vertical: isWide ? 110 : 80,
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
                fontSize: isNarrow ? 24 : (isWide ? 40 : 30),
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.5,
                shadows: const [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                'A Digital Platform for Recruitment, Employee Management, and HR Services of the Municipality of Plaridel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: isNarrow ? 15 : (isWide ? 19 : 17),
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 14,
              children: [
                FilledButton.icon(
                  onPressed: onApplyForJobTap,
                  icon: const Icon(Icons.how_to_reg, size: 20),
                  label: const Text('Apply for Job'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                    shadowColor: AppTheme.primaryNavy.withOpacity(0.35),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onTrackApplicationTap,
                  icon: const Icon(Icons.find_in_page_outlined, size: 20),
                  label: const Text('Track Application Status'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: const BorderSide(color: AppTheme.primaryNavy, width: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onViewJobVacanciesTap,
                  icon: const Icon(Icons.work_outline, size: 20),
                  label: const Text('View Job Vacancies'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: const BorderSide(color: AppTheme.primaryNavy, width: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            ],
          ),
            ),
          ],
        ),
      ),
    );
  }
}
