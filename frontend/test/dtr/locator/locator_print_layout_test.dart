import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final type = LocatorRequestType.locator.copyWith(
    label: 'Travel Order',
    employeeDetailSchema: const [
      LeaveCustomFieldDefinition(
        key: 'destination',
        label: 'Place of Destination',
      ),
    ],
  );
  test(
    'layout includes additional fields, preserves placement and rejects off-page boxes',
    () {
      final layout = LocatorPrintLayout.defaults(type);
      expect(
        layout.elements.any((e) => e.source == 'custom:destination'),
        true,
      );
      expect(
        LocatorPrintLayout.fromJson(layout.toJson()).toJson(),
        layout.toJson(),
      );
      expect(layout.validate(), null);
      expect(
        layout.elements
            .where((e) => e.kind == 'signature')
            .every((e) => e.label.isEmpty),
        isTrue,
      );
      final bad = layout.copyWith(
        elements: [layout.elements.first.copyWith(x: 1000)],
      );
      expect(bad.validate(), isNotNull);
    final many=type.copyWith(employeeDetailSchema:List.generate(20,(i)=>LeaveCustomFieldDefinition(key:'extra_$i',label:'Extra field $i')));
    for(final orientation in ['portrait','landscape']){
      expect(LocatorPrintLayout.defaults(many,orientation:orientation).validate(),null);
    }
    },
  );
  test(
    'custom layout puts short extra answers on the main page and spills long answers safely',
    () async {
      final layout = LocatorPrintLayout.defaults(type);
      Future<List<int>> render(String answer) => buildLocatorLayoutPdf(
        layout: layout,
        form: {
          'employee_name': 'Alice',
          'slip_date': '2026-10-13',
          'request_type_label': 'Travel Order',
          'office': 'HR',
          'reason': 'Travel',
          'additional_details': {'destination': answer},
          'employee_detail_schema_snapshot': type.employeeDetailSchema
              .map((e) => e.toJson())
              .toList(),
        },
        signatories: const LocatorFormSignatories(),
      );
      final short = await render('Municipal Hall');
      expect(
        RegExp(
          r'/Type\s*/Page\b',
        ).allMatches(String.fromCharCodes(short)).length,
        1,
      );
      final long = await render(List.filled(400, 'Long destination').join(' '));
      expect(
        RegExp(
          r'/Type\s*/Page\b',
        ).allMatches(String.fromCharCodes(long)).length,
        greaterThan(1),
      );
    },
  );
  test(
    'automatic signature captions use the actual position with role fallback and preserve custom labels',
    () {
      final layout = LocatorPrintLayout.defaults(type);
      for (final source in ['applicant', 'department_head', 'hr_approver']) {
        final item = layout.elements.firstWhere((e) => e.source == source);
        expect(
          locatorSignatureCaption(
            item,
            const LocatorPrintedSignatory(
              positionTitle: 'Administrative Officer',
            ),
          ),
          'Administrative Officer',
        );
        expect(
          locatorSignatureCaption(
            item.copyWith(label: 'Authorized signer'),
            const LocatorPrintedSignatory(
              positionTitle: 'Administrative Officer',
            ),
          ),
          'Authorized signer',
        );
      }
      final applicant = layout.elements.firstWhere(
        (e) => e.source == 'applicant',
      );
      expect(
        locatorSignatureCaption(applicant, const LocatorPrintedSignatory()),
        'Employee',
      );
      expect(
        locatorSignatureCaption(
          layout.elements.firstWhere((e) => e.source == 'department_head'),
          const LocatorPrintedSignatory(),
        ),
        'Head of Office',
      );
      expect(
        locatorSignatureCaption(
          layout.elements.firstWhere((e) => e.source == 'hr_approver'),
          const LocatorPrintedSignatory(positionTitle: 'Municipal Mayor'),
        ),
        'Municipal Mayor',
      );
    },
  );
  test('an unapproved workflow block never prints the final reviewer signature', () async {
    final png=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC');
    final bytes=await buildLocatorLayoutPdf(layout:LocatorPrintLayout(elements:const[
      LocatorPrintElement(id:'future',kind:'signature',source:'workflow_step_2',x:40,y:200,width:240,height:80),
    ]),form:const{},signatories:LocatorFormSignatories(finalApprover:LocatorPrintedSignatory(name:'Final Official',signatureBytes:png)));
    expect(RegExp(r'/Subtype\s*/Image').allMatches(latin1.decode(bytes)).length,0);
  });
  testWidgets(
    'dragging keeps controls and other elements stable until release',
    (t) async {
      t.view.physicalSize = const Size(1500, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      LocatorPrintLayout? result;
      LocatorPrintLayout? previewed;
      final layout = LocatorPrintLayout.defaults(type);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<LocatorPrintLayout>(
                    context: context,
                    builder: (_) => LocatorPrintLayoutEditor(
                      requestType: type,
                      initialLayout: layout,
                      onPreview: (value) async => previewed = value,
                    ),
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open editor'));
      await t.pumpAndSettle();
      final editorBody = find
          .descendant(
            of: find.byType(LocatorPrintLayoutEditor),
            matching: find.byType(Column),
          )
          .first;
      expect(t.getRect(editorBody), const Rect.fromLTWH(0, 0, 1500, 1200));
      final box = find.byKey(
        ValueKey('layout-element-${layout.elements.first.id}'),
      );
      final stationaryBox = find.byKey(
        ValueKey('layout-element-${layout.elements[1].id}'),
      );
      final leftInput = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Left (pt)',
      );
      final leftController = t.widget<TextField>(leftInput).controller!;
      final initialPosition = t.getTopLeft(box);
      final gesture = await t.startGesture(t.getCenter(box));
      await gesture.moveBy(const Offset(25, 30));
      await t.pump();
      // Selection can rebuild once. Subsequent movement must leave the sidebar
      // and stationary elements alone while the dragged element moves onscreen.
      final controlsBefore = t.widget(leftInput);
      final stationaryBefore = t.widget(stationaryBox);
      final stationaryPosition = t.getTopLeft(stationaryBox);
      var inputUpdates = 0;
      leftController.addListener(() => inputUpdates++);
      await gesture.moveBy(const Offset(25, 30));
      await t.pump();
      await gesture.moveBy(const Offset(25, 30));
      await t.pump();
      expect(t.getTopLeft(box).dx, greaterThan(initialPosition.dx));
      expect(t.getTopLeft(box).dy, greaterThan(initialPosition.dy));
      expect(t.getTopLeft(stationaryBox), stationaryPosition);
      expect(inputUpdates, 0);
      expect(identical(t.widget(leftInput), controlsBefore), isTrue);
      expect(identical(t.widget(stationaryBox), stationaryBefore), isTrue);
      await gesture.up();
      await t.pump();
      expect(
        double.parse(leftController.text),
        greaterThan(layout.elements.first.x),
      );
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(previewed, isNotNull);
      await t.tap(find.text('Use layout'));
      await t.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.elements.first.x, greaterThan(layout.elements.first.x));
      expect(result!.elements.first.y, greaterThan(layout.elements.first.y));
      expect(result!.toJson(), previewed!.toJson());
    },
  );
  for (final width in [900.0, 1500.0]) {
    testWidgets(
      'drag stays on the page and cancellation keeps its position at width $width',
      (t) async {
        t.view.physicalSize = Size(width, 1200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final layout = LocatorPrintLayout.defaults(type);
        LocatorPrintLayout? previewed;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LocatorPrintLayoutEditor(
                requestType: type,
                initialLayout: layout,
                onPreview: (value) async => previewed = value,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final box = find.byKey(
          ValueKey('layout-element-${layout.elements.first.id}'),
        );
        final page = find.byWidgetPredicate((w) => w is DragTarget<String>);
        final gesture = await t.startGesture(t.getCenter(box));
        await gesture.moveBy(const Offset(25, 30));
        await t.pump();
        await gesture.moveBy(const Offset(10000, 10000));
        await t.pump();
        final pageBounds = t.getRect(page);
        expect(t.getRect(box).right, closeTo(pageBounds.right, .001));
        expect(t.getRect(box).bottom, closeTo(pageBounds.bottom, .001));
        await gesture.cancel();
        await t.pump();
        final leftInput = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Left (pt)',
        );
        expect(
          t.widget<TextField>(leftInput).controller!.text,
          (layout.pageWidth - layout.elements.first.width).toStringAsFixed(1),
        );
        await t.tap(find.text('Preview layout'));
        await t.pumpAndSettle();
        expect(
          previewed!.elements.first.x,
          closeTo(layout.pageWidth - layout.elements.first.width, .1),
        );
        expect(
          previewed!.elements.first.y,
          closeTo(layout.pageHeight - layout.elements.first.height, .1),
        );

        // Editing coordinates after a drag must reposition the element and become
        // the starting point for the next drag, rather than a stale cached offset.
        await t.enterText(leftInput, '5');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pump();
        final scale = pageBounds.width / layout.pageWidth;
        expect(t.getRect(box).left, closeTo(pageBounds.left + 5 * scale, .001));
        final nextGesture = await t.startGesture(t.getCenter(box));
        await nextGesture.moveBy(const Offset(-25, -30));
        await t.pump();
        await nextGesture.moveBy(const Offset(-10000, -10000));
        await t.pump();
        expect(t.getRect(box).left, closeTo(pageBounds.left, .001));
        expect(t.getRect(box).top, closeTo(pageBounds.top, .001));
        await nextGesture.up();
        await t.pump();
        await t.tap(find.text('Preview layout'));
        await t.pumpAndSettle();
        expect(previewed!.elements.first.x, 0);
        expect(previewed!.elements.first.y, 0);
      },
    );
  }
  testWidgets(
    'signature captions can use actual position or preserve a custom label',
    (t) async {
      t.view.physicalSize = const Size(1500, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final defaults = LocatorPrintLayout.defaults(type);
      final applicant = defaults.elements.firstWhere(
        (e) => e.source == 'applicant',
      );
      final layout = defaults.copyWith(
        elements: [
          for (final item in defaults.elements)
            item.id == applicant.id ? item.copyWith(label: 'Employee') : item,
        ],
      );
      LocatorPrintLayout? previewed;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocatorPrintLayoutEditor(
              requestType: type,
              initialLayout: layout,
              onPreview: (value) async => previewed = value,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('layout-element-${applicant.id}')));
      await t.pumpAndSettle();
      expect(find.text('Custom label'), findsOneWidget);
      final captionMenu = find
          .ancestor(
            of: find.text('Custom label'),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .first;
      await t.tap(captionMenu);
      await t.pumpAndSettle();
      await t.tap(find.text("Signer's position").last);
      await t.pumpAndSettle();
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(
        previewed!.elements.firstWhere((e) => e.source == 'applicant').label,
        '',
      );
      await t.tap(
        find
            .ancestor(
              of: find.text("Signer's position"),
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Custom label').last);
      await t.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Label',
      );
      await t.enterText(input, '');
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(
        find.text("Enter a custom label or choose Signer's position."),
        findsOneWidget,
      );
      await t.enterText(input, 'Authorized employee');
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(
        previewed!.elements.firstWhere((e) => e.source == 'applicant').label,
        'Authorized employee',
      );
    },
  );
  testWidgets('editor fills a narrow screen and can be closed', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<LocatorPrintLayout>(
                context: context,
                builder: (_) => LocatorPrintLayoutEditor(
                  requestType: type,
                  onPreview: (_) async {},
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open editor'));
    await t.pumpAndSettle();
    final editorBody = find
        .descendant(
          of: find.byType(LocatorPrintLayoutEditor),
          matching: find.byType(Column),
        )
        .first;
    expect(t.getRect(editorBody), const Rect.fromLTWH(0, 0, 390, 844));
    expect(find.byKey(const ValueKey('layout-workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-inspector')), findsNothing);
    await t.tap(find.byTooltip('Page and element settings'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-inspector')), findsOneWidget);
    expect(find.text('Element properties'), findsOneWidget);
    await t.tap(find.byTooltip('Page and element settings'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-workspace')), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.byType(LocatorPrintLayoutEditor), findsNothing);
  });
  testWidgets(
    'print workspace has a right inspector and nonprinting zoom and grid controls',
    (t) async {
      t.view.physicalSize = const Size(1500, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      LocatorPrintLayout? previewed;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocatorPrintLayoutEditor(
              requestType: type,
              onPreview: (value) async => previewed = value,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final workspace = find.byKey(const ValueKey('layout-workspace'));
      final inspector = find.byKey(const ValueKey('layout-inspector'));
      final page = find.byWidgetPredicate((w) => w is DragTarget<String>);
      final workspaceBounds = t.getRect(workspace);
      final fittedPage = t.getRect(page);
      expect(
        t.getRect(inspector).left,
        greaterThanOrEqualTo(workspaceBounds.right),
      );
      expect(workspaceBounds.contains(fittedPage.topLeft), isTrue);
      expect(workspaceBounds.contains(fittedPage.bottomRight), isTrue);
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      final original = previewed!.toJson();
      await t.tap(find.byKey(const ValueKey('layout-zoom')));
      await t.pumpAndSettle();
      await t.tap(find.text('100%').last);
      await t.pumpAndSettle();
      // Keep zoom as a number: whole doubles stringify differently on the web
      // ("1") and the native runtime ("1.0"). Labels must not be selection keys.
      expect(
        t
            .widget<DropdownButton<dynamic>>(
              find.byKey(const ValueKey('layout-zoom')),
            )
            .value,
        1.0,
      );
      expect(t.getRect(page).width, greaterThan(fittedPage.width));
      await t.tap(find.byTooltip('Show grid'));
      await t.pump();
      expect(find.byKey(const ValueKey('layout-grid')), findsOneWidget);
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(previewed!.toJson(), original);
      await t.tap(find.byTooltip('Fit page'));
      await t.pumpAndSettle();
      expect(t.getRect(page).width, closeTo(fittedPage.width, .1));
      for (final (label, scale) in [
        ('50%', .5),
        ('75%', .75),
        ('100%', 1.0),
        ('125%', 1.25),
        ('150%', 1.5),
      ]) {
        await t.tap(find.byKey(const ValueKey('layout-zoom')));
        await t.pumpAndSettle();
        await t.tap(find.text(label).last);
        await t.pumpAndSettle();
        expect(
          t.getRect(page).width,
          closeTo(previewed!.pageWidth * scale, .1),
        );
        expect(t.takeException(), isNull);
      }
      await t.tap(find.byTooltip('Fit page'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Insert field'));
      await t.pumpAndSettle();
      await t.tap(find.text('Place of Destination').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Preview layout'));
      await t.pumpAndSettle();
      expect(previewed!.elements.last.source, 'custom:destination');
      expect(
        previewed!.elements.length,
        (original['elements'] as List).length + 1,
      );
    },
  );
}
