import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/shared/widgets/user_avatar.dart';
import 'collapsible_dashboard_sidebar.dart';
import 'dashboard_notifications_dropdown.dart';
import 'sign_out_flow.dart';

/// Label for profile header / account menu (employee number only, never auth UUID).
String? dashboardAccountIdLabel(AppUser? user) {
  if (user == null) return null;
  final empId = user.displayEmployeeId;
  if (empId.isEmpty) return null;
  return 'User ID · $empId';
}

/// Human-readable account role for account details and unassigned positions.
String dashboardAccountRoleLabel(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
      return 'Admin';
    case 'super_admin':
      return 'Super Admin';
    case 'hr':
      return 'HR';
    case 'mayor':
      return 'Mayor';
    case 'mayor_office_staff':
      return "Mayor's Office Staff";
    case 'supervisor':
      return 'Supervisor';
    case 'employee':
      return 'Employee';
    default:
      final raw = (role ?? '').trim();
      if (raw.isEmpty) return 'Employee';
      return raw
          .split(RegExp(r'[_\s]+'))
          .where((part) => part.isNotEmpty)
          .map(
            (part) =>
                '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
          )
          .join(' ');
  }
}

/// Sidebar subtitle prefers the assigned job title over the account role.
String dashboardAccountPositionLabel(AppUser? user) {
  final position = (user?.positionName ?? '').trim();
  return position.isNotEmpty ? position : dashboardAccountRoleLabel(user?.role);
}

/// Theme toggle + notifications bell for admin/employee dashboard top bars.
class DashboardHeaderActions extends StatelessWidget {
  const DashboardHeaderActions({
    super.key,
    this.compact = false,
    this.onViewAllNotifications,
    this.onNotificationTap,
    this.showNotifications = true,
  });

  final bool compact;
  final VoidCallback? onViewAllNotifications;
  final void Function(NotificationTapResult? result)? onNotificationTap;

  /// When false, the notification bell is hidden (e.g. mobile, where the bell
  /// lives in the bottom navigation bar instead).
  final bool showNotifications;

  static const Color _darkModeCircleNavy = Color(0xFF1A237E);
  static const Color _darkModeMoonBlue = Color(0xFF90CAF9);
  static const Color _lightModeCircleAmber = Color(0xFFFFF8E1);
  static const Color _lightModeIconYellow = Color(0xFFFFD600);

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeModeNotifier>().isDark;
    final iconSize = compact ? 20.0 : 22.0;
    final pad = compact ? 8.0 : 10.0;
    final circleColor = isDark ? _darkModeCircleNavy : _lightModeCircleAmber;
    final iconColor = isDark ? _darkModeMoonBlue : _lightModeIconYellow;
    final icon = isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          child: Material(
            color: circleColor,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: isDark ? 0 : 1,
            shadowColor: _lightModeIconYellow.withValues(alpha: 0.35),
            child: InkWell(
              onTap: () => context.read<ThemeModeNotifier>().toggle(),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Icon(
                    key: ValueKey<bool>(isDark),
                    icon,
                    color: iconColor,
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showNotifications) ...[
          SizedBox(width: compact ? 6 : 8),
          DashboardNotificationBellButton(
            compact: compact,
            onViewAll: onViewAllNotifications,
            onNotificationTap: onNotificationTap,
          ),
        ],
      ],
    );
  }
}

/// Vertical rule between header action controls (theme / notifications / profile).
class DashboardHeaderActionDivider extends StatelessWidget {
  const DashboardHeaderActionDivider({
    super.key,
    this.compact = false,
    this.emphasized = false,
  });

  final bool compact;

  /// Stronger line before the profile avatar (easier to see).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: emphasized ? 2 : 1,
      height: compact ? 28 : (emphasized ? 36 : 32),
      margin: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: emphasized
            ? AppTheme.primaryNavy.withValues(alpha: 0.35)
            : AppTheme.dashHairlineOf(context),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Header profile photo with accent ring, glow, and hover animation.
class DashboardHeaderProfileAvatar extends StatefulWidget {
  const DashboardHeaderProfileAvatar({
    super.key,
    this.avatarPath,
    this.compact = false,
    this.tooltip,
  });

  final String? avatarPath;
  final bool compact;
  final String? tooltip;

  @override
  State<DashboardHeaderProfileAvatar> createState() =>
      _DashboardHeaderProfileAvatarState();
}

class _DashboardHeaderProfileAvatarState
    extends State<DashboardHeaderProfileAvatar>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.compact ? 18.0 : 20.0;
    final diameter = radius * 2;

    return Tooltip(
      message: widget.tooltip ?? 'Account menu',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final pulseT = _pulse.value;
            final ringOpacity = _hovered ? 1.0 : (0.55 + pulseT * 0.45);
            final glowOpacity = _hovered ? 0.42 : (0.12 + pulseT * 0.16);

            return AnimatedScale(
              scale: _hovered ? 1.07 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(
                        alpha: glowOpacity,
                      ),
                      blurRadius: _hovered ? 16 : 10,
                      spreadRadius: _hovered ? 2 : 0.5,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryNavy.withValues(
                        alpha: ringOpacity,
                      ),
                      width: 2.5,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryNavy.withValues(alpha: 0.12),
                        AppTheme.primaryNavyLight.withValues(alpha: 0.06),
                      ],
                    ),
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: UserAvatar(
            avatarPath: widget.avatarPath,
            radius: radius,
            backgroundColor: AppTheme.dashHairlineOf(context),
            placeholderIconColor: AppTheme.primaryNavy,
          ),
        ),
      ),
    );
  }
}

/// Sidebar footer profile card — accent border, glow, hover + pulse (matches header avatar).
class DashboardSidebarProfileCard extends StatefulWidget {
  const DashboardSidebarProfileCard({
    super.key,
    required this.displayName,
    required this.subtitle,
    this.avatarPath,
    this.collapsed = false,
    this.onProfile,
  });

  final String displayName;
  final String subtitle;
  final String? avatarPath;
  final bool collapsed;

  /// When set, tapping the card toggles the account menu above it.
  final VoidCallback? onProfile;

  @override
  State<DashboardSidebarProfileCard> createState() =>
      _DashboardSidebarProfileCardState();
}

class _DashboardSidebarProfileCardState
    extends State<DashboardSidebarProfileCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const avatarRadius = 20.0;

    final card = sidebarCollapseCrossfade(
      alignment: Alignment.center,
      collapsed: CollapsedSidebarProfileOrb(
        displayName: widget.displayName,
        subtitle: widget.subtitle,
        avatarPath: widget.avatarPath,
      ),
      expanded: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final pulseT = _pulse.value;
          final borderAlpha = _hovered ? 0.85 : (0.45 + pulseT * 0.4);
          final glowAlpha = _hovered ? 0.22 : (0.08 + pulseT * 0.1);

          return MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: _hovered ? 1.02 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.dashPanelOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: borderAlpha),
                    width: _hovered ? 2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(alpha: glowAlpha),
                      blurRadius: _hovered ? 14 : 8,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppTheme.primaryNavy.withValues(
                        alpha: _hovered ? 0.1 : 0.05 + pulseT * 0.04,
                      ),
                      AppTheme.dashMutedSurfaceOf(context),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    _SidebarAvatarRing(
                      avatarPath: widget.avatarPath,
                      radius: avatarRadius,
                      pulse: _pulse,
                      hovered: _hovered,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    final onProfile = widget.onProfile;
    if (onProfile == null) return card;
    return DashboardAccountMenuButton(
      onProfile: onProfile,
      avatarPath: widget.avatarPath,
      openAbove: true,
      child: card,
    );
  }
}

class _SidebarAvatarRing extends StatelessWidget {
  const _SidebarAvatarRing({
    required this.avatarPath,
    required this.radius,
    required this.pulse,
    required this.hovered,
  });

  final String? avatarPath;
  final double radius;
  final Animation<double> pulse;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final ringOpacity = hovered ? 1.0 : (0.55 + pulse.value * 0.45);
        return Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: ringOpacity),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(
                  alpha: hovered ? 0.35 : 0.12 + pulse.value * 0.12,
                ),
                blurRadius: hovered ? 10 : 6,
              ),
            ],
          ),
          child: child,
        );
      },
      child: UserAvatar(
        avatarPath: avatarPath,
        radius: radius,
        backgroundColor: Colors.white,
        placeholderIconColor: AppTheme.primaryNavy,
      ),
    );
  }
}

/// Header avatar that opens a modern account dropdown (profile + sign out).
class DashboardAccountMenuButton extends StatelessWidget {
  const DashboardAccountMenuButton({
    super.key,
    required this.onProfile,
    this.avatarPath,
    this.compact = false,
    this.tooltip,
    this.openAbove = false,
    this.child,
  });

  final VoidCallback onProfile;
  final String? avatarPath;
  final bool compact;
  final String? tooltip;

  /// Places the menu above [child] instead of under the header avatar.
  final bool openAbove;

  /// Custom tap target. The header avatar is used when this is null.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = (auth.user?.role ?? '').trim().toLowerCase();
    if (role == 'admin' ||
        role == 'employee' ||
        role == 'mayor' ||
        role == 'mayor_office_staff') {
      return _AdminAccountMenuButton(
        onProfile: onProfile,
        avatarPath: avatarPath ?? auth.user?.avatarPath,
        compact: compact,
        tooltip: tooltip,
        displayName: auth.displayName,
        email: auth.email,
        roleLabel: dashboardAccountRoleLabel(auth.user?.role),
        employeeId: auth.user?.displayEmployeeId,
        openAbove: openAbove,
        child: child,
      );
    }
    return _LegacyAccountMenuButton(
      onProfile: onProfile,
      avatarPath: avatarPath,
      compact: compact,
      tooltip: tooltip,
    );
  }
}

class _LegacyAccountMenuButton extends StatelessWidget {
  const _LegacyAccountMenuButton({
    required this.onProfile,
    this.avatarPath,
    this.compact = false,
    this.tooltip,
  });

  final VoidCallback onProfile;
  final String? avatarPath;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName;
    final email = auth.email;
    final user = auth.user;
    final idLabel = dashboardAccountIdLabel(user);

    return PopupMenuButton<String>(
      offset: const Offset(0, 52),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: AppTheme.dashPanelOf(context),
      padding: EdgeInsets.zero,
      child: DashboardHeaderProfileAvatar(
        avatarPath: avatarPath,
        compact: compact,
        tooltip: tooltip ?? displayName,
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _AccountMenuHeader(
            displayName: displayName.isNotEmpty ? displayName : 'User',
            email: email,
            idLabel: idLabel,
            avatarPath: avatarPath ?? user?.avatarPath,
            role: user?.role,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'profile',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: _AccountMenuActionRow(
            icon: Icons.settings_outlined,
            label: 'Settings',
            iconBackground: AppTheme.primaryNavy.withValues(alpha: 0.12),
            iconColor: AppTheme.primaryNavy,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'signout',
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: _AccountMenuActionRow(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            iconBackground: const Color(0xFFFFEBEE),
            iconColor: const Color(0xFFC62828),
            labelColor: const Color(0xFFC62828),
            labelWeight: FontWeight.w600,
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'profile') {
          onProfile();
          return;
        }
        if (value == 'signout') {
          await performDashboardSignOut(context);
        }
      },
    );
  }
}

class _AccountMenuHeader extends StatelessWidget {
  const _AccountMenuHeader({
    required this.displayName,
    required this.email,
    this.idLabel,
    this.avatarPath,
    this.role,
  });

  final String displayName;
  final String email;
  final String? idLabel;
  final String? avatarPath;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavy.withValues(alpha: 0.14),
            AppTheme.primaryNavyLight.withValues(alpha: 0.06),
            AppTheme.dashPanelOf(context),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.55),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: UserAvatar(
                  avatarPath: avatarPath,
                  radius: 26,
                  backgroundColor: AppTheme.dashHairlineOf(context),
                  placeholderIconColor: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: primary,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.mail_outline_rounded,
                            size: 14,
                            color: secondary.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                fontSize: 13,
                                color: secondary,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (idLabel != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: AppTheme.dashPanelOf(context).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 16,
                    color: AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      idLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryNavy,
                        letterSpacing: 0.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (role != null && role!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              role!.trim().toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: secondary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountMenuActionRow extends StatelessWidget {
  const _AccountMenuActionRow({
    required this.icon,
    required this.label,
    required this.iconBackground,
    required this.iconColor,
    this.labelColor,
    this.labelWeight = FontWeight.w500,
  });

  final IconData icon;
  final String label;
  final Color iconBackground;
  final Color iconColor;
  final Color? labelColor;
  final FontWeight labelWeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 22, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: labelWeight,
              color: labelColor ?? AppTheme.dashTextPrimaryOf(context),
              letterSpacing: -0.1,
            ),
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          size: 22,
          color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.65),
        ),
      ],
    );
  }
}

class _AdminAccountMenuButton extends StatefulWidget {
  const _AdminAccountMenuButton({
    required this.onProfile,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    this.avatarPath,
    this.employeeId,
    this.compact = false,
    this.tooltip,
    this.openAbove = false,
    this.child,
  });

  final VoidCallback onProfile;
  final String displayName;
  final String email;
  final String roleLabel;
  final String? avatarPath;
  final String? employeeId;
  final bool compact;
  final String? tooltip;
  final bool openAbove;
  final Widget? child;

  @override
  State<_AdminAccountMenuButton> createState() =>
      _AdminAccountMenuButtonState();
}

class _AdminAccountMenuButtonState extends State<_AdminAccountMenuButton> {
  final LayerLink _link = LayerLink();
  final GlobalKey<_AdminAccountDropdownState> _menuKey =
      GlobalKey<_AdminAccountDropdownState>();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _close() async {
    final menu = _menuKey.currentState;
    if (menu != null) {
      await menu.close();
    }
    _removeEntry();
  }

  double _menuWidth(double screenW) {
    if (screenW < 720) return (screenW - 28).clamp(260.0, 340.0);
    return 340;
  }

  /// Horizontal shift so the menu stays on screen when the sidebar is collapsed.
  ///
  /// The profile card is laid out at the full sidebar width and then clipped to
  /// the narrow rail, so its left edge sits off-screen. Anchor the menu to the
  /// right of that visible rail instead.
  double _anchorDx(double menuWidth) {
    if (!widget.openAbove) return 0;
    final target = context.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject();
    if (target is! RenderBox ||
        !target.hasSize ||
        !target.attached ||
        overlay is! RenderBox ||
        !overlay.hasSize) {
      return 0;
    }
    final origin = target.localToGlobal(Offset.zero, ancestor: overlay);
    var menuLeft = origin.dx;
    if (menuLeft < 8) {
      final center = origin.dx + target.size.width / 2;
      menuLeft = center + kDashboardSidebarCollapsedWidth / 2 + 8;
    }
    final maxLeft = overlay.size.width - menuWidth - 8;
    if (menuLeft > maxLeft) menuLeft = maxLeft;
    if (menuLeft < 8) menuLeft = 8;
    return menuLeft - origin.dx;
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final screenW = MediaQuery.sizeOf(context).width;
    final width = _menuWidth(screenW);
    final anchorDx = _anchorDx(width);
    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _AdminAccountDropdown(
          key: _menuKey,
          link: _link,
          width: width,
          anchorDx: anchorDx,
          displayName: widget.displayName.isNotEmpty
              ? widget.displayName
              : 'User',
          email: widget.email,
          roleLabel: widget.roleLabel,
          employeeId: widget.employeeId,
          avatarPath: widget.avatarPath,
          onDismiss: _removeEntry,
          onSettings: () async {
            await _close();
            if (!mounted) return;
            widget.onProfile();
          },
          onSignOut: () async {
            await _close();
            if (!mounted) return;
            await performDashboardSignOut(context);
          },
          openAbove: widget.openAbove,
        );
      },
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: widget.child ??
              DashboardHeaderProfileAvatar(
                avatarPath: widget.avatarPath,
                compact: widget.compact,
                tooltip: widget.tooltip ?? widget.displayName,
              ),
        ),
      ),
    );
  }
}

class _AdminAccountDropdown extends StatefulWidget {
  const _AdminAccountDropdown({
    super.key,
    required this.link,
    required this.width,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.employeeId,
    required this.avatarPath,
    required this.onDismiss,
    required this.onSettings,
    required this.onSignOut,
    this.openAbove = false,
    this.anchorDx = 0,
  });

  final LayerLink link;
  final double width;
  final double anchorDx;
  final String displayName;
  final String email;
  final String roleLabel;
  final String? employeeId;
  final String? avatarPath;
  final VoidCallback onDismiss;
  final Future<void> Function() onSettings;
  final Future<void> Function() onSignOut;
  final bool openAbove;

  @override
  State<_AdminAccountDropdown> createState() => _AdminAccountDropdownState();
}

class _AdminAccountDropdownState extends State<_AdminAccountDropdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
  }

  Future<void> _dismiss() async {
    await close();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor: widget.openAbove
              ? Alignment.topLeft
              : Alignment.bottomRight,
          followerAnchor: widget.openAbove
              ? Alignment.bottomLeft
              : Alignment.topRight,
          offset: Offset(
            widget.openAbove ? widget.anchorDx : 0,
            widget.openAbove ? -8 : 8,
          ),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, widget.openAbove ? 0.06 : -0.06),
                end: Offset.zero,
              ).animate(curved),
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _dismiss();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: _AdminAccountCard(
                  width: widget.width,
                  displayName: widget.displayName,
                  email: widget.email,
                  roleLabel: widget.roleLabel,
                  employeeId: widget.employeeId,
                  avatarPath: widget.avatarPath,
                  onSettings: widget.onSettings,
                  onSignOut: widget.onSignOut,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminAccountCard extends StatelessWidget {
  const _AdminAccountCard({
    required this.width,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.employeeId,
    required this.avatarPath,
    required this.onSettings,
    required this.onSignOut,
  });

  final double width;
  final String displayName;
  final String email;
  final String roleLabel;
  final String? employeeId;
  final String? avatarPath;
  final Future<void> Function() onSettings;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final id = (employeeId ?? '').trim();
    final role = roleLabel.trim();

    return Material(
      color: AppTheme.dashPanelOf(context),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountMenuHeader(
              displayName: displayName,
              email: email,
              idLabel: id.isEmpty ? null : 'User ID · $id',
              avatarPath: avatarPath,
              role: role.isEmpty ? null : role,
            ),
            const Divider(height: 1, thickness: 1),
            _AdminMenuTap(
              onTap: onSettings,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _AccountMenuActionRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                iconBackground: AppTheme.primaryNavy.withValues(alpha: 0.12),
                iconColor: AppTheme.primaryNavy,
              ),
            ),
            const Divider(height: 1, thickness: 1),
            _AdminMenuTap(
              onTap: onSignOut,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: const _AccountMenuActionRow(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                iconBackground: Color(0xFFFFEBEE),
                iconColor: Color(0xFFC62828),
                labelColor: Color(0xFFC62828),
                labelWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMenuTap extends StatefulWidget {
  const _AdminMenuTap({
    required this.onTap,
    required this.padding,
    required this.child,
  });

  final Future<void> Function() onTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<_AdminMenuTap> createState() => _AdminMenuTapState();
}

class _AdminMenuTapState extends State<_AdminMenuTap> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? AppTheme.primaryNavy.withValues(alpha: 0.06)
            : Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}
