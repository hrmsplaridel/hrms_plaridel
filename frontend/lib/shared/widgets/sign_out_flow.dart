import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

// Sign-out loading palette (scoped to this file only).
const Color _kSoOrange = Color(0xFFEA580C);
const Color _kSoOrangeMid = Color(0xFFFB923C);
const Color _kSoOrangeLight = Color(0xFFFDBA74);
const Color _kSoOrangePale = Color(0xFFFED7AA);
const Color _kSoTextPrimary = Color(0xFF1F2937);
const Color _kSoTextMuted = Color(0xFF6B7280);
const Color _kSoCream = Color(0xFFFFF7ED);
const Color _kSoPeach = Color(0xFFFFEDD5);
const String _kSoLogoAsset = 'assets/images/logo.png';
const String _kSoCenterSealAsset = 'assets/images/Plaridel Logo.jpg';

/// Full-screen logout loading experience — branding, animated rings, progress cues, footer.
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
  late final AnimationController _outerCtrl;
  late final AnimationController _innerCtrl;
  late final AnimationController _dotsCtrl;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _outerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _innerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    // Start after first frame so we can honor reduced-motion from MediaQuery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.disableAnimationsOf(context);
      if (reduce) {
        _outerCtrl.value = 0.15;
        _innerCtrl.value = 0.35;
        _dotsCtrl.value = 0.5;
        _glowCtrl.value = 0.9;
      } else {
        _outerCtrl.repeat();
        _innerCtrl.repeat();
        _dotsCtrl.repeat();
        _glowCtrl.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _outerCtrl.dispose();
    _innerCtrl.dispose();
    _dotsCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isNarrow = size.width < 700;
    final isMobile = size.width < 520;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final canvas = isDark ? const Color(0xFF12151C) : Colors.white;
    final primaryText = isDark
        ? AppTheme.dashTextPrimaryOf(context)
        : _kSoTextPrimary;
    final mutedText = isDark
        ? AppTheme.dashTextSecondaryOf(context)
        : _kSoTextMuted;

    final logoSize = isMobile ? 80.0 : (isNarrow ? 96.0 : 108.0);
    final ringSize = logoSize + (isMobile ? 56 : 72);
    final titleSize = isMobile ? 21.0 : 26.0;

    return Material(
      color: canvas,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _outerCtrl,
          _innerCtrl,
          _dotsCtrl,
          _glowCtrl,
        ]),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Soft radial glow behind the logo area.
              Positioned.fill(
                child: CustomPaint(
                  painter: _SignOutBackdropPainter(
                    pulse: reduceMotion ? 0.9 : (0.85 + _glowCtrl.value * 0.15),
                    isDark: isDark,
                  ),
                ),
              ),

              // Decorative large background rings (subtle).
              if (!isMobile)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SignOutDecorRingsPainter(isDark: isDark),
                    ),
                  ),
                ),

              // Footer waves + branding.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SignOutFooter(
                  isNarrow: isNarrow,
                  isMobile: isMobile,
                  isDark: isDark,
                  mutedText: mutedText,
                ),
              ),

              // Main content.
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? 16 : 28,
                        isMobile ? 12 : 18,
                        isMobile ? 16 : 28,
                        0,
                      ),
                      child: _SignOutHeader(
                        logoAsset: _kSoLogoAsset,
                        isNarrow: isNarrow,
                        isMobile: isMobile,
                        isDark: isDark,
                        primaryText: primaryText,
                        mutedText: mutedText,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 24 : 40,
                            vertical: 12,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: ringSize + 24,
                                  height: ringSize + 24,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: Size(ringSize, ringSize),
                                        painter: _SignOutRingsPainter(
                                          outerProgress: _outerCtrl.value,
                                          innerProgress: _innerCtrl.value,
                                          logoRadius: logoSize / 2,
                                          reduceMotion: reduceMotion,
                                        ),
                                      ),
                                      Container(
                                        width: logoSize,
                                        height: logoSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color: _kSoOrange.withValues(
                                                alpha: isDark ? 0.28 : 0.18,
                                              ),
                                              blurRadius: 22,
                                              spreadRadius: 1,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Image.asset(
                                          _kSoCenterSealAsset,
                                          fit: BoxFit.cover,
                                          alignment: Alignment.center,
                                          filterQuality: FilterQuality.high,
                                          errorBuilder: (_, __, ___) => Icon(
                                            Icons.shield_moon_outlined,
                                            size: logoSize * 0.42,
                                            color: _kSoOrange,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: isMobile ? 22 : 28),
                                Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: primaryText,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.subtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: mutedText,
                                    fontSize: isMobile ? 14 : 16,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                  ),
                                ),
                                SizedBox(height: isMobile ? 20 : 26),
                                _SignOutDotLoader(
                                  animation: _dotsCtrl,
                                  reduceMotion: reduceMotion,
                                ),
                                SizedBox(height: isMobile ? 28 : 36),
                                _SignOutProgressIndicators(
                                  isMobile: isMobile,
                                  isDark: isDark,
                                  mutedText: mutedText,
                                  primaryText: primaryText,
                                ),
                                // Keep content clear of the footer waves.
                                SizedBox(height: isMobile ? 100 : 140),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _SignOutHeader extends StatelessWidget {
  const _SignOutHeader({
    required this.logoAsset,
    required this.isNarrow,
    required this.isMobile,
    required this.isDark,
    required this.primaryText,
    required this.mutedText,
  });

  final String logoAsset;
  final bool isNarrow;
  final bool isMobile;
  final bool isDark;
  final Color primaryText;
  final Color mutedText;

  @override
  Widget build(BuildContext context) {
    final logoSize = isMobile ? 48.0 : 60.0;

    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            logoAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.account_balance_rounded,
              size: logoSize * 0.7,
              color: _kSoOrange,
            ),
          ),
        ),
        SizedBox(width: isMobile ? 10 : 14),
        Container(
          width: 1.5,
          height: isMobile ? 36 : 44,
          color: _kSoOrange.withValues(alpha: 0.7),
        ),
        SizedBox(width: isMobile ? 10 : 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'HUMAN RESOURCE',
                style: TextStyle(
                  color: primaryText,
                  fontSize: isMobile ? 12 : 15,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                'MANAGEMENT SYSTEM',
                style: TextStyle(
                  color: primaryText,
                  fontSize: isMobile ? 12 : 15,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'INTEGRATED SOLUTIONS',
                style: TextStyle(
                  color: mutedText,
                  fontSize: isMobile ? 9.5 : 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          brand,
          const SizedBox(height: 12),
          _TaglineBlock(mutedText: mutedText, compact: true),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: brand),
        const SizedBox(width: 16),
        _TaglineBlock(mutedText: mutedText, compact: false),
      ],
    );
  }
}

class _TaglineBlock extends StatelessWidget {
  const _TaglineBlock({required this.mutedText, required this.compact});

  final Color mutedText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget sep() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _kSoOrange,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PEOPLE',
              style: TextStyle(
                color: mutedText,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            sep(),
            Text(
              'PROCESS',
              style: TextStyle(
                color: mutedText,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            sep(),
            Text(
              'PROGRESS',
              style: TextStyle(
                color: mutedText,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'A Better Public Service for a Stronger Plaridel',
          textAlign: compact ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            color: mutedText.withValues(alpha: 0.9),
            fontSize: compact ? 10 : 11.5,
            fontStyle: FontStyle.italic,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// ─── Progress indicators ──────────────────────────────────────────────────────

class _SignOutProgressIndicators extends StatelessWidget {
  const _SignOutProgressIndicators({
    required this.isMobile,
    required this.isDark,
    required this.mutedText,
    required this.primaryText,
  });

  final bool isMobile;
  final bool isDark;
  final Color mutedText;
  final Color primaryText;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.verified_user_outlined, 'Clearing\nyour session'),
      (Icons.lock_outline_rounded, 'Protecting\nyour data'),
      (Icons.check_circle_outline_rounded, 'Almost\ndone...'),
    ];

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14),
            child: Container(
              width: 1,
              height: isMobile ? 40 : 48,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : const Color(0xFFE2E8F0),
            ),
          ),
        );
      }
      children.add(
        Expanded(
          child: _ProgressItem(
            icon: items[i].$1,
            label: items[i].$2,
            isMobile: isMobile,
            isDark: isDark,
            mutedText: mutedText,
            primaryText: primaryText,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ProgressItem extends StatelessWidget {
  const _ProgressItem({
    required this.icon,
    required this.label,
    required this.isMobile,
    required this.isDark,
    required this.mutedText,
    required this.primaryText,
  });

  final IconData icon;
  final String label;
  final bool isMobile;
  final bool isDark;
  final Color mutedText;
  final Color primaryText;

  @override
  Widget build(BuildContext context) {
    final size = isMobile ? 42.0 : 48.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? _kSoOrange.withValues(alpha: 0.16)
                : _kSoCream,
            border: Border.all(
              color: _kSoOrange.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(
            icon,
            size: isMobile ? 20 : 22,
            color: _kSoOrange,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: mutedText,
            fontSize: isMobile ? 11 : 12.5,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _SignOutFooter extends StatelessWidget {
  const _SignOutFooter({
    required this.isNarrow,
    required this.isMobile,
    required this.isDark,
    required this.mutedText,
  });

  final bool isNarrow;
  final bool isMobile;
  final bool isDark;
  final Color mutedText;

  @override
  Widget build(BuildContext context) {
    final footerHeight = isMobile ? 120.0 : (isNarrow ? 140.0 : 160.0);

    return SizedBox(
      height: footerHeight,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            painter: _SignOutWavePainter(isDark: isDark),
            size: Size.infinite,
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: isMobile ? 14 : 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MUNICIPALITY OF PLARIDEL',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutedText,
                    fontSize: isMobile ? 10.5 : 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: isMobile ? 28 : 40,
                      height: 1.5,
                      color: _kSoOrange.withValues(
                        alpha: 0.55,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'Service with People at the Heart',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: isMobile ? 10 : 11.5,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      width: isMobile ? 28 : 40,
                      height: 1.5,
                      color: _kSoOrange.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Painters & loaders ───────────────────────────────────────────────────────

class _SignOutBackdropPainter extends CustomPainter {
  _SignOutBackdropPainter({required this.pulse, required this.isDark});

  final double pulse;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.40);
    final radius = size.shortestSide * 0.42 * pulse;

    final glow = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        isDark
            ? [
                _kSoOrange.withValues(alpha: 0.22),
                _kSoOrangeMid.withValues(alpha: 0.08),
                Colors.transparent,
              ]
            : [
                _kSoOrangePale.withValues(alpha: 0.55),
                _kSoCream.withValues(alpha: 0.35),
                Colors.white.withValues(alpha: 0),
              ],
        const [0.0, 0.45, 1.0],
      );

    canvas.drawCircle(center, radius, glow);
  }

  @override
  bool shouldRepaint(covariant _SignOutBackdropPainter oldDelegate) =>
      oldDelegate.pulse != pulse || oldDelegate.isDark != isDark;
}

class _SignOutDecorRingsPainter extends CustomPainter {
  _SignOutDecorRingsPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.40);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = _kSoOrange.withValues(
        alpha: isDark ? 0.12 : 0.10,
      );

    final base = size.shortestSide * 0.22;
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(center, base + i * (size.shortestSide * 0.08), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignOutDecorRingsPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _SignOutRingsPainter extends CustomPainter {
  _SignOutRingsPainter({
    required this.outerProgress,
    required this.innerProgress,
    required this.logoRadius,
    required this.reduceMotion,
  });

  final double outerProgress;
  final double innerProgress;
  final double logoRadius;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = logoRadius + 22;
    final midR = logoRadius + 14;
    final innerR = logoRadius + 7;

    // Soft track rings.
    void track(double r, double alpha) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _kSoOrangePale.withValues(alpha: alpha),
      );
    }

    track(outerR, 0.55);
    track(midR, 0.4);
    track(innerR, 0.35);

    final outerAngle = reduceMotion
        ? -math.pi / 2
        : outerProgress * math.pi * 2 - math.pi / 2;
    final innerAngle = reduceMotion
        ? math.pi / 4
        : -innerProgress * math.pi * 2 - math.pi / 2;

    // Outer solid orange arc (clockwise).
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR),
      outerAngle,
      1.35,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = _kSoOrange,
    );

    // Mid light arc.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: midR),
      outerAngle + math.pi * 0.7,
      0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = _kSoOrangeMid,
    );

    // Inner counter-clockwise arc.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerR),
      innerAngle,
      1.05,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = _kSoOrangeLight,
    );

    // Orbiting dots.
    void dot(double r, double angle, double size, Color color) {
      final p = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      canvas.drawCircle(
        p,
        size + 1.5,
        Paint()..color = color.withValues(alpha: 0.28),
      );
      canvas.drawCircle(p, size, Paint()..color = color);
    }

    if (!reduceMotion) {
      dot(
        outerR,
        outerAngle + 1.35,
        4.2,
        _kSoOrange,
      );
      dot(
        midR,
        outerAngle + math.pi * 0.7 + 0.9,
        3.4,
        _kSoOrangeMid,
      );
      dot(
        innerR,
        innerAngle + 1.05,
        3.8,
        _kSoOrangeLight,
      );
    } else {
      // Static accent dots when motion is reduced.
      dot(outerR, -math.pi / 2 + 1.2, 4, _kSoOrange);
      dot(innerR, math.pi / 3, 3.5, _kSoOrangeLight);
    }
  }

  @override
  bool shouldRepaint(covariant _SignOutRingsPainter oldDelegate) =>
      oldDelegate.outerProgress != outerProgress ||
      oldDelegate.innerProgress != innerProgress ||
      oldDelegate.logoRadius != logoRadius ||
      oldDelegate.reduceMotion != reduceMotion;
}

class _SignOutWavePainter extends CustomPainter {
  _SignOutWavePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Path wave(double yBase, double amp, double phase) {
      final path = Path()..moveTo(0, h);
      path.lineTo(0, yBase);
      for (var x = 0.0; x <= w; x += 8) {
        final y =
            yBase +
            math.sin((x / w) * math.pi * 2 + phase) * amp +
            math.sin((x / w) * math.pi * 4 + phase * 1.3) * (amp * 0.25);
        path.lineTo(x, y);
      }
      path.lineTo(w, h);
      path.close();
      return path;
    }

    final c1 = isDark
        ? _kSoOrange.withValues(alpha: 0.14)
        : _kSoCream;
    final c2 = isDark
        ? _kSoOrangeMid.withValues(alpha: 0.12)
        : _kSoPeach;
    final c3 = isDark
        ? _kSoOrangePale.withValues(alpha: 0.10)
        : _kSoOrangePale.withValues(alpha: 0.55);

    canvas.drawPath(wave(h * 0.28, 14, 0.2), Paint()..color = c1);
    canvas.drawPath(wave(h * 0.42, 11, 1.1), Paint()..color = c2);
    canvas.drawPath(wave(h * 0.58, 8, 2.0), Paint()..color = c3);
  }

  @override
  bool shouldRepaint(covariant _SignOutWavePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Three-dot loader — sequential fade/bounce in orange tones.
class _SignOutDotLoader extends StatelessWidget {
  const _SignOutDotLoader({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  static const _colors = [
    Color(0xFFEA580C),
    Color(0xFFFDBA74),
    Color(0xFFFED7AA),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          if (reduceMotion) {
            return Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colors[index],
                ),
              ),
            );
          }

          final phase = (animation.value - index * 0.22 + 1) % 1.0;
          final lift = Curves.easeInOut.transform(
            phase < 0.5 ? phase * 2 : 1 - (phase - 0.5) * 2,
          );
          final opacity = 0.45 + lift * 0.55;

          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
            child: Transform.translate(
              offset: Offset(0, -lift * 7),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colors[index],
                    boxShadow: [
                      BoxShadow(
                        color: _colors[index].withValues(alpha: 0.4),
                        blurRadius: lift > 0.5 ? 6 : 2,
                      ),
                    ],
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

  await rootNav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
}
