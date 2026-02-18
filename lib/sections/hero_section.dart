import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      color: const Color(0xFFE9ECEF),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Triangular accents behind seal (blue top-left, gold bottom-left)
          Positioned(
            left: 0,
            top: 0,
            child: CustomPaint(
              size: Size(isWide ? 180 : 140, 160),
              painter: _TriangleAccentPainter(),
            ),
          ),
          // Login button in upper right
          Positioned(
            top: isWide ? 32 : 24,
            right: isWide ? 80 : 24,
            child: FilledButton.icon(
              onPressed: () => _handleLogin(context),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Login'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                elevation: 1,
              ),
            ),
          ),
          // Logo and text hierarchy positioned in upper left
          Positioned(
            top: isWide ? 24 : 20,
            left: isWide ? 80 : 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LguLogo(),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Republic of the Philippines',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: isNarrow ? 9 : 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'PROVINCE OF MISAMIS OCCIDENTAL',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: isNarrow ? 9 : 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: isNarrow ? 200 : 320,
                      height: 2,
                      color: Colors.black,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'MUNICIPALITY OF PLARIDEL',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: isNarrow ? 18 : (isWide ? 26 : 22),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
                      style: TextStyle(
                        color: const Color(0xFFB85C38),
                        fontSize: isNarrow ? 10 : (isWide ? 13 : 11),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content - non-positioned so it gives Stack its size
          SectionContainer(
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 80 : 24,
              vertical: isWide ? 24 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: isWide ? 90 : 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleLogin(BuildContext context) {
    // Ready for backend integration
  }
}

/// Paints blue (top-left) and gold (bottom-left) triangular accents behind the seal.
class _TriangleAccentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Blue triangle - top left
    final bluePath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.85, 0)
      ..lineTo(0, size.height * 0.6)
      ..close();
    canvas.drawPath(
      bluePath,
      Paint()..color = AppTheme.primaryNavy.withOpacity(0.25),
    );

    // Gold triangle - bottom left
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

class _LguLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/images/Plaridel Logo.jpg',
        height: 90,
        width: 90,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 90,
          width: 90,
          decoration: BoxDecoration(
            color: AppTheme.lightGray,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.textSecondary.withOpacity(0.3)),
          ),
          child: Icon(
            Icons.account_balance,
            color: AppTheme.textSecondary,
            size: 40,
          ),
        ),
      ),
    );
  }
}
