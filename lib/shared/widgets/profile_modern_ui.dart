import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Soft wave pattern for the profile hero banner.
class ProfileWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wave = Paint()
      ..color = const Color(0xFF90CAF9).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final wave2 = Paint()
      ..color = const Color(0xFF64B5F6).withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < 6; i++) {
      final path = Path();
      final y = size.height * (0.1 + i * 0.13);
      path.moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 28) {
        path.quadraticBezierTo(
          x + 14,
          y + (i.isEven ? 10 : -10),
          x + 28,
          y,
        );
      }
      canvas.drawPath(path, i.isEven ? wave : wave2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Top banner with avatar, name, role, email — full-width on dashboard.
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
  });

  final String displayName;
  final String email;
  final String roleLabel;
  final Widget avatar;
  final String? idLabel;
  final bool wideLayout;
  final VoidCallback? onChangePhoto;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final titleColor = AppTheme.dashTextPrimaryOf(context);
    final muted = AppTheme.dashTextSecondaryOf(context);

    final bannerColors = dark
        ? [const Color(0xFF1E2A3D), const Color(0xFF243447)]
        : [
            const Color(0xFFE3F2FD),
            const Color(0xFFF0F7FC),
            Colors.white,
          ];

    Widget avatarBlock() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: isUploading ? null : onChangePhoto,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: avatar,
            ),
          ),
          if (onChangePhoto != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: isUploading ? null : onChangePhoto,
              icon: Icon(
                Icons.camera_alt_outlined,
                size: 16,
                color: AppTheme.primaryNavy,
              ),
              label: Text(
                'Change photo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryNavy,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      );
    }

    Widget nameRow({bool alignStart = false}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            alignStart ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wideLayout ? 520 : 280,
            ),
            child: Text(
              displayName,
              textAlign: alignStart ? TextAlign.start : TextAlign.center,
              style: TextStyle(
                color: titleColor,
                fontSize: wideLayout ? 24 : 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.35,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.verified_rounded,
            size: wideLayout ? 24 : 20,
            color: Colors.green.shade600,
          ),
        ],
      );
    }

    Widget metaColumn({required CrossAxisAlignment align}) {
      return Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameRow(alignStart: align == CrossAxisAlignment.start),
          if (idLabel != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.badge_outlined, size: 15, color: AppTheme.primaryNavy),
                  const SizedBox(width: 6),
                  Text(
                    idLabel!,
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              roleLabel,
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(
                email.isEmpty ? '—' : email,
                style: TextStyle(color: muted, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      );
    }

    final verticalPad = wideLayout ? 32.0 : 28.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, verticalPad, 24, verticalPad + 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bannerColors,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: ProfileWavePainter()),
          ),
          Positioned(
            left: wideLayout ? 20 : 12,
            top: wideLayout ? 16 : 10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/Plaridel Logo.jpg',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.account_balance_rounded,
                    size: 28,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatarBlock(),
              const SizedBox(height: 18),
              metaColumn(align: CrossAxisAlignment.center),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: selected ? 56 : 0,
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

/// Label–value row for the About / work info panel.
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
    final bg = iconBackground ??
        AppTheme.primaryNavy.withValues(alpha: 0.1);

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
