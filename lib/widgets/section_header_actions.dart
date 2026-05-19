import 'package:flutter/material.dart';

/// Lays out section header action buttons: 2-column grid on mobile, wrap on wider screens.
class SectionHeaderActions extends StatelessWidget {
  const SectionHeaderActions({
    super.key,
    required this.children,
    this.mobileBreakpoint = 600,
    this.spacing = 8,
  });

  final List<Widget> children;
  final double mobileBreakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < mobileBreakpoint;

    if (!isMobile) {
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: children,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// Shared compact styling for header action buttons on narrow screens.
class SectionHeaderActionButton {
  SectionHeaderActionButton._();

  static const double mobileBreakpoint = 600;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static ButtonStyle _compactOutlinedStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
    );
  }

  static ButtonStyle _compactFilledStyle() {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
    );
  }

  static Widget outlined({
    required BuildContext context,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
  }) {
    final compact = isMobile(context);
    final iconSize = compact ? 16.0 : 18.0;
    final child = Text(label);

    if (!compact) {
      if (icon != null) {
        return OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: iconSize),
          label: child,
        );
      }
      return OutlinedButton(onPressed: onPressed, child: child);
    }

    if (icon != null) {
      return SizedBox(
        width: double.infinity,
        height: 36,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: _compactOutlinedStyle(),
          icon: Icon(icon, size: iconSize),
          label: child,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: _compactOutlinedStyle(),
        child: child,
      ),
    );
  }

  static Widget filled({
    required BuildContext context,
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
  }) {
    final compact = isMobile(context);
    final iconSize = compact ? 16.0 : 18.0;
    final child = Text(label);

    if (!compact) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        label: child,
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 36,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: _compactFilledStyle(),
        icon: Icon(icon, size: iconSize),
        label: child,
      ),
    );
  }
}
