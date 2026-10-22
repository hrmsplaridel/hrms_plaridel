import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'collapsible_dashboard_sidebar.dart';
import 'dashboard_header_actions.dart';

/// Sidebar width — keep in sync with dashboard sidebars.
const double kDashboardSidebarWidth = 276;

double dashboardHeaderBarHeight(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 72 : 76;
}

const String _kUnityPillarLogoAsset = 'assets/images/UnityPillarLogo.png';
const String _kPlaridelSealAsset = 'assets/images/PlaridelLogo.jpg';

/// UnityPillar mark cropped into a circle so it fits the sidebar header.
class _UnityPillarCircle extends StatelessWidget {
  const _UnityPillarCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: Transform.scale(
            scale: 1.18,
            child: UnityPillarLogo(size: size),
          ),
        ),
      ),
    );
  }
}

/// UnityPillar mark. The artwork already has its own shape, so it is not
/// cropped into a circle.
class UnityPillarLogo extends StatelessWidget {
  const UnityPillarLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _kUnityPillarLogoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('UnityPillar logo failed to load: $error');
        return SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.hub_rounded,
            size: size * 0.6,
            color: AppTheme.primaryNavy,
          ),
        );
      },
    );
  }
}

/// Municipality of Plaridel seal, cropped to a circle.
class PlaridelSealLogo extends StatelessWidget {
  const PlaridelSealLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: Colors.white,
          // The JPG has a white margin around the seal; scale in to fill.
          child: Transform.scale(
            scale: 1.12,
            child: Image.asset(
              _kPlaridelSealAsset,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Plaridel seal failed to load: $error');
                return Icon(
                  Icons.account_balance_rounded,
                  size: size * 0.5,
                  color: AppTheme.primaryNavy,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar brand: UnityPillar logo, name, and system title.
class DashboardHeaderBrand extends StatelessWidget {
  const DashboardHeaderBrand({
    super.key,
    this.compact = false,
    this.maxLogoSize,
  });

  /// Slightly smaller logo/text for the drawer.
  final bool compact;

  /// Caps the logo size (e.g. header bar height minus vertical padding).
  final double? maxLogoSize;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final unityColor = dark ? const Color(0xFF7FA8F0) : const Color(0xFF1F4E9E);
    final subtitleColor = dark
        ? AppTheme.dashTextSecondaryOf(context)
        : const Color(0xFF1F3F7A);

    var logoSize = compact ? 52.0 : 56.0;
    final cap = maxLogoSize;
    if (cap != null && logoSize > cap) {
      logoSize = cap;
    }

    final nameStyle = TextStyle(
      fontSize: compact ? 17 : 18,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -0.2,
    );
    final subtitleStyle = TextStyle(
      color: subtitleColor,
      fontSize: compact ? 11.5 : 12,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _UnityPillarCircle(size: logoSize),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Unity',
                        style: TextStyle(color: unityColor),
                      ),
                      const TextSpan(
                        text: 'Pillar',
                        style: TextStyle(color: AppTheme.primaryNavy),
                      ),
                    ],
                  ),
                  style: nameStyle,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text('Human Resource', style: subtitleStyle, maxLines: 1),
                Text('Management System', style: subtitleStyle, maxLines: 1),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Header brand: Plaridel seal with the municipality name.
class DashboardMunicipalityBrand extends StatelessWidget {
  const DashboardMunicipalityBrand({
    super.key,
    this.compact = false,
    this.maxLogoSize,
  });

  final bool compact;
  final double? maxLogoSize;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    var sealSize = compact ? 40.0 : 52.0;
    final cap = maxLogoSize;
    if (cap != null && sealSize > cap) {
      sealSize = cap;
    }

    final smallStyle = TextStyle(
      color: secondary,
      fontSize: compact ? 10 : 12,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    final nameStyle = TextStyle(
      color: primary,
      fontSize: compact ? 12.5 : 15.5,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: 0.1,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PlaridelSealLogo(size: sealSize),
        SizedBox(width: compact ? 8 : 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Republic of the Philippines',
                  style: smallStyle,
                  maxLines: 1,
                ),
                Text('MUNICIPALITY OF PLARIDEL', style: nameStyle, maxLines: 1),
                Text('Misamis Occidental', style: smallStyle, maxLines: 1),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Sidebar header (mobile drawer).
class PortalSidebarBrand extends StatelessWidget {
  const PortalSidebarBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: DashboardHeaderBrand(compact: true),
    );
  }
}

/// Top bar: brand + actions (mobile) or actions only (desktop right column).
class DashboardAppHeaderBar extends StatelessWidget {
  const DashboardAppHeaderBar({
    super.key,
    this.trailing,
    this.showBrand = true,
    this.showMenuButton = false,
    this.onMenuPressed,
    this.showSidebarToggle = false,
    this.onSidebarToggle,
    this.sidebarCollapsed = false,
    this.compactActions = false,
    this.onViewAllNotifications,
    this.onNotificationTap,
    this.showNotifications = true,
  });

  final Widget? trailing;
  final VoidCallback? onViewAllNotifications;
  final void Function(NotificationTapResult? result)? onNotificationTap;

  /// When false, the header notification bell is hidden (mobile uses the bottom
  /// navigation bell instead).
  final bool showNotifications;

  /// Kept for call-site compatibility; the header always shows the Plaridel
  /// seal and municipality name.
  final bool showBrand;
  final bool showMenuButton;
  final VoidCallback? onMenuPressed;

  /// Desktop rail collapse — hamburger at start of content header (edusync-style).
  final bool showSidebarToggle;
  final VoidCallback? onSidebarToggle;
  final bool sidebarCollapsed;
  final bool compactActions;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final compact = compactActions || isNarrow;
    final barH = dashboardHeaderBarHeight(context);

    return Container(
      height: barH,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showMenuButton) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: onMenuPressed,
              color: AppTheme.dashTextPrimaryOf(context),
              tooltip: 'Menu',
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: hairline,
            ),
          ],
          Expanded(
            child: DashboardMunicipalityBrand(
              compact: isNarrow,
              maxLogoSize: barH - 16,
            ),
          ),
          DashboardHeaderActions(
            compact: compact,
            onViewAllNotifications: onViewAllNotifications,
            onNotificationTap: onNotificationTap,
            showNotifications: showNotifications,
          ),
          if (trailing != null) ...[
            DashboardHeaderActionDivider(compact: compact, emphasized: true),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Brand block sized for the sidebar rail header (matches top bar height).
class SidebarRailHeader extends StatelessWidget {
  const SidebarRailHeader({super.key, this.onToggle});

  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final barH = dashboardHeaderBarHeight(context);

    return Container(
      height: barH,
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.only(left: 8, right: 6),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      child: sidebarCollapseCrossfade(
        expanded: Row(
          children: [
            Expanded(
              child: DashboardHeaderBrand(
                compact: true,
                maxLogoSize: barH - 18,
              ),
            ),
            if (onToggle != null)
              SidebarCollapseButton(
                onPressed: onToggle!,
                tooltip: 'Collapse sidebar',
              ),
          ],
        ),
        collapsed: Center(
          child: _CollapsedSidebarLogo(onExpand: onToggle, size: 46),
        ),
      ),
    );
  }
}

/// Logo left behind when the sidebar is collapsed. Dragging or resting the
/// pointer on it reveals the button that opens the sidebar again.
class _CollapsedSidebarLogo extends StatefulWidget {
  const _CollapsedSidebarLogo({required this.onExpand, required this.size});

  final VoidCallback? onExpand;
  final double size;

  @override
  State<_CollapsedSidebarLogo> createState() => _CollapsedSidebarLogoState();
}

class _CollapsedSidebarLogoState extends State<_CollapsedSidebarLogo> {
  final GlobalKey _logoKey = GlobalKey();
  OverlayEntry? _entry;
  Timer? _hideTimer;
  bool _overLogo = false;
  bool _overButton = false;

  bool get _fullyCollapsed => SidebarCollapseScope.of(context) > 0.98;

  void _reveal() {
    _hideTimer?.cancel();
    if (!_fullyCollapsed || widget.onExpand == null || _entry != null) return;
    final overlay = Overlay.maybeOf(context);
    final box = _logoKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    _entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: origin.dx + box.size.width + 6,
          top: origin.dy + (box.size.height - 32) / 2,
          child: MouseRegion(
            onEnter: (_) {
              _overButton = true;
              _hideTimer?.cancel();
            },
            onExit: (_) {
              _overButton = false;
              _scheduleHide();
            },
            child: Material(
              color: AppTheme.dashPanelOf(overlayContext),
              elevation: 3,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              child: SidebarCollapseButton(
                onPressed: () {
                  _removeButton();
                  widget.onExpand?.call();
                },
                tooltip: 'Expand sidebar',
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 220), () {
      if (!_overLogo && !_overButton) _removeButton();
    });
  }

  void _removeButton() {
    _hideTimer?.cancel();
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_fullyCollapsed && _entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _removeButton();
      });
    }
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) {
        _overLogo = true;
        _reveal();
      },
      onExit: (_) {
        _overLogo = false;
        _scheduleHide();
      },
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          if (details.delta.dx > 0.5) _reveal();
        },
        child: _UnityPillarCircle(key: _logoKey, size: widget.size),
      ),
    );
  }
}

/// Panel icon that collapses or expands the sidebar.
class SidebarCollapseButton extends StatelessWidget {
  const SidebarCollapseButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final color = dark ? Colors.white : const Color(0xFF1F1F1F);
    return IconButton(
      icon: _CursorSidebarToggleIcon(color: color),
      onPressed: onPressed,
      color: color,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        hoverColor: color.withValues(alpha: dark ? 0.12 : 0.06),
        highlightColor: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fixedSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Rounded window with the left panel marked. Same control ChatGPT puts in the sidebar.
class _CursorSidebarToggleIcon extends StatelessWidget {
  const _CursorSidebarToggleIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(16),
      painter: _CursorSidebarToggleIconPainter(color),
    );
  }
}

class _CursorSidebarToggleIconPainter extends CustomPainter {
  const _CursorSidebarToggleIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.shortestSide * 0.085).clamp(1.15, 1.4);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inset = stroke / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - stroke,
      size.height - stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.18)),
      paint,
    );
    final x = rect.left + rect.width * 0.34;
    canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
  }

  @override
  bool shouldRepaint(covariant _CursorSidebarToggleIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
