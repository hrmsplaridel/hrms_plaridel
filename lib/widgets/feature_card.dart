import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';

/// Responsive grid for [FeatureCard] rows — cards stretch to fill width.
class FeatureCardGrid extends StatelessWidget {
  const FeatureCardGrid({
    super.key,
    required this.children,
    this.minCardWidth = 260,
    this.cardHeight = 286,
    this.spacing = 16,
  });

  final List<Widget> children;
  final double minCardWidth;
  final double cardHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (!maxW.isFinite || maxW <= 0) {
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: children,
          );
        }

        var columns = ((maxW + spacing) / (minCardWidth + spacing)).floor();
        columns = columns.clamp(1, 8);
        final cardWidth = (maxW - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, height: cardHeight, child: child),
          ],
        );
      },
    );
  }
}

/// Reusable feature card for RSP, DTR, L&D, and other dashboard sections.
/// Tap target with hover lift, top accent, icon tile, and optional action label.
class FeatureCard extends StatefulWidget {
  const FeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.actionLabel,
    this.maxSubtitleLines = 5,
    this.showActionArrow = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  /// Shown on the bottom row (defaults to "Open"), aligned right.
  final String? actionLabel;

  /// Lines of subtitle before ellipsis.
  final int maxSubtitleLines;

  /// When false, only the action label is shown (no trailing arrow).
  final bool showActionArrow;

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverCtrl;
  late final Animation<double> _hoverT;

  static const double _fallbackWidth = 280;
  static const double _fallbackHeight = 286;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _hoverT = CurvedAnimation(
      parent: _hoverCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : _fallbackWidth;
        final height =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : _fallbackHeight;

        return _buildCard(width: width, height: height);
      },
    );
  }

  Widget _buildCard({required double width, required double height}) {
    final navy = AppTheme.primaryNavy;
    final action = widget.actionLabel ?? 'Open';
    final dark = AppTheme.dashIsDark(context);
    final cardBg = dark ? const Color(0xFF1E2430) : AppTheme.white;
    final hoverCardBg = dark ? const Color(0xFF232A38) : AppTheme.white;
    final idleBorder = dark
        ? AppTheme.dashHairlineOf(context)
        : Colors.black.withValues(alpha: 0.07);
    final hoverBorder = navy.withValues(alpha: dark ? 0.6 : 0.4);
    final titleColor = AppTheme.dashTextPrimaryOf(context);
    final subtitleColor = AppTheme.dashTextSecondaryOf(
      context,
    ).withValues(alpha: 0.95);

    return MouseRegion(
      onEnter: (_) => _hoverCtrl.forward(),
      onExit: (_) => _hoverCtrl.reverse(),
      cursor: SystemMouseCursors.click,
      opaque: true,
      hitTestBehavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _hoverT,
        builder: (context, child) {
          final t = _hoverT.value;

          final liftY = lerpDouble(0, -4, t)!;
          final accentH = lerpDouble(4, 5, t)!;
          final borderW = lerpDouble(1, 1.5, t)!;
          final shadowBlur = lerpDouble(12, 26, t)!;
          final shadowY = lerpDouble(5, 12, t)!;
          final shadowAlpha = lerpDouble(
            dark ? 0.28 : 0.06,
            dark ? 0.5 : 0.14,
            t,
          )!;
          final actionAlpha = lerpDouble(0.82, 1, t)!;
          final arrowOffset = lerpDouble(0, 0.08, t)!;

          final cardColor = Color.lerp(cardBg, hoverCardBg, t)!;
          final borderColor = Color.lerp(idleBorder, hoverBorder, t)!;

          final iconGradA = lerpDouble(
            dark ? 0.22 : 0.12,
            dark ? 0.3 : 0.16,
            t,
          )!;
          final iconGradB = lerpDouble(
            dark ? 0.14 : 0.08,
            dark ? 0.2 : 0.12,
            t,
          )!;
          final iconBorderA = lerpDouble(
            dark ? 0.32 : 0.14,
            dark ? 0.45 : 0.22,
            t,
          )!;

          return Transform.translate(
            offset: Offset(0, liftY),
            child: SizedBox(
              width: width,
              height: height,
              child: Material(
                color: Colors.transparent,
                elevation: 0,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(18),
                  hoverColor: Colors.transparent,
                  splashColor: dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : navy.withValues(alpha: 0.08),
                  highlightColor: dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : navy.withValues(alpha: 0.04),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor, width: borderW),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: shadowAlpha),
                          blurRadius: shadowBlur,
                          spreadRadius: lerpDouble(0, 0.5, t)!,
                          offset: Offset(0, shadowY),
                        ),
                        if (!dark)
                          BoxShadow(
                            color: navy.withValues(
                              alpha: lerpDouble(0.04, 0.1, t)!,
                            ),
                            blurRadius: lerpDouble(0, 20, t)!,
                            offset: Offset(0, lerpDouble(4, 6, t)!),
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: accentH,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  navy,
                                  Color.lerp(
                                    AppTheme.primaryNavyLight.withValues(
                                      alpha: 0.85,
                                    ),
                                    AppTheme.primaryNavyLight,
                                    t,
                                  )!,
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          navy.withValues(alpha: iconGradA),
                                          AppTheme.primaryNavyLight.withValues(
                                            alpha: iconGradB,
                                          ),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: navy.withValues(
                                          alpha: iconBorderA,
                                        ),
                                      ),
                                    ),
                                    child: Icon(
                                      widget.icon,
                                      size: 28,
                                      color: navy,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    widget.title,
                                    style: TextStyle(
                                      color: titleColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Text(
                                      widget.subtitle,
                                      style: TextStyle(
                                        color: subtitleColor,
                                        fontSize: 13,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: widget.maxSubtitleLines,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          action,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            letterSpacing: 0.15,
                                            color: navy.withValues(
                                              alpha: actionAlpha,
                                            ),
                                          ),
                                        ),
                                        if (widget.showActionArrow) ...[
                                          const SizedBox(width: 4),
                                          Transform.translate(
                                            offset: Offset(arrowOffset * 20, 0),
                                            child: Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 20,
                                              color: navy.withValues(
                                                alpha: lerpDouble(0.72, 1, t)!,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
