import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import '../models/document.dart';
import '../models/document_status.dart';

/// Step 13: Countdown timer or remaining time on assigned documents.
class DocumentCountdownTimer extends StatelessWidget {
  const DocumentCountdownTimer({
    super.key,
    required this.document,
    this.compact = false,
  });

  final DocuTrackerDocument document;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (document.deadlineTime == null) return const SizedBox.shrink();
    if (document.status == DocumentStatus.approved ||
        document.status == DocumentStatus.rejected) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final deadline = document.deadlineTime!;
    final isOverdue = now.isAfter(deadline);
    final remaining = deadline.difference(now);

    String text;
    Color color;
    if (isOverdue) {
      final overdue = now.difference(deadline);
      text = _formatDuration(overdue, prefix: 'Overdue by ');
      color = Colors.red;
    } else {
      text = _formatDuration(remaining, prefix: '');
      if (remaining.inMinutes < 60) {
        color = Colors.orange;
      } else {
        color = AppTheme.textSecondary;
      }
    }

    if (compact) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d, {String prefix = ''}) {
    if (d.isNegative) d = -d;
    if (d.inDays > 0) return '$prefix${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '$prefix${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '$prefix${d.inMinutes}m';
    return '${prefix}${d.inSeconds}s';
  }
}
