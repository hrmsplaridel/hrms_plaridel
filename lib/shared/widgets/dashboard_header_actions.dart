import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/app_user.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../landingpage/screens/landing_page.dart';
import '../../login/screens/login_page.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../widgets/user_avatar.dart';
import 'collapsible_dashboard_sidebar.dart';
import 'dashboard_notifications_dropdown.dart';

/// Label for profile header / account menu (employee number only, never auth UUID).
String? dashboardAccountIdLabel(AppUser? user) {
  if (user == null) return null;
  final empId = user.displayEmployeeId;
  if (empId.isEmpty) return null;
  return 'Employee ID · $empId';
}

/// Theme toggle + notifications bell for admin/employee dashboard top bars.
class DashboardHeaderActions extends StatelessWidget {
  const DashboardHeaderActions({
    super.key,
    this.compact = false,
    this.onViewAllNotifications,
  });

  final bool compact;
  final VoidCallback? onViewAllNotifications;

  static const Color _moonCircleNavy = Color(0xFF1A237E);
  static const Color _moonIconBlue = Color(0xFF90CAF9);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconSize = compact ? 20.0 : 22.0;
    final pad = compact ? 8.0 : 10.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          child: Material(
            color: _moonCircleNavy,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: InkWell(
              onTap: () => context.read<ThemeModeNotifier>().toggle(),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: _moonIconBlue,
                  size: iconSize,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        DashboardNotificationBellButton(
          compact: compact,
          onViewAll: onViewAllNotifications,
        ),
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
  });

  final String displayName;
  final String subtitle;
  final String? avatarPath;
  final bool collapsed;

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
    final collapsed = widget.collapsed;

    if (collapsed) {
      return CollapsedSidebarProfileOrb(
        displayName: widget.displayName,
        subtitle: widget.subtitle,
        avatarPath: widget.avatarPath,
      );
    }

    return AnimatedBuilder(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                          maxLines: 1,
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
              width: 2.5,
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
        backgroundColor: AppTheme.dashHairlineOf(context),
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
          await context.read<AuthProvider>().signOut();
          if (!context.mounted) return;
          final dest = kIsWeb ? const LandingPage() : const LoginPage();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => dest),
            (route) => false,
          );
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
            Tooltip(
              message: idLabel!,
              child: Container(
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
