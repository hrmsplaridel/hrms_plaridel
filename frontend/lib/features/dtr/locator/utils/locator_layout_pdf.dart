import 'dart:typed_data';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/locator_print_layout.dart';
import '../models/locator_request_type.dart';
import 'locator_form_signatories.dart';
import 'print_layout_fonts.dart';

Map<String, dynamic> locatorLayoutSample(LocatorRequestType type) => {
  'employee_name': 'Sample Employee',
  'slip_date': '2026-10-13',
  'request_type_label': type.label,
  'office': 'Sample ${type.locationLabel}',
  'reason': 'Sample purpose or reason',
  'am_in': true,
  'am_out': true,
  'pm_in': true,
  'pm_out': true,
  'employee_detail_schema_snapshot': type.employeeDetailSchema
      .map((f) => f.toJson())
      .toList(),
  'additional_details': {
    for (final field in type.employeeDetailSchema)
      field.key: switch (field.type.value) {
        'date' => '2026-10-13',
        'number' => 1,
        'boolean' => true,
        'select' => field.options.firstOrNull ?? 'Sample',
        _ => 'Sample ${field.label}',
      },
  },
};

String locatorLayoutValue(String source, Map<String, dynamic> form) {
  final custom = Map<String, dynamic>.from(
    form['additional_details'] as Map? ?? {},
  );
  final dynamic value = source.startsWith('custom:')
      ? custom[source.substring(7)]
      : switch (source) {
          'date' => form['slip_date'],
          'request_type' => form['request_type_label'],
          'time_segments' => [
            for (final slot in {
              'am_in': 'AM IN',
              'am_out': 'AM OUT',
              'pm_in': 'PM IN',
              'pm_out': 'PM OUT',
            }.entries)
              if (form[slot.key] == true) slot.value,
          ].join(', '),
          _ => form[source],
        };
  return value is bool ? (value ? 'Yes' : 'No') : value?.toString() ?? '';
}

String locatorSignatureCaption(
  LocatorPrintElement item,
  LocatorPrintedSignatory person,
) {
  if (item.label.trim().isNotEmpty) {
    return item.label.trim();
  }
  if (person.positionTitle.trim().isNotEmpty) {
    return person.positionTitle.trim();
  }
  return switch (item.source) {
    'applicant' => 'Employee',
    'department_head' => 'Head of Office',
    'certification_officer' => 'Certification officer',
    _ => 'Final approver',
  };
}

LocatorPrintedSignatory locatorLayoutSampleSignatory(
  LocatorRequestType type,
  String source,
) => LocatorPrintedSignatory(
  name: 'Sample signer',
  positionTitle: switch (source) {
    'applicant' => 'Sample employee position',
    'department_head' => 'Department Head',
    _ => type.approvalRoute == 'hr' ? 'HR Officer' : 'Municipal Mayor',
  },
);

Future<Uint8List> buildLocatorLayoutPdf({
  required LocatorPrintLayout layout,
  required Map<String, dynamic> form,
  required LocatorFormSignatories signatories,
  Map<String, LocatorPrintedSignatory> extraSignatories = const {},
  pw.Font? regularFont,
  pw.Font? strongFont,
}) async {
  final error = layout.validate();
  if (error != null) throw FormatException(error);
  final requestedFamilies = {
    if (layout.fontFamily != null) layout.fontFamily!,
    for (final item in layout.elements)
      if (item.fontFamily != null) item.fontFamily!,
  };
  final fonts = <String, (pw.Font, pw.Font)>{};
  for (final family in requestedFamilies) {
    fonts[family] = await loadPrintLayoutFonts(family);
  }
  final defaultFonts =
      fonts[layout.fontFamily] ??
      (
        regularFont ?? pw.Font.helvetica(),
        strongFont ?? pw.Font.helveticaBold(),
      );
  final font = defaultFonts.$1, boldFont = defaultFonts.$2;
  pw.Font itemFont(LocatorPrintElement item, bool bold) {
    final pair = fonts[item.fontFamily ?? layout.fontFamily] ?? defaultFonts;
    return bold ? pair.$2 : pair.$1;
  }

  final doc = pw.Document(
    theme:
        layout.fontFamily != null || regularFont != null || strongFont != null
        ? pw.ThemeData.withFont(base: font, bold: boldFont)
        : null,
  );
  final overflow = <String, String>{}, overflowFonts = <String, pw.Font>{};
  final format = PdfPageFormat(layout.pageWidth, layout.pageHeight);
  pw.TextAlign alignment(String value) => switch (value) {
    'center' => pw.TextAlign.center,
    'right' => pw.TextAlign.right,
    _ => pw.TextAlign.left,
  };
  List<String> wrap(
    String value,
    double width,
    double size,
    pw.Context context,
    pw.Font chosen,
  ) {
    final metrics = chosen.getFont(context);
    final rows = <String>[];
    var row = '';
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (char == '\n') {
        rows.add(row);
        row = '';
        continue;
      }
      if (row.isNotEmpty &&
          metrics.stringMetrics('$row$char').width * size > width) {
        rows.add(row);
        row = '';
      }
      row += char;
    }
    if (row.isNotEmpty) rows.add(row);
    return rows;
  }

  pw.Widget tableCell(
    LocatorPrintElement item,
    int row,
    int column,
    double width,
    double height,
    pw.Context context,
  ) {
    final cell = item.cells[row][column];
    final chosen = itemFont(item, item.bold || (item.headerRow && row == 0));
    final value = cell.kind == 'field'
        ? locatorLayoutValue(cell.source, form)
        : cell.text;
    final count = ((height - 8) / (item.fontSize * 1.5)).floor().clamp(0, 100);
    final lines = wrap(value, width - 8, item.fontSize, context, chosen);
    final continued = lines.length > count;
    if (continued && value.isNotEmpty) {
      final heading =
          item.headerRow && row > 0 && item.cells[0][column].kind == 'text'
          ? item.cells[0][column].text
          : '';
      overflowFonts['table:${item.id}:$row:$column'] = chosen;
      overflow['table:${item.id}:$row:$column'] =
          '${heading.isEmpty ? 'Table row ${row + 1}, column ${column + 1}' : heading}: $value';
    }
    final shown = count == 0
        ? ''
        : continued
        ? '${lines.take((count - 1).clamp(0, count)).join('\n')}\nSee continuation'
              .trim()
        : lines.join('\n');
    return pw.SizedBox(
      width: width,
      height: height,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          color: item.headerRow && row == 0 ? PdfColors.grey100 : null,
          border: item.borders ? pw.Border.all(width: .5) : null,
        ),
        child: pw.Text(
          shown,
          textAlign: alignment(item.align),
          softWrap: false,
          maxLines: count.clamp(1, 100),
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(font: chosen, fontSize: item.fontSize),
        ),
      ),
    );
  }

  pw.Widget itemWidget(LocatorPrintElement item, pw.Context context) {
    final chosen = itemFont(item, item.bold),
        itemBold = itemFont(item, true),
        itemRegular = itemFont(item, false);
    if (item.kind == 'table') {
      final total = item.columnWidths.fold(0.0, (a, b) => a + b);
      final rowHeight = item.height / item.cells.length;
      return pw.Column(
        children: [
          for (var r = 0; r < item.cells.length; r++)
            pw.SizedBox(
              height: rowHeight,
              child: pw.Row(
                children: [
                  for (var c = 0; c < item.cells[r].length; c++)
                    tableCell(
                      item,
                      r,
                      c,
                      item.width * item.columnWidths[c] / total,
                      rowHeight,
                      context,
                    ),
                ],
              ),
            ),
        ],
      );
    }
    if (item.kind == 'line') {
      return pw.Center(child: pw.Container(height: 1, color: PdfColors.black));
    }
    if (item.kind == 'signature') {
      final styled = item.fontFamily != null || layout.fontFamily != null;
      final nameSize = styled
          ? item.fontSize
          : item.fontSize.clamp(8, 12).toDouble();
      final captionSize = styled
          ? (item.fontSize * .75).clamp(6, 54).toDouble()
          : 8.0;
      final person =
          extraSignatories[item.source] ??
          switch (item.source) {
            'applicant' => signatories.applicant,
            'department_head' => signatories.departmentHead,
            _ => signatories.finalApprover,
          };
      final name = person.name.isEmpty && item.source == 'applicant'
          ? form['employee_name']?.toString() ?? ''
          : person.name;
      return pw.Column(
        children: [
          pw.Expanded(
            child: person.signatureBytes == null
                ? pw.SizedBox()
                : pw.Image(
                    pw.MemoryImage(person.signatureBytes!),
                    fit: pw.BoxFit.contain,
                  ),
          ),
          pw.SizedBox(
            height: styled ? nameSize * 1.2 : 14,
            child: name.isEmpty
                ? null
                : pw.FittedBox(
                    child: pw.Text(
                      name,
                      style: pw.TextStyle(font: itemBold, fontSize: nameSize),
                    ),
                  ),
          ),
          pw.Divider(height: 3, thickness: .7),
          pw.Text(
            locatorSignatureCaption(item, person),
            textAlign: alignment(item.align),
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(font: itemRegular, fontSize: captionSize),
          ),
        ],
      );
    }
    if (item.kind == 'text') {
      return pw.Text(
        item.text,
        textAlign: alignment(item.align),
        maxLines: (item.height / (item.fontSize * 1.5)).floor().clamp(1, 100),
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(font: chosen, fontSize: item.fontSize),
      );
    }
    final value = locatorLayoutValue(item.source, form);
    final labelHeight = item.showLabel && item.label.isNotEmpty ? 12.0 : 0.0;
    final available = (item.height - labelHeight - 2).clamp(0, item.height);
    final count = (available / (item.fontSize * 1.5)).floor();
    final rows = wrap(value, item.width, item.fontSize, context, chosen);
    final hasOverflow = rows.length > count;
    if (hasOverflow && value.isNotEmpty) {
      overflowFonts[item.source] = chosen;
      overflow[item.source] =
          '${item.label.isEmpty ? item.source : item.label}: $value';
    }
    final visible = count <= 0
        ? ''
        : hasOverflow
        ? '${rows.take((count - 1).clamp(0, count)).join('\n')}\nSee continuation'
              .trim()
        : rows.join('\n');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (labelHeight > 0)
          pw.SizedBox(
            height: labelHeight,
            child: pw.Text(
              item.label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(font: itemBold, fontSize: 8),
            ),
          ),
        pw.Expanded(
          child: pw.Text(
            visible,
            softWrap: false,
            textAlign: alignment(item.align),
            maxLines: count.clamp(1, 100),
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(font: chosen, fontSize: item.fontSize),
          ),
        ),
      ],
    );
  }

  final measureContext = pw.Context(document: doc.document);
  final widgets = {
    for (final item in layout.elements)
      item.id: itemWidget(item, measureContext),
  };
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.SizedBox(
        width: layout.pageWidth,
        height: layout.pageHeight,
        child: pw.Stack(
          children: [
            for (final item in layout.elements)
              pw.Positioned(
                left: item.x,
                top: item.y,
                child: pw.SizedBox(
                  width: item.width,
                  height: item.height,
                  child: widgets[item.id]!,
                ),
              ),
          ],
        ),
      ),
    ),
  );
  // Unplaced custom answers remain available in the printout as well.
  for (final field
      in (form['employee_detail_schema_snapshot'] as List? ?? [])
          .whereType<Map>()) {
    final source = 'custom:${field['key']}';
    final value = locatorLayoutValue(source, form);
    if (value.isNotEmpty &&
        !layout.elements.any(
          (e) =>
              (e.kind == 'field' && e.source == source) ||
              (e.kind == 'table' &&
                  e.cells.any(
                    (row) => row.any(
                      (cell) => cell.kind == 'field' && cell.source == source,
                    ),
                  )),
        )) {
      overflow[source] = '${field['label']}: $value';
    }
  }
  if (overflow.isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat:
            layout.paperSize != 'a4' ||
                !layout.margins.isEmpty ||
                layout.fontFamily != null
            ? format
            : PdfPageFormat.a4,
        margin:
            layout.paperSize != 'a4' ||
                !layout.margins.isEmpty ||
                layout.fontFamily != null
            ? pw.EdgeInsets.fromLTRB(
                layout.margins.left,
                layout.margins.top,
                layout.margins.right,
                layout.margins.bottom,
              )
            : null,
        maxPages: 100,
        build: (_) => [
          pw.Text(
            '${form['request_type_label'] ?? 'Locator'} - continuation',
            style: pw.TextStyle(font: boldFont, fontSize: 16),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '${form['employee_name'] ?? ''} / ${form['slip_date'] ?? ''}',
          ),
          pw.SizedBox(height: 16),
          for (final entry in overflow.entries)
            for (var offset = 0; offset < entry.value.length; offset += 500)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  entry.value.substring(
                    offset,
                    (offset + 500).clamp(0, entry.value.length),
                  ),
                  style: pw.TextStyle(
                    font: overflowFonts[entry.key] ?? font,
                    fontSize: layout.defaultFontSize,
                  ),
                ),
              ),
        ],
      ),
    );
  }
  return doc.save();
}
