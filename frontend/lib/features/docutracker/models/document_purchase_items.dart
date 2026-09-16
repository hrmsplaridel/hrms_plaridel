import 'dart:convert';

/// Editable PR form cells stored inside the existing page Delta, not workflow data.
class DocumentPurchaseItems {
  DocumentPurchaseItems({required List<List<String>> rows, this.total = ''})
    : rows = List.unmodifiable(rows.map(List<String>.unmodifiable));

  static const embedType = 'docutracker-purchase-items';
  static const headers = [
    'Item No.',
    'Unit',
    'Item Description',
    'Quantity',
    'Unit Cost',
    'Total Cost',
  ];
  final List<List<String>> rows;
  final String total;

  factory DocumentPurchaseItems.blank() => DocumentPurchaseItems(
    rows: List.generate(3, (index) => ['${index + 1}', '', '', '', '', '']),
  );

  factory DocumentPurchaseItems.decode(Object? value) {
    if (value is! String) throw const FormatException('Invalid PR table');
    final json = jsonDecode(value);
    if (json is! Map || json['rows'] is! List || json['total'] is! String) {
      throw const FormatException('Invalid PR table');
    }
    final rows = <List<String>>[];
    for (final row in json['rows'] as List) {
      if (row is! List ||
          row.length != headers.length ||
          row.any((cell) => cell is! String)) {
        throw const FormatException('Invalid PR table row');
      }
      rows.add(row.cast<String>());
    }
    if (rows.isEmpty) throw const FormatException('Empty PR table');
    return DocumentPurchaseItems(rows: rows, total: json['total'] as String);
  }

  String encode() => jsonEncode({'rows': rows, 'total': total});
  Map<String, dynamic> toInsertJson() => {embedType: encode()};
}
