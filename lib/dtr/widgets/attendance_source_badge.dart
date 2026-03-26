import 'package:flutter/material.dart';

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
  static (Color text, Color bg) getColors(String? source) {
    if (source == null || source.isEmpty) {
      return (Colors.grey, Colors.grey.withOpacity(0.2));
    }
    switch (source.toLowerCase()) {
      case 'manual':
        return (Colors.blue.shade800, Colors.blue.shade50);
      case 'system':
        return (Colors.green.shade800, Colors.green.shade50);
      case 'adjusted':
        return (Colors.orange.shade800, Colors.orange.shade50);
      default:
        return (Colors.grey.shade700, Colors.grey.shade200);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = getLabel(source);
    if (label.isEmpty) return const SizedBox.shrink();

    final (textColor, bgColor) = getColors(source);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final fontSize = compact ? 10.0 : 11.0;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withOpacity(0.4), width: 1),
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
