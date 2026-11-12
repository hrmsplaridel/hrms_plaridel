import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/widgets/section_container.dart';

/// Hero: title, subtitle, primary CTA, and scroll cue over municipal hall photo.
class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    this.height,
    this.onViewVacanciesTap,
    this.onScrollToVacancies,
    this.onTrackApplicationTap,
  });

  static const String _heroFont = 'NotoSans';
  static const String _hrmsTitleFont = 'Milanello';

  /// When set (e.g. from [LayoutBuilder] on the landing page), fills the viewport below the header.
  final double? height;

  final VoidCallback? onViewVacanciesTap;
  final VoidCallback? onScrollToVacancies;

  /// Navigates to the track-application page.
  final VoidCallback? onTrackApplicationTap;

  static double _resolveHeight(BuildContext context, double? height) {
    if (height != null && height.isFinite && height > 0) {
      return height;
    }
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final padding = MediaQuery.paddingOf(context);
    return math.max(520.0, viewportHeight - padding.top - padding.bottom);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > LandingBreakpoints.wide;
    final isNarrow = width < 600;
    final isCompact = width < LandingBreakpoints.compact;
    final heroHeight = _resolveHeight(context, height);
    final hPad = isWide ? 80.0 : (isCompact ? 16.0 : 20.0);
    final vPadTop = isWide ? 48.0 : (isCompact ? 20.0 : 28.0);
    final vPadBottom = isWide ? 40.0 : (isCompact ? 18.0 : 24.0);
    final titleSize = isCompact
        ? 22.0
        : (isNarrow ? 26.0 : (isWide ? 44.0 : 32.0));
    final bodySize = isCompact
        ? 14.5
        : (isNarrow ? 15.5 : (isWide ? 19.0 : 17.0));
    final gapAfterBadge = isCompact ? 14.0 : 20.0;
    final gapAfterTitle = isCompact ? 12.0 : 20.0;
    final gapAfterBody = isCompact ? 24.0 : 36.0;
    final gapBeforeCue = isWide ? 56.0 : (isCompact ? 28.0 : 40.0);

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
            padding: EdgeInsets.fromLTRB(hPad, vPadTop, hPad, vPadBottom),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 10 : 12,
                        vertical: isCompact ? 5 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        isCompact
                            ? 'Official Website · Plaridel'
                            : 'Official Website · Municipality of Plaridel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _heroFont,
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: isCompact ? 10.5 : 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.35,
                        ),
                      ),
                    ),
                    SizedBox(height: gapAfterBadge),
                    Text(
                      'Human Resource Management System',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _hrmsTitleFont,
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w400,
                        height: 1.12,
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
                    SizedBox(height: gapAfterTitle),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Text(
                        'A digital platform for recruitment, employee management, and HR services of the Municipality of Plaridel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _heroFont,
                          color: Colors.white.withValues(alpha: 0.96),
                          fontSize: bodySize,
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
                    SizedBox(height: gapAfterBody),
                    _TrackButton(
                      onTap: onTrackApplicationTap,
                      isNarrow: isNarrow,
                      fullWidth: isCompact,
                      heroFont: _heroFont,
                    ),
                    SizedBox(height: gapBeforeCue),
                    if (scrollToVacancies != null)
                      _ScrollCue(
                        onTap: scrollToVacancies,
                        heroFont: _heroFont,
                      ),
                  ],
                );

                // Short phones: keep hero readable without overflow clipping.
                if (isNarrow) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: content,
                    ),
                  );
                }
                return content;
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Modern animated "Track application status" CTA button ────────────────────

class _TrackButton extends StatefulWidget {
  const _TrackButton({
    required this.onTap,
    required this.isNarrow,
    required this.heroFont,
    this.fullWidth = false,
  });
  final VoidCallback? onTap;
  final bool isNarrow;
  final bool fullWidth;
  final String heroFont;

  @override
  State<_TrackButton> createState() => _TrackButtonState();
}

class _TrackButtonState extends State<_TrackButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.955,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.forward();
  void _onTapUp(_) => _ctrl.reverse();
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final hPad = widget.isNarrow ? 18.0 : 22.0;
    final vPad = widget.isNarrow ? 12.0 : 10.0;
    final iconSize = widget.isNarrow ? 22.0 : 24.0;
    final labelSize = widget.isNarrow ? 13.0 : 14.0;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: widget.fullWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _hovering
              ? [AppTheme.primaryNavy, AppTheme.primaryNavyLight]
              : [AppTheme.primaryNavyDark, AppTheme.primaryNavy],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(
              alpha: _hovering ? 0.5 : 0.35,
            ),
            blurRadius: _hovering ? 16 : 12,
            spreadRadius: _hovering ? 1 : 0,
            offset: Offset(0, _hovering ? 5 : 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.track_changes_rounded,
              color: Colors.white,
              size: iconSize * 0.58,
            ),
          ),
          SizedBox(width: widget.isNarrow ? 8 : 10),
          Flexible(
            child: Text(
              'Track application status',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: widget.heroFont,
                color: Colors.white,
                fontSize: labelSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ),
          SizedBox(width: widget.isNarrow ? 6 : 8),
          Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: labelSize + 1,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: 'Track application status',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: kIsWeb ? (_) => setState(() => _hovering = true) : null,
        onExit: kIsWeb ? (_) => setState(() => _hovering = false) : null,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: button,
          ),
        ),
      ),
    );
  }
}

// ── Animated "See openings" scroll cue ───────────────────────────────────────

class _ScrollCue extends StatefulWidget {
  const _ScrollCue({required this.onTap, required this.heroFont});
  final VoidCallback? onTap;
  final String heroFont;

  @override
  State<_ScrollCue> createState() => _ScrollCueState();
}

class _ScrollCueState extends State<_ScrollCue>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _bounce = Tween<double>(
      begin: 0,
      end: 6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See openings',
                style: TextStyle(
                  fontFamily: widget.heroFont,
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: _bounce,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _bounce.value),
                  child: child,
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
