import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/auth/theme/login_theme.dart';

/// Same faint grid + wash used on the login form panel.
class LoginStyleGridBackdrop extends StatelessWidget {
  const LoginStyleGridBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF7F8FA),
                Color(0xFFF1F3F6),
                Color(0xFFFAFBFC),
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: LoginStyleGridPainter()),
          ),
        ),
        Positioned(
          top: -60,
          left: 20,
          right: 20,
          height: 320,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.95,
                  colors: [
                    LoginTheme.bluePrimary.withValues(alpha: 0.11),
                    LoginTheme.blueLight.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -50,
          bottom: 80,
          child: IgnorePointer(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    LoginTheme.bluePrimary.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class LoginStyleGridPainter extends CustomPainter {
  const LoginStyleGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 24.0;
    final paint = Paint()
      ..color = const Color(0xFF1A237E).withValues(alpha: 0.035)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
