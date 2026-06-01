import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'docutracker_status_theme.dart';

/// Status chip with dot + label. Consistent across DocuTracker.
class DocuTrackerStatusBadge extends StatelessWidget {
  const DocuTrackerStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
    this.showIcon = true,
    this.dotStyle = false,
  });

  final DocumentStatus status;
  final bool compact;
  final bool showIcon;

  /// When true, renders a colored dot instead of an icon.
  final bool dotStyle;

  @override
  Widget build(BuildContext context) {
    final fg = DocuTrackerStatusTheme.foreground(status);
    final fontSize = compact ? 11.0 : 12.0;
    final padH = compact ? 8.0 : 10.0;
    final padV = compact ? 3.0 : 5.0;
    final radius = compact ? 7.0 : 8.0;

    return Semantics(
      label: 'Status: ${status.displayName}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: DocuTrackerStatusTheme.chipBackground(status),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: DocuTrackerStatusTheme.chipBorder(status)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (dotStyle) ...[
              Container(
                width: compact ? 6 : 8,
                height: compact ? 6 : 8,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
              SizedBox(width: compact ? 5 : 6),
            ] else if (showIcon) ...[
              Icon(
                DocuTrackerStatusTheme.icon(status),
                size: compact ? 12 : 14,
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
                letterSpacing: 0.1,
                height: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
