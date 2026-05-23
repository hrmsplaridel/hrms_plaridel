import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Hero: Title, subtitle, and primary CTA. No registration link.
/// Opens combined recruitment flow (apply, check status, continue) in one place.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key, this.onRecruitmentTap});

  static const String _heroFont = 'NotoSans';
  static const String _hrmsTitleFont = 'Milanello';

  final VoidCallback? onRecruitmentTap;

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
      decoration: const BoxDecoration(color: Colors.transparent),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/Building.jpg',
                fit: BoxFit.fitWidth,
                alignment: Alignment.center,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.sectionAlt,
                        AppTheme.offWhite,
                        AppTheme.lightGray,
                      ],
                    ),
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
                    'Human Resource Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _hrmsTitleFont,
                      color: AppTheme.primaryNavy,
                      fontSize: isNarrow ? 26 : (isWide ? 44 : 32),
                      fontWeight: FontWeight.w400,
                      height: 1.08,
                      letterSpacing: isWide ? -0.35 : -0.2,
                      wordSpacing: isWide ? 1.5 : 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      'A Digital Platform for Recruitment, Employee Management, and HR Services of the Municipality of Plaridel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _heroFont,
                        color: Colors.white.withValues(alpha: 0.97),
                        fontSize: isNarrow ? 15.5 : (isWide ? 19.5 : 17.5),
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.15,
                        wordSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Semantics(
                    button: true,
                    label: 'Job application',
                    child: OutlinedButton.icon(
                      onPressed: onRecruitmentTap,
                      icon: Icon(
                        Icons.work_outline_rounded,
                        size: isNarrow ? 20 : 22,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      label: Text(
                        'Job application',
                        style: TextStyle(
                          fontFamily: _heroFont,
                          fontWeight: FontWeight.w700,
                          fontSize: isNarrow ? 15 : 16,
                          letterSpacing: 0.2,
                          color: Colors.white,
                          shadows: const [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 8,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.92),
                          width: 1.75,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 22 : 28,
                          vertical: isNarrow ? 14 : 16,
                        ),
                        minimumSize: Size(0, isNarrow ? 48 : 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                    ),
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
