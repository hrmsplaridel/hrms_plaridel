import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Hero: title, subtitle, primary CTA, and scroll cue over municipal hall photo.
class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    this.height,
    this.onViewVacanciesTap,
    this.onScrollToVacancies,
  });

  static const String _heroFont = 'NotoSans';
  static const String _hrmsTitleFont = 'Milanello';

  /// When set (e.g. from [LayoutBuilder] on the landing page), fills the viewport below the header.
  final double? height;

  final VoidCallback? onViewVacanciesTap;
  final VoidCallback? onScrollToVacancies;

  static double _resolveHeight(BuildContext context, double? height) {
    if (height != null && height.isFinite && height > 0) {
      return height;
    }
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final padding = MediaQuery.paddingOf(context);
    return math.max(
      520.0,
      viewportHeight - padding.top - padding.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 800;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final heroHeight = _resolveHeight(context, height);

    final scrollToVacancies = onScrollToVacancies ?? onViewVacanciesTap;

    return SizedBox(
      width: double.infinity,
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Image.asset(
            'assets/images/Building.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => DecoratedBox(
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
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          SectionContainer(
            backgroundColor: Colors.transparent,
            withShadow: false,
            padding: EdgeInsets.fromLTRB(
              isWide ? 80 : 24,
              isWide ? 48 : 32,
              isWide ? 80 : 24,
              isWide ? 40 : 28,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'Official Website · Municipality of Plaridel',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _heroFont,
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Human Resource Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _hrmsTitleFont,
                      color: Colors.white,
                      fontSize: isNarrow ? 26 : (isWide ? 44 : 32),
                      fontWeight: FontWeight.w400,
                      height: 1.08,
                      letterSpacing: isWide ? -0.35 : -0.2,
                      shadows: const [
                        Shadow(
                          color: Color(0x88000000),
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      'A digital platform for recruitment, employee management, and HR services of the Municipality of Plaridel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _heroFont,
                        color: Colors.white.withValues(alpha: 0.96),
                        fontSize: isNarrow ? 15.5 : (isWide ? 19 : 17),
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 8,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Semantics(
                    button: true,
                    label: 'View job vacancies',
                    child: FilledButton.icon(
                      onPressed: onViewVacanciesTap,
                      icon: const Icon(Icons.work_outline_rounded, size: 20),
                      label: const Text('View job vacancies'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 22 : 28,
                          vertical: isNarrow ? 14 : 16,
                        ),
                        minimumSize: Size(0, isNarrow ? 48 : 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  SizedBox(height: isWide ? 56 : 40),
                  if (scrollToVacancies != null)
                    Semantics(
                      button: true,
                      label: 'Scroll to job vacancies',
                      child: InkWell(
                        onTap: scrollToVacancies,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'See openings',
                                style: TextStyle(
                                  fontFamily: _heroFont,
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white.withValues(alpha: 0.9),
                                size: 28,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
