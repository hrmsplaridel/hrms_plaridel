import 'package:flutter/material.dart';

/// Shared responsive switcher for desktop vs mobile layouts.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.desktop,
    required this.mobile,
    this.mobileBreakpoint = 600,
  });

  final Widget desktop;
  final Widget mobile;
  final double mobileBreakpoint;

  static bool isMobileWidth(double width, {double mobileBreakpoint = 600}) {
    return width < mobileBreakpoint;
  }

  static bool isMobileContext(
    BuildContext context, {
    double mobileBreakpoint = 600,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return isMobileWidth(width, mobileBreakpoint: mobileBreakpoint);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return isMobileWidth(width, mobileBreakpoint: mobileBreakpoint)
            ? mobile
            : desktop;
      },
    );
  }
}
