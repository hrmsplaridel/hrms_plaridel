import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_ink.dart';

void main() {
  group('docuTrackerSignatureInkBounds', () {
    test('returns null for empty ink', () {
      expect(docuTrackerSignatureInkBounds(const []), isNull);
      expect(docuTrackerSignatureInkBounds(const [null, null]), isNull);
    });

    test('expands point bounds by stroke padding', () {
      final bounds = docuTrackerSignatureInkBounds(const [
        Offset(10, 20),
        Offset(40, 50),
        null,
      ], strokeWidth: 2);
      expect(bounds, isNotNull);
      // pad = 2 * (0.5 + 1.5) = 4
      expect(bounds!.left, closeTo(6, 0.001));
      expect(bounds.top, closeTo(16, 0.001));
      expect(bounds.right, closeTo(44, 0.001));
      expect(bounds.bottom, closeTo(54, 0.001));
    });
  });

  group('docuTrackerSignatureInkLayout', () {
    test('centers ink and preserves aspect ratio', () {
      const ink = Rect.fromLTWH(0, 0, 100, 50);
      const canvas = Size(400, 200);
      final layout = docuTrackerSignatureInkLayout(
        ink,
        canvas,
        insetFraction: 0.1,
      );
      expect(layout, isNotNull);
      // Available = 320 x 160; scale limited by height: 160/50 = 3.2
      expect(layout!.scale, closeTo(3.2, 0.001));
      expect(layout.destination.width, closeTo(320, 0.001));
      expect(layout.destination.height, closeTo(160, 0.001));
      expect(layout.destination.center.dx, closeTo(200, 0.001));
      expect(layout.destination.center.dy, closeTo(100, 0.001));
    });

    test('does not stretch a tall signature', () {
      const ink = Rect.fromLTWH(0, 0, 40, 200);
      const canvas = Size(900, 360);
      final layout = docuTrackerSignatureInkLayout(ink, canvas);
      expect(layout, isNotNull);
      expect(
        layout!.destination.width / layout.destination.height,
        closeTo(ink.width / ink.height, 0.001),
      );
      expect(layout.destination.center.dx, closeTo(450, 0.5));
      expect(layout.destination.center.dy, closeTo(180, 0.5));
    });
  });

  group('docuTrackerShouldKeepSignatureSample', () {
    test('keeps the first sample and drops near duplicates', () {
      expect(
        docuTrackerShouldKeepSignatureSample(null, const Offset(1, 1)),
        isTrue,
      );
      expect(
        docuTrackerShouldKeepSignatureSample(
          const Offset(0, 0),
          const Offset(0.5, 0.5),
        ),
        isFalse,
      );
      expect(
        docuTrackerShouldKeepSignatureSample(
          const Offset(0, 0),
          const Offset(3, 0),
        ),
        isTrue,
      );
    });
  });

  group('DocuTrackerSignatureStrokeController', () {
    test('thins samples and only force-updates preview on stroke end', () {
      final controller = DocuTrackerSignatureStrokeController();
      addTearDown(controller.dispose);

      var previewTicks = 0;
      controller.previewListenable.addListener(() => previewTicks++);

      controller.beginStroke(const Offset(0, 0));
      expect(previewTicks, 1);
      controller.appendStroke(const Offset(0.2, 0.1)); // too close
      controller.appendStroke(const Offset(4, 0));
      expect(controller.points.whereType<Offset>().length, 2);
      expect(previewTicks, 2); // throttled immediate tick on first append batch

      controller.endStroke();
      expect(controller.points.last, isNull);
      expect(previewTicks, greaterThanOrEqualTo(3));
      expect(controller.hasInk, isTrue);

      controller.undoLastStroke();
      expect(controller.hasInk, isFalse);
      expect(controller.points, isEmpty);
    });
  });

  group('docuTrackerUndoLastSignatureStroke', () {
    test('removes the last stroke including trailing separator', () {
      final points = <Offset?>[
        const Offset(1, 1),
        const Offset(2, 2),
        null,
        const Offset(3, 3),
        const Offset(4, 4),
        null,
      ];
      docuTrackerUndoLastSignatureStroke(points);
      expect(points, <Offset?>[const Offset(1, 1), const Offset(2, 2), null]);
      docuTrackerUndoLastSignatureStroke(points);
      expect(points, isEmpty);
    });

    test('removes an unfinished stroke without a trailing null', () {
      final points = <Offset?>[
        const Offset(1, 1),
        null,
        const Offset(5, 5),
        const Offset(6, 6),
      ];
      docuTrackerUndoLastSignatureStroke(points);
      expect(points, <Offset?>[const Offset(1, 1), null]);
    });
  });

  group('encodeDocuTrackerSignaturePng', () {
    test('exports cropped centered transparent PNG at expected size', () async {
      final points = <Offset?>[
        const Offset(20, 20),
        const Offset(80, 40),
        const Offset(120, 30),
        null,
      ];
      final bytes = await encodeDocuTrackerSignaturePng(
        points,
        logicalSize: const Size(300, 120),
        pixelRatio: 2,
      );
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(8));
      // PNG magic
      expect(bytes[0], 0x89);
      expect(bytes[1], 0x50);

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      expect(image.width, 600);
      expect(image.height, 240);

      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba, isNotNull);
      // Corner pixel should be fully transparent.
      expect(rgba!.getUint8(3), 0);

      // Find at least one opaque/semi-opaque ink pixel.
      var foundInk = false;
      for (var i = 3; i < rgba.lengthInBytes; i += 4) {
        if (rgba.getUint8(i) > 0) {
          foundInk = true;
          break;
        }
      }
      expect(foundInk, isTrue);
      image.dispose();
    });

    test('returns null when there is nothing to encode', () async {
      expect(await encodeDocuTrackerSignaturePng(const []), isNull);
      expect(await encodeDocuTrackerSignaturePng(const [null]), isNull);
    });

    test(
      'scales a tiny stroke up so it is not a speck on the canvas',
      () async {
        final points = <Offset?>[
          const Offset(50, 50),
          const Offset(52, 51),
          null,
        ];
        final bytes = await encodeDocuTrackerSignaturePng(
          points,
          logicalSize: const Size(400, 160),
          pixelRatio: 1,
        );
        expect(bytes, isNotNull);
        final codec = await ui.instantiateImageCodec(bytes!);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(rgba, isNotNull);

        var inkPixels = 0;
        for (var i = 3; i < rgba!.lengthInBytes; i += 4) {
          if (rgba.getUint8(i) > 0) inkPixels++;
        }
        // After proportional upscale + stroke scaling, ink should cover
        // meaningfully more than a couple of source pixels.
        expect(inkPixels, greaterThan(80));
        image.dispose();
      },
    );
  });
}
