import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Header: Municipality logo, nav links (Home, Job Vacancies, Recruitment Process, Contact),
/// and a single Login button. No public registration.
class HeaderSection extends StatelessWidget {
  const HeaderSection({
    super.key,
    this.onHomeTap,
    this.onJobVacanciesTap,
    this.onRecruitmentProcessTap,
    this.onContactTap,
    this.onLoginTap,
  });

  final VoidCallback? onHomeTap;
  final VoidCallback? onJobVacanciesTap;
  final VoidCallback? onRecruitmentProcessTap;
  final VoidCallback? onContactTap;
  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryNavy, AppTheme.primaryNavyDark],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
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
          SectionContainer(
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 80 : 20,
              vertical: isWide ? 18 : 14,
            ),
            child: isWide
                ? Row(
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
                      const SizedBox(width: 40),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _NavLink(
                            label: 'Home',
                            onTap: onHomeTap,
                            lightOnColoredHeader: true,
                          ),
                          const SizedBox(width: 24),
                          _NavLink(
                            label: 'Job Vacancies',
                            onTap: onJobVacanciesTap,
                            lightOnColoredHeader: true,
                          ),
                          const SizedBox(width: 24),
                          _NavLink(
                            label: 'Contact',
                            onTap: onContactTap,
                            lightOnColoredHeader: true,
                          ),
                          const SizedBox(width: 32),
                          _HeaderLoginButton(onLoginTap: onLoginTap),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _LguBranding(
                            isNarrow: isNarrow,
                            isWide: isWide,
                            showBackground: true,
                            lightOnColoredHeader: true,
                          ),
                          _HeaderLoginButton(
                            onLoginTap: onLoginTap,
                            compact: true,
                          ),
                        ],
                      ),
                      if (!isNarrow) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _NavLink(
                              label: 'Home',
                              onTap: onHomeTap,
                              lightOnColoredHeader: true,
                            ),
                            _NavLink(
                              label: 'Job Vacancies',
                              onTap: onJobVacanciesTap,
                              lightOnColoredHeader: true,
                            ),
                            _NavLink(
                              label: 'Contact',
                              onTap: onContactTap,
                              lightOnColoredHeader: true,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Single login button, pill shape, and hover effect.
/// On orange header uses white fill + orange text for contrast.
class _HeaderLoginButton extends StatefulWidget {
  const _HeaderLoginButton({this.onLoginTap, this.compact = false});

  final VoidCallback? onLoginTap;
  final bool compact;

  @override
  State<_HeaderLoginButton> createState() => _HeaderLoginButtonState();
}

class _HeaderLoginButtonState extends State<_HeaderLoginButton> {
  bool _hover = false;

  static const _radius = 24.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 24, vertical: 12);
  static const _paddingCompact = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 10,
  );

  @override
  Widget build(BuildContext context) {
    final pad = widget.compact ? _paddingCompact : _padding;
    final minW = widget.compact ? 100.0 : 120.0;
    final minH = widget.compact ? 42.0 : 46.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: FilledButton(
          onPressed: widget.onLoginTap,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryNavyDark,
            padding: pad,
            minimumSize: Size(minW, minH),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
            elevation: 0,
            side: BorderSide(
              color: AppTheme.primaryNavyDark.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            'Login',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: widget.compact ? 14 : 15,
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
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: widget.lightOnColoredHeader
                ? (_hover ? Colors.white : Colors.white.withValues(alpha: 0.92))
                : AppTheme.primaryNavy,
            fontSize: 15,
            fontWeight: _hover ? FontWeight.w800 : FontWeight.w600,
            shadows: widget.lightOnColoredHeader
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: widget.lightOnColoredHeader
                ? Colors.white
                : AppTheme.primaryNavy,
            decorationThickness: 2,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

/// Upper-left LGU branding: light grey background, blue/beige accents, circular logo, text hierarchy.
/// When [showBackground] is false, only logo + text (for use inside the full-width header bar).
/// When [expandWidth] is true, the text column stretches to fill space beside the logo (wide header).
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
            fontSize: isNarrow ? 14 : (isWide ? 22 : 18),
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
            fontSize: isNarrow ? 8 : (isWide ? 12 : 10),
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
          size: isNarrow ? 64 : (isWide ? 90 : 72),
          lightEdge: lightOnColoredHeader,
        ),
        SizedBox(width: isWide ? 20 : 12),
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
