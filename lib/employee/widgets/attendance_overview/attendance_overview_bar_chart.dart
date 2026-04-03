import 'package:flutter/material.dart';

import 'attendance_overview_data.dart';

/// Vertical bar chart: one bar per day, height constant, color = status.
class AttendanceOverviewBarChart extends StatelessWidget {
  const AttendanceOverviewBarChart({super.key, required this.days});

  final List<AttendanceOverviewDay> days;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _AttendanceOverviewBarPainter(days: days));
  }
}

class _AttendanceOverviewBarPainter extends CustomPainter {
  _AttendanceOverviewBarPainter({required this.days});

  final List<AttendanceOverviewDay> days;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const padH = 6.0;
    const padTop = 6.0;
    const padBottom = 20.0;
    final chartH = (size.height - padTop - padBottom).clamp(0.0, size.height);
    final w = size.width - padH * 2;
    if (w <= 0 || chartH <= 0) return;

    final n = days.length;
    final slotW = w / n;
    final barW = (slotW * 0.62).clamp(2.0, slotW * 0.85);

    final fill = Paint()..style = PaintingStyle.fill;
    final track = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    final baselineY = padTop + chartH;
    canvas.drawLine(
      Offset(padH, baselineY),
      Offset(padH + w, baselineY),
      track,
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < n; i++) {
      final day = days[i];
      final cx = padH + i * slotW + slotW / 2;
      final left = cx - barW / 2;
      final top = padTop;

      fill.color = day.barColor;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barW, chartH),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(rect, fill);

      final showLabel = n <= 10 || i % 2 == 0 || i == n - 1;
      if (showLabel) {
        tp.text = TextSpan(
          text: '${day.dayOfMonth}',
          style: TextStyle(
            fontSize: n > 12 ? 8.5 : 9.5,
            color: Colors.black.withValues(alpha: 0.45),
            fontWeight: FontWeight.w600,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, baselineY + 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AttendanceOverviewBarPainter oldDelegate) {
    if (identical(oldDelegate.days, days)) return false;
    if (oldDelegate.days.length != days.length) return true;
    for (var i = 0; i < days.length; i++) {
      final a = oldDelegate.days[i];
      final b = days[i];
      if (a.dayOfMonth != b.dayOfMonth || a.barColor != b.barColor) {
        return true;
      }
    }
    return false;
  }
}
