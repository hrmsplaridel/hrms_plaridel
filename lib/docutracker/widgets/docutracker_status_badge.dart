import 'package:flutter/material.dart';
import '../models/document_status.dart';
import 'docutracker_status_theme.dart';

/// Status chip with icon + label (accessible, consistent across DocuTracker).
class DocuTrackerStatusBadge extends StatelessWidget {
  const DocuTrackerStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
    this.showIcon = true,
  });

  final DocumentStatus status;
  final bool compact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final fg = DocuTrackerStatusTheme.foreground(status);
    final fontSize = compact ? 11.0 : 13.0;
    final padH = compact ? 8.0 : 12.0;
    final padV = compact ? 4.0 : 6.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: DocuTrackerStatusTheme.chipBackground(status),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DocuTrackerStatusTheme.chipBorder(status)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              DocuTrackerStatusTheme.icon(status),
              size: compact ? 14 : 16,
              color: fg,
            ),
            SizedBox(width: compact ? 4 : 6),
          ],
          Text(
            status.displayName,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
