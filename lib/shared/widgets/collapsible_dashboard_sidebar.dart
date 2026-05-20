import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../widgets/user_avatar.dart';
import 'portal_sidebar_brand.dart';

/// Icon-only rail width — fits orbital nav + medallion header.
const double kDashboardSidebarCollapsedWidth = 72;

/// Collapsed nav touch target (circular orb inside).
const double kDashboardSidebarCollapsedOrbSize = 40;

const Duration kDashboardSidebarAnimationDuration =
    Duration(milliseconds: 280);

/// Below this animated width, sidebar content stays in compact (icon-only) mode.
const double kDashboardSidebarCompactThreshold = 260;

bool dashboardSidebarIsCompact(double width) =>
    width < kDashboardSidebarCompactThreshold;

/// Smoothly animates sidebar width; clips children so nothing paints outside.
class AnimatedSidebarWidth extends StatelessWidget {
  const AnimatedSidebarWidth({
    super.key,
    required this.collapsed,
    required this.builder,
  });

  final bool collapsed;
  final Widget Function(BuildContext context, bool compact) builder;

  @override
  Widget build(BuildContext context) {
    final target =
        collapsed ? kDashboardSidebarCollapsedWidth : kDashboardSidebarWidth;

    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: AnimatedContainer(
        duration: kDashboardSidebarAnimationDuration,
        curve: Curves.easeInOutCubic,
        width: target,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                dashboardSidebarIsCompact(constraints.maxWidth);
            return builder(context, compact);
          },
        ),
      ),
    );
  }
}

/// Collapsed-rail chrome: gradient spine, soft panel wash, right border.
class DashboardSidebarRailFrame extends StatelessWidget {
  const DashboardSidebarRailFrame({
    super.key,
    required this.compact,
    required this.hairline,
    required this.canvas,
    required this.child,
  });

  final bool compact;
  final Color hairline;
  final Color canvas;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: hairline)),
        color: compact ? null : panel,
        gradient: compact
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
          if (compact)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.letterheadNavy.withValues(alpha: 0.9),
                      AppTheme.primaryNavy,
                      AppTheme.primaryNavyLight,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(3),
                    bottomRight: Radius.circular(3),
                  ),
                ),
              ),
            ),
          if (compact)
            Positioned(
              right: 0,
              top: 72,
              bottom: 88,
              child: Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.primaryNavy.withValues(alpha: 0),
                      AppTheme.primaryNavy.withValues(alpha: 0.12),
                      AppTheme.primaryNavy.withValues(alpha: 0),
                    ],
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
    final inactive = AppTheme.dashTextSecondaryOf(context);
    final selected = widget.selected;
    final collapsed = widget.collapsed;

    if (collapsed) {
      return Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 400),
        child: _CollapsedNavOrb(
          icon: widget.icon,
          selected: selected,
          hovered: _hover,
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
        ),
      );
    }

    final bg = selected
        ? AppTheme.primaryNavy
        : (_hover ? AppTheme.dashMutedSurfaceOf(context) : Colors.transparent);
    final fg = selected ? Colors.white : inactive;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
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
    );
  }
}

/// Collapsed nav: left spine tick + circular orb (HRMS signature rail look).
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (selected)
                    Positioned(
                      left: 4,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 4,
                        height: 26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.primaryNavyLight,
                              AppTheme.primaryNavy,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryNavy.withValues(
                                alpha: 0.45,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  AnimatedScale(
                    scale: hovered && !selected ? 1.06 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
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
                                    alpha: dark ? 0.18 : 0.08,
                                  )
                                : Colors.transparent),
                        border: selected
                            ? null
                            : Border.all(
                                color: hovered
                                    ? AppTheme.primaryNavy.withValues(
                                        alpha: 0.35,
                                      )
                                    : AppTheme.dashHairlineOf(context),
                                width: 1.5,
                              ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : (hovered
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: selected ? Colors.white : inactive,
                      ),
                    ),
                  ),
                ],
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
    this.collapsed = false,
  });

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Center(child: _CollapsedSectionGem()),
      );
    }

    return Align(
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
    return Transform.rotate(
      angle: 0.785398, // 45° diamond
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryNavyLight.withValues(alpha: 0.95),
              AppTheme.primaryNavy.withValues(alpha: 0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryNavy.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed footer profile — squircle frame + HR accent bar.
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.15),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.45),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _CollapsedAvatar(avatarPath: avatarPath),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 20,
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
