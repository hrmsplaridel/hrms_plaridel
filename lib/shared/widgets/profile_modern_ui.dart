import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Geometric accent mesh for the profile hero (replaces flat waves).
class ProfileHeroMeshPainter extends CustomPainter {
  ProfileHeroMeshPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final navy = dark ? const Color(0xFF2A3550) : AppTheme.primaryNavy;
    final orange = const Color(0xFFE85D04);

    final orb = Paint()
      ..shader = RadialGradient(
        colors: [
          orange.withValues(alpha: dark ? 0.35 : 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.88, size.height * 0.15),
        radius: size.width * 0.42,
      ));
    canvas.drawRect(Offset.zero & size, orb);

    final arc = Paint()
      ..color = Colors.white.withValues(alpha: dark ? 0.06 : 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path();
    path.moveTo(size.width * 0.55, 0);
    path.quadraticBezierTo(
      size.width * 0.2,
      size.height * 0.45,
      -20,
      size.height * 0.9,
    );
    canvas.drawPath(path, arc);

    final dots = Paint()
      ..color = navy.withValues(alpha: 0.08);
    for (var x = 16.0; x < size.width; x += 28) {
      for (var y = 12.0; y < size.height * 0.55; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.2, dots);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ProfileHeroMeshPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

/// Role-based accent for profile hero chips.
class ProfileRoleStyle {
  const ProfileRoleStyle({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  static ProfileRoleStyle fromLabel(String roleLabel) {
    final r = roleLabel.toLowerCase();
    if (r.contains('admin')) {
      return ProfileRoleStyle(
        label: roleLabel,
        color: AppTheme.primaryNavy,
        icon: Icons.admin_panel_settings_rounded,
      );
    }
    if (r.contains('hr')) {
      return ProfileRoleStyle(
        label: roleLabel,
        color: const Color(0xFF1565C0),
        icon: Icons.groups_rounded,
      );
    }
    return ProfileRoleStyle(
      label: roleLabel,
      color: const Color(0xFF2E7D32),
      icon: Icons.badge_outlined,
    );
  }
}

/// Circular back control for the profile hero (dashboard settings overlay).
class ProfileBackButton extends StatelessWidget {
  const ProfileBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Tooltip(
      message: 'Back',
      child: Material(
        color: dark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: dark ? Colors.white : AppTheme.primaryNavy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Identity hero: overlapping avatar, single metadata row, navy band.
class ProfileHeroHeader extends StatelessWidget {
  const ProfileHeroHeader({
    super.key,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.avatar,
    this.idLabel,
    this.wideLayout = false,
    this.onChangePhoto,
    this.isUploading = false,
    this.onBack,
  });

  final String displayName;
  final String email;
  final String roleLabel;
  final Widget avatar;
  final String? idLabel;
  final bool wideLayout;
  final VoidCallback? onChangePhoto;
  final bool isUploading;
  final VoidCallback? onBack;

  static const double _avatarRadius = 54;
  static const double _headerBandHeight = 118;
  /// Avatar overlaps below the navy band; header stack must include this so taps register.
  static const double _avatarOverlap = _avatarRadius;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final roleStyle = ProfileRoleStyle.fromLabel(roleLabel);
    final titleColor = dark ? const Color(0xFFF4F7FB) : Colors.white;
    final bodyBg = dark ? const Color(0xFF1A1F2A) : const Color(0xFFFAFBFC);
    final muted = AppTheme.dashTextSecondaryOf(context);
    final primaryText = AppTheme.dashTextPrimaryOf(context);

    final bandGradient = dark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E2A3D), Color(0xFF243B55)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryNavy, Color(0xFF2D4A7C)],
          );

    Widget avatarFrame() {
      final frame = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: _avatarRadius * 2 + 10,
            height: _avatarRadius * 2 + 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE85D04), Color(0xFFFFB74D)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          Container(
            width: _avatarRadius * 2 + 4,
            height: _avatarRadius * 2 + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: ClipOval(child: avatar),
          ),
          if (onChangePhoto != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: const Color(0xFFE85D04),
                elevation: 4,
                shadowColor: Colors.black26,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: isUploading ? null : onChangePhoto,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      if (onChangePhoto == null || isUploading) return frame;
      return GestureDetector(
        onTap: onChangePhoto,
        behavior: HitTestBehavior.opaque,
        child: frame,
      );
    }

    Widget headerBandStack({required List<Widget> children}) {
      return SizedBox(
        height: _headerBandHeight + _avatarOverlap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _headerBandHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: bandGradient),
                child: CustomPaint(
                  painter: ProfileHeroMeshPainter(dark: dark),
                ),
              ),
            ),
            ...children,
          ],
        ),
      );
    }

    Widget metaChip({
      required IconData icon,
      required String text,
      required Color accent,
      bool onDark = false,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.12)
              : accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: onDark
                ? Colors.white.withValues(alpha: 0.2)
                : accent.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: onDark ? Colors.white.withValues(alpha: 0.9) : accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: onDark ? Colors.white : primaryText,
                  letterSpacing: 0.15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final identityBody = Column(
      crossAxisAlignment:
          wideLayout ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: wideLayout
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                displayName,
                textAlign: wideLayout ? TextAlign.start : TextAlign.center,
                style: TextStyle(
                  color: primaryText,
                  fontSize: wideLayout ? 26 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.verified_rounded,
                size: wideLayout ? 22 : 20,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment:
              wideLayout ? WrapAlignment.start : WrapAlignment.center,
          children: [
            if (idLabel != null)
              metaChip(
                icon: Icons.pin_rounded,
                text: idLabel!,
                accent: AppTheme.primaryNavy,
              ),
            metaChip(
              icon: roleStyle.icon,
              text: roleStyle.label,
              accent: roleStyle.color,
            ),
            metaChip(
              icon: Icons.alternate_email_rounded,
              text: email.isEmpty ? 'No email' : email,
              accent: muted,
            ),
          ],
        ),
      ],
    );

    if (wideLayout) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: bodyBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(bottom: BorderSide(color: AppTheme.dashHairlineOf(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headerBandStack(
              children: [
                Positioned(
                  left: 20,
                  top: 20,
                  right: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (onBack != null) ...[
                        ProfileBackButton(onPressed: onBack!),
                        const SizedBox(width: 12),
                      ],
                      Icon(
                        Icons.account_circle_rounded,
                        size: 18,
                        color: titleColor.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'My profile',
                        style: TextStyle(
                          color: titleColor.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 32,
                  bottom: 0,
                  child: avatarFrame(),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                32 + _avatarRadius * 2 + 28,
                20,
                32,
                28,
              ),
              child: identityBody,
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bodyBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: AppTheme.dashHairlineOf(context))),
      ),
      child: Column(
        children: [
          headerBandStack(
            children: [
              if (onBack != null)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ProfileBackButton(onPressed: onBack!),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.account_circle_rounded,
                        size: 18,
                        color: titleColor.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'My profile',
                          style: TextStyle(
                            color: titleColor.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                top: onBack != null ? 60 : 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: 0.9,
                    child: Image.asset(
                      'assets/images/TransparentLogo.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.account_balance_rounded,
                        color: titleColor.withValues(alpha: 0.8),
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(child: avatarFrame()),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              children: [
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Verified account',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (idLabel != null)
                      metaChip(
                        icon: Icons.pin_rounded,
                        text: idLabel!,
                        accent: AppTheme.primaryNavy,
                      ),
                    metaChip(
                      icon: roleStyle.icon,
                      text: roleStyle.label,
                      accent: roleStyle.color,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                metaChip(
                  icon: Icons.mail_outline_rounded,
                  text: email.isEmpty ? '?' : email,
                  accent: AppTheme.primaryNavy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum ProfilePageTab {
  account,
  security,
  notification,
  preference,
  about,
}

/// Scrollable underline tabs for My Profile (account + former Settings sections).
class ProfileTabBar extends StatelessWidget {
  const ProfileTabBar({
    super.key,
    required this.tab,
    required this.onChanged,
    this.showAccount = true,
    this.showSecurity = true,
    this.showAppSettings = true,
  });

  final ProfilePageTab tab;
  final ValueChanged<ProfilePageTab> onChanged;
  final bool showAccount;
  final bool showSecurity;
  final bool showAppSettings;

  @override
  Widget build(BuildContext context) {
    final entries = <({ProfilePageTab t, String label})>[];
    if (showAccount) {
      entries.add((t: ProfilePageTab.account, label: 'Account'));
    }
    if (showSecurity) {
      entries.add((t: ProfilePageTab.security, label: 'Password & Security'));
    }
    if (showAppSettings) {
      entries.add((t: ProfilePageTab.notification, label: 'Notification'));
      entries.add((t: ProfilePageTab.preference, label: 'Preference'));
      entries.add((t: ProfilePageTab.about, label: 'About'));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(width: 24),
              _Tab(
                label: entries[i].label,
                selected: tab == entries[i].t,
                onTap: () => onChanged(entries[i].t),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppTheme.primaryNavy
        : AppTheme.dashTextSecondaryOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: selected ? 32 : 0,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White card shell for profile sections.
class ModernProfileCard extends StatelessWidget {
  const ModernProfileCard({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    required this.child,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dashPanelOf(context) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppTheme.primaryNavy),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Label?value row for the About / work info panel.
class ProfileAboutRow extends StatelessWidget {
  const ProfileAboutRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppTheme.dashTextPrimaryOf(context),
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );
    final valueStyle = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context),
      fontSize: 13.5,
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppTheme.primaryNavy),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: RichText(
              text: TextSpan(
                style: valueStyle,
                children: [
                  TextSpan(text: label, style: labelStyle),
                  const TextSpan(text: ' '),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileAboutDivider extends StatelessWidget {
  const ProfileAboutDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.dashHairlineOf(context),
    );
  }
}

/// Password strength for the security tab meter.
class ProfilePasswordStrength {
  const ProfilePasswordStrength({
    required this.label,
    required this.color,
    required this.score,
  });

  final String label;
  final Color color;
  final int score;

  static ProfilePasswordStrength evaluate(String value) {
    if (value.isEmpty) {
      return ProfilePasswordStrength(
        label: '',
        color: Colors.grey,
        score: 0,
      );
    }
    final hasLower = value.contains(RegExp(r'[a-z]'));
    final hasUpper = value.contains(RegExp(r'[A-Z]'));
    final hasDigit = value.contains(RegExp(r'[0-9]'));
    final hasSpecial = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    final length = value.length;
    var score = 0;
    if (length >= 6) score++;
    if (length >= 10) score++;
    if (hasLower && hasUpper) score++;
    if (hasDigit) score++;
    if (hasSpecial) score++;
    if (score <= 1) {
      return ProfilePasswordStrength(
        label: 'Weak',
        color: const Color(0xFFC62828),
        score: 1,
      );
    }
    if (score <= 3) {
      return ProfilePasswordStrength(
        label: 'Fair',
        color: const Color(0xFFE65100),
        score: 2,
      );
    }
    return ProfilePasswordStrength(
      label: 'Strong',
      color: const Color(0xFF2E7D32),
      score: 4,
    );
  }
}

/// Segmented strength bar under the new-password field.
class ProfilePasswordStrengthMeter extends StatelessWidget {
  const ProfilePasswordStrengthMeter({super.key, required this.strength});

  final ProfilePasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    if (strength.score == 0) return const SizedBox.shrink();
    final muted = AppTheme.dashTextSecondaryOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: List.generate(4, (i) {
                    final filled = i < strength.score;
                    return Expanded(
                      child: Container(
                        height: 5,
                        margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                        decoration: BoxDecoration(
                          color: filled
                              ? strength.color
                              : AppTheme.dashHairlineOf(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              strength.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: strength.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Mix letters, numbers, and symbols for a stronger password.',
          style: TextStyle(fontSize: 11.5, color: muted, height: 1.3),
        ),
      ],
    );
  }
}

/// Soft inset surface for grouped form fields.
class ProfileInsetSurface extends StatelessWidget {
  const ProfileInsetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.dashHairlineOf(context).withValues(
            alpha: dark ? 0.5 : 1,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Tip banner for the security tab.
class ProfileSecurityTipBanner extends StatelessWidget {
  const ProfileSecurityTipBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  AppTheme.primaryNavy.withValues(alpha: 0.18),
                  AppTheme.primaryNavy.withValues(alpha: 0.08),
                ]
              : [
                  AppTheme.primaryNavy.withValues(alpha: 0.1),
                  AppTheme.primaryNavy.withValues(alpha: 0.04),
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 20,
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Choose a unique password you do not use elsewhere. '
              'Update it regularly to keep your account secure.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Setting row with icon, title, subtitle, and trailing control.
class ProfileSettingTile extends StatelessWidget {
  const ProfileSettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.iconColor,
    this.iconBackground,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Color? iconColor;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? AppTheme.primaryNavy;
    final bg = iconBackground ?? AppTheme.primaryNavy.withValues(alpha: 0.1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// Empty state for lists inside profile cards.
class ProfileCardEmptyState extends StatelessWidget {
  const ProfileCardEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          Icon(
            icon,
            size: 36,
            color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.55),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}