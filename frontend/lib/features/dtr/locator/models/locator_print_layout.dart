import 'dart:convert';
import 'dart:math' as math;
import 'locator_request_type.dart';

const printPaperSizes = <String, (double, double)>{
  'a4': (595.28, 841.89),
  'letter': (612, 792),
  'long': (612, 936),
  'legal': (612, 1008),
};
const printPaperLabels = <String, String>{
  'a4': 'A4 (210 × 297 mm)',
  'letter': 'Letter (8.5 × 11 in)',
  'long': 'Long Bond (8.5 × 13 in)',
  'legal': 'Legal (8.5 × 14 in)',
};
const printFontFamilies = <String, String>{
  'sans': 'NotoSans',
  'serif': 'NotoSerif',
  'mono': 'NotoSansMono',
};
const printFontLabels = <String, String>{
  'sans': 'Noto Sans',
  'serif': 'Noto Serif',
  'mono': 'Noto Sans Mono',
};
String printPaperFromAspect(double width, double height) {
  final ratio = math.min(width, height) / math.max(width, height);
  return printPaperSizes.keys.reduce(
    (a, b) =>
        (ratio - printPaperSizes[a]!.$1 / printPaperSizes[a]!.$2).abs() <=
            (ratio - printPaperSizes[b]!.$1 / printPaperSizes[b]!.$2).abs()
        ? a
        : b,
  );
}

class PrintLayoutMargins {
  const PrintLayoutMargins({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });
  final double top, right, bottom, left;
  bool get isEmpty => top == 0 && right == 0 && bottom == 0 && left == 0;
  Map<String, dynamic> toJson() => {
    'top': top,
    'right': right,
    'bottom': bottom,
    'left': left,
  };
  factory PrintLayoutMargins.fromJson(Map<String, dynamic> json) =>
      PrintLayoutMargins(
        top: (json['top'] as num).toDouble(),
        right: (json['right'] as num).toDouble(),
        bottom: (json['bottom'] as num).toDouble(),
        left: (json['left'] as num).toDouble(),
      );
}

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
    this.fontFamily,
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
  final String? fontFamily;
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
    String? fontFamily,
    bool inheritFont = false,
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
    fontFamily: inheritFont ? null : fontFamily ?? this.fontFamily,
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
    if (fontFamily != null) 'font_family': fontFamily,
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
        fontFamily: json['font_family'] as String?,
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
    this.paperSize = 'a4',
    this.margins = const PrintLayoutMargins(),
    this.fontFamily,
    this.defaultFontSize = 11,
    required this.elements,
  });
  final String orientation, paperSize;
  final PrintLayoutMargins margins;
  final String? fontFamily;
  final double defaultFontSize;
  final List<LocatorPrintElement> elements;
  double get pageWidth => orientation == 'portrait'
      ? (printPaperSizes[paperSize] ?? printPaperSizes['a4']!).$1
      : (printPaperSizes[paperSize] ?? printPaperSizes['a4']!).$2;
  double get pageHeight => orientation == 'portrait'
      ? (printPaperSizes[paperSize] ?? printPaperSizes['a4']!).$2
      : (printPaperSizes[paperSize] ?? printPaperSizes['a4']!).$1;
  double get contentWidth => pageWidth - margins.left - margins.right;
  double get contentHeight => pageHeight - margins.top - margins.bottom;
  LocatorPrintLayout copyWith({
    String? orientation,
    String? paperSize,
    PrintLayoutMargins? margins,
    String? fontFamily,
    bool inheritFont = false,
    double? defaultFontSize,
    List<LocatorPrintElement>? elements,
  }) => LocatorPrintLayout(
    orientation: orientation ?? this.orientation,
    paperSize: paperSize ?? this.paperSize,
    margins: margins ?? this.margins,
    fontFamily: inheritFont ? null : fontFamily ?? this.fontFamily,
    defaultFontSize: defaultFontSize ?? this.defaultFontSize,
    elements: elements ?? this.elements,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'orientation': orientation,
    if (paperSize != 'a4') 'paper_size': paperSize,
    if (!margins.isEmpty) 'margins': margins.toJson(),
    if (fontFamily != null) 'font_family': fontFamily,
    if (defaultFontSize != 11) 'default_font_size': defaultFontSize,
    'elements': elements.map((e) => e.toJson()).toList(),
  };
  factory LocatorPrintLayout.fromJson(Map<String, dynamic> json) =>
      LocatorPrintLayout(
        orientation: json['orientation'] as String,
        paperSize: json['paper_size'] as String? ?? 'a4',
        margins: json['margins'] is Map
            ? PrintLayoutMargins.fromJson(
                Map<String, dynamic>.from(json['margins'] as Map),
              )
            : const PrintLayoutMargins(),
        fontFamily: json['font_family'] as String?,
        defaultFontSize: (json['default_font_size'] as num? ?? 11).toDouble(),
        elements: (json['elements'] as List)
            .map(
              (e) => LocatorPrintElement.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
  String? pageSettingsError() {
    if (!printPaperSizes.containsKey(paperSize) ||
        !['portrait', 'landscape'].contains(orientation)) {
      return 'Choose a supported paper size and orientation.';
    }
    if (fontFamily != null && !printFontFamilies.containsKey(fontFamily)) {
      return 'Choose a supported font family.';
    }
    if (!defaultFontSize.isFinite ||
        defaultFontSize < 6 ||
        defaultFontSize > 72) {
      return 'Default font size must be 6 to 72 points.';
    }
    if ([
          margins.top,
          margins.right,
          margins.bottom,
          margins.left,
        ].any((v) => !v.isFinite || v < 0) ||
        contentWidth < 100 ||
        contentHeight < 100) {
      return 'Margins must leave at least 100 points of usable page width and height.';
    }
    return null;
  }

  LocatorPrintLayout withPageSettings({
    String? paperSize,
    String? orientation,
    PrintLayoutMargins? margins,
  }) {
    final next = copyWith(
      paperSize: paperSize,
      orientation: orientation,
      margins: margins,
    );
    if (next.pageSettingsError() != null) return next;
    return next.copyWith(
      elements: [for (final item in elements) _fitElement(item, next)],
    );
  }

  LocatorPrintElement _fitElement(
    LocatorPrintElement item,
    LocatorPrintLayout next,
  ) {
    final minWidth = item.kind == 'signature'
        ? 100.0
        : item.kind == 'table'
        ? 20 *
              item.columnWidths.fold(0.0, (a, b) => a + b) /
              item.columnWidths.reduce(math.min)
        : 20.0;
    final minHeight = switch (item.kind) {
      'signature' =>
        item.fontFamily != null || next.fontFamily != null
            ? math.max(60.0, item.fontSize * 3.5 + 12)
            : 60.0,
      'field' => 20.0,
      'text' => 12.0,
      'table' => item.cells.length * (item.fontSize * 1.5 + 8),
      _ => 2.0,
    };
    final width = (item.width / contentWidth * next.contentWidth).clamp(
      math.min(minWidth, next.contentWidth),
      next.contentWidth,
    );
    final height = (item.height / contentHeight * next.contentHeight).clamp(
      math.min(minHeight, next.contentHeight),
      next.contentHeight,
    );
    return item.copyWith(
      width: width.toDouble(),
      height: height.toDouble(),
      x:
          (next.margins.left +
                  (item.x - margins.left) / contentWidth * next.contentWidth)
              .clamp(
                next.margins.left,
                next.pageWidth - next.margins.right - width,
              ),
      y:
          (next.margins.top +
                  (item.y - margins.top) / contentHeight * next.contentHeight)
              .clamp(
                next.margins.top,
                next.pageHeight - next.margins.bottom - height,
              ),
    );
  }

  String? validate() {
    final pageError = pageSettingsError();
    if (pageError != null) return pageError;
    if (elements.isEmpty || elements.length > 60) {
      return 'Add 1 to 60 elements.';
    }
    if (elements.map((e) => e.id).toSet().length != elements.length) {
      return 'Each element needs a unique ID.';
    }
    for (final e in elements) {
      if ([e.x, e.y, e.width, e.height, e.fontSize].any((n) => !n.isFinite) ||
          e.x < margins.left ||
          e.y < margins.top ||
          e.width < 20 ||
          e.height < 2 ||
          e.x + e.width > pageWidth - margins.right + .1 ||
          e.y + e.height > pageHeight - margins.bottom + .1) {
        return 'Keep all elements inside the page margins.';
      }
      if (e.fontFamily != null &&
          !printFontFamilies.containsKey(e.fontFamily)) {
        return 'Choose a supported element font family.';
      }
      if (e.fontSize < 6 || e.fontSize > 72) {
        return 'Font size must be 6 to 72 points.';
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
      if (e.kind == 'signature' &&
          (e.fontFamily != null || fontFamily != null) &&
          e.height < math.max(60, e.fontSize * 3.5 + 12)) {
        return 'Signature blocks need enough height for their font size. Increase the height or reduce the font size.';
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
