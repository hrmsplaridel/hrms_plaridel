import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../models/document_purchase_items.dart';

/// Official purchase-request page geometry.
///
/// The editor and the PDF both use this plan. Stored signature rows stay on
/// page 1 at their existing coordinates; the closing band is only a display
/// of the Requested by and Approved by labels.
abstract final class DocuTrackerPurchaseMetrics {
  static const double paperWidth = 794;
  static const double paperHeight = 1123;
  static const double frameLeft = 56;
  static const double frameTop = 230;
  static const double frameRight = 56;
  static const double frameBottom = 117;
  static const double titleGap = 18;
  static const double contentWidth = paperWidth - frameLeft - frameRight;

  /// Matches [DocuTrackerPurchaseSignatureBand]: 12px gap plus a 132px row.
  static const double signatureBandHeight = 144;

  static const List<double> columnFlex = <double>[0.7, 0.7, 3, 0.9, 1.1, 1.1];
  static const double cellFontSize = 12;
  static const double cellLineHeight = 1.1;
  static const double cellMinHeight = 32;
  static const double cellPadH = 5;
  static const double cellPadV = 7;
  static const double tableBorder = 0.8;

  static const TextStyle titleStyle = TextStyle(
    color: Color(0xFFE85D04),
    fontSize: 18,
    fontWeight: FontWeight.w800,
  );

  static double bodyHeightFor(String title) {
    final painter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: contentWidth);
    return paperHeight - frameTop - frameBottom - painter.height - titleGap;
  }

  static List<double> columnWidths(double tableWidth) {
    final sum = columnFlex.fold<double>(0, (total, flex) => total + flex);
    return [for (final flex in columnFlex) tableWidth * flex / sum];
  }

  static TextStyle cellStyle({required bool heading}) => TextStyle(
    color: Colors.black,
    fontSize: cellFontSize,
    height: cellLineHeight,
    fontWeight: heading ? FontWeight.bold : FontWeight.normal,
  );

  static double cellHeight(
    String text, {
    required double columnWidth,
    required bool heading,
  }) {
    final inner = math.max(1.0, columnWidth - cellPadH * 2);
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? ' ' : text,
        style: cellStyle(heading: heading),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: inner);
    return math.max(cellMinHeight, painter.height + cellPadV * 2);
  }
}

class PurchaseSpan {
  const PurchaseSpan(this.text, {required this.bold, required this.fontSize});

  final String text;
  final bool bold;
  final double fontSize;

  TextStyle get style => TextStyle(
    color: Colors.black,
    fontSize: fontSize,
    height: 1.15,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
  );
}

class PurchaseParagraph {
  PurchaseParagraph({
    required this.spans,
    required this.align,
    required this.emptyFontSize,
    required this.height,
  });

  final List<PurchaseSpan> spans;
  final TextAlign align;
  final double emptyFontSize;
  final double height;

  String get plain => spans.map((span) => span.text).join();
}

class PurchaseParts {
  const PurchaseParts({
    required this.preambleOps,
    required this.purposeOps,
    required this.preamble,
    required this.purpose,
    required this.items,
    required this.tableError,
  });

  final List<Map<String, dynamic>> preambleOps;
  final List<Map<String, dynamic>> purposeOps;
  final List<PurchaseParagraph> preamble;
  final List<PurchaseParagraph> purpose;
  final DocumentPurchaseItems? items;
  final bool tableError;
}

class PurchasePageSlice {
  PurchasePageSlice({
    required this.preamble,
    required this.preambleComplete,
    required this.tableRows,
    required this.showTotal,
    required this.total,
    required this.purpose,
    required this.purposeComplete,
    required this.showSignatures,
    required this.tableError,
    required this.contentHeight,
  });

  final List<PurchaseParagraph> preamble;
  final bool preambleComplete;
  final List<List<String>> tableRows;
  final bool showTotal;
  final String total;
  final List<PurchaseParagraph> purpose;
  final bool purposeComplete;
  final bool showSignatures;
  final bool tableError;
  final double contentHeight;

  bool get hasTable => tableRows.isNotEmpty || showTotal;
}

class PurchaseDocumentPlan {
  const PurchaseDocumentPlan({
    required this.parts,
    required this.pages,
    required this.bodyHeight,
    required this.contentWidth,
  });

  final PurchaseParts parts;
  final List<PurchasePageSlice> pages;
  final double bodyHeight;
  final double contentWidth;
}

/// One official sheet per planned slice, plus any extra stored pages after it.
int docuTrackerPurchaseSheetCount({
  required int storedPages,
  required int slices,
}) {
  if (storedPages <= 0) return 0;
  return math.max(1, slices) + storedPages - 1;
}

PurchaseParts parsePurchaseDelta(
  List<Map<String, dynamic>> delta, {
  required double contentWidth,
}) {
  final embedIndex = delta.indexWhere((op) {
    final insert = op['insert'];
    return insert is Map && insert.containsKey(DocumentPurchaseItems.embedType);
  });
  if (embedIndex < 0) {
    final ops = List<Map<String, dynamic>>.from(delta);
    return PurchaseParts(
      preambleOps: ops,
      purposeOps: const [],
      preamble: _paragraphs(ops, contentWidth),
      purpose: const [],
      items: null,
      tableError: false,
    );
  }
  var purposeStart = embedIndex + 1;
  if (purposeStart < delta.length && delta[purposeStart]['insert'] == '\n') {
    purposeStart += 1;
  }
  final preambleOps = delta.sublist(0, embedIndex);
  final purposeOps = delta.sublist(purposeStart);
  final raw =
      (delta[embedIndex]['insert'] as Map)[DocumentPurchaseItems.embedType];
  DocumentPurchaseItems? items;
  var tableError = false;
  try {
    items = DocumentPurchaseItems.decode(raw);
  } on FormatException {
    tableError = true;
  }
  return PurchaseParts(
    preambleOps: preambleOps,
    purposeOps: purposeOps,
    preamble: _paragraphs(preambleOps, contentWidth),
    purpose: _paragraphs(purposeOps, contentWidth),
    items: items,
    tableError: tableError,
  );
}

List<Map<String, dynamic>> composePurchaseDelta({
  required List<Map<String, dynamic>> preambleOps,
  required DocumentPurchaseItems? items,
  required List<Map<String, dynamic>> purposeOps,
}) {
  final ops = <Map<String, dynamic>>[...preambleOps];
  if (items != null) {
    ops.add({'insert': items.toInsertJson()});
    ops.add({'insert': '\n'});
  }
  ops.addAll(purposeOps);
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return ops;
}

/// Replaces the hidden page document after a section edit.
///
/// Quill keeps a trailing newline, so the replacement delta omits its own.
void writePurchaseDocument(
  quill.QuillController controller,
  List<Map<String, dynamic>> delta,
) {
  final next = quill.Document.fromJson(delta).toDelta();
  if (next.isNotEmpty && next.last.data == '\n' && next.last.isInsert) {
    next.operations.removeLast();
  }
  final length = controller.document.length;
  controller.replaceText(
    0,
    length <= 1 ? 0 : length - 1,
    next.isEmpty ? '' : next,
    const TextSelection.collapsed(offset: 0),
  );
}

PurchaseDocumentPlan planPurchaseDocument({
  required List<Map<String, dynamic>> delta,
  required String title,
  double? bodyHeight,
  double contentWidth = DocuTrackerPurchaseMetrics.contentWidth,
}) {
  final height = bodyHeight ?? DocuTrackerPurchaseMetrics.bodyHeightFor(title);
  final parts = parsePurchaseDelta(delta, contentWidth: contentWidth);
  return PurchaseDocumentPlan(
    parts: parts,
    pages: _paginate(parts, bodyHeight: height, contentWidth: contentWidth),
    bodyHeight: height,
    contentWidth: contentWidth,
  );
}

List<PurchasePageSlice> _paginate(
  PurchaseParts parts, {
  required double bodyHeight,
  required double contentWidth,
}) {
  final columns = DocuTrackerPurchaseMetrics.columnWidths(contentWidth);
  final headerHeight = _rowHeight(
    DocumentPurchaseItems.headers,
    columns,
    heading: true,
  );
  final maxRow = math.max(1.0, bodyHeight - headerHeight);
  final rows = parts.items == null
      ? const <List<String>>[]
      : [
          for (final row in parts.items!.rows)
            ..._splitRow(row, columns, maxRow),
        ];
  final totalHeight = parts.items == null
      ? 0.0
      : _totalHeight(parts.items!.total, columns);
  final preamble = _explode(parts.preamble, bodyHeight, contentWidth);
  final purpose = _explode(
    parts.purpose,
    math.max(1.0, bodyHeight - DocuTrackerPurchaseMetrics.signatureBandHeight),
    contentWidth,
  );
  final pages = <_DraftPage>[_DraftPage()];
  var current = pages.first;

  void nextPage() {
    current = _DraftPage();
    pages.add(current);
  }

  bool fits(double height) => current.used + height <= bodyHeight + 0.01;

  void placeParagraphs(
    List<PurchaseParagraph> block,
    void Function(PurchaseParagraph paragraph) add,
    void Function() markComplete,
  ) {
    if (block.isEmpty) return;
    final raw = block.fold<double>(0, (sum, item) => sum + item.height);
    if (!fits(raw) && raw <= bodyHeight && current.used > 0.01) nextPage();
    final home = current;
    var broke = false;
    for (final paragraph in block) {
      if (!fits(paragraph.height) && current.used > 0.01) {
        nextPage();
        broke = true;
      }
      add(paragraph);
      current.used += paragraph.height;
    }
    if (!broke && identical(home, current)) markComplete();
  }

  placeParagraphs(
    preamble,
    (paragraph) => current.preamble.add(paragraph),
    () => current.preambleComplete = true,
  );

  if (parts.tableError) {
    final message = _paragraphs(const [
      {
        'insert':
            'This purchase table could not be read. Reload the document before editing.\n',
      },
    ], contentWidth).single;
    if (!fits(message.height) && current.used > 0.01) nextPage();
    current.tableError = true;
    current.used += message.height;
    current.errorHeight = message.height;
  }

  if (parts.items != null) {
    for (final row in rows) {
      final header = current.tableOpen ? 0.0 : headerHeight;
      final rowHeight = _rowHeight(row, columns, heading: false);
      if (!fits(header + rowHeight) && current.used > 0.01) nextPage();
      if (!current.tableOpen) {
        current.tableOpen = true;
        current.used += headerHeight;
      }
      current.tableRows.add(row);
      current.used += rowHeight;
    }
    final header = current.tableOpen ? 0.0 : headerHeight;
    if (!fits(header + totalHeight) && current.used > 0.01) nextPage();
    if (!current.tableOpen) {
      current.tableOpen = true;
      current.used += headerHeight;
    }
    current.showTotal = true;
    current.total = parts.items!.total;
    current.used += totalHeight;
  }

  final band = DocuTrackerPurchaseMetrics.signatureBandHeight;
  final purposeHeight = purpose.fold<double>(
    0,
    (sum, item) => sum + item.height,
  );
  if (current.used + purposeHeight + band <= bodyHeight + 0.01) {
    current.purpose.addAll(purpose);
    current.purposeComplete = purpose.isNotEmpty;
    current.used += purposeHeight;
    current.showSignatures = true;
    current.used += band;
  } else if (purposeHeight + band <= bodyHeight && current.used > 0.01) {
    nextPage();
    current.purpose.addAll(purpose);
    current.purposeComplete = purpose.isNotEmpty;
    current.used += purposeHeight;
    current.showSignatures = true;
    current.used += band;
  } else {
    var index = 0;
    while (index < purpose.length) {
      final rest =
          purpose
              .skip(index)
              .fold<double>(0, (sum, item) => sum + item.height) +
          band;
      if (current.used > 0.01 && rest <= bodyHeight && !fits(rest)) {
        nextPage();
      }
      final last = index == purpose.length - 1;
      final need = purpose[index].height + (last ? band : 0);
      if (current.used > 0.01 && !fits(need)) {
        nextPage();
        continue;
      }
      current.purpose.add(purpose[index]);
      current.used += purpose[index].height;
      if (last) {
        current.showSignatures = true;
        current.used += band;
      }
      index += 1;
    }
    if (!current.showSignatures) {
      if (current.used > 0.01 && !fits(band)) nextPage();
      current.showSignatures = true;
      current.used += band;
    }
  }

  final built = [
    for (final page in pages)
      if (page.hasContent)
        PurchasePageSlice(
          preamble: List<PurchaseParagraph>.unmodifiable(page.preamble),
          preambleComplete: page.preambleComplete,
          tableRows: List<List<String>>.unmodifiable(
            page.tableRows.map(List<String>.unmodifiable),
          ),
          showTotal: page.showTotal,
          total: page.total,
          purpose: List<PurchaseParagraph>.unmodifiable(page.purpose),
          purposeComplete: page.purposeComplete,
          showSignatures: page.showSignatures,
          tableError: page.tableError,
          contentHeight: page.used,
        ),
  ];
  if (built.isNotEmpty) return built;
  return [
    PurchasePageSlice(
      preamble: const [],
      preambleComplete: false,
      tableRows: const [],
      showTotal: false,
      total: '',
      purpose: const [],
      purposeComplete: false,
      showSignatures: true,
      tableError: false,
      contentHeight: band,
    ),
  ];
}

class _DraftPage {
  final List<PurchaseParagraph> preamble = [];
  final List<List<String>> tableRows = [];
  final List<PurchaseParagraph> purpose = [];
  bool preambleComplete = false;
  bool purposeComplete = false;
  bool tableOpen = false;
  bool showTotal = false;
  bool showSignatures = false;
  bool tableError = false;
  double errorHeight = 0;
  String total = '';
  double used = 0;

  bool get hasContent =>
      preamble.isNotEmpty ||
      tableRows.isNotEmpty ||
      showTotal ||
      purpose.isNotEmpty ||
      showSignatures ||
      tableError;
}

double _rowHeight(
  List<String> cells,
  List<double> columns, {
  required bool heading,
}) {
  var height = DocuTrackerPurchaseMetrics.cellMinHeight;
  for (var index = 0; index < cells.length && index < columns.length; index++) {
    height = math.max(
      height,
      DocuTrackerPurchaseMetrics.cellHeight(
        cells[index],
        columnWidth: columns[index],
        heading: heading,
      ),
    );
  }
  return height;
}

double _totalHeight(String total, List<double> columns) {
  final cells = ['', '', 'TOTAL', '', '', total];
  var height = DocuTrackerPurchaseMetrics.cellMinHeight;
  for (var index = 0; index < cells.length; index++) {
    height = math.max(
      height,
      DocuTrackerPurchaseMetrics.cellHeight(
        cells[index],
        columnWidth: columns[index],
        heading: index == 2 || index == 5,
      ),
    );
  }
  return height;
}

List<List<String>> _splitRow(
  List<String> row,
  List<double> columns,
  double maxHeight,
) {
  final full = _rowHeight(row, columns, heading: false);
  if (full <= maxHeight + 0.01 || row.length < 3) return [row];
  final description = row[2];
  final ranges = _lineRanges(
    description,
    DocuTrackerPurchaseMetrics.cellStyle(heading: false),
    math.max(1.0, columns[2] - DocuTrackerPurchaseMetrics.cellPadH * 2),
  );
  if (ranges.length <= 1) return [row];
  final chunks = <List<String>>[];
  var start = 0;
  var end = ranges.first.end;
  void emit(int from, int to, {required bool first}) {
    final cells = <String>[
      row[0],
      first ? row.elementAt(1) : '',
      description.substring(from, to),
      first && row.length > 3 ? row[3] : '',
      first && row.length > 4 ? row[4] : '',
      first && row.length > 5 ? row[5] : '',
    ];
    chunks.add(cells);
  }

  for (var index = 1; index < ranges.length; index++) {
    final candidate = description.substring(start, ranges[index].end);
    final height = DocuTrackerPurchaseMetrics.cellHeight(
      candidate,
      columnWidth: columns[2],
      heading: false,
    );
    if (height > maxHeight && end > start) {
      emit(start, end, first: chunks.isEmpty);
      start = end;
    }
    end = ranges[index].end;
  }
  if (start < description.length) {
    emit(start, description.length, first: chunks.isEmpty);
  }
  return chunks.isEmpty ? [row] : chunks;
}

List<({int start, int end})> _lineRanges(
  String text,
  TextStyle style,
  double width,
) {
  if (text.isEmpty) return const [(start: 0, end: 0)];
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final ranges = <({int start, int end})>[];
  var offset = 0;
  while (offset < text.length) {
    final range = painter.getLineBoundary(TextPosition(offset: offset));
    if (range.end <= offset) {
      ranges.add((start: offset, end: text.length));
      break;
    }
    ranges.add((start: range.start, end: range.end));
    offset = range.end;
  }
  return ranges;
}

List<PurchaseParagraph> _explode(
  List<PurchaseParagraph> source,
  double maxHeight,
  double width,
) {
  final exploded = <PurchaseParagraph>[];
  for (final paragraph in source) {
    if (paragraph.height <= maxHeight + 0.01 || paragraph.plain.isEmpty) {
      exploded.add(paragraph);
      continue;
    }
    final style = paragraph.spans.first.style;
    final ranges = _lineRanges(paragraph.plain, style, width);
    if (ranges.length <= 1) {
      exploded.add(paragraph);
      continue;
    }
    for (final range in ranges) {
      final text = paragraph.plain.substring(range.start, range.end);
      exploded.add(
        _measure(
          [
            PurchaseSpan(
              text,
              bold: paragraph.spans.first.bold,
              fontSize: paragraph.spans.first.fontSize,
            ),
          ],
          paragraph.align,
          paragraph.emptyFontSize,
          width,
        ),
      );
    }
  }
  return exploded;
}

List<PurchaseParagraph> _paragraphs(
  List<Map<String, dynamic>> ops,
  double width,
) {
  final paragraphs = <PurchaseParagraph>[];
  final runs = <PurchaseSpan>[];
  void flush(Object? alignName, double newlineSize) {
    paragraphs.add(
      _measure(
        List<PurchaseSpan>.from(runs),
        switch (alignName) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          'justify' => TextAlign.justify,
          _ => TextAlign.left,
        },
        newlineSize,
        width,
      ),
    );
    runs.clear();
  }

  for (final op in ops) {
    final insert = op['insert'];
    if (insert is! String) continue;
    final attributes = op['attributes'];
    final bold = attributes is Map && attributes['bold'] == true;
    final size = attributes is Map ? attributes['size'] : null;
    final fontSize = size == null ? 16.0 : (double.tryParse('$size') ?? 16.0);
    final align = attributes is Map ? attributes['align'] : null;
    final pieces = insert.split('\n');
    for (var index = 0; index < pieces.length; index++) {
      if (pieces[index].isNotEmpty) {
        runs.add(PurchaseSpan(pieces[index], bold: bold, fontSize: fontSize));
      }
      if (index < pieces.length - 1) flush(align, fontSize);
    }
  }
  if (runs.isNotEmpty) {
    flush(null, runs.map((run) => run.fontSize).reduce(math.max));
  }
  return paragraphs;
}

PurchaseParagraph _measure(
  List<PurchaseSpan> spans,
  TextAlign align,
  double emptyFontSize,
  double width,
) {
  if (spans.isEmpty) {
    return PurchaseParagraph(
      spans: const [],
      align: align,
      emptyFontSize: emptyFontSize,
      height: emptyFontSize * 1.15,
    );
  }
  final painter = TextPainter(
    text: TextSpan(
      children: [
        for (final span in spans) TextSpan(text: span.text, style: span.style),
      ],
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  return PurchaseParagraph(
    spans: List<PurchaseSpan>.unmodifiable(spans),
    align: align,
    emptyFontSize: emptyFontSize,
    height: painter.height,
  );
}
