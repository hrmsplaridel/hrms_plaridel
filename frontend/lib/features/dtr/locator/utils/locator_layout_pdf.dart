import 'dart:typed_data';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/locator_print_layout.dart';
import '../models/locator_request_type.dart';
import 'locator_form_signatories.dart';

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

Future<Uint8List> buildLocatorLayoutPdf({
  required LocatorPrintLayout layout,
  required Map<String, dynamic> form,
  required LocatorFormSignatories signatories,
}) async {
  final error = layout.validate();
  if (error != null) throw FormatException(error);
  final doc = pw.Document();
  final overflow = <String, String>{};
  final format = PdfPageFormat(layout.pageWidth, layout.pageHeight);
  final font = pw.Font.helvetica(), boldFont = pw.Font.helveticaBold();
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

  pw.Widget itemWidget(LocatorPrintElement item, pw.Context context) {
    final chosen = item.bold ? boldFont : font;
    if (item.kind == 'line') {
      return pw.Center(child: pw.Container(height: 1, color: PdfColors.black));
    }
    if (item.kind == 'signature') {
      final person = switch (item.source) {
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
            height: 14,
            child: name.isEmpty
                ? null
                : pw.FittedBox(
                    child: pw.Text(
                      name,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: item.fontSize.clamp(8, 12),
                      ),
                    ),
                  ),
          ),
          pw.Divider(height: 3, thickness: .7),
          pw.Text(
            item.label.isNotEmpty ? item.label : person.positionTitle,
            textAlign: alignment(item.align),
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(font: font, fontSize: 8),
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
              style: pw.TextStyle(font: boldFont, fontSize: 8),
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
        !layout.elements.any((e) => e.kind == 'field' && e.source == source)) {
      overflow[source] = '${field['label']}: $value';
    }
  }
  if (overflow.isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
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
          for (final value in overflow.values)
            for (var offset = 0; offset < value.length; offset += 500)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  value.substring(
                    offset,
                    (offset + 500).clamp(0, value.length),
                  ),
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
        ],
      ),
    );
  }
  return doc.save();
}
