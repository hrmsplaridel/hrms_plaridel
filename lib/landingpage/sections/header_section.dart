import 'package:flutter/foundation.dart' show kIsWeb;
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
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
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
          SectionContainer(
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 80 : 20,
              vertical: isWide ? 12 : 10,
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
                              onTap: onHomeTap,
                              lightOnColoredHeader: true,
                            ),
                            const SizedBox(width: 6),
                            _NavLink(
                              label: 'Job Vacancies',
                              onTap: onJobVacanciesTap,
                              lightOnColoredHeader: true,
                            ),
                            const SizedBox(width: 6),
                            _NavLink(
                              label: 'Contact',
                              onTap: onContactTap,
                              lightOnColoredHeader: true,
                            ),
                            const SizedBox(width: 10),
                            _HeaderLoginButton(onLoginTap: onLoginTap),
                          ],
                        ),
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
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
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

  static const _radius = 20.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  static const _paddingCompact = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 7,
  );

  @override
  Widget build(BuildContext context) {
    final pad = widget.compact ? _paddingCompact : _padding;
    final fontSize = widget.compact ? 12.5 : 13.0;
    final iconSize = widget.compact ? 15.0 : 16.0;

    return MouseRegion(
      onEnter: kIsWeb ? (_) => setState(() => _hover = true) : null,
      onExit: kIsWeb ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: FilledButton.icon(
          onPressed: widget.onLoginTap,
          icon: Icon(Icons.login_rounded, size: iconSize),
          label: Text(
            'Login',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              letterSpacing: 0.2,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                _hover ? Colors.white : Colors.white.withValues(alpha: 0.96),
            foregroundColor: AppTheme.primaryNavyDark,
            padding: pad,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
            elevation: 0,
            side: BorderSide(
              color: AppTheme.primaryNavyDark.withValues(alpha: 0.1),
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
