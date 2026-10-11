import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/widgets/request_filters_bar.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('search keeps focus and cursor while typing at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var query = '';
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return RequestFiltersBar<String>(
                  options: const [RequestFilterOption(label: 'All')],
                  selectedValue: null,
                  onStatusChanged: (_) {},
                  visibleCount: 0,
                  totalCount: 0,
                  searchQuery: query,
                  showDateRange: false,
                  onSearchChanged: (value) => setState(() => query = value),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      final originalState = tester.state(find.byType(EditableText));
      for (final text in ['m', 'ma', 'mak']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pump();
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.focusNode.hasFocus, isTrue);
        expect(tester.state(find.byType(EditableText)), same(originalState));
        expect(field.controller.text, text);
        expect(field.controller.selection.baseOffset, text.length);
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'mark',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .selection
            .baseOffset,
        3,
      );
      rebuild(() => query = '');
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
