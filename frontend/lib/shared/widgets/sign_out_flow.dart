import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/pages/landing_page.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

/// Full-screen HRMS loading experience — soft glow, HRMS mark, animated dots.
class SignOutLoadingOverlay extends StatefulWidget {
  const SignOutLoadingOverlay({
    super.key,
    this.title = 'Ending your session',
    this.subtitle = 'Securing your account before you leave',
  });

  final String title;
  final String subtitle;

  @override
  State<SignOutLoadingOverlay> createState() => _SignOutLoadingOverlayState();
}

class _SignOutLoadingOverlayState extends State<SignOutLoadingOverlay>
    with TickerProviderStateMixin {
  static const _logoAsset = 'assets/images/hrmslogo.png';

  late final AnimationController _glowCtrl;
  late final AnimationController _orbitCtrl;
  late final AnimationController _dotsCtrl;
  late final Animation<double> _glowPulse;
  late final Animation<double> _orbitProgress;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _glowPulse = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _orbitProgress = Tween<double>(begin: 0, end: 1).animate(_orbitCtrl);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _orbitCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? const Color(0xFF12151C) : Colors.white;
    final textPrimary = AppTheme.dashTextPrimaryOf(context);
    final textSecondary = AppTheme.dashTextSecondaryOf(context);

    final logoSize = isNarrow ? 72.0 : 84.0;
    final ringPaintSize = isNarrow ? 128.0 : 148.0;
    final logoRadius = logoSize / 2 + 4;

    return Material(
      color: canvas,
      child: AnimatedBuilder(
        animation: Listenable.merge([_glowCtrl, _orbitCtrl, _dotsCtrl]),
        builder: (context, _) {
          final orbitT = _orbitProgress.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SignOutGlowPainter(
                    pulse: _glowPulse.value,
                    isDark: isDark,
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 36 : 48,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: ringPaintSize + 12,
                          height: ringPaintSize + 12,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              CustomPaint(
                                size: Size(ringPaintSize, ringPaintSize),
                                painter: _SignOutRoamingRingsPainter(
                                  progress: orbitT,
                                  logoRadius: logoRadius,
                                ),
                              ),
                              Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: canvas,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.22,
                                      ),
                                      blurRadius: 22,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: AppTheme.letterheadNavy.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Image.asset(
                                  _logoAsset,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.shield_moon_outlined,
                                    size: isNarrow ? 36 : 42,
                                    color: AppTheme.primaryNavy,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isNarrow ? 28 : 36),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: isNarrow ? 18 : 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.35,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textSecondary.withValues(alpha: 0.9),
                            fontSize: isNarrow ? 13 : 14,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                        SizedBox(height: isNarrow ? 28 : 34),
                        _SignOutDotLoader(animation: _dotsCtrl),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Soft municipal glow — orange + navy (unique to HRMS, not purple reference).
class _SignOutGlowPainter extends CustomPainter {
  _SignOutGlowPainter({required this.pulse, required this.isDark});

  final double pulse;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.44);
    final radius = size.shortestSide * 0.52 * pulse;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                AppTheme.primaryNavy.withValues(alpha: 0.28),
                AppTheme.letterheadNavy.withValues(alpha: 0.12),
                Colors.transparent,
              ]
            : [
                AppTheme.primaryNavyLight.withValues(alpha: 0.22),
                AppTheme.letterheadNavy.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0),
              ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, glow);
  }

  @override
  bool shouldRepaint(covariant _SignOutGlowPainter oldDelegate) =>
      oldDelegate.pulse != pulse || oldDelegate.isDark != isDark;
}

/// Concentric rings with arcs and dots that orbit around the logo while loading.
class _SignOutRoamingRingsPainter extends CustomPainter {
  const _SignOutRoamingRingsPainter({
    required this.progress,
    required this.logoRadius,
  });

  /// 0.0–1.0, advances continuously (one full turn per cycle).
  final double progress;
  final double logoRadius;

  static const _rings = [
    _RoamingRingSpec(
      radiusOffset: 6,
      phase: 0,
      sweepRadians: 1.15,
      strokeWidth: 3.5,
      trackAlpha: 0.22,
      isPrimary: true,
      spinTurns: 1.0,
      orbitDot: true,
      orbitDotPhase: math.pi,
      orbitDotSize: 4,
    ),
    _RoamingRingSpec(
      radiusOffset: 12,
      phase: math.pi * 0.55,
      sweepRadians: 0.82,
      strokeWidth: 2.2,
      trackAlpha: 0.18,
      isPrimary: false,
      spinTurns: -0.75,
    ),
    _RoamingRingSpec(
      radiusOffset: 18,
      phase: math.pi * 1.35,
      sweepRadians: 0.62,
      strokeWidth: 2.8,
      trackAlpha: 0.2,
      isPrimary: true,
      spinTurns: 1.35,
      orbitDot: true,
      orbitDotPhase: 0,
      orbitDotSize: 5,
    ),
  ];

  double _ringAngle(_RoamingRingSpec ring) =>
      progress * math.pi * 2 * ring.spinTurns + ring.phase - math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final ring in _rings) {
      final radius = logoRadius + ring.radiusOffset;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final start = _ringAngle(ring);

      final track = Paint()
        ..color = AppTheme.letterheadNavy.withValues(alpha: ring.trackAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.strokeWidth * 0.7;

      canvas.drawCircle(center, radius, track);

      final arcColor = ring.isPrimary
          ? AppTheme.primaryNavy
          : AppTheme.letterheadNavy.withValues(alpha: 0.5);

      final arcPaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, start, ring.sweepRadians, false, arcPaint);

      if (ring.isPrimary) {
        final tail = Paint()
          ..shader = LinearGradient(
            colors: [
              AppTheme.primaryNavy.withValues(alpha: 0.05),
              AppTheme.primaryNavy.withValues(alpha: 0.35),
            ],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.strokeWidth * 0.75
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          rect,
          start - ring.sweepRadians * 0.4,
          ring.sweepRadians * 0.4,
          false,
          tail,
        );
      }

      final tipAngle = start + ring.sweepRadians;
      final tip = Offset(
        center.dx + math.cos(tipAngle) * radius,
        center.dy + math.sin(tipAngle) * radius,
      );

      if (ring.isPrimary) {
        canvas.drawCircle(tip, 3, Paint()..color = AppTheme.primaryNavyLight);
      }

      if (ring.orbitDot) {
        final dotAngle =
            progress * math.pi * 2 * ring.spinTurns + ring.orbitDotPhase;
        final dotCenter = Offset(
          center.dx + math.cos(dotAngle) * radius,
          center.dy + math.sin(dotAngle) * radius,
        );
        final r = ring.orbitDotSize;
        canvas.drawCircle(
          dotCenter,
          r + 1.5,
          Paint()..color = AppTheme.primaryNavyLight.withValues(alpha: 0.35),
        );
        canvas.drawCircle(dotCenter, r, Paint()..color = AppTheme.primaryNavy);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignOutRoamingRingsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.logoRadius != logoRadius;
}

class _RoamingRingSpec {
  const _RoamingRingSpec({
    required this.radiusOffset,
    required this.phase,
    required this.sweepRadians,
    required this.strokeWidth,
    required this.trackAlpha,
    required this.isPrimary,
    required this.spinTurns,
    this.orbitDot = false,
    this.orbitDotPhase = 0,
    this.orbitDotSize = 4,
  });

  /// Pixels outside the logo circle edge.
  final double radiusOffset;
  final double phase;
  final double sweepRadians;
  final double strokeWidth;
  final double trackAlpha;
  final bool isPrimary;

  /// Full rotations per animation cycle (+ clockwise, − counter-clockwise).
  final double spinTurns;
  final bool orbitDot;
  final double orbitDotPhase;
  final double orbitDotSize;
}

/// Three-dot loader — orange, white, amber bounce.
class _SignOutDotLoader extends StatelessWidget {
  const _SignOutDotLoader({required this.animation});

  final Animation<double> animation;

  static const _orange = AppTheme.primaryNavy;
  static const _amber = AppTheme.primaryNavyLight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          // Sequential wave: each dot peaks in turn (0 → 1 → 2).
          final phase = (animation.value - index * 0.28 + 1) % 1.0;
          final lift = Curves.easeInOut.transform(
            phase < 0.5 ? phase * 2 : 1 - (phase - 0.5) * 2,
          );
          final scale = 0.72 + lift * 0.38;
          final opacity = 0.4 + lift * 0.6;
          final isCenter = index == 1;

          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 12),
            child: Transform.translate(
              offset: Offset(0, -lift * 10),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCenter
                          ? Colors.white
                          : (index == 0 ? _orange : _amber),
                      border: isCenter
                          ? Border.all(
                              color: AppTheme.letterheadNavy.withValues(
                                alpha: 0.18,
                              ),
                              width: 1,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isCenter
                                      ? AppTheme.letterheadNavy
                                      : (index == 0 ? _orange : _amber))
                                  .withValues(alpha: isCenter ? 0.2 : 0.5),
                          blurRadius: lift > 0.6 ? 8 : 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Minimum time the sign-out loading screen stays visible (3–5 s range).
const Duration kSignOutLoadingMinDuration = Duration(seconds: 4);

/// Signs the user out with a blocking loading overlay, then navigates to login/landing.
Future<void> performDashboardSignOut(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  if (auth.isSigningOut) return;

  final rootNav = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    builder: (dialogContext) =>
        const PopScope(canPop: false, child: SignOutLoadingOverlay()),
  );

  try {
    await Future.wait([
      auth.signOut(),
      Future<void>.delayed(kSignOutLoadingMinDuration),
    ]);
  } catch (e) {
    debugPrint('performDashboardSignOut error: $e');
    await Future<void>.delayed(kSignOutLoadingMinDuration);
  }

  if (!context.mounted) return;

  final dest = kIsWeb ? const LandingPage() : const LoginPage();
  await rootNav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => dest),
    (route) => false,
  );
}
