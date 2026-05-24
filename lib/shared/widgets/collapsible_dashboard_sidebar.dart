import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../widgets/user_avatar.dart';
import 'portal_sidebar_brand.dart';

/// Icon-only rail width — fits orbital nav + medallion header.
const double kDashboardSidebarCollapsedWidth = 72;

/// Expanded sidebar width (must match [kDashboardSidebarWidth] in portal_sidebar_brand).
const double kDashboardSidebarExpandedWidth = kDashboardSidebarWidth;

/// Collapsed nav touch target (circular orb inside).
const double kDashboardSidebarCollapsedOrbSize = 40;

const Duration kDashboardSidebarAnimationDuration =
    Duration(milliseconds: 280);

/// 0 = fully expanded, 1 = fully collapsed.
class SidebarCollapseScope extends InheritedWidget {
  const SidebarCollapseScope({
    super.key,
    required this.collapseT,
    required super.child,
  });

  final double collapseT;

  static double of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SidebarCollapseScope>();
    return scope?.collapseT ?? 0;
  }

  static double? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<SidebarCollapseScope>()
        ?.collapseT;
  }

  @override
  bool updateShouldNotify(SidebarCollapseScope oldWidget) =>
      oldWidget.collapseT != collapseT;
}

/// Animates width only; [child] is laid out at full expanded width and clipped.
/// Content cross-fades via [SidebarCollapseScope] — no tree swap per frame.
class AnimatedSidebarWidth extends StatefulWidget {
  const AnimatedSidebarWidth({
    super.key,
    required this.collapsed,
    required this.child,
  });

  final bool collapsed;
  final Widget child;

  @override
  State<AnimatedSidebarWidth> createState() => _AnimatedSidebarWidthState();
}

class _AnimatedSidebarWidthState extends State<AnimatedSidebarWidth>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _collapseT;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kDashboardSidebarAnimationDuration,
    );
    _collapseT = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    if (widget.collapsed) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(AnimatedSidebarWidth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed) {
      if (widget.collapsed) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _collapseT,
      child: widget.child,
      builder: (context, child) {
        final t = _collapseT.value;
        final width = lerpDouble(
          kDashboardSidebarExpandedWidth,
          kDashboardSidebarCollapsedWidth,
          t,
        )!;
        // Lay out at full expanded width inside OverflowBox so collapsing
        // never squeezes the tree to 72px (which broke translate + clip).
        final alignX = lerpDouble(-1.0, 0.0, t)!;
        return ClipRect(
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: width,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                return SidebarCollapseScope(
                  collapseT: t,
                  child: OverflowBox(
                    minWidth: kDashboardSidebarExpandedWidth,
                    maxWidth: kDashboardSidebarExpandedWidth,
                    minHeight: h,
                    maxHeight: h,
                    alignment: Alignment(alignX, 0),
                    child: SizedBox(
                      width: kDashboardSidebarExpandedWidth,
                      height: h,
                      child: child!,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight expanded ↔ collapsed cross-fade (no [AnimatedSwitcher]).
Widget sidebarCollapseCrossfade({
  required Widget expanded,
  required Widget collapsed,
  AlignmentGeometry alignment = Alignment.center,
}) {
  return Builder(
    builder: (context) {
      final t = SidebarCollapseScope.of(context);
      final fadeOut = Curves.easeInCubic.transform((1 - t).clamp(0.0, 1.0));
      final fadeIn = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
      return Stack(
        alignment: alignment,
        children: [
          Opacity(
            opacity: fadeOut,
            child: IgnorePointer(
              ignoring: t > 0.5,
              child: expanded,
            ),
          ),
          Opacity(
            opacity: fadeIn,
            child: IgnorePointer(
              ignoring: t < 0.5,
              child: collapsed,
            ),
          ),
        ],
      );
    },
  );
}

/// Collapsed-rail chrome: gradient spine, soft panel wash, right border.
class DashboardSidebarRailFrame extends StatelessWidget {
  const DashboardSidebarRailFrame({
    super.key,
    required this.hairline,
    required this.canvas,
    required this.child,
  });

  final Color hairline;
  final Color canvas;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    final t = SidebarCollapseScope.maybeOf(context) ?? 0.0;
    final showRailChrome = t > 0.35;

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: hairline)),
        color: showRailChrome ? null : panel,
        gradient: showRailChrome
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  panel,
                  Color.lerp(panel, canvas, 0.45)!,
                ],
              )
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3 * t,
            child: Opacity(
              opacity: t,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.letterheadNavy,
                      AppTheme.primaryNavy,
                      AppTheme.primaryNavyLight,
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Nav row used by admin and employee sidebars.
class DashboardSidebarNavTile extends StatefulWidget {
  const DashboardSidebarNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    @Deprecated('Reads collapse progress from SidebarCollapseScope')
    this.collapsed = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  State<DashboardSidebarNavTile> createState() =>
      _DashboardSidebarNavTileState();
}

class _DashboardSidebarNavTileState extends State<DashboardSidebarNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = SidebarCollapseScope.of(context);
    final inactive = AppTheme.dashTextSecondaryOf(context);
    final selected = widget.selected;
    final bg = selected
        ? AppTheme.primaryNavy
        : (_hover ? AppTheme.dashMutedSurfaceOf(context) : Colors.transparent);
    final fg = selected ? Colors.white : inactive;
    final fadeOut = Curves.easeInCubic.transform((1 - t).clamp(0.0, 1.0));
    final fadeIn = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

    return RepaintBoundary(
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: fadeOut,
              child: IgnorePointer(
                ignoring: t > 0.5,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = true),
                  onExit: (_) => setState(() => _hover = false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(widget.icon, size: 22, color: fg),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  widget.label,
                                  style: TextStyle(
                                    color: fg,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 14,
                                    letterSpacing: -0.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
            ),
            Opacity(
              opacity: fadeIn,
              child: IgnorePointer(
                ignoring: t < 0.5,
                child: Tooltip(
                  message: widget.label,
                  waitDuration: const Duration(milliseconds: 400),
                  child: _CollapsedNavOrb(
                    icon: widget.icon,
                    selected: selected,
                    hovered: _hover,
                    onTap: widget.onTap,
                    onHover: (v) => setState(() => _hover = v),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed nav: centered circular orb (reference rail style).
class _CollapsedNavOrb extends StatelessWidget {
  const _CollapsedNavOrb({
    required this.icon,
    required this.selected,
    required this.hovered,
    required this.onTap,
    required this.onHover,
  });

  final IconData icon;
  final bool selected;
  final bool hovered;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final inactive = AppTheme.dashTextSecondaryOf(context);

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Container(
              width: kDashboardSidebarCollapsedOrbSize,
              height: kDashboardSidebarCollapsedOrbSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryNavyLight,
                          AppTheme.primaryNavy,
                        ],
                      )
                    : null,
                color: selected
                    ? null
                    : (hovered
                        ? AppTheme.primaryNavy.withValues(
                            alpha: dark ? 0.14 : 0.06,
                          )
                        : Colors.white),
                border: selected
                    ? null
                    : Border.all(
                        color: hovered
                            ? AppTheme.primaryNavy.withValues(alpha: 0.4)
                            : AppTheme.dashHairlineOf(context),
                        width: 1.5,
                      ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? Colors.white : inactive,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section label (expanded) or gem marker (collapsed).
class DashboardSidebarSectionLabel extends StatelessWidget {
  const DashboardSidebarSectionLabel(
    this.label, {
    super.key,
    @Deprecated('Uses SidebarCollapseScope') this.collapsed = false,
  });

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return sidebarCollapseCrossfade(
      alignment: Alignment.center,
      expanded: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.dashIsDark(context)
                  ? AppTheme.primaryNavyLight.withValues(alpha: 0.95)
                  : AppTheme.letterheadNavy.withValues(alpha: 0.92),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.15,
              height: 1.1,
            ),
          ),
        ),
      ),
      collapsed: const Padding(
        padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Center(child: _CollapsedSectionGem()),
      ),
    );
  }
}

/// Distinct section break — stacked diamond dots (no letter labels).
class _CollapsedSectionGem extends StatelessWidget {
  const _CollapsedSectionGem();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gemDot(context, 0.55),
        const SizedBox(height: 5),
        _gemDot(context, 1),
        const SizedBox(height: 5),
        _gemDot(context, 0.55),
      ],
    );
  }

  Widget _gemDot(BuildContext context, double scale) {
    final size = 5.0 * scale;
    final isCenter = scale >= 0.99;
    return Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isCenter
                ? const [
                    AppTheme.primaryNavyLight,
                    AppTheme.primaryNavy,
                  ]
                : [
                    AppTheme.primaryNavy.withValues(alpha: 0.55),
                    AppTheme.primaryNavy.withValues(alpha: 0.35),
                  ],
          ),
          borderRadius: BorderRadius.circular(1.5),
          boxShadow: isCenter
              ? [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// Collapsed footer profile — avatar + spinning orange accent ring.
class CollapsedSidebarProfileOrb extends StatelessWidget {
  const CollapsedSidebarProfileOrb({
    super.key,
    required this.displayName,
    required this.subtitle,
    this.avatarPath,
  });

  final String displayName;
  final String subtitle;
  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$displayName\n$subtitle',
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SidebarRotatingAccentRing(
          size: 44,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: _CollapsedAvatar(avatarPath: avatarPath),
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedAvatar extends StatelessWidget {
  const _CollapsedAvatar({this.avatarPath});

  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: UserAvatar(
        avatarPath: avatarPath,
        radius: 18,
        backgroundColor: AppTheme.dashMutedSurfaceOf(context),
        placeholderIconColor: AppTheme.primaryNavy,
      ),
    );
  }
}

/// Spinning orange arc around rail logo or profile (collapsed sidebar).
class SidebarRotatingAccentRing extends StatefulWidget {
  const SidebarRotatingAccentRing({
    super.key,
    required this.size,
    required this.child,
    this.showAccentBar = true,
    this.backgroundColor,
    this.boxShadow,
  });

  final double size;
  final Widget child;
  final bool showAccentBar;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;

  @override
  State<SidebarRotatingAccentRing> createState() =>
      _SidebarRotatingAccentRingState();
}

class _SidebarRotatingAccentRingState extends State<SidebarRotatingAccentRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.backgroundColor ?? AppTheme.dashPanelOf(context);
    final shadow = widget.boxShadow ??
        [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: panel,
            boxShadow: shadow,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _spin,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: SidebarAccentRingPainter(
                      rotation: _spin.value * 2 * math.pi,
                    ),
                  );
                },
              ),
              widget.child,
            ],
          ),
        ),
        if (widget.showAccentBar) ...[
          const SizedBox(height: 8),
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [
                  AppTheme.primaryNavyLight,
                  AppTheme.primaryNavy,
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Orange accent segment that spins around a circular rail element.
class SidebarAccentRingPainter extends CustomPainter {
  const SidebarAccentRingPainter({
    required this.rotation,
    this.strokeWidth = 2.5,
  });

  final double rotation;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;

    final trackPaint = Paint()
      ..color = AppTheme.primaryNavy.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, trackPaint);

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final arcPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          AppTheme.primaryNavyLight,
          AppTheme.primaryNavy,
          AppTheme.primaryNavyDark,
          AppTheme.primaryNavyLight,
        ],
        stops: [0, 0.4, 0.7, 1],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 1.35, false, arcPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SidebarAccentRingPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.strokeWidth != strokeWidth;
}
