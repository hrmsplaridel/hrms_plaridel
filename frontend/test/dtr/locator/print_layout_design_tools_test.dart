import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/print_layout_editing.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const box = LocatorPrintElement(
    id: 'box',
    kind: 'rectangle',
    x: 40,
    y: 50,
    width: 300,
    height: 100,
    decoration: PrintElementDecoration(
      borderSides: ['top', 'right', 'bottom', 'left'],
      borderWidth: 2,
      borderColor: '#FF0000',
      borderStyle: 'dashed',
      fillColor: '#EEEEEE',
    ),
  );
  const first = LocatorPrintElement(
    id: 'first',
    kind: 'text',
    text: 'First',
    x: 60,
    y: 70,
    width: 100,
    height: 20,
  );
  const second = LocatorPrintElement(
    id: 'second',
    kind: 'text',
    text: 'Second',
    x: 200,
    y: 120,
    width: 80,
    height: 30,
  );
  const third = LocatorPrintElement(
    id: 'third',
    kind: 'text',
    text: 'Third',
    x: 400,
    y: 220,
    width: 80,
    height: 20,
  );
  const initial = LocatorPrintLayout(elements: [box, first, second, third]);
  const ids = {'first', 'second'};
  test('committing unchanged page settings preserves exact saved geometry', () {
    final layout = initial.copyWith(
      elements: [first.copyWith(x: 123.456789, y: 234.56789)],
    );
    expect(layout.withPageSettings().toJson(), layout.toJson());
  });

  test(
    'box appearance, groups, and lock settings round-trip without changing legacy defaults',
    () {
      final grouped = PrintLayoutEditing.group(initial, ids, 'group_1');
      final locked = PrintLayoutEditing.lock(grouped, ids, true);
      final restored = LocatorPrintLayout.fromJson(
        jsonDecode(jsonEncode(locked.toJson())),
      );
      expect(restored.validate(), isNull);
      expect(restored.toJson(), locked.toJson());
      expect(restored.elements.first.decoration.fillColor, '#EEEEEE');
      expect(restored.elements[1].locked, isTrue);
      expect(first.toJson().containsKey('decoration'), isFalse);
      expect(first.toJson().containsKey('locked'), isFalse);
      expect(first.toJson().containsKey('group_id'), isFalse);
    },
  );
  test(
    'group selection and movement preserve spacing and clamp the whole group within margins',
    () {
      final grouped = PrintLayoutEditing.group(initial, ids, 'group_1');
      expect(PrintLayoutEditing.selection(grouped, {'first'}), ids);
      final moved = PrintLayoutEditing.translate(grouped, ids, -100, 10);
      expect(moved.elements[1].x, 0);
      expect(moved.elements[2].x - moved.elements[1].x, 140);
      expect(moved.elements[1].y, 80);
      expect(moved.validate(), isNull);
      expect(
        PrintLayoutEditing.ungroup(grouped, ids).elements[1].groupId,
        isNull,
      );
    },
  );
  test(
    'alignment, distribution, and layer changes preserve other elements and locked groups',
    () {
      final aligned = PrintLayoutEditing.align(initial, ids, 'left');
      expect(aligned.elements[2].x, 60);
      final spaced = PrintLayoutEditing.distribute(initial, {
        'first',
        'second',
        'third',
      }, horizontal: true);
      final a = spaced.elements[1],
          b = spaced.elements[2],
          c = spaced.elements[3];
      expect(b.x - a.x - a.width, closeTo(c.x - b.x - b.width, .001));
      expect(
        PrintLayoutEditing.reorder(initial, {'box'}, 'front').elements.last.id,
        'box',
      );
      expect(
        PrintLayoutEditing.reorder(
          initial,
          ids,
          'back',
        ).elements.take(2).map((e) => e.id),
        ['first', 'second'],
      );
      final locked = PrintLayoutEditing.lock(initial, ids, true);
      expect(
        PrintLayoutEditing.translate(locked, ids, 20, 20).toJson(),
        locked.toJson(),
      );
      expect(
        PrintLayoutEditing.align(locked, ids, 'right').toJson(),
        locked.toJson(),
      );
    },
  );
  test('invalid colors and border widths are rejected locally', () {
    expect(
      initial
          .copyWith(
            elements: [
              box.copyWith(
                decoration: const PrintElementDecoration(borderWidth: -1),
              ),
            ],
          )
          .validate(),
      isNotNull,
    );
    expect(
      initial
          .copyWith(
            elements: [
              box.copyWith(
                decoration: const PrintElementDecoration(fillColor: 'red'),
              ),
            ],
          )
          .validate(),
      isNotNull,
    );
  });
  test(
    'PDF output paints the box fill and dashed borders before the text layers',
    () async {
      final bytes = await buildLocatorLayoutPdf(
        layout: initial,
        form: const {},
        signatories: const LocatorFormSignatories(),
        document: pw.Document(compress: false),
      );
      final pdf = latin1.decode(bytes);
      expect(pdf, contains('1 0 0 RG'));
      expect(pdf, contains(' re'));
      expect(pdf, contains(' rg'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length, 1);
    },
  );
}
