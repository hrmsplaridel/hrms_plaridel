import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';

Map<String, dynamic> pageJson(String paper) => {
  'version': 1,
  'orientation': 'portrait',
  'paper_size': paper,
  'margins': {'top': 36, 'right': 36, 'bottom': 36, 'left': 36},
  'font_family': 'serif',
  'default_font_size': 14,
  'elements': [
    {
      'id': 'title',
      'kind': 'text',
      'text': 'TRAVEL ORDER',
      'x': 40,
      'y': 40,
      'width': 400,
      'height': 90,
      'font_size': 48,
      'font_family': 'mono',
    },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('page size, margins and typography survive serialization', () {
    final layout = LocatorPrintLayout.fromJson(pageJson('long'));
    expect(layout.pageHeight, 936);
    expect(layout.validate(), isNull);
    final json = layout.toJson();
    expect(json['paper_size'], 'long');
    expect(json['margins']['left'], 36);
    expect(json['font_family'], 'serif');
    expect(json['elements'][0]['font_family'], 'mono');
  });
  test(
    'custom PDFs use the selected paper and embedded offline fonts',
    () async {
      for (final paper in ['letter', 'long', 'legal']) {
        final bytes = await buildLocatorLayoutPdf(
          layout: LocatorPrintLayout.fromJson(pageJson(paper)),
          form: {},
          signatories: const LocatorFormSignatories(),
        );
        final content = latin1.decode(bytes);
        expect(
          content,
          contains(
            '/MediaBox[0 0 612 ${switch (paper) {
              'long' => 936,
              'legal' => 1008,
              _ => 792,
            }}]',
          ),
        );
        expect(content, contains('NotoSansMono'));
      }
    },
  );
  test(
    'paper changes keep elements within margins and reject unusable settings',
    () {
      final initial = LocatorPrintLayout.fromJson(pageJson('legal'));
      final adjusted = initial.withPageSettings(
        paperSize: 'a4',
        orientation: 'landscape',
        margins: const PrintLayoutMargins(
          top: 55,
          left: 90,
          right: 30,
          bottom: 20,
        ),
      );
      expect(adjusted.validate(), isNull);
      expect(adjusted.elements.single.x, greaterThanOrEqualTo(90));
      expect(adjusted.elements.single.y, greaterThanOrEqualTo(55));
      expect(
        adjusted.elements.single.x + adjusted.elements.single.width,
        lessThanOrEqualTo(adjusted.pageWidth - 30),
      );
      expect(
        initial
            .copyWith(margins: const PrintLayoutMargins(left: 600))
            .validate(),
        isNotNull,
      );
      expect(initial.copyWith(defaultFontSize: 73).validate(), isNotNull);
      expect(initial.copyWith(fontFamily: 'unknown').validate(), isNotNull);
    },
  );
  test(
    'signature fonts and continuation pages honor paper and font settings',
    () async {
      for (final family in printFontFamilies.keys) {
        final layout = LocatorPrintLayout(
          paperSize: 'long',
          orientation: 'landscape',
          fontFamily: family,
          defaultFontSize: 16,
          margins: const PrintLayoutMargins(
            top: 36,
            right: 36,
            bottom: 36,
            left: 36,
          ),
          elements: const [
            LocatorPrintElement(
              id: 'sign',
              kind: 'signature',
              source: 'applicant',
              x: 40,
              y: 40,
              width: 200,
              height: 100,
              fontSize: 24,
            ),
            LocatorPrintElement(
              id: 'details',
              kind: 'field',
              source: 'reason',
              x: 40,
              y: 180,
              width: 200,
              height: 40,
              fontSize: 16,
            ),
          ],
        );
        final bytes = await buildLocatorLayoutPdf(
          layout: layout,
          form: {
            'employee_name': 'Maria Employee',
            'reason': List.filled(50, 'Long reason').join(' '),
          },
          signatories: const LocatorFormSignatories(),
        );
        final content = latin1.decode(bytes);
        final pages = RegExp(r'/MediaBox\[0 0 936 612\]').allMatches(content);
        expect(pages.length, greaterThan(1));
        expect(content, contains(printFontFamilies[family]!));
      }
    },
  );
  testWidgets('signature canvas uses the selected font and size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocatorPrintLayoutEditor(
            requestType: LocatorRequestType.locator,
            initialLayout: const LocatorPrintLayout(
              fontFamily: 'serif',
              elements: [
                LocatorPrintElement(
                  id: 'sig',
                  kind: 'signature',
                  source: 'applicant',
                  x: 40,
                  y: 40,
                  width: 300,
                  height: 120,
                  fontSize: 24,
                ),
              ],
            ),
            onPreview: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final name = tester.widget<Text>(find.text('Sample signer'));
    final caption = tester.widget<Text>(
      find.text('Sample employee position').first,
    );
    expect(name.style!.fontFamily, 'NotoSerif');
    expect(caption.style!.fontFamily, 'NotoSerif');
    expect(
      name.style!.fontSize! / caption.style!.fontSize!,
      closeTo(24 / 18, .01),
    );
    expect(tester.takeException(), isNull);
  });
  test('large signature fonts require enough room for name and position', () {
    const layout = LocatorPrintLayout(
      fontFamily: 'serif',
      elements: [
        LocatorPrintElement(
          id: 'sig',
          kind: 'signature',
          source: 'applicant',
          x: 40,
          y: 40,
          width: 300,
          height: 80,
          fontSize: 48,
        ),
      ],
    );
    expect(layout.validate(), contains('Signature'));
  });
  for (final empty in [false, true]) {
    testWidgets('designer saves page and element settings (empty: $empty)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      LocatorPrintLayout? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<LocatorPrintLayout>(
                    context: context,
                    builder: (_) => LocatorPrintLayoutEditor(
                      requestType: LocatorRequestType.locator,
                      initialLayout: empty
                          ? const LocatorPrintLayout(elements: [])
                          : null,
                      onPreview: (_) async {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Finder dropdown(String label) => find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField && w.decoration.labelText == label,
      );
      tester
          .widget<DropdownButtonFormField<String>>(dropdown('Paper size'))
          .onChanged!('long');
      await tester.pump();
      tester
          .widget<DropdownButtonFormField<String>>(
            dropdown('Default font family'),
          )
          .onChanged!('serif');
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('default-font-size')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('default-font-size')),
        '16',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('margin-left')));
      await tester.enterText(find.byKey(const ValueKey('margin-left')), '15');
      await tester.tap(find.text('Text').first);
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButtonFormField<String>>(
            dropdown('Element font family'),
          )
          .onChanged!('mono');
      await tester.pump();
      await tester.tap(find.text('Use layout'));
      await tester.pumpAndSettle();
      expect(result!.toJson()['paper_size'], 'long');
      expect(result!.toJson()['font_family'], 'serif');
      expect(result!.toJson()['margins']['left'], closeTo(15 * 72 / 25.4, .01));
      expect(result!.elements.last.fontSize, 16);
      expect(result!.elements.last.toJson()['font_family'], 'mono');
    });
  }
}
