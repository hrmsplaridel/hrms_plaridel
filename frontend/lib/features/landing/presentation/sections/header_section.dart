import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/widgets/section_container.dart';

/// Which landing section is highlighted in the mobile nav panel.
enum LandingNavSection { home, jobVacancies, contact }

/// Header: Municipality logo and nav links for the public applicant landing page.
///
/// Desktop (≥768px) keeps the existing single-row branding + inline nav.
/// Mobile (<768px) uses a compact seal + branding + hamburger menu.
class HeaderSection extends StatefulWidget {
  const HeaderSection({
    super.key,
    this.onHomeTap,
    this.onJobVacanciesTap,
    this.onRecruitmentProcessTap,
    this.onContactTap,
    this.compact = false,
    this.menuOpen = false,
    this.onMenuOpenChanged,
  });

  final VoidCallback? onHomeTap;
  final VoidCallback? onJobVacanciesTap;
  final VoidCallback? onRecruitmentProcessTap;
  final VoidCallback? onContactTap;

  /// Mobile only: shorter sticky header while scrolled.
  final bool compact;

  /// Mobile only: whether the hamburger panel is open.
  final bool menuOpen;
  final ValueChanged<bool>? onMenuOpenChanged;

  @override
  State<HeaderSection> createState() => _HeaderSectionState();
}

class _HeaderSectionState extends State<HeaderSection> {
  static const double _mobileBreakpoint = 768;

  void _setMenuOpen(bool open) {
    widget.onMenuOpenChanged?.call(open);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < _mobileBreakpoint;
    final isWide = width > 800;
    final isNarrow = width < 600;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryNavyDark,
                  AppTheme.primaryNavy,
                  Color(0xFFD84315),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: widget.compact ? 8 : 12,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: CustomPaint(
                    size: const Size(100, 200),
                    painter: const _TriangleAccentPainter(onOrangeHeader: true),
                  ),
                ),
                Positioned(
                  right: -20,
                  top: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                if (isMobile)
                  _MobileHeaderBar(
                    compact: widget.compact,
                    menuOpen: widget.menuOpen,
                    onToggleMenu: () => _setMenuOpen(!widget.menuOpen),
                  )
                else
                  SectionContainer(
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 80 : 20,
                      vertical: isWide ? 12 : 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _LguBranding(
                            isNarrow: isNarrow,
                            isWide: isWide,
                            showBackground: false,
                            expandWidth: true,
                            lightOnColoredHeader: true,
                          ),
                        ),
                        const SizedBox(width: 28),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _NavLink(
                                label: 'Home',
                                onTap: widget.onHomeTap,
                                lightOnColoredHeader: true,
                              ),
                              const SizedBox(width: 6),
                              _NavLink(
                                label: 'Job Vacancies',
                                onTap: widget.onJobVacanciesTap,
                                lightOnColoredHeader: true,
                              ),
                              const SizedBox(width: 6),
                              _NavLink(
                                label: 'Contact',
                                onTap: widget.onContactTap,
                                lightOnColoredHeader: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact single-row mobile header: seal | branding | hamburger.
class _MobileHeaderBar extends StatelessWidget {
  const _MobileHeaderBar({
    required this.compact,
    required this.menuOpen,
    required this.onToggleMenu,
  });

  final bool compact;
  final bool menuOpen;
  final VoidCallback onToggleMenu;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final veryNarrow = width < 360;
    final sealSize = compact ? 40.0 : (veryNarrow ? 46.0 : 50.0);
    final menuSize = compact ? 42.0 : 46.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        veryNarrow ? 12 : 14,
        compact ? 8 : 12,
        veryNarrow ? 10 : 12,
        compact ? 8 : 12,
      ),
      constraints: BoxConstraints(minHeight: compact ? 64 : 88),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MunicipalityLogoCircular(size: sealSize, lightEdge: true),
          SizedBox(width: veryNarrow ? 8 : 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: compact
                  ? _MobileCompactBranding(
                      key: const ValueKey('compact'),
                      veryNarrow: veryNarrow,
                    )
                  : _MobileExpandedBranding(
                      key: const ValueKey('expanded'),
                      veryNarrow: veryNarrow,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          _HamburgerButton(
            size: menuSize,
            open: menuOpen,
            onTap: onToggleMenu,
          ),
        ],
      ),
    );
  }
}

class _MobileExpandedBranding extends StatelessWidget {
  const _MobileExpandedBranding({super.key, required this.veryNarrow});

  final bool veryNarrow;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.88);
    final shadow = [
      Shadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Republic of the Philippines',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontSize: veryNarrow ? 7.5 : 8.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            height: 1.15,
            shadows: shadow,
          ),
        ),
        Text(
          'PROVINCE OF MISAMIS OCCIDENTAL',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontSize: veryNarrow ? 7.5 : 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            height: 1.15,
            shadows: shadow,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 36,
          height: 1.5,
          color: Colors.white.withValues(alpha: 0.55),
        ),
        const SizedBox(height: 3),
        Text(
          'MUNICIPALITY OF PLARIDEL',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: veryNarrow ? 11.5 : 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            height: 1.15,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.94),
            fontSize: veryNarrow ? 6.5 : 7.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.35,
            height: 1.2,
            shadows: shadow,
          ),
        ),
      ],
    );
  }
}

class _MobileCompactBranding extends StatelessWidget {
  const _MobileCompactBranding({super.key, required this.veryNarrow});

  final bool veryNarrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'MUNICIPALITY OF PLARIDEL',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: veryNarrow ? 12 : 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            height: 1.1,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'HR MANAGEMENT AND DEVELOPMENT OFFICE',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: veryNarrow ? 7 : 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _HamburgerButton extends StatelessWidget {
  const _HamburgerButton({
    required this.size,
    required this.open,
    required this.onTap,
  });

  final double size;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: open ? 0.28 : 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              open ? Icons.close_rounded : Icons.menu_rounded,
              key: ValueKey(open),
              color: Colors.white,
              size: size * 0.48,
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating mobile nav panel shown below the sticky header.
class LandingMobileNavPanel extends StatelessWidget {
  const LandingMobileNavPanel({
    super.key,
    required this.activeSection,
    required this.onHome,
    required this.onJobVacancies,
    required this.onContact,
  });

  final LandingNavSection activeSection;
  final VoidCallback onHome;
  final VoidCallback onJobVacancies;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Material(
        color: Colors.white,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MobileNavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                active: activeSection == LandingNavSection.home,
                onTap: onHome,
              ),
              _MobileNavItem(
                icon: Icons.work_outline_rounded,
                label: 'Job Vacancies',
                active: activeSection == LandingNavSection.jobVacancies,
                onTap: onJobVacancies,
              ),
              _MobileNavItem(
                icon: Icons.mail_outline_rounded,
                label: 'Contact',
                active: activeSection == LandingNavSection.contact,
                onTap: onContact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryNavy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active ? accent : const Color(0xFF64748B),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? accent : const Color(0xFF1F2937),
                    ),
                  ),
                ),
                if (active)
                  Icon(Icons.chevron_right_rounded, size: 20, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({
    required this.label,
    this.onTap,
    this.lightOnColoredHeader = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool lightOnColoredHeader;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: kIsWeb ? (_) => setState(() => _hover = true) : null,
      onExit: kIsWeb ? (_) => setState(() => _hover = false) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: widget.lightOnColoredHeader
                  ? Colors.white.withValues(alpha: _hover ? 0.18 : 0.0)
                  : AppTheme.primaryNavy.withValues(alpha: _hover ? 0.08 : 0.0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.lightOnColoredHeader
                    ? Colors.white.withValues(alpha: _hover ? 1 : 0.9)
                    : AppTheme.primaryNavy,
                fontSize: 13.5,
                fontWeight: _hover ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.1,
                shadows: widget.lightOnColoredHeader
                    ? [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Upper-left LGU branding (desktop header path).
class _LguBranding extends StatelessWidget {
  const _LguBranding({
    required this.isNarrow,
    required this.isWide,
    this.showBackground = true,
    this.expandWidth = false,
    this.lightOnColoredHeader = false,
  });

  final bool isNarrow;
  final bool isWide;
  final bool showBackground;
  final bool expandWidth;
  final bool lightOnColoredHeader;

  Widget _buildContent(BuildContext context) {
    final lineMuted = lightOnColoredHeader
        ? Colors.white.withValues(alpha: 0.88)
        : AppTheme.textPrimary;
    final titleColor = lightOnColoredHeader
        ? Colors.white
        : AppTheme.textPrimary;
    final dividerColor = lightOnColoredHeader
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black;
    final hrOfficeColor = lightOnColoredHeader
        ? Colors.white.withValues(alpha: 0.94)
        : const Color(0xFFB85C38);

    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Republic of the Philippines',
          style: TextStyle(
            color: lineMuted,
            fontSize: isNarrow ? 8 : 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            shadows: lightOnColoredHeader
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
        Text(
          'PROVINCE OF MISAMIS OCCIDENTAL',
          style: TextStyle(
            color: lineMuted,
            fontSize: isNarrow ? 8 : 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            shadows: lightOnColoredHeader
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Container(width: double.infinity, height: 2, color: dividerColor),
        const SizedBox(height: 4),
        Text(
          'MUNICIPALITY OF PLARIDEL',
          style: TextStyle(
            color: titleColor,
            fontSize: isNarrow ? 13 : (isWide ? 19 : 16),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            height: 1.2,
            shadows: lightOnColoredHeader
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
          style: TextStyle(
            color: hrOfficeColor,
            fontSize: isNarrow ? 7.5 : (isWide ? 10.5 : 9),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            height: 1.25,
            shadows: lightOnColoredHeader
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
      ],
    );

    return Row(
      mainAxisSize: expandWidth ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _MunicipalityLogoCircular(
          size: isNarrow ? 56 : (isWide ? 72 : 64),
          lightEdge: lightOnColoredHeader,
        ),
        SizedBox(width: isWide ? 16 : 10),
        if (expandWidth)
          Expanded(child: textColumn)
        else
          IntrinsicWidth(child: textColumn),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!showBackground) {
      return _buildContent(context);
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 0 : 12,
        vertical: isWide ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: lightOnColoredHeader
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(12),
        border: lightOnColoredHeader
            ? Border.all(color: Colors.white.withValues(alpha: 0.28))
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: CustomPaint(
              size: Size(isWide ? 100 : 70, 80),
              painter: _TriangleAccentPainter(
                onOrangeHeader: lightOnColoredHeader,
              ),
            ),
          ),
          _buildContent(context),
        ],
      ),
    );
  }
}

class _TriangleAccentPainter extends CustomPainter {
  const _TriangleAccentPainter({this.onOrangeHeader = false});

  final bool onOrangeHeader;

  @override
  void paint(Canvas canvas, Size size) {
    final bluePath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.85, 0)
      ..lineTo(0, size.height * 0.6)
      ..close();
    canvas.drawPath(
      bluePath,
      Paint()
        ..color = onOrangeHeader
            ? Colors.white.withValues(alpha: 0.12)
            : AppTheme.primaryNavy.withValues(alpha: 0.25),
    );
    final goldPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.65, size.height)
      ..lineTo(0, size.height * 0.4)
      ..close();
    canvas.drawPath(
      goldPath,
      Paint()
        ..color = onOrangeHeader
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFD4A84B).withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(covariant _TriangleAccentPainter oldDelegate) =>
      oldDelegate.onOrangeHeader != onOrangeHeader;
}

class _MunicipalityLogoCircular extends StatelessWidget {
  const _MunicipalityLogoCircular({this.size = 90, this.lightEdge = false});

  final double size;
  final bool lightEdge;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: lightEdge
            ? Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2)
            : null,
        boxShadow: lightEdge
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/Plaridel Logo.jpg',
          height: size,
          width: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: AppTheme.lightGray,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.account_balance,
              color: AppTheme.primaryNavy,
              size: size * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}
