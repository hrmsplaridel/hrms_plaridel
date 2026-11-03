import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/locator_print_layout.dart';

Color printLayoutColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// Shared logical-point strokes keep the editor and exported PDF in agreement.
List<(double, double, double, double)> printLayoutBorderSegments(
  LocatorPrintElement item,
) {
  final style = item.decoration;
  if (style.borderWidth == 0) return [];
  final inset = math.min(
    style.borderWidth / 2,
    math.min(item.width, item.height) / 2,
  );
  final edges = item.kind == 'line'
      ? [(0.0, item.height / 2, item.width, item.height / 2)]
      : [
          if (style.borderSides.contains('top'))
            (inset, inset, item.width - inset, inset),
          if (style.borderSides.contains('right'))
            (
              item.width - inset,
              inset,
              item.width - inset,
              item.height - inset,
            ),
          if (style.borderSides.contains('bottom'))
            (
              inset,
              item.height - inset,
              item.width - inset,
              item.height - inset,
            ),
          if (style.borderSides.contains('left'))
            (inset, inset, inset, item.height - inset),
        ];
  if (style.borderStyle == 'solid') return edges;
  final result = <(double, double, double, double)>[];
  for (final (x1, y1, x2, y2) in edges) {
    final length = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
    if (length == 0) continue;
    final dash = math.max(4.0, style.borderWidth * 3),
        gap = math.max(3.0, style.borderWidth * 2);
    for (var at = 0.0; at < length; at += dash + gap) {
      final end = math.min(length, at + dash);
      result.add((
        x1 + (x2 - x1) * at / length,
        y1 + (y2 - y1) * at / length,
        x1 + (x2 - x1) * end / length,
        y1 + (y2 - y1) * end / length,
      ));
    }
  }
  return result;
}

class PrintLayoutDecorationView extends StatelessWidget {
  const PrintLayoutDecorationView({
    super.key,
    required this.item,
    required this.scale,
    required this.child,
  });
  final LocatorPrintElement item;
  final double scale;
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DecorationPainter(item, scale, fill: true),
    foregroundPainter: _DecorationPainter(item, scale, fill: false),
    child: child,
  );
}

class _DecorationPainter extends CustomPainter {
  _DecorationPainter(this.item, this.scale, {required this.fill});
  final LocatorPrintElement item;
  final double scale;
  final bool fill;
  @override
  void paint(Canvas canvas, Size size) {
    if (fill) {
      if (item.decoration.fillColor != null) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = printLayoutColor(item.decoration.fillColor!),
        );
      }
      return;
    }
    final paint = Paint()
      ..color = printLayoutColor(item.decoration.borderColor)
      ..strokeWidth = item.decoration.borderWidth * scale;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (x1, y1, x2, y2) in printLayoutBorderSegments(item)) {
      canvas.drawLine(
        Offset(x1 * scale, y1 * scale),
        Offset(x2 * scale, y2 * scale),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DecorationPainter old) =>
      old.item != item || old.scale != scale || old.fill != fill;
}

pw.Widget decoratePrintLayoutPdf(LocatorPrintElement item, pw.Widget child) {
  if (item.decoration.isDefault && item.kind != 'line') return child;
  return pw.Stack(
    fit: pw.StackFit.expand,
    children: [
      if (item.decoration.fillColor != null)
        pw.Positioned.fill(
          child: pw.Container(
            color: PdfColor.fromHex(item.decoration.fillColor!),
          ),
        ),
      pw.Positioned.fill(child: child),
      pw.Positioned.fill(
        child: pw.ClipRect(
          child: pw.CustomPaint(
            painter: (canvas, size) {
              canvas
                ..setStrokeColor(PdfColor.fromHex(item.decoration.borderColor))
                ..setLineWidth(item.decoration.borderWidth);
              for (final (x1, y1, x2, y2) in printLayoutBorderSegments(item)) {
                canvas
                  ..drawLine(x1, size.y - y1, x2, size.y - y2)
                  ..strokePath();
              }
            },
          ),
        ),
      ),
    ],
  );
}
