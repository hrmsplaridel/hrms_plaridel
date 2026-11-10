import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_placement_overlay.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_placement_preview.dart';

class _StubSignatureProvider extends DocuTrackerProvider {
  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async =>
      const [];
}

void main() {
  const paper = Size(794, 1123);

  group('placement geometry', () {
    test('zoom does not change the page fraction', () {
      final fitted = DocuTrackerPlacementSession.free();
      final zoomed = DocuTrackerPlacementSession.free();
      final atFit = fitted.track(
        const Offset(200, 300),
        paper: paper,
        kind: PointerDeviceKind.mouse,
      );
      final atZoom = zoomed.track(
        const Offset(400, 600),
        paper: paper,
        scale: 2,
        kind: PointerDeviceKind.mouse,
      );
      expect(atZoom.left, closeTo(atFit.left, 0.0001));
      expect(atZoom.top, closeTo(atFit.top, 0.0001));
      expect(atZoom.width, closeTo(atFit.width, 0.0001));
      expect(atZoom.height, closeTo(atFit.height, 0.0001));
    });

    test('touch lifts the preview and confirmation uses that outline', () {
      final mouse = DocuTrackerPlacementSession.free();
      final touch = DocuTrackerPlacementSession.free();
      const point = Offset(397, 560);
      final mouseRect = mouse.track(
        point,
        paper: paper,
        kind: PointerDeviceKind.mouse,
      );
      final touchRect = touch.track(
        point,
        paper: paper,
        kind: PointerDeviceKind.touch,
      );
      expect(touchRect.top, lessThan(mouseRect.top));
      expect(touchRect.left, closeTo(mouseRect.left, 0.0001));
      expect(touch.confirm(), touchRect);
      expect(docuTrackerPlacementCommit(touch, confirmed: true), touchRect);
    });

    test(
      'cancel persists nothing and tracking an anchored slot does not move it',
      () {
        final slot = DocuTrackerPlacementSession.anchored(
          DocuTrackerMemoLayout.preparedField,
        );
        slot.track(
          const Offset(10, 10),
          paper: paper,
          scale: 2,
          kind: PointerDeviceKind.touch,
        );
        expect(slot.confirm(), DocuTrackerMemoLayout.preparedField);
        expect(docuTrackerPlacementCommit(slot, confirmed: false), isNull);
        expect(docuTrackerPlacementCommit(null, confirmed: true), isNull);
      },
    );

    test(
      'a free memorandum signature stays off the letterhead and closing block',
      () {
        const probes = <Offset>[
          Offset(20, 20),
          Offset(397, 1000),
          Offset(700, 620),
          Offset(100, 280),
          Offset(794, 1123),
        ];
        for (final probe in probes) {
          final session = DocuTrackerPlacementSession.free(
            bounds: docuTrackerMemoFreePlacementBounds(),
          );
          final rect = session.track(
            probe,
            paper: paper,
            kind: PointerDeviceKind.stylus,
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(DocuTrackerMemoLayout.letterheadHeaderBottom),
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(DocuTrackerMemoLayout.closingTop),
          );
          expect(rect.overlaps(DocuTrackerMemoLayout.footerStrip), isFalse);
          for (final obstacle in DocuTrackerMemoLayout.closingObstacles) {
            expect(
              rect.overlaps(obstacle),
              isFalse,
              reason: '$probe overlaps $obstacle',
            );
          }
        }
      },
    );

    test('preview image keeps its aspect ratio inside the field', () {
      const field = Rect.fromLTWH(10, 20, 120, 40);
      final wide = docuTrackerContainSignatureBox(field, 4);
      expect(wide.width / wide.height, closeTo(4, 0.001));
      expect(wide.center.dx, closeTo(field.center.dx, 0.001));
      expect(wide.center.dy, closeTo(field.center.dy, 0.001));
      final tall = docuTrackerContainSignatureBox(field, 0.5);
      expect(tall.width / tall.height, closeTo(0.5, 0.001));
      expect(tall.height, closeTo(field.height, 0.001));
    });
  });

  group('placement bar', () {
    Future<void> pumpBar(WidgetTester tester, Size surface) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var confirmed = 0;
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocuTrackerSignaturePlacementBar(
              free: true,
              enabled: true,
              onConfirm: () => confirmed++,
              onCancel: () => cancelled++,
            ),
          ),
        ),
      );
      expect(find.text('Confirm placement'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('docutracker_signature_preview_cancel')),
      );
      await tester.pump();
      expect(cancelled, 1);
      expect(confirmed, 0);
      await tester.tap(
        find.byKey(const Key('docutracker_signature_preview_confirm')),
      );
      await tester.pump();
      expect(confirmed, 1);
    }

    testWidgets('desktop cancel does not confirm', (tester) async {
      await pumpBar(tester, const Size(1280, 800));
    });

    testWidgets('phone controls stay tappable', (tester) async {
      await pumpBar(tester, const Size(360, 740));
      expect(tester.takeException(), isNull);
      final cancel = tester.getSize(
        find.byKey(const Key('docutracker_signature_preview_cancel')),
      );
      expect(cancel.height, greaterThanOrEqualTo(44));
    });
  });

  testWidgets('drawing does not add a circular cursor', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _StubSignatureProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showDocuTrackerSignatureDialog(context, provider: provider),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('docutracker_signature_brush')), findsNothing);

    final pad = find.byKey(const Key('docutracker_signature_pad'));
    final start = tester.getTopLeft(pad) + const Offset(48, 48);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(70, 16));
    await tester.pump();
    expect(find.byKey(const Key('docutracker_signature_brush')), findsNothing);
    expect(find.text('Start here'), findsNothing);
    await gesture.up();
    await tester.pump();
  });
}
