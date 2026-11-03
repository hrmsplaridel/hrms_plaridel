import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';

void main() {
  const first = LocatorPrintElement(
    id: 'first',
    kind: 'text',
    text: 'First',
    x: 40,
    y: 70,
    width: 120,
    height: 30,
  );
  const second = LocatorPrintElement(
    id: 'second',
    kind: 'text',
    text: 'Second',
    x: 240,
    y: 130,
    width: 100,
    height: 30,
  );
  const initial = LocatorPrintLayout(elements: [first, second]);
  LocatorPrintLayout? saved;
  Future<void> mount(
    WidgetTester t, {
    LocatorPrintLayout layout = initial,
  }) async {
    saved = null;
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
            onPreview: (v) async => saved = v,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> preview(WidgetTester t) async {
    await t.tap(find.text('Preview layout'));
    await t.pumpAndSettle();
  }

  Future<void> multi(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.byKey(const ValueKey('layout-element-second')));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.text('2 elements selected'), findsOneWidget);
  }

  Future<void> arrange(WidgetTester t, String value) async {
    await t.tap(find.byKey(const ValueKey('layout-arrange')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('layout-arrange-$value')));
    await t.pumpAndSettle();
  }

  Offset pagePoint(WidgetTester t, Offset point) {
    final page = t.getRect(
      find.byWidgetPredicate((w) => w is DragTarget<String>),
    );
    return page.topLeft + point * (page.width / initial.pageWidth);
  }

  Future<TestGesture> selectBox(
    WidgetTester t,
    Offset start,
    Offset end,
  ) async {
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(pagePoint(t, start));
    await mouse.moveTo(pagePoint(t, end));
    await t.pump();
    return mouse;
  }

  testWidgets(
    'mouse box selection selects enclosed elements without editing the layout',
    (t) async {
      await mount(t);
      final mouse = await selectBox(
        t,
        const Offset(20, 50),
        const Offset(360, 180),
      );
      expect(
        find.byKey(const ValueKey('layout-selection-box')),
        findsOneWidget,
      );
      await mouse.up();
      await t.pumpAndSettle();
      expect(find.text('2 elements selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('layout-selection-box')), findsNothing);
      await preview(t);
      expect(saved!.toJson(), initial.toJson());
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'reverse box selection works when zoomed and Ctrl-click can remove a member',
    (t) async {
      await mount(t);
      t
          .widget<Slider>(find.byKey(const ValueKey('layout-zoom-slider')))
          .onChanged!(1.25);
      await t.pumpAndSettle();
      final mouse = await selectBox(
        t,
        const Offset(360, 180),
        const Offset(20, 50),
      );
      await mouse.up();
      await t.pumpAndSettle();
      expect(find.text('2 elements selected'), findsOneWidget);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.tap(find.byKey(const ValueKey('layout-element-second')));
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(find.text('2 elements selected'), findsNothing);
      await preview(t);
      expect(saved!.toJson(), initial.toJson());
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Shift adds box selection and Escape cancels it without changing selection',
    (t) async {
      const third = LocatorPrintElement(
        id: 'third',
        kind: 'text',
        text: 'Third',
        x: 70,
        y: 250,
        width: 100,
        height: 30,
      );
      await mount(
        t,
        layout: const LocatorPrintLayout(elements: [first, second, third]),
      );
      await t.tap(find.byKey(const ValueKey('layout-element-third')));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final mouse = await selectBox(
        t,
        const Offset(20, 50),
        const Offset(360, 180),
      );
      await mouse.up();
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pumpAndSettle();
      expect(find.text('3 elements selected'), findsOneWidget);
      final cancelled = await selectBox(
        t,
        const Offset(400, 300),
        const Offset(460, 360),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await cancelled.up();
      await t.pumpAndSettle();
      expect(find.text('3 elements selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('layout-selection-box')), findsNothing);
      final empty = await selectBox(
        t,
        const Offset(400, 300),
        const Offset(460, 360),
      );
      await empty.up();
      await t.pumpAndSettle();
      expect(
        find.text('Select an element on the page to edit it.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('rectangle and appearance settings survive preview and reopen', (
    t,
  ) async {
    await mount(t);
    await t.tap(find.byKey(const ValueKey('layout-add-rectangle')));
    await t.pumpAndSettle();
    await preview(t);
    final box = saved!.elements.last;
    expect(box.kind, 'rectangle');
    expect(box.decoration.borderSides.length, 4);
    final appearance = find.byKey(const ValueKey('layout-appearance'));
    await t.ensureVisible(appearance);
    await t.pumpAndSettle();
    final fill = find.byKey(const ValueKey('layout-fill-color'));
    await t.ensureVisible(fill);
    await t.enterText(fill, '#EEEEEE');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    final stroke = find.byKey(const ValueKey('layout-border-color'));
    await t.ensureVisible(stroke);
    await t.enterText(stroke, '#FF0000');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    final width = find.byKey(const ValueKey('layout-border-width'));
    await t.ensureVisible(width);
    await t.enterText(width, '2.5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    final style = find.byKey(ValueKey('layout-border-style-${box.id}-solid'));
    t.widget<DropdownButtonFormField<String>>(style).onChanged!('dashed');
    await t.pumpAndSettle();
    final none = find.text('No borders');
    await t.ensureVisible(none);
    await t.tap(none);
    await t.pumpAndSettle();
    final top = find.widgetWithText(FilterChip, 'Top');
    await t.ensureVisible(top);
    await t.tap(top);
    await t.pumpAndSettle();
    await preview(t);
    expect(saved!.elements.last.decoration.fillColor, '#EEEEEE');
    expect(saved!.elements.last.decoration.borderColor, '#FF0000');
    expect(saved!.elements.last.decoration.borderWidth, 2.5);
    expect(saved!.elements.last.decoration.borderStyle, 'dashed');
    expect(saved!.elements.last.decoration.borderSides, ['top']);
    final reopened = LocatorPrintLayout.fromJson(saved!.toJson());
    await mount(t, layout: reopened);
    await preview(t);
    expect(saved!.elements.last.decoration.fillColor, '#EEEEEE');
    expect(t.takeException(), isNull);
  });
  testWidgets('box selection expands groups and respects their locked state', (t) async {
    final layout=initial.copyWith(elements:[first.copyWith(groupId:'group_1',locked:true),second.copyWith(groupId:'group_1')]);
    await mount(t,layout:layout);
    final mouse=await selectBox(t,const Offset(20,50),const Offset(180,110));
    await mouse.up();await t.pumpAndSettle();
    expect(find.text('2 elements selected'),findsOneWidget);
    await t.drag(find.byKey(const ValueKey('layout-element-first')),const Offset(50,30));await t.pumpAndSettle();
    await preview(t);expect(saved!.toJson(),layout.toJson());expect(t.takeException(),isNull);
  });
  testWidgets('touch scrolling does not create a mouse selection box', (t) async {
    await mount(t);
    await t.dragFrom(pagePoint(t,const Offset(420,220)),const Offset(0,-40));await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-selection-box')),findsNothing);
    expect(find.text('2 elements selected'),findsNothing);
    await preview(t);expect(saved!.toJson(),initial.toJson());expect(t.takeException(),isNull);
  });
  testWidgets('multi selection supports align, group drag, ungroup and undo', (
    t,
  ) async {
    await mount(t);
    await multi(t);
    await arrange(t, 'left');
    await preview(t);
    expect(saved!.elements[1].x, 40);
    await arrange(t, 'group');
    await preview(t);
    expect(saved!.elements.first.groupId, isNotNull);
    expect(saved!.elements.last.groupId, saved!.elements.first.groupId);
    await t.drag(
      find.byKey(const ValueKey('layout-element-first')),
      const Offset(35, 25),
    );
    await t.pumpAndSettle();
    await preview(t);
    expect(saved!.elements[1].y - saved!.elements[0].y, 60);
    expect(saved!.elements.first.x, greaterThan(40));
    await arrange(t, 'ungroup');
    await preview(t);
    expect(saved!.elements.every((e) => e.groupId == null), isTrue);
    await t.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await t.pumpAndSettle();
    await preview(t);
    expect(saved!.elements.first.groupId, isNotNull);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'locking blocks dragging and deleting; layers can still select and unlock',
    (t) async {
      await mount(t);
      await arrange(t, 'lock');
      await t.drag(
        find.byKey(const ValueKey('layout-element-first')),
        const Offset(70, 50),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await preview(t);
      expect(saved!.elements.length, 2);
      expect(saved!.elements.first.x, 40);
      expect(saved!.elements.first.locked, isTrue);
      await arrange(t, 'unlock');
      await preview(t);
      expect(saved!.elements.first.locked, isFalse);
      await arrange(t, 'front');
      await preview(t);
      expect(saved!.elements.last.id, 'first');
      expect(find.byKey(const ValueKey('layout-layers')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('mobile layers allow multi-selection without a keyboard', (
    t,
  ) async {
    await mount(t);
    t.view.physicalSize = const Size(390, 900);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Page and element settings'));
    await t.pumpAndSettle();
    final layer = find.byKey(const ValueKey('layout-layer-select-second'));
    await t.ensureVisible(layer);
    await t.pumpAndSettle();
    await t.tap(layer);
    await t.pumpAndSettle();
    expect(find.text('2 elements selected'), findsOneWidget);
    await arrange(t, 'group');
    await preview(t);
    expect(saved!.elements.first.groupId, isNotNull);
    expect(saved!.elements.last.groupId, saved!.elements.first.groupId);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'invalid pending border settings prevent preview until corrected',
    (t) async {
      await mount(t);
      final fill = find.byKey(const ValueKey('layout-fill-color'));
      await t.ensureVisible(fill);
      await t.enterText(fill, '#bad');
      await preview(t);
      expect(saved, isNull);
      expect(
        find.text('Use a six-digit color such as #000000.'),
        findsOneWidget,
      );
      await t.ensureVisible(fill);
      await t.enterText(fill, '#FFFFFF');
      await preview(t);
      expect(saved!.elements.first.decoration.fillColor, '#FFFFFF');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('thicker lines keep their center and expand their saved bounds', (
    t,
  ) async {
    await mount(
      t,
      layout: const LocatorPrintLayout(
        elements: [
          LocatorPrintElement(
            id: 'line',
            kind: 'line',
            x: 40,
            y: 70,
            width: 200,
            height: 2,
          ),
        ],
      ),
    );
    final width = find.byKey(const ValueKey('layout-border-width'));
    await t.ensureVisible(width);
    await t.enterText(width, '12');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await preview(t);
    expect(saved!.elements.single.height, 12);
    expect(saved!.elements.single.y + saved!.elements.single.height / 2, 71);
    expect(saved!.validate(), isNull);
    expect(t.takeException(), isNull);
  });
}
