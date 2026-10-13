import 'dart:convert';
import 'locator_request_type.dart';

class LocatorPrintTableCell {
  const LocatorPrintTableCell({
    this.kind = 'text',
    this.text = '',
    this.source = '',
  });
  final String kind, text, source;
  Map<String, dynamic> toJson() => kind == 'field'
      ? {'kind': kind, 'source': source}
      : {'kind': kind, 'text': text};
  factory LocatorPrintTableCell.fromJson(Map<String, dynamic> json) =>
      LocatorPrintTableCell(
        kind: json['kind'] as String? ?? 'text',
        text: json['text'] as String? ?? '',
        source: json['source'] as String? ?? '',
      );
}

class LocatorPrintElement {
  const LocatorPrintElement({
    required this.id,
    required this.kind,
    this.source = '',
    this.text = '',
    this.label = '',
    this.x = 40,
    this.y = 180,
    this.width = 240,
    this.height = 40,
    this.fontSize = 11,
    this.align = 'left',
    this.bold = false,
    this.showLabel = true,
    this.cells = const [],
    this.columnWidths = const [],
    this.headerRow = true,
    this.borders = true,
  });
  final String id, kind, source, text, label, align;
  final double x, y, width, height, fontSize;
  final bool bold, showLabel;
  final List<List<LocatorPrintTableCell>> cells;
  final List<double> columnWidths;
  final bool headerRow, borders;
  LocatorPrintElement copyWith({
    String? id,
    String? text,
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
    double? fontSize,
    String? align,
    bool? bold,
    bool? showLabel,
    List<List<LocatorPrintTableCell>>? cells,
    List<double>? columnWidths,
    bool? headerRow,
    bool? borders,
  }) => LocatorPrintElement(
    id: id ?? this.id,
    kind: kind,
    source: source,
    text: text ?? this.text,
    label: label ?? this.label,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    fontSize: fontSize ?? this.fontSize,
    align: align ?? this.align,
    bold: bold ?? this.bold,
    showLabel: showLabel ?? this.showLabel,
    cells: cells ?? this.cells,
    columnWidths: columnWidths ?? this.columnWidths,
    headerRow: headerRow ?? this.headerRow,
    borders: borders ?? this.borders,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'source': source,
    'text': text,
    'label': label,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'font_size': fontSize,
    'align': align,
    'bold': bold,
    'show_label': showLabel,
    if (kind == 'table') ...{
      'cells': cells
          .map((row) => row.map((cell) => cell.toJson()).toList())
          .toList(),
      'column_widths': columnWidths,
      'header_row': headerRow,
      'borders': borders,
    },
  };
  factory LocatorPrintElement.fromJson(Map<String, dynamic> json) =>
      LocatorPrintElement(
        id: json['id'] as String,
        kind: json['kind'] as String,
        source: json['source'] as String? ?? '',
        text: json['text'] as String? ?? '',
        label: json['label'] as String? ?? '',
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        fontSize: (json['font_size'] as num).toDouble(),
        align: json['align'] as String? ?? 'left',
        bold: json['bold'] == true,
        showLabel: json['show_label'] != false,
        cells: (json['cells'] as List? ?? [])
            .map(
              (row) => (row as List)
                  .map(
                    (cell) => LocatorPrintTableCell.fromJson(
                      Map<String, dynamic>.from(cell as Map),
                    ),
                  )
                  .toList(),
            )
            .toList(),
        columnWidths: (json['column_widths'] as List? ?? [])
            .map((w) => (w as num).toDouble())
            .toList(),
        headerRow: json['header_row'] != false,
        borders: json['borders'] != false,
      );
}

class LocatorPrintLayout {
  const LocatorPrintLayout({
    this.orientation = 'portrait',
    required this.elements,
  });
  final String orientation;
  final List<LocatorPrintElement> elements;
  double get pageWidth => orientation == 'portrait' ? 595.28 : 841.89;
  double get pageHeight => orientation == 'portrait' ? 841.89 : 595.28;
  LocatorPrintLayout copyWith({
    String? orientation,
    List<LocatorPrintElement>? elements,
  }) => LocatorPrintLayout(
    orientation: orientation ?? this.orientation,
    elements: elements ?? this.elements,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'orientation': orientation,
    'elements': elements.map((e) => e.toJson()).toList(),
  };
  factory LocatorPrintLayout.fromJson(Map<String, dynamic> json) =>
      LocatorPrintLayout(
        orientation: json['orientation'] as String,
        elements: (json['elements'] as List)
            .map(
              (e) => LocatorPrintElement.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
  String? validate() {
    if (elements.isEmpty || elements.length > 60) {
      return 'Add 1 to 60 elements.';
    }
    if (elements.map((e) => e.id).toSet().length != elements.length) {
      return 'Each element needs a unique ID.';
    }
    for (final e in elements) {
      if ([e.x, e.y, e.width, e.height, e.fontSize].any((n) => !n.isFinite) ||
          e.x < 0 ||
          e.y < 0 ||
          e.width < 20 ||
          e.height < 2 ||
          e.x + e.width > pageWidth + .1 ||
          e.y + e.height > pageHeight + .1) {
        return 'Keep all elements inside the page.';
      }
      if (e.fontSize < 8 || e.fontSize > 28) {
        return 'Font size must be 8 to 28 points.';
      }
      if (e.kind == 'text' && (e.text.trim().isEmpty || e.text.length > 500)) {
        return 'Text needs 1 to 500 characters.';
      }
      if (e.label.length > 100) return 'Labels must be 100 characters or less.';
      if (e.kind == 'field' && e.height < 20) {
        return 'Field boxes need at least 20 points of height.';
      }
      if (e.kind == 'text' && e.height < 12) {
        return 'Text boxes need at least 12 points of height.';
      }
      if (e.kind == 'table') {
        if (e.cells.isEmpty ||
            e.cells.length > 12 ||
            e.cells.first.isEmpty ||
            e.cells.first.length > 6 ||
            e.cells.any((row) => row.length != e.cells.first.length)) {
          return 'Tables need 1 to 12 rows and 1 to 6 matching columns.';
        }
        if (e.columnWidths.length != e.cells.first.length ||
            e.columnWidths.any((w) => !w.isFinite || w < .1 || w > 10)) {
          return 'Column width weights must be 0.1 to 10.';
        }
        final total = e.columnWidths.fold(0.0, (a, b) => a + b);
        if (e.height < e.cells.length * (e.fontSize * 1.5 + 8) ||
            e.columnWidths.any((w) => e.width * w / total < 20)) {
          return 'Table rows need enough height for their font; columns need 20 points.';
        }
        for (final row in e.cells) {
          for (final cell in row) {
            if (!['text', 'field'].contains(cell.kind) ||
                (cell.kind == 'field' && cell.source.isEmpty)) {
              return 'Each cell needs text or a field.';
            }
            if (cell.text.length > 500) {
              return 'Cell text must be 500 characters or less.';
            }
          }
        }
      }
      if (e.kind == 'signature' && (e.width < 100 || e.height < 60)) {
        return 'Signature blocks need at least 100 by 60 points.';
      }
    }
    if (utf8
            .encode(const JsonEncoder.withIndent(' ').convert(toJson()))
            .length >
        100000) {
      return 'Printed layout must fit within 100 KB.';
    }
    return null;
  }

  factory LocatorPrintLayout.defaults(
    LocatorRequestType type, {
    String orientation = 'portrait',
  }) {
    final portrait = orientation == 'portrait';
    final pageWidth = portrait ? 595.28 : 841.89;
    final fields = <String, String>{
      'employee_name': 'Employee',
      'date': 'Date',
      'request_type': 'Type',
      'time_segments': 'DTR slots',
      'office': type.locationLabel,
      'reason': 'Remarks / Reasons',
      for (final field in type.employeeDetailSchema)
        'custom:${field.key}': field.label,
    };
    final elements = <LocatorPrintElement>[
      LocatorPrintElement(
        id: 'title',
        kind: 'text',
        text: type.label.toUpperCase(),
        x: 40,
        y: portrait ? 135 : 40,
        width: pageWidth - 80,
        height: 32,
        fontSize: 20,
        align: 'center',
        bold: true,
      ),
    ];
    final rowHeight = portrait ? 32.0 : 28.0;
    final start = portrait ? 190.0 : 95.0;
    final width = (pageWidth - 94) / 2;
    var index = 0;
    for (final field in fields.entries) {
      elements.add(
        LocatorPrintElement(
          id: 'field_$index',
          kind: 'field',
          source: field.key,
          label: field.value,
          x: 40 + (index % 2) * (width + 14),
          y: start + (index ~/ 2) * rowHeight,
          width: width,
          height: rowHeight - 2,
          fontSize: portrait ? 10 : 8,
        ),
      );
      index++;
    }
    final signatureY = start + ((index + 1) ~/ 2) * rowHeight + 20;
    final signatureWidth = (pageWidth - 108) / 3;
    for (final entry in const [
      'applicant',
      'department_head',
      'hr_approver',
    ].asMap().entries) {
      elements.add(
        LocatorPrintElement(
          id: 'signature_${entry.value}',
          kind: 'signature',
          source: entry.value,
          // An empty signature label uses the request's signer position.
          label: '',
          x: 40 + entry.key * (signatureWidth + 14),
          y: signatureY,
          width: signatureWidth,
          height: 75,
          fontSize: 10,
          align: 'center',
        ),
      );
    }
    return LocatorPrintLayout(orientation: orientation, elements: elements);
  }
}
