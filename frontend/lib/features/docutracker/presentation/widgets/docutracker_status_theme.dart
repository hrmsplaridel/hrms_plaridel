import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';

/// Single source of truth for document status colors and icons.
/// Uses a modern SaaS palette (e.g. Tailwind-inspired) for maximum readability.
class DocuTrackerStatusTheme {
  DocuTrackerStatusTheme._();

  static Color foreground(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => const Color(0xFF4B5563), // Gray 600
      DocumentStatus.inReview => const Color(0xFF1D4ED8), // Blue 700
      DocumentStatus.approved => const Color(0xFF047857), // Emerald 700
      DocumentStatus.rejected => const Color(0xFFB91C1C), // Red 700
      DocumentStatus.returned => const Color(0xFFB45309), // Amber 700
      DocumentStatus.overdue => const Color(0xFF991B1B), // Dark Red 800
      DocumentStatus.escalated => const Color(0xFF6D28D9), // Purple 700
      DocumentStatus.cancelled => const Color(0xFF6B7280), // Gray 500
    };
  }

  static Color chipBackground(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => const Color(0xFFF3F4F6), // Gray 100
      DocumentStatus.inReview => const Color(0xFFEFF6FF), // Blue 50
      DocumentStatus.approved => const Color(0xFFECFDF5), // Emerald 50
      DocumentStatus.rejected => const Color(0xFFFEF2F2), // Red 50
      DocumentStatus.returned => const Color(0xFFFFFBEB), // Amber 50
      DocumentStatus.overdue => const Color(0xFFFEF2F2), // Red 50
      DocumentStatus.escalated => const Color(0xFFF5F3FF), // Purple 50
      DocumentStatus.cancelled => const Color(0xFFF9FAFB), // Gray 50
    };
  }

  static Color chipBorder(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => const Color(0xFFE5E7EB), // Gray 200
      DocumentStatus.inReview => const Color(0xFFBFDBFE), // Blue 200
      DocumentStatus.approved => const Color(0xFFA7F3D0), // Emerald 200
      DocumentStatus.rejected => const Color(0xFFFECACA), // Red 200
      DocumentStatus.returned => const Color(0xFFFDE68A), // Amber 200
      DocumentStatus.overdue => const Color(0xFFFCA5A5), // Red 300
      DocumentStatus.escalated => const Color(0xFFDDD6FE), // Purple 200
      DocumentStatus.cancelled => const Color(0xFFE5E7EB), // Gray 200
    };
  }

  static IconData icon(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => Icons.hourglass_empty_rounded,
      DocumentStatus.inReview => Icons.remove_red_eye_rounded,
      DocumentStatus.approved => Icons.check_circle_outline_rounded,
      DocumentStatus.rejected => Icons.cancel_outlined,
      DocumentStatus.returned => Icons.keyboard_return_rounded,
      DocumentStatus.overdue => Icons.alarm_off_rounded,
      DocumentStatus.escalated => Icons.notifications_active_outlined,
      DocumentStatus.cancelled => Icons.block_rounded,
    };
  }
}
