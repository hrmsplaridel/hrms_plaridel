import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Shared landing breakpoints (match header / page shell).
abstract final class LandingBreakpoints {
  static const double mobile = 768;
  static const double phone = 600;
  static const double compact = 480;
  static const double phoneNarrow = 380;
  static const double wide = 800;

  static bool isMobile(double width) => width < mobile;
  static bool isPhone(double width) => width < phone;
  static bool isCompact(double width) => width < compact;
  static bool isPhoneNarrow(double width) => width < phoneNarrow;
  static bool isWide(double width) => width > wide;
}

/// Reusable section wrapper with consistent padding and background.
class SectionContainer extends StatelessWidget {
  const SectionContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding,
    this.borderRadius,
    this.withShadow = true,
    this.margin,
  });

  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  /// When true and background is not fully transparent, draws [AppTheme.panelShadow].
  final bool withShadow;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = LandingBreakpoints.isWide(width);
    final isCompact = LandingBreakpoints.isCompact(width);
    final isPhoneNarrow = LandingBreakpoints.isPhoneNarrow(width);
    final horizontalPadding = isWide
        ? 80.0
        : (isPhoneNarrow ? 12.0 : (isCompact ? 16.0 : 20.0));
    final verticalPadding = isWide
        ? 72.0
        : (isPhoneNarrow ? 28.0 : (isCompact ? 36.0 : 44.0));

    final bg = backgroundColor ?? AppTheme.white;
    final showShadow = withShadow && bg.a > 0;

    return Container(
      width: double.infinity,
      margin: margin,
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius != null
            ? BorderRadius.circular(borderRadius!)
            : null,
        boxShadow: showShadow ? AppTheme.panelShadow : null,
      ),
      child: child,
    );
  }
}
