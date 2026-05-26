import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Compact badge showing attendance source: Manual (Fallback), Biometric, or Adjusted.
/// Returns [SizedBox.shrink()] when [source] is null or empty.
class AttendanceSourceBadge extends StatelessWidget {
  const AttendanceSourceBadge({super.key, this.source, this.compact = false});

  /// Raw source value from API: 'manual', 'system', 'adjusted', or null.
  final String? source;

  /// When true, uses smaller font and padding.
  final bool compact;

  /// Label for display. manual → "Manual (Fallback)", system → "Biometric", adjusted → "Adjusted".
  static String getLabel(String? source) {
    if (source == null || source.isEmpty) return '';
    switch (source.toLowerCase()) {
      case 'manual':
        return 'Manual';
      case 'system':
        return 'Biometric';
      case 'adjusted':
        return 'Adjusted';
      default:
        return source;
    }
  }

  /// Color for the badge. manual → blue, system → green, adjusted → orange.
  static (Color text, Color bg) getColors(String? source, {bool dark = false}) {
    (Color fg, Color lightBg) pair(Color f, Color b) =>
        dark ? (f.withValues(alpha: 0.92), f.withValues(alpha: 0.24)) : (f, b);

    if (source == null || source.isEmpty) {
      return dark
          ? (Colors.grey.shade300, Colors.grey.withValues(alpha: 0.24))
          : (Colors.grey, Colors.grey.withValues(alpha: 0.2));
    }
    switch (source.toLowerCase()) {
      case 'manual':
        return pair(Colors.blue.shade800, Colors.blue.shade50);
      case 'system':
        return pair(Colors.green.shade800, Colors.green.shade50);
      case 'adjusted':
        return pair(Colors.orange.shade800, Colors.orange.shade50);
      default:
        return pair(Colors.grey.shade700, Colors.grey.shade200);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = getLabel(source);
    if (label.isEmpty) return const SizedBox.shrink();

    final dark = AppTheme.dashIsDark(context);
    final (textColor, bgColor) = getColors(source, dark: dark);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final fontSize = compact ? 10.0 : 11.0;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
