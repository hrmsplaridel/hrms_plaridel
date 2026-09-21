import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Stroke styling shared by the draw pad, live preview, and PNG export.
const double kDocuTrackerSignatureStrokeWidth = 2.4;
const Color kDocuTrackerSignatureInkColor = Color(0xFF111827);

/// High-quality export canvas (logical pixels before [pixelRatio]).
const Size kDocuTrackerSignatureExportSize = Size(900, 360);

/// Extra padding around ink bounds, in stroke radii (half-widths).
const double kDocuTrackerSignatureBoundsPadRadii = 1.5;

/// Fraction of the export canvas kept as empty margin around the ink.
const double kDocuTrackerSignatureExportInset = 0.1;

/// Axis-aligned bounds of drawn ink, expanded by stroke radius + pad.
///
/// Returns `null` when there are no drawable points.
Rect? docuTrackerSignatureInkBounds(
  List<Offset?> points, {
  double strokeWidth = kDocuTrackerSignatureStrokeWidth,
}) {
  var hasPoint = false;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;

  for (final point in points) {
    if (point == null) continue;
    hasPoint = true;
    if (point.dx < minX) minX = point.dx;
    if (point.dy < minY) minY = point.dy;
    if (point.dx > maxX) maxX = point.dx;
    if (point.dy > maxY) maxY = point.dy;
  }

  if (!hasPoint) return null;

  final pad = strokeWidth * (0.5 + kDocuTrackerSignatureBoundsPadRadii);
  return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
}

/// How to map [inkBounds] into [canvasSize] while preserving aspect ratio
/// and centering the ink with a uniform inset.
class DocuTrackerSignatureInkLayout {
  const DocuTrackerSignatureInkLayout({
    required this.inkBounds,
    required this.scale,
    required this.translation,
    required this.destination,
  });

  final Rect inkBounds;
  final double scale;
  final Offset translation;
  final Rect destination;

  Offset mapPoint(Offset point) =>
      Offset(point.dx * scale, point.dy * scale) + translation;

  double mapStrokeWidth(double strokeWidth) => strokeWidth * scale;
}

DocuTrackerSignatureInkLayout? docuTrackerSignatureInkLayout(
  Rect inkBounds,
  Size canvasSize, {
  double insetFraction = kDocuTrackerSignatureExportInset,
}) {
  if (inkBounds.isEmpty ||
      !inkBounds.isFinite ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0) {
    return null;
  }

  final inset = insetFraction.clamp(0.0, 0.45);
  final available = Size(
    canvasSize.width * (1 - inset * 2),
    canvasSize.height * (1 - inset * 2),
  );
  if (available.width <= 0 || available.height <= 0) return null;

  final scaleX = available.width / inkBounds.width;
  final scaleY = available.height / inkBounds.height;
  final scale = scaleX < scaleY ? scaleX : scaleY;

  final scaledWidth = inkBounds.width * scale;
  final scaledHeight = inkBounds.height * scale;
  final left = (canvasSize.width - scaledWidth) / 2;
  final top = (canvasSize.height - scaledHeight) / 2;
  final destination = Rect.fromLTWH(left, top, scaledWidth, scaledHeight);
  final translation = Offset(
    left - inkBounds.left * scale,
    top - inkBounds.top * scale,
  );

  return DocuTrackerSignatureInkLayout(
    inkBounds: inkBounds,
    scale: scale,
    translation: translation,
    destination: destination,
  );
}

/// Removes the last completed or in-progress stroke from [points].
///
/// Strokes are sequences of non-null [Offset]s separated by `null`.
void docuTrackerUndoLastSignatureStroke(List<Offset?> points) {
  if (points.isEmpty) return;

  var end = points.length;
  if (points[end - 1] == null) {
    end -= 1;
  }
  var start = end;
  while (start > 0 && points[start - 1] != null) {
    start -= 1;
  }
  points.removeRange(start, points.length);
}

/// Minimum distance (logical px) between kept samples while drawing.
const double kDocuTrackerSignatureMinSampleDistance = 1.75;

/// Preview refresh interval while the stylus is moving.
const Duration kDocuTrackerSignaturePreviewThrottle = Duration(
  milliseconds: 50,
);

/// Whether [next] is far enough from [lastKept] to store another sample.
bool docuTrackerShouldKeepSignatureSample(
  Offset? lastKept,
  Offset next, {
  double minDistance = kDocuTrackerSignatureMinSampleDistance,
}) {
  if (lastKept == null) return true;
  return (next - lastKept).distanceSquared >= minDistance * minDistance;
}

/// Mutable stroke buffer optimized for live drawing (pad repaints only).
///
/// [notifyListeners] drives the draw pad. [previewListenable] is throttled so
/// the cropped preview does not recompute bounds on every pointer sample.
class DocuTrackerSignatureStrokeController extends ChangeNotifier {
  final List<Offset?> points = <Offset?>[];

  final ValueNotifier<int> previewListenable = ValueNotifier<int>(0);

  Offset? _lastKept;
  bool _hasInk = false;
  bool _previewDirty = false;
  Timer? _previewTimer;

  bool get hasInk => _hasInk;

  void beginStroke(Offset point) {
    points.add(point);
    _lastKept = point;
    _setHasInk(true);
    notifyListeners();
    _schedulePreview(force: true);
  }

  void appendStroke(Offset point) {
    if (!docuTrackerShouldKeepSignatureSample(_lastKept, point)) return;
    points.add(point);
    _lastKept = point;
    notifyListeners();
    _schedulePreview();
  }

  void endStroke() {
    if (_lastKept == null && (points.isEmpty || points.last == null)) {
      return;
    }
    points.add(null);
    _lastKept = null;
    notifyListeners();
    _schedulePreview(force: true);
  }

  void undoLastStroke() {
    if (!_hasInk) return;
    docuTrackerUndoLastSignatureStroke(points);
    _lastKept = null;
    _setHasInk(points.any((point) => point != null));
    notifyListeners();
    _schedulePreview(force: true);
  }

  void clear() {
    if (points.isEmpty && !_hasInk) return;
    points.clear();
    _lastKept = null;
    _setHasInk(false);
    notifyListeners();
    _schedulePreview(force: true);
  }

  void _setHasInk(bool value) {
    _hasInk = value;
  }

  void _schedulePreview({bool force = false}) {
    if (force) {
      _previewTimer?.cancel();
      _previewTimer = null;
      _previewDirty = false;
      previewListenable.value++;
      return;
    }
    if (_previewTimer != null) {
      _previewDirty = true;
      return;
    }
    previewListenable.value++;
    _previewTimer = Timer(kDocuTrackerSignaturePreviewThrottle, () {
      _previewTimer = null;
      if (_previewDirty) {
        _previewDirty = false;
        previewListenable.value++;
      }
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    previewListenable.dispose();
    super.dispose();
  }
}

/// Paints signature strokes onto [canvas], optionally remapped by [layout].
void paintDocuTrackerSignatureInk(
  Canvas canvas,
  List<Offset?> points, {
  DocuTrackerSignatureInkLayout? layout,
  Color color = kDocuTrackerSignatureInkColor,
  double strokeWidth = kDocuTrackerSignatureStrokeWidth,
}) {
  final width = layout?.mapStrokeWidth(strokeWidth) ?? strokeWidth;
  final strokePaint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..isAntiAlias = true;
  final dotPaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  final path = Path();
  Offset? strokeStart;
  var strokePointCount = 0;

  void finishStroke() {
    final start = strokeStart;
    if (strokePointCount == 1 && start != null) {
      canvas.drawCircle(start, width / 2, dotPaint);
    }
    strokeStart = null;
    strokePointCount = 0;
  }

  for (final point in points) {
    if (point == null) {
      finishStroke();
      continue;
    }
    final mapped = layout == null ? point : layout.mapPoint(point);
    if (strokePointCount == 0) {
      path.moveTo(mapped.dx, mapped.dy);
      strokeStart = mapped;
      strokePointCount = 1;
    } else {
      path.lineTo(mapped.dx, mapped.dy);
      strokePointCount++;
    }
  }
  finishStroke();
  canvas.drawPath(path, strokePaint);
}

/// Encodes drawn strokes as a cropped, centered, transparent PNG.
///
/// The ink is scaled proportionally to fill [logicalSize] (minus inset)
/// so the signature is not tiny, clipped, or stretched when placed on
/// documents via `BoxFit.contain`.
Future<Uint8List?> encodeDocuTrackerSignaturePng(
  List<Offset?> points, {
  Size logicalSize = kDocuTrackerSignatureExportSize,
  double pixelRatio = 2,
  double strokeWidth = kDocuTrackerSignatureStrokeWidth,
  Color color = kDocuTrackerSignatureInkColor,
  double insetFraction = kDocuTrackerSignatureExportInset,
}) async {
  final bounds = docuTrackerSignatureInkBounds(
    points,
    strokeWidth: strokeWidth,
  );
  if (bounds == null) return null;

  final layout = docuTrackerSignatureInkLayout(
    bounds,
    logicalSize,
    insetFraction: insetFraction,
  );
  if (layout == null) return null;

  final ratio = pixelRatio <= 0 ? 1.0 : pixelRatio;
  final widthPx = (logicalSize.width * ratio).round().clamp(1, 4096);
  final heightPx = (logicalSize.height * ratio).round().clamp(1, 4096);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  paintDocuTrackerSignatureInk(
    canvas,
    points,
    layout: layout,
    color: color,
    strokeWidth: strokeWidth,
  );

  final image = await recorder.endRecording().toImage(widthPx, heightPx);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
