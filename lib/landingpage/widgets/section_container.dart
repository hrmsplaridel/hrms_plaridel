import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

/// Reusable section wrapper with consistent padding and background.
class SectionContainer extends StatelessWidget {
  const SectionContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding,
  });

  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    final horizontalPadding = isWide ? 80.0 : 24.0;
    final verticalPadding = isWide ? 64.0 : 40.0;

    return Container(
      width: double.infinity,
      color: backgroundColor ?? AppTheme.white,
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
      child: child,
    );
  }
}
