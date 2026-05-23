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
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: child,
              ),
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

class _FeatureCardState extends State<FeatureCard> {
  bool _hover = false;

  static const double _fallbackWidth = 280;
  static const double _fallbackHeight = 286;

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
    final idleBorder = dark
        ? AppTheme.dashHairlineOf(context)
        : Colors.black.withValues(alpha: 0.07);
    final titleColor = AppTheme.dashTextPrimaryOf(context);
    final subtitleColor = AppTheme.dashTextSecondaryOf(
      context,
    ).withValues(alpha: 0.95);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.015 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: width,
          height: height,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(18),
              hoverColor: dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : navy.withValues(alpha: 0.06),
              splashColor: dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : navy.withValues(alpha: 0.08),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _hover
                        ? navy.withValues(alpha: dark ? 0.55 : 0.35)
                        : idleBorder,
                    width: _hover ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: dark
                            ? (_hover ? 0.45 : 0.28)
                            : (_hover ? 0.12 : 0.06),
                      ),
                      blurRadius: _hover ? 22 : 12,
                      offset: Offset(0, _hover ? 10 : 5),
                    ),
                    if (!dark)
                      BoxShadow(
                        color: navy.withValues(alpha: _hover ? 0.08 : 0.04),
                        blurRadius: _hover ? 18 : 0,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 4,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [navy, AppTheme.primaryNavyLight],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
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
                                      navy.withValues(
                                        alpha: dark ? 0.22 : 0.12,
                                      ),
                                      AppTheme.primaryNavyLight.withValues(
                                        alpha: dark ? 0.14 : 0.08,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: navy.withValues(
                                      alpha: dark ? 0.32 : 0.14,
                                    ),
                                  ),
                                ),
                                child: Icon(widget.icon, size: 28, color: navy),
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
                                          alpha: _hover ? 1 : 0.88,
                                        ),
                                      ),
                                    ),
                                    if (widget.showActionArrow) ...[
                                      const SizedBox(width: 4),
                                      AnimatedSlide(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        offset: _hover
                                            ? const Offset(0.06, 0)
                                            : Offset.zero,
                                        child: Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 20,
                                          color: navy.withValues(
                                            alpha: _hover ? 1 : 0.75,
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
      ),
    );
  }
}
