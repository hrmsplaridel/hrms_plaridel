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
    const headerGray = Color(0xFFE9ECEF);

    return Container(
      width: double.infinity,
      color: headerGray,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: CustomPaint(
              size: const Size(120, 200),
              painter: _TriangleAccentPainter(),
            ),
          ),
          SectionContainer(
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 80 : 24,
              vertical: isWide ? 16 : 12,
            ),
            child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LguBranding(isNarrow: isNarrow, isWide: isWide, showBackground: false),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _NavLink(label: 'Home', onTap: onHomeTap),
                      const SizedBox(width: 24),
                      _NavLink(label: 'Job Vacancies', onTap: onJobVacanciesTap),
                      const SizedBox(width: 24),
                      _NavLink(label: 'Recruitment Process', onTap: onRecruitmentProcessTap),
                      const SizedBox(width: 24),
                      _NavLink(label: 'Contact', onTap: onContactTap),
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
                      _LguBranding(isNarrow: isNarrow, isWide: isWide, showBackground: true),
                      IconButton(
                        onPressed: onLoginTap,
                        icon: const Icon(Icons.login_rounded),
                        color: AppTheme.primaryNavy,
                        tooltip: 'Login',
                      ),
                    ],
                  ),
                  if (!isNarrow) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _NavLink(label: 'Home', onTap: onHomeTap),
                        _NavLink(label: 'Job Vacancies', onTap: onJobVacanciesTap),
                        _NavLink(label: 'Recruitment Process', onTap: onRecruitmentProcessTap),
                        _NavLink(label: 'Contact', onTap: onContactTap),
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

/// Single login button with icon, pill shape, and hover effect.
class _HeaderLoginButton extends StatefulWidget {
  const _HeaderLoginButton({this.onLoginTap});

  final VoidCallback? onLoginTap;

  @override
  State<_HeaderLoginButton> createState() => _HeaderLoginButtonState();
}

class _HeaderLoginButtonState extends State<_HeaderLoginButton> {
  bool _hover = false;

  static const _radius = 24.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 24, vertical: 12);

  @override
  Widget build(BuildContext context) {
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
                    color: AppTheme.primaryNavy.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: FilledButton.icon(
          onPressed: widget.onLoginTap,
          icon: Icon(Icons.login_rounded, size: 20, color: AppTheme.white),
          label: const Text('Login', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: AppTheme.white,
            padding: _padding,
            minimumSize: const Size(120, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

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
        child: Text(
          widget.label,
          style: TextStyle(
            color: AppTheme.primaryNavy,
            fontSize: 14,
            fontWeight: _hover ? FontWeight.w600 : FontWeight.w500,
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: AppTheme.primaryNavy,
          ),
        ),
      ),
    );
  }
}

/// Upper-left LGU branding: light grey background, blue/beige accents, circular logo, text hierarchy.
/// When [showBackground] is false, only logo + text (for use inside the full-width header bar).
class _LguBranding extends StatelessWidget {
  const _LguBranding({
    required this.isNarrow,
    required this.isWide,
    this.showBackground = true,
  });

  final bool isNarrow;
  final bool isWide;
  final bool showBackground;

  Widget _buildContent(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _MunicipalityLogoCircular(size: isNarrow ? 64 : (isWide ? 90 : 72)),
        SizedBox(width: isWide ? 20 : 12),
        IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Republic of the Philippines',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: isNarrow ? 8 : 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'PROVINCE OF MISAMIS OCCIDENTAL',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: isNarrow ? 8 : 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                height: 2,
                color: Colors.black,
              ),
              const SizedBox(height: 4),
              Text(
                'MUNICIPALITY OF PLARIDEL',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: isNarrow ? 14 : (isWide ? 22 : 18),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
                style: TextStyle(
                  color: const Color(0xFFB85C38),
                  fontSize: isNarrow ? 8 : (isWide ? 12 : 10),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
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
        color: const Color(0xFFE9ECEF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: CustomPaint(
              size: Size(isWide ? 100 : 70, 80),
              painter: _TriangleAccentPainter(),
            ),
          ),
          _buildContent(context),
        ],
      ),
    );
  }
}

class _TriangleAccentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bluePath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.85, 0)
      ..lineTo(0, size.height * 0.6)
      ..close();
    canvas.drawPath(
      bluePath,
      Paint()..color = AppTheme.primaryNavy.withOpacity(0.25),
    );
    final goldPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.65, size.height)
      ..lineTo(0, size.height * 0.4)
      ..close();
    canvas.drawPath(
      goldPath,
      Paint()..color = const Color(0xFFD4A84B).withOpacity(0.4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MunicipalityLogoCircular extends StatelessWidget {
  const _MunicipalityLogoCircular({this.size = 90});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
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
            border: Border.all(color: AppTheme.textSecondary.withOpacity(0.3)),
          ),
          child: Icon(Icons.account_balance, color: AppTheme.primaryNavy, size: size * 0.45),
        ),
      ),
    );
  }
}
