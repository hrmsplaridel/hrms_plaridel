import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:hrms_plaridel/features/docutracker/models/document_table.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_document_table.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_pdf.dart';

void main() {
  group('DocumentTable', () {
    test('blank table encodes and reloads with the same shape', () {
      final table = DocumentTable.blank(rows: 2, cols: 3);
      final restored = DocumentTable.decode(table.encode());

      expect(restored.rowCount, 2);
      expect(restored.columnCount, 3);
      expect(restored.cells, [
        ['', '', ''],
        ['', '', ''],
      ]);
      expect(table.toInsertJson().keys, [DocumentTable.embedType]);
    });

    test('tryFromInsert reads a Quill embed map', () {
      final table = DocumentTable(
        cells: const [
          ['A', 'B'],
          ['C', 'D'],
        ],
      );
      final restored = DocumentTable.tryFromInsert(table.toInsertJson());
      expect(restored?.cells, table.cells);
      expect(DocumentTable.tryFromInsert('text'), isNull);
      expect(DocumentTable.tryFromInsert({'other': 'x'}), isNull);
    });

    test('rejects invalid shapes', () {
      expect(
        () => DocumentTable.decode('{"cells":[]}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DocumentTable.decode('{"cells":[["a"],["b","c"]]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWithCell updates one cell only', () {
      final table = DocumentTable.blank(
        rows: 2,
        cols: 2,
      ).copyWithCell(1, 0, 'Hello');
      expect(table.cells[1][0], 'Hello');
      expect(table.cells[0][0], isEmpty);
    });
  });

  testWidgets('inline table cells accept text and stay bordered', (
    tester,
  ) async {
    DocumentTable? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerDocumentTableView(
            table: DocumentTable.blank(rows: 2, cols: 2),
            editable: true,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('docutracker-document-table')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('docutracker-table-cell-0-0')),
      'Alpha',
    );
    await tester.pump();
    expect(changed?.cells[0][0], 'Alpha');
  });

  testWidgets('insert table dialog returns the chosen size', (tester) async {
    DocumentTable? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDocuTrackerInsertTableDialog(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Rows'));
    await tester.tap(find.byTooltip('More Columns'));
    await tester.tap(
      find.byKey(const ValueKey('docutracker-insert-table-confirm')),
    );
    await tester.pumpAndSettle();

    expect(result?.rowCount, 4);
    expect(result?.columnCount, 4);
  });

  test('memo body widgets keep table content for PDF', () {
    final table = DocumentTable(
      cells: const [
        ['One', 'Two'],
        ['Three', 'Four'],
      ],
    );
    final widgets = docuTrackerMemoBodyWidgets([
      {'insert': 'Before\n'},
      {'insert': table.toInsertJson()},
      {'insert': '\nAfter\n'},
    ]);

    expect(widgets.length, greaterThanOrEqualTo(3));
  });

  test('quill page round-trip keeps the table embed', () {
    final table = DocumentTable.blank(rows: 1, cols: 2).copyWithCell(0, 0, 'X');
    final document = quill.Document.fromJson([
      {'insert': 'Intro\n'},
      {'insert': table.toInsertJson()},
      {'insert': '\n'},
    ]);
    final ops = document.toDelta().toJson().cast<Map<String, dynamic>>();
    final restored = DocumentTable.tryFromInsert(
      ops.firstWhere((op) => op['insert'] is Map)['insert'],
    );
    expect(restored?.cells[0][0], 'X');
    expect(restored?.columnCount, 2);
  });
}
