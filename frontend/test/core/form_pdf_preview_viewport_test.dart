import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview_viewport.dart';

final _image = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  ),
);

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  int count = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FormPdfPreviewViewport(
          pages: List.generate(
            count,
            (_) => PdfPreviewPageData(image: _image, width: 1200, height: 1600),
          ),
          rasterDpi: 144,
        ),
      ),
    ),
  );
  await tester.pump();
}

TransformationController _controller(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

void _wheel(WidgetTester tester, Offset position, Offset delta) {
  tester.binding.handlePointerEvent(
    PointerScrollEvent(position: position, scrollDelta: delta),
  );
}

void main() {
  testWidgets('zoom buttons and fit controls change the view within limits', (
    tester,
  ) async {
    await _open(tester);
    final controller = _controller(tester);
    final widthScale = controller.value.getMaxScaleOnAxis();
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.text('${(widthScale * 100).round()}%'), findsOneWidget);
    await tester.tap(find.text('Fit page'));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), lessThan(widthScale));
    await tester.tap(find.text('Fit width'));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(widthScale, .001));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(widthScale));
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    expect(controller.value.getMaxScaleOnAxis(), 4);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_rounded),
          )
          .onPressed,
      isNull,
    );
    for (var i = 0; i < 50; i++) {
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
    }
    expect(controller.value.getMaxScaleOnAxis(), .1);
  });

  testWidgets(
    'wheel scrolls multiple pages; Ctrl wheel zooms around the pointer',
    (tester) async {
      await _open(tester, count: 2);
      final controller = _controller(tester);
      final position = tester.getCenter(
        find.byKey(const ValueKey('pdf-preview-viewport')),
      );
      final scale = controller.value.getMaxScaleOnAxis();
      _wheel(tester, position, const Offset(0, 160));
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), scale);
      expect(controller.value.getTranslation().y, lessThan(-100));
      final box = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('pdf-preview-viewport')),
      );
      final local = box.globalToLocal(position);
      final before = controller.toScene(local);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      _wheel(tester, position, const Offset(0, -80));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(scale));
      expect((controller.toScene(local) - before).distance, lessThan(.01));
      final zoom = controller.value.getMaxScaleOnAxis();
      _wheel(tester, position, const Offset(0, 100000));
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), zoom);
      final scene = tester.getSize(
        find.byKey(const ValueKey('pdf-preview-pages')),
      );
      expect(
        controller.value.getTranslation().y,
        closeTo(box.size.height - scene.height * zoom, .01),
      );
    },
  );

  testWidgets('fit width follows viewport resizing and toolbar fits mobile', (
    tester,
  ) async {
    await _open(tester);
    final controller = _controller(tester);
    final oldScale = controller.value.getMaxScaleOnAxis();
    await tester.binding.setSurfaceSize(const Size(320, 600));
    await tester.pump();
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), lessThan(oldScale));
    expect(find.text('Fit width'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'trackpad scroll pans once and wheel signals are claimed for the app',
    (tester) async {
      await _open(tester, count: 2);
      final controller = _controller(tester);
      final position = tester.getCenter(
        find.byKey(const ValueKey('pdf-preview-viewport')),
      );
      final scale = controller.value.getMaxScaleOnAxis();
      var platformDefaultAllowed = false;
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          kind: PointerDeviceKind.trackpad,
          position: position,
          scrollDelta: const Offset(0, 100),
          onRespond: ({required bool allowPlatformDefault}) {
            platformDefaultAllowed = allowPlatformDefault;
          },
        ),
      );
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), scale);
      expect(controller.value.getTranslation().y, closeTo(-100, .01));
      expect(platformDefaultAllowed, isFalse);
    },
  );

  testWidgets('touch pinch zooms the document', (tester) async {
    await _open(tester, size: const Size(390, 700));
    final controller = _controller(tester);
    final scale = controller.value.getMaxScaleOnAxis();
    final center = tester.getCenter(
      find.byKey(const ValueKey('pdf-preview-viewport')),
    );
    final first = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(scale));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });
}
