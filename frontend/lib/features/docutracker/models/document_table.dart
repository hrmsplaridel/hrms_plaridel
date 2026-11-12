import 'dart:convert';

/// General-purpose table stored inside a page Quill Delta as a custom embed.
///
/// Used by Memorandum body and free-form document types. Purchase Request keeps
/// its own [DocumentPurchaseItems] embed and must not use this type.
class DocumentTable {
  DocumentTable({required List<List<String>> cells})
    : assert(cells.isNotEmpty, 'Table needs at least one row'),
      assert(
        cells.every((row) => row.length == cells.first.length),
        'Table rows must share one column count',
      ),
      cells = List.unmodifiable(cells.map(List<String>.unmodifiable));

  static const embedType = 'docutracker-table';
  static const int minRows = 1;
  static const int minCols = 1;
  static const int maxRows = 12;
  static const int maxCols = 8;

  final List<List<String>> cells;

  int get rowCount => cells.length;
  int get columnCount => cells.first.length;

  factory DocumentTable.blank({required int rows, required int cols}) {
    final safeRows = rows.clamp(minRows, maxRows);
    final safeCols = cols.clamp(minCols, maxCols);
    return DocumentTable(
      cells: List.generate(safeRows, (_) => List.generate(safeCols, (_) => '')),
    );
  }

  factory DocumentTable.decode(Object? value) {
    if (value is! String) throw const FormatException('Invalid document table');
    final json = jsonDecode(value);
    if (json is! Map || json['cells'] is! List) {
      throw const FormatException('Invalid document table');
    }
    final rows = <List<String>>[];
    for (final row in json['cells'] as List) {
      if (row is! List || row.isEmpty || row.any((cell) => cell is! String)) {
        throw const FormatException('Invalid document table row');
      }
      rows.add(row.cast<String>());
    }
    if (rows.isEmpty) throw const FormatException('Empty document table');
    final width = rows.first.length;
    if (width < minCols ||
        width > maxCols ||
        rows.length > maxRows ||
        rows.any((row) => row.length != width)) {
      throw const FormatException('Invalid document table shape');
    }
    return DocumentTable(cells: rows);
  }

  /// Reads a Quill insert map when the operation embeds a document table.
  static DocumentTable? tryFromInsert(Object? insert) {
    if (insert is! Map) return null;
    final raw = insert[embedType];
    if (raw == null) return null;
    try {
      return DocumentTable.decode(raw);
    } on FormatException {
      return null;
    }
  }

  DocumentTable copyWithCell(int row, int col, String value) {
    final next = [
      for (var r = 0; r < cells.length; r++)
        [
          for (var c = 0; c < cells[r].length; c++)
            r == row && c == col ? value : cells[r][c],
        ],
    ];
    return DocumentTable(cells: next);
  }

  String encode() => jsonEncode({'cells': cells});

  Map<String, dynamic> toInsertJson() => {embedType: encode()};
}
