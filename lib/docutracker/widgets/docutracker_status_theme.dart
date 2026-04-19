import 'package:flutter/material.dart';
import '../models/document_status.dart';

/// Single source of truth for document status colors and icons (lists, detail, admin).
class DocuTrackerStatusTheme {
  DocuTrackerStatusTheme._();

  static Color foreground(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => const Color(0xFF616161),
      DocumentStatus.inReview => const Color(0xFF1565C0),
      DocumentStatus.approved => const Color(0xFF2E7D32),
      DocumentStatus.rejected => const Color(0xFFC62828),
      DocumentStatus.returned => const Color(0xFFE65100),
      DocumentStatus.overdue => const Color(0xFFBF360C),
      DocumentStatus.escalated => const Color(0xFF4527A0),
    };
  }

  static Color chipBackground(DocumentStatus status) =>
      foreground(status).withValues(alpha: 0.12);

  static Color chipBorder(DocumentStatus status) =>
      foreground(status).withValues(alpha: 0.45);

  static IconData icon(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => Icons.hourglass_empty_rounded,
      DocumentStatus.inReview => Icons.rate_review_rounded,
      DocumentStatus.approved => Icons.verified_rounded,
      DocumentStatus.rejected => Icons.cancel_rounded,
      DocumentStatus.returned => Icons.reply_rounded,
      DocumentStatus.overdue => Icons.warning_amber_rounded,
      DocumentStatus.escalated => Icons.trending_up_rounded,
    };
  }
}
