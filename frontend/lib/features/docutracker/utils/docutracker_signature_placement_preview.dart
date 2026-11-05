import 'dart:ui';

import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

/// Free-placement box. Same size the editor already uses for "Insert signature".
const Size kDocuTrackerFreeSignatureFraction = Size(0.30, 0.12);

/// Page-fraction lift so a finger or stylus does not cover the preview.
const double kDocuTrackerTouchPreviewLift = 0.045;

/// Open band of the official memorandum: below the letterhead and above the
/// release stamp, signatory lines, and footer art.
Rect docuTrackerMemoFreePlacementBounds() {
  final bottom = DocuTrackerMemoLayout.releaseBlock.top;
  return Rect.fromLTWH(
    DocuTrackerMemoLayout.marginX,
    DocuTrackerMemoLayout.letterheadHeaderBottom,
    1 - DocuTrackerMemoLayout.marginX * 2,
    bottom - DocuTrackerMemoLayout.letterheadHeaderBottom,
  );
}

double docuTrackerPlacementLift(PointerDeviceKind kind) => switch (kind) {
  PointerDeviceKind.touch ||
  PointerDeviceKind.stylus ||
  PointerDeviceKind.invertedStylus => kDocuTrackerTouchPreviewLift,
  _ => 0.0,
};

/// Point on a page, as fractions. [local] may be measured on a zoomed page;
/// [scale] is divided out so 100% and 200% name the same spot.
Offset docuTrackerPaperFraction(
  Offset local, {
  required Size paper,
  double scale = 1,
}) {
  final safeScale = scale <= 0 ? 1.0 : scale;
  final width = paper.width <= 0 ? 1.0 : paper.width;
  final height = paper.height <= 0 ? 1.0 : paper.height;
  return Offset(local.dx / safeScale / width, local.dy / safeScale / height);
}

/// Keeps a signature box inside [bounds]. The returned rect is the one
/// confirmation stores; nothing is shifted again afterwards.
Rect docuTrackerClampPlacementRect({
  required Offset topLeft,
  required Size size,
  Rect bounds = const Rect.fromLTWH(0, 0, 1, 1),
}) {
  final limit = bounds.isEmpty ? const Rect.fromLTWH(0, 0, 1, 1) : bounds;
  var width = size.width;
  var height = size.height;
  if (width > limit.width) width = limit.width;
  if (height > limit.height) height = limit.height;
  if (width < 0) width = 0;
  if (height < 0) height = 0;
  final left = topLeft.dx.clamp(limit.left, limit.right - width);
  final top = topLeft.dy.clamp(limit.top, limit.bottom - height);
  return Rect.fromLTWH(left, top, width, height);
}

Rect docuTrackerInitialFreePlacement({Rect? bounds}) {
  final box = bounds ?? const Rect.fromLTWH(0, 0, 1, 1);
  return docuTrackerClampPlacementRect(
    topLeft: Offset(
      box.center.dx - kDocuTrackerFreeSignatureFraction.width / 2,
      box.center.dy - kDocuTrackerFreeSignatureFraction.height / 2,
    ),
    size: kDocuTrackerFreeSignatureFraction,
    bounds: box,
  );
}

/// Box centered on [pointerFraction], lifted for touch, then clamped.
/// The result is the outline the user sees and the rect confirmation saves.
Rect docuTrackerFreePlacementRect({
  required Offset pointerFraction,
  Size size = kDocuTrackerFreeSignatureFraction,
  double lift = 0,
  Rect? bounds,
}) {
  return docuTrackerClampPlacementRect(
    topLeft: Offset(
      pointerFraction.dx - size.width / 2,
      pointerFraction.dy - size.height / 2 - lift,
    ),
    size: size,
    bounds: bounds ?? const Rect.fromLTWH(0, 0, 1, 1),
  );
}

/// `BoxFit.contain` rectangle for a signature of [aspectRatio] (width/height)
/// inside [field]. Matches how a saved signature is painted in that field.
Rect docuTrackerContainSignatureBox(Rect field, double aspectRatio) {
  if (field.isEmpty || aspectRatio <= 0 || !aspectRatio.isFinite) return field;
  final fieldAspect = field.width / field.height;
  if (aspectRatio >= fieldAspect) {
    final height = field.width / aspectRatio;
    return Rect.fromLTWH(
      field.left,
      field.top + (field.height - height) / 2,
      field.width,
      height,
    );
  }
  final width = field.height * aspectRatio;
  return Rect.fromLTWH(
    field.left + (field.width - width) / 2,
    field.top,
    width,
    field.height,
  );
}

/// Where a not-yet-saved signature is shown. Tracking never persists.
class DocuTrackerPlacementSession {
  DocuTrackerPlacementSession.anchored(Rect field)
    : free = false,
      bounds = null,
      anchor = field,
      pointer = null;

  DocuTrackerPlacementSession.free({Rect? bounds})
    : free = true,
      bounds = bounds,
      anchor = docuTrackerInitialFreePlacement(bounds: bounds),
      pointer = null;

  final bool free;
  final Rect? bounds;
  Rect anchor;
  Offset? pointer;

  /// Updates the outline. Returns the same rect confirmation will save.
  Rect track(
    Offset local, {
    required Size paper,
    double scale = 1,
    required PointerDeviceKind kind,
  }) {
    if (!free) return anchor;
    final fraction = docuTrackerPaperFraction(
      local,
      paper: paper,
      scale: scale,
    );
    pointer = fraction;
    anchor = docuTrackerFreePlacementRect(
      pointerFraction: fraction,
      lift: docuTrackerPlacementLift(kind),
      bounds: bounds,
    );
    return anchor;
  }

  Rect confirm() => anchor;
}

/// The rect to persist. Cancel and a missing session persist nothing.
Rect? docuTrackerPlacementCommit(
  DocuTrackerPlacementSession? session, {
  required bool confirmed,
}) {
  if (!confirmed || session == null) return null;
  return session.confirm();
}
