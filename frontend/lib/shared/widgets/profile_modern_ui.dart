import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Cropped Municipal Hall photograph used behind the profile banner.
const String kPlaridelMunicipalHallAsset = 'assets/images/SETTINGS.jpg';

/// Intrinsic size of [kPlaridelMunicipalHallAsset] (portrait 3:4).
const double kMunicipalHallImageWidth = 1536;
const double kMunicipalHallImageHeight = 2048;

/// CSS `object-position: center 39%` — shift the photo up so the hall
/// facade (not the sky) sits in the wide header.
const double kMunicipalHallObjectPositionY = 0.39;

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
    return Tooltip(
      message: 'Back',
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          hoverColor: Colors.white.withValues(alpha: 0.18),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal profile banner.
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

  static const double _avatarRadius = 48;
  static const double _desktopBannerHeight = 172;

  @override
  Widget build(BuildContext context) {
    final roleStyle = ProfileRoleStyle.fromLabel(roleLabel);
    const onPhoto = Colors.white;

    final overlay = wideLayout
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.fromRGBO(234, 88, 12, 0.86),
              Color.fromRGBO(180, 75, 30, 0.40),
              Color.fromRGBO(25, 35, 65, 0.28),
            ],
            stops: [0.0, 0.36, 1.0],
          )
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.fromRGBO(234, 88, 12, 0.82),
              Color.fromRGBO(40, 48, 72, 0.48),
              Color.fromRGBO(18, 26, 48, 0.40),
            ],
            stops: [0.0, 0.45, 1.0],
          );

    Widget avatarFrame() {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _avatarRadius * 2,
            height: _avatarRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(child: avatar),
          ),
          if (onChangePhoto != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Tooltip(
                message: isUploading
                    ? 'Uploading photo…'
                    : 'Change profile picture',
                child: Semantics(
                  button: true,
                  enabled: !isUploading,
                  label: 'Change profile picture',
                  child: Material(
                    color: const Color(0xFFE85D04),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: isUploading ? null : onChangePhoto,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: isUploading
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    Widget chip(String text) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: onPhoto,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wideLayout
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        const Text(
          'My Profile',
          style: TextStyle(
            color: Color(0xE6FFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName,
                textAlign: wideLayout ? TextAlign.start : TextAlign.center,
                style: TextStyle(
                  color: onPhoto,
                  fontSize: wideLayout ? 22 : 20,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  shadows: const [
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.verified_rounded, size: 16, color: Colors.green.shade300),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: wideLayout ? WrapAlignment.start : WrapAlignment.center,
          children: [
            if (idLabel != null) chip(idLabel!.replaceAll(' · ', ': ')),
            chip(roleStyle.label),
            chip(email.isEmpty ? 'No email' : email),
          ],
        ),
      ],
    );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        wideLayout ? 20 : 16,
        wideLayout ? 18 : 16,
        wideLayout ? 20 : 16,
        wideLayout ? 18 : 16,
      ),
      child: wideLayout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onBack != null) ...[
                  Align(
                    alignment: Alignment.topCenter,
                    child: ProfileBackButton(onPressed: onBack!),
                  ),
                  const SizedBox(width: 12),
                ],
                Align(alignment: Alignment.center, child: avatarFrame()),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: identity,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                if (onBack != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ProfileBackButton(onPressed: onBack!),
                    ),
                  ),
                avatarFrame(),
                const SizedBox(height: 12),
                identity,
              ],
            ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Semantics(
        label: 'My Profile header, Municipality of Plaridel',
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: wideLayout ? 160 : 0,
            maxHeight: wideLayout ? 180 : double.infinity,
          ),
          child: SizedBox(
            width: double.infinity,
            height: wideLayout ? _desktopBannerHeight : null,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ExcludeSemantics(
                    child: _MunicipalHallCoverImage(),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: overlay),
                  ),
                ),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// CSS-equivalent of `object-fit: cover; object-position: center 39%`.
class _MunicipalHallCoverImage extends StatelessWidget {
  const _MunicipalHallCoverImage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth;
        final boxH = constraints.maxHeight;
        if (!boxW.isFinite || !boxH.isFinite || boxW <= 0 || boxH <= 0) {
          return const SizedBox.shrink();
        }

        final scale = math.max(
          boxW / kMunicipalHallImageWidth,
          boxH / kMunicipalHallImageHeight,
        );
        final scaledW = kMunicipalHallImageWidth * scale;
        final scaledH = kMunicipalHallImageHeight * scale;
        final left = (boxW - scaledW) / 2;
        final top = kMunicipalHallObjectPositionY * (boxH - scaledH);

        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: scaledW,
                height: scaledH,
                child: Image.asset(
                  kPlaridelMunicipalHallAsset,
                  width: scaledW,
                  height: scaledH,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum ProfilePageTab { account, security, notification, preference, about }

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
    final entries = <({ProfilePageTab t, String label, IconData icon})>[];
    if (showAccount) {
      entries.add((
        t: ProfilePageTab.account,
        label: 'Account',
        icon: Icons.person_outline_rounded,
      ));
    }
    if (showSecurity) {
      entries.add((
        t: ProfilePageTab.security,
        label: 'Security',
        icon: Icons.lock_outline_rounded,
      ));
    }
    if (showAppSettings) {
      entries.add((
        t: ProfilePageTab.notification,
        label: 'Notifications',
        icon: Icons.notifications_none_rounded,
      ));
      entries.add((
        t: ProfilePageTab.preference,
        label: 'Preferences',
        icon: Icons.settings_outlined,
      ));
      entries.add((
        t: ProfilePageTab.about,
        label: 'About',
        icon: Icons.info_outline_rounded,
      ));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == entries.length - 1 ? 0 : 32,
                  ),
                  child: _Tab(
                    label: entries[i].label,
                    icon: entries[i].icon,
                    selected: tab == entries[i].t,
                    onTap: () => onChanged(entries[i].t),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.dashTextSecondaryOf(context);
    final color = selected ? AppTheme.primaryNavy : muted;

    return InkWell(
      onTap: onTap,
      hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 2.5,
              width: selected ? 22 : 0,
              color: AppTheme.primaryNavy,
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
    this.subtitle,
    this.icon,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dashPanelOf(context) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

InputDecoration profileFieldDecoration(
  BuildContext context, {
  String? hint,
  Widget? suffixIcon,
  String? helper,
}) {
  return AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    helperText: helper,
    suffixIcon: suffixIcon,
    radius: 10,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  ).copyWith(
    floatingLabelBehavior: FloatingLabelBehavior.never,
    labelText: null,
  );
}

class ProfileLabeledField extends StatelessWidget {
  const ProfileLabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
  });

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child:
                valueWidget ??
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class ProfileStatusBadge extends StatelessWidget {
  const ProfileStatusBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final raw = label.trim().replaceAll('_', ' ');
    final normalized = raw.toLowerCase();
    final color = (normalized.isEmpty || normalized == 'active')
        ? const Color(0xFF2E7D32)
        : (normalized.contains('inactiv') ||
              normalized.contains('separat') ||
              normalized.contains('resign'))
        ? const Color(0xFFC62828)
        : const Color(0xFFE65100);
    final text = raw.isEmpty ? 'Active' : raw;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '${text[0].toUpperCase()}${text.substring(1)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class ProfileCardActions extends StatelessWidget {
  const ProfileCardActions({
    super.key,
    this.secondary,
    required this.primary,
  });

  final Widget? secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [if (secondary != null) secondary!, primary],
      ),
    );
  }
}

class ProfileThemeChoice extends StatelessWidget {
  const ProfileThemeChoice({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryNavy;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.08)
          : AppTheme.dashIsDark(context)
          ? Colors.white.withValues(alpha: 0.04)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : AppTheme.dashHairlineOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? accent
                    : AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected
                      ? accent
                      : AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

