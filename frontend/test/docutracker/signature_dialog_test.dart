import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';

class _StubSignatureProvider extends DocuTrackerProvider {
  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async =>
      const [];
}

Future<void> _openDialog(
  WidgetTester tester, {
  Size surface = const Size(1200, 900),
}) async {
  tester.view.physicalSize = surface;
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
}

Finder get _pad => find.byKey(const Key('docutracker_signature_pad'));

Future<void> _drawStroke(WidgetTester tester, {Offset? start}) async {
  final topLeft = tester.getTopLeft(_pad);
  final origin = start ?? topLeft + const Offset(40, 40);
  final gesture = await tester.startGesture(origin);
  await gesture.moveBy(const Offset(80, 20));
  await gesture.moveBy(const Offset(40, -10));
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('draw pad is larger on desktop and shows live preview', (
    tester,
  ) async {
    await _openDialog(tester, surface: const Size(1280, 900));

    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Your signature will appear here'), findsOneWidget);
    expect(
      find.byKey(const Key('docutracker_signature_preview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('docutracker_signature_undo')), findsOneWidget);
    expect(
      find.byKey(const Key('docutracker_signature_clear')),
      findsOneWidget,
    );

    final padBox = tester.getSize(_pad);
    expect(padBox.height, greaterThanOrEqualTo(300));
  });

  testWidgets('draw pad stays usable on a narrow phone', (tester) async {
    await _openDialog(tester, surface: const Size(360, 740));

    expect(find.text('Draw'), findsOneWidget);
    final padBox = tester.getSize(_pad);
    expect(padBox.height, greaterThanOrEqualTo(260));
    expect(padBox.height, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical strokes draw instead of scrolling the dialog', (
    tester,
  ) async {
    await _openDialog(tester, surface: const Size(360, 640));

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    final offsetBefore = scrollable.position.pixels;

    final gesture = await tester.startGesture(
      tester.getTopLeft(_pad) + const Offset(60, 10),
    );
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(scrollable.position.pixels, offsetBefore);
    final undo = find.byKey(const Key('docutracker_signature_undo'));
    expect(tester.widget<TextButton>(undo).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('strokes can start anywhere in the dialog body', (tester) async {
    await _openDialog(tester);
    final undo = find.byKey(const Key('docutracker_signature_undo'));
    expect(tester.widget<TextButton>(undo).onPressed, isNull);

    final gesture = await tester.startGesture(
      tester.getTopLeft(_pad) + const Offset(10, -20),
    );
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(15, 12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(tester.widget<TextButton>(undo).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, Offset Function(WidgetTester)>{
    'below the pad': (tester) =>
        tester.getBottomRight(_pad) + const Offset(-60, 20),
    'outside the dialog': (tester) =>
        tester.getTopLeft(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        ) +
        const Offset(-20, 200),
  }.entries) {
    testWidgets('strokes starting ${entry.key} still draw', (tester) async {
      await _openDialog(tester, surface: const Size(1400, 1400));
      final undo = find.byKey(const Key('docutracker_signature_undo'));
      expect(tester.widget<TextButton>(undo).onPressed, isNull);

      final gesture = await tester.startGesture(entry.value(tester));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(12, -15));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(tester.widget<TextButton>(undo).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cancel still closes the dialog in draw mode', (tester) async {
    await _openDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('mode switch above the pad still responds to taps', (
    tester,
  ) async {
    await _openDialog(tester);
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(_pad, findsNothing);
    expect(find.text('Choose PNG or JPEG (max 2 MB)'), findsOneWidget);
  });

  testWidgets('Undo Last Stroke and Clear update the drawing', (tester) async {
    await _openDialog(tester);

    final undo = find.byKey(const Key('docutracker_signature_undo'));
    final clear = find.byKey(const Key('docutracker_signature_clear'));
    expect(tester.widget<TextButton>(undo).onPressed, isNull);
    expect(tester.widget<TextButton>(clear).onPressed, isNull);

    await _drawStroke(tester);
    expect(tester.widget<TextButton>(undo).onPressed, isNotNull);
    expect(tester.widget<TextButton>(clear).onPressed, isNotNull);

    await _drawStroke(
      tester,
      start: tester.getTopLeft(_pad) + const Offset(60, 90),
    );
    await tester.tap(undo);
    await tester.pump();
    expect(tester.widget<TextButton>(undo).onPressed, isNotNull);

    await tester.tap(undo);
    await tester.pump();
    expect(tester.widget<TextButton>(undo).onPressed, isNull);
    expect(tester.widget<TextButton>(clear).onPressed, isNull);

    await _drawStroke(tester);
    await tester.tap(clear);
    await tester.pump();
    expect(tester.widget<TextButton>(undo).onPressed, isNull);
    expect(tester.widget<TextButton>(clear).onPressed, isNull);
  });

  testWidgets('Use signature exports drawn ink without error', (tester) async {
    DocuTrackerSignatureChoice? choice;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _StubSignatureProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              choice = await showDocuTrackerSignatureDialog(
                context,
                provider: provider,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _drawStroke(tester);

    await tester.tap(find.text('Use signature'));
    await tester.pump();
    // PNG encode uses dart:ui and needs the real async event loop.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.text('Insert E-Signature'), findsNothing);
    expect(choice, isNotNull);
    expect(choice!.imageBytes, isNotNull);
    expect(choice!.imageBytes, isNotEmpty);
    expect(choice!.sourceType, 'drawn');
    expect(choice!.mimeType, 'image/png');
    expect(tester.takeException(), isNull);
  });
}
