import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'designer_field_test_helpers.dart';

const initial = LocatorPrintLayout(
  elements: [
    LocatorPrintElement(
      id: 'title',
      kind: 'text',
      text: 'Original title',
      x: 60,
      y: 100,
      width: 220,
      height: 50,
    ),
  ],
);

void main() {
  Future<void> mount(
    WidgetTester t, {
    ValueChanged<LocatorPrintLayout>? preview,
    ValueChanged<List<LeaveCustomFieldDefinition>>? fieldsChanged,
    ValueChanged<List<LeaveCustomFieldDefinition>>? previewFields,
    LocatorPrintLayout layout = initial,
  }) async {
    t.view.physicalSize = const Size(1500, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocatorPrintLayoutEditor(
            requestType: LocatorRequestType.locator,
            initialLayout: layout,
            onPreview: (layout) async => preview?.call(layout),
            onCustomFieldsChanged: fieldsChanged,
            onPreviewWithFields: previewFields == null
                ? null
                : (_, fields) async => previewFields(fields),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> shortcut(
    WidgetTester t,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(key);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
  }

  final title = find.byKey(const ValueKey('layout-element-title'));
  Future<void> wheel(WidgetTester t, Offset position, double delta) async {
    t.binding.handlePointerEvent(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: position,
        scrollDelta: Offset(0, delta),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'zoom preserves inspector and canvas content widgets with pending property edits',
    (t) async {
      LocatorPrintLayout? preview;
      await mount(t, preview: (v) => preview = v);
      final widthInput = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Width (pt)',
      );
      await t.enterText(widthInput, '260');
      final inspector = find.byKey(const ValueKey('layout-inspector'));
      final panelBefore = t.widget(inspector);
      final inputBefore = t.widget<TextField>(widthInput);
      final content = find
          .descendant(of: title, matching: find.byType(Text))
          .first;
      final contentBefore = t.widget(content);
      final boxBefore = t.widget(title);
      await wheel(t, t.getCenter(title), -100);
      expect(identical(t.widget(inspector), panelBefore), isTrue);
      expect(identical(t.widget(widthInput), inputBefore), isTrue);
      expect(identical(t.widget(content), contentBefore), isTrue);
      expect(identical(t.widget(title), boxBefore), isTrue);
      expect(inputBefore.controller!.text, '260');
      t
          .widget<Slider>(find.byKey(const ValueKey('layout-zoom-slider')))
          .onChanged!(1.25);
      await t.pumpAndSettle();
      expect(identical(t.widget(inspector), panelBefore), isTrue);
      expect(identical(t.widget(content), contentBefore), isTrue);
      expect(t.getRect(title).width, closeTo(220 * 1.25, .001));
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(preview!.elements.single.width, 260);
    },
  );
  testWidgets(
    'wheel bursts reuse page content and preserve the cursor anchor after one frame',
    (t) async {
      await mount(t);
      t
          .widget<Slider>(find.byKey(const ValueKey('layout-zoom-slider')))
          .onChanged!(1.5);
      await t.pumpAndSettle();
      final page = find.byWidgetPredicate((w) => w is DragTarget<String>);
      final pointer = t.getCenter(title);
      final anchorY = (pointer.dy - t.getRect(page).top) / 1.5;
      final content = t.widget(title);
      for (var i = 0; i < 8; i++) {
        t.binding.handlePointerEvent(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: pointer,
            scrollDelta: const Offset(0, -25),
          ),
        );
      }
      await t.pumpAndSettle();
      final renderedScale = t.getRect(page).width / initial.pageWidth;
      expect(renderedScale, closeTo(1.815, .0001));
      expect(
        t.getRect(page).top + anchorY * renderedScale,
        closeTo(pointer.dy, .01),
      );
      expect(identical(t.widget(title), content), isTrue);
    },
  );
  testWidgets(
    'mouse wheel over canvas zooms both ways without editing or scrolling the page',
    (t) async {
      LocatorPrintLayout? preview;
      await mount(t, preview: (v) => preview = v);
      final before = t.getRect(title).size.width;
      await wheel(t, t.getCenter(title), -100);
      expect(t.getRect(title).size.width, greaterThan(before));
      expect(t.takeException(), isNull);
      await wheel(t, t.getCenter(title), 100);
      expect(t.getRect(title).size.width, closeTo(before, .001));
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Undo (Ctrl+Z)',
              ),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(preview!.toJson(), initial.toJson());
    },
  );
  testWidgets(
    'wheel zoom is bounded, anchored vertically at the pointer, and inspector still scrolls',
    (t) async {
      await mount(t);
      t
          .widget<Slider>(find.byKey(const ValueKey('layout-zoom-slider')))
          .onChanged!(1.5);
      await t.pumpAndSettle();
      final page = find.byWidgetPredicate((w) => w is DragTarget<String>);
      final before = t.getRect(page);
      final point = t.getCenter(title);
      final pageY = (point.dy - before.top) / 1.5;
      await wheel(t, point, -100);
      final after = t.getRect(page);
      expect(
        after.top + pageY * after.width / initial.pageWidth,
        closeTo(point.dy, .01),
      );
      await wheel(t, t.getCenter(title), -10000);
      expect(t.getRect(title).size.width, closeTo(440, .001));
      await wheel(t, t.getCenter(title), 10000);
      expect(t.getRect(title).size.width, closeTo(55, .001));
      final inspector = find.byKey(const ValueKey('layout-inspector'));
      final scrollable = find
          .descendant(of: inspector, matching: find.byType(Scrollable))
          .first;
      final state = t.state<ScrollableState>(scrollable);
      final offset = state.position.pixels;
      await wheel(t, t.getCenter(inspector), 180);
      expect(state.position.pixels, greaterThan(offset));
      expect(t.getRect(title).size.width, closeTo(55, .001));
    },
  );

  testWidgets(
    'keyboard undo redo and delete restore selection and clear redo on new edits',
    (t) async {
      await mount(t);
      await t.tap(find.widgetWithText(OutlinedButton, 'Text'));
      await t.pumpAndSettle();
      expect(find.text('2 elements'), findsOneWidget);
      await shortcut(t, LogicalKeyboardKey.keyZ);
      expect(find.text('1 elements'), findsOneWidget);
      await shortcut(t, LogicalKeyboardKey.keyZ, shift: true);
      expect(find.text('2 elements'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pumpAndSettle();
      expect(find.text('1 elements'), findsOneWidget);
      await shortcut(t, LogicalKeyboardKey.keyZ);
      expect(find.text('2 elements'), findsOneWidget);
      await shortcut(t, LogicalKeyboardKey.keyY);
      expect(find.text('1 elements'), findsOneWidget);
      await shortcut(t, LogicalKeyboardKey.keyZ);
      await t.tap(find.widgetWithText(OutlinedButton, 'Line'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Redo (Ctrl+Y / Ctrl+Shift+Z)',
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'text editing keeps native shortcuts and groups changes for canvas undo',
    (t) async {
      LocatorPrintLayout? preview;
      await mount(t, preview: (v) => preview = v);
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Text',
      );
      await t.enterText(input, 'Changed');
      await t.enterText(input, 'Changed title');
      await shortcut(t, LogicalKeyboardKey.keyZ);
      expect(title, findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pumpAndSettle();
      expect(title, findsOneWidget);
      await t.tap(title);
      await shortcut(t, LogicalKeyboardKey.keyZ);
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(preview!.elements.single.text, 'Original title');
    },
  );

  testWidgets('a complete drag is one undo step', (t) async {
    await mount(t);
    final before = t.getRect(title);
    final g = await t.startGesture(t.getCenter(title));
    await g.moveBy(const Offset(30, 20));
    await t.pump();
    await g.moveBy(const Offset(30, 20));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(t.getRect(title).left, greaterThan(before.left));
    await shortcut(t, LogicalKeyboardKey.keyZ);
    expect(t.getRect(title), before);
  });

  testWidgets(
    'zoom slider supports intermediate zoom without dropdown assertion or changing saved geometry',
    (t) async {
      LocatorPrintLayout? preview;
      await mount(t, preview: (v) => preview = v);
      final slider = t.widget<Slider>(
        find.byKey(const ValueKey('layout-zoom-slider')),
      );
      slider.onChanged!(1.1);
      await t.pumpAndSettle();
      expect(t.getRect(title).size.width, closeTo(220 * 1.1, .001));
      expect(t.takeException(), isNull);
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(preview!.toJson(), initial.toJson());
      slider.onChanged!(.5);
      await t.pumpAndSettle();
      expect(t.getRect(title).size.width, closeTo(110, .001));
    },
  );

  testWidgets(
    'resize handles change box area within margins, synchronize controls and undo once',
    (t) async {
      LocatorPrintLayout? preview;
      await mount(t, preview: (v) => preview = v);
      final original = t.getRect(title).size;
      final g = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('layout-resize-title-se'))),
      );
      await g.moveBy(const Offset(40, 30));
      await t.pump();
      expect(t.getRect(title).size.width, greaterThan(original.width));
      await g.moveBy(const Offset(10000, 10000));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(
        preview!.elements.single.width,
        closeTo(initial.pageWidth - 60, .001),
      );
      expect(
        preview!.elements.single.height,
        closeTo(initial.pageHeight - 100, .001),
      );
      expect(preview!.validate(), isNull);
      await t.tap(find.byKey(const ValueKey('layout-element-title')));
      await shortcut(t, LogicalKeyboardKey.keyZ);
      expect(t.getRect(title).size, original);
    },
  );
  testWidgets(
    'creating a field is one undo step for both schema and page placement',
    (t) async {
      List<LeaveCustomFieldDefinition>? previewFields;
      await mount(
        t,
        fieldsChanged: (_) {},
        previewFields: (fields) => previewFields = fields,
      );
      await createDesignerField(t, 'Arrival date');
      expect(find.text('2 elements'), findsOneWidget);
      await shortcut(t, LogicalKeyboardKey.keyZ);
      expect(find.text('1 elements'), findsOneWidget);
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(previewFields, isEmpty);
      await shortcut(t, LogicalKeyboardKey.keyY);
      expect(find.text('2 elements'), findsOneWidget);
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(previewFields!.single.label, 'Arrival date');
    },
  );
  testWidgets(
    'resizing from the top left honors minimum size and cancellation leaves no history entry',
    (t) async {
      LocatorPrintLayout? preview;
      await mount(
        t,
        preview: (v) => preview = v,
        layout: initial.copyWith(
          margins: const PrintLayoutMargins(
            top: 24,
            right: 24,
            bottom: 24,
            left: 24,
          ),
        ),
      );
      var handle = find.byKey(const ValueKey('layout-resize-title-nw'));
      final g = await t.startGesture(t.getCenter(handle));
      await g.moveBy(const Offset(10000, 10000));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(preview!.elements.single.width, 20);
      expect(preview!.elements.single.height, 12);
      expect(preview!.elements.single.x, 260);
      expect(preview!.elements.single.y, 138);
      await shortcut(t, LogicalKeyboardKey.keyZ);
      final before = t.getRect(title);
      handle = find.byKey(const ValueKey('layout-resize-title-nw'));
      final cancelled = await t.startGesture(t.getCenter(handle));
      await cancelled.moveBy(const Offset(-10000, -10000));
      await t.pump();
      await cancelled.cancel();
      await t.pumpAndSettle();
      expect(t.getRect(title), before);
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Undo (Ctrl+Z)',
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
