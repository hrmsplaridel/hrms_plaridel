import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

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
    final isWide = MediaQuery.of(context).size.width > 800;
    final horizontalPadding = isWide ? 80.0 : 24.0;
    final verticalPadding = isWide ? 72.0 : 48.0;

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
