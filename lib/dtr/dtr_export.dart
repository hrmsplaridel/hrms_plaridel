import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/time_record.dart';

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _dayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// DTR export to PDF, Excel, and Word (HTML) — single page, matches official form.
class DtrExport {
  DtrExport._();

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute;
    final ampm = h >= 12 ? 'pm' : 'am';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}$ampm';
  }

  static String _formatDateWithDay(DateTime d) {
    return '${d.day} ${_dayNames[d.weekday - 1]}';
  }

  static String _getDisplayValue(TimeRecord? r, bool isWeekend) {
    if (r == null) return isWeekend ? '' : 'ABSENT';
    if (r.timeIn == null) return 'ABSENT';
    final status = r.status;
    if (status != null && status.isNotEmpty) {
      if (status == 'absent') return 'ABSENT';
      if (status == 'on_leave') return 'On Leave';
      if (status == 'holiday') return 'Holiday';
    }
    return ''; // Show times in AM/PM columns
  }

  static const String _noon = '12:00pm';
  static const String _pmIn = '01:00pm';

  /// Returns (hours, minutes) of undertime. Absent = 8h 0m. Weekend / Holiday = 0.
  static (int, int) _computeUndertime(
    TimeRecord? r,
    DateTime dt,
    bool isWeekend,
  ) {
    if (isWeekend) return (0, 0);
    if (r != null && r.status == 'holiday') return (0, 0);
    if (r == null || r.timeIn == null) return (8, 0);
    final actual = r.totalHours ?? 0;
    final undertime = (8.0 - actual).clamp(0.0, 8.0);
    final h = undertime.floor();
    final m = ((undertime - h) * 60).round();
    return (h, m);
  }

  static double _computeEquivalentDay(int totalUndertimeMinutes) {
    return totalUndertimeMinutes / (8 * 60);
  }

  static pw.Widget _buildFooter(double equivalentDay) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Equivalent Day (deduction, 8 hr/day): ${equivalentDay.toStringAsFixed(3)}',
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.',
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Verified as to the prescribed office hours.',
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'HON. GADWIN E. HANDUMON',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Municipal Mayor', style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'MARCELO B. CAÑARES',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Human Resource Mgt. and Dev\'t. Officer',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Text('01/13 ON FIELD', style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ],
    );
  }

  /// Generate PDF bytes — single page, matches official DTR form design.
  static Future<Uint8List> generatePdf({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) async {
    var totalUndertimeMin = 0;
    final rows = <pw.TableRow>[];
    const fs = 5.5;

    // Two-row header (matches reference DTR — grey background, bold, centered)
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Date', fs, bold: true, center: true),
          _cell('AM', fs, bold: true, center: true),
          _cell('AM', fs, bold: true, center: true),
          _cell('PM', fs, bold: true, center: true),
          _cell('PM', fs, bold: true, center: true),
          _cell('UNDERTIME', fs, bold: true, center: true),
          _cell('UNDERTIME', fs, bold: true, center: true),
        ],
      ),
    );
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Date', fs, bold: true, center: true),
          _cell('IN', fs, bold: true, center: true),
          _cell('OUT', fs, bold: true, center: true),
          _cell('IN', fs, bold: true, center: true),
          _cell('OUT', fs, bold: true, center: true),
          _cell('Hours', fs, bold: true, center: true),
          _cell('Min', fs, bold: true, center: true),
        ],
      ),
    );

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(rec, dt, isWeekend);
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;

      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = displayVal.isEmpty && rec != null;

      final amInStr = showTimes && rec.timeIn != null
          ? _formatTime(rec.timeIn)
          : (displayVal == 'ABSENT' ? 'ABSENT' : '');
      final amOutStr = showTimes ? _noon : '';
      final pmInStr = showTimes ? _pmIn : '';
      final pmOutStr = showTimes && rec.timeOut != null
          ? _formatTime(rec.timeOut)
          : '';

      rows.add(
        pw.TableRow(
          children: [
            _cell(_formatDateWithDay(dt), fs),
            _cell(amInStr, fs, center: true),
            _cell(amOutStr, fs, center: true),
            _cell(pmInStr, fs, center: true),
            _cell(pmOutStr, fs, center: true),
            _cell(isWeekend ? '' : '$uh', fs, right: true),
            _cell(isWeekend ? '' : '$um', fs, right: true),
          ],
        ),
      );
    }

    // Total undertime row
    final totalH = totalUndertimeMin ~/ 60;
    final totalM = totalUndertimeMin % 60;
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Total Undertime', fs, bold: true),
          _cell('', fs),
          _cell('', fs),
          _cell('', fs),
          _cell('', fs),
          _cell('$totalH', fs, bold: true, right: true),
          _cell('$totalM', fs, bold: true, right: true),
        ],
      ),
    );

    final equivalentDay = _computeEquivalentDay(totalUndertimeMin);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              'DAILY TIME RECORD',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),
            pw.RichText(
              textAlign: pw.TextAlign.center,
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'Name : ',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: employeeName.toUpperCase(),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 2),
            pw.RichText(
              textAlign: pw.TextAlign.center,
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'PERIOD : ',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: '${_months[month - 1]} 1-${end.day}, $year',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 2),
            pw.RichText(
              textAlign: pw.TextAlign.center,
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'Official Hours: ',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: '8:00AM-12:00PM 01:00PM-5:00PM',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Transform.scale(
              scale: 0.75,
              alignment: pw.Alignment.topLeft,
              child: pw.Table(
                border: pw.TableBorder.all(
                  width: 0.5,
                  color: PdfColors.grey800,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  1: const pw.FlexColumnWidth(1.0),
                  2: const pw.FlexColumnWidth(1.0),
                  3: const pw.FlexColumnWidth(1.0),
                  4: const pw.FlexColumnWidth(1.0),
                  5: const pw.FlexColumnWidth(0.6),
                  6: const pw.FlexColumnWidth(0.6),
                },
                children: rows,
              ),
            ),
            pw.SizedBox(height: 6),
            _buildFooter(equivalentDay),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _cell(
    String text,
    double fs, {
    bool bold = false,
    bool center = false,
    bool right = false,
  }) {
    pw.TextAlign? align;
    if (center) align = pw.TextAlign.center;
    if (right) align = pw.TextAlign.right;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fs,
          fontWeight: bold ? pw.FontWeight.bold : null,
        ),
        textAlign: align,
      ),
    );
  }

  /// Generate Excel bytes — matches reference DTR form design.
  static Future<Uint8List> generateExcel({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) async {
    var totalUndertimeMin = 0;
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultName, 'DTR');
    final sheet = excel['DTR'];
    final thinBorder = Border(borderStyle: BorderStyle.Thin);
    final greyBg = ExcelColor.fromHexString(
      'FFD3D3D3',
    ); // Light grey like reference DTR
    final headerStyle = CellStyle(
      fontSize: 7,
      bold: true,
      backgroundColorHex: greyBg,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      horizontalAlign: HorizontalAlign.Center,
    );
    final cellStyle = CellStyle(
      fontSize: 6,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final cellStyleCenter = CellStyle(
      fontSize: 6,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      horizontalAlign: HorizontalAlign.Center,
    );
    final cellStyleRight = CellStyle(
      fontSize: 6,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      horizontalAlign: HorizontalAlign.Right,
    );
    final totalStyle = CellStyle(
      fontSize: 6,
      bold: true,
      backgroundColorHex: greyBg,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final totalStyleRight = CellStyle(
      fontSize: 6,
      bold: true,
      backgroundColorHex: greyBg,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      horizontalAlign: HorizontalAlign.Right,
    );

    // Column widths to match reference DTR
    for (var c = 0; c <= 6; c++) {
      sheet.setColumnWidth(c, c == 0 ? 12.0 : (c <= 4 ? 10.0 : 6.0));
    }

    int row = 0;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'DAILY TIME RECORD',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      fontSize: 11,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Name : ${employeeName.toUpperCase()}',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
    );
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'PERIOD : ${_months[month - 1]} 1-${end.day}, $year',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
    );
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Official Hours: 8:00AM-12:00PM 01:00PM-5:00PM',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
    );
    row += 2;

    // Two-row header (matches official DTR form)
    final headerRow1 = [
      'Date',
      'AM',
      'AM',
      'PM',
      'PM',
      'UNDERTIME',
      'UNDERTIME',
    ];
    for (var c = 0; c <= 6; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
          .value = TextCellValue(
        headerRow1[c],
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
              .cellStyle =
          headerStyle;
    }
    row++;
    final headerRow2 = ['Date', 'IN', 'OUT', 'IN', 'OUT', 'Hours', 'Min'];
    for (var c = 0; c <= 6; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
          .value = TextCellValue(
        headerRow2[c],
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
              .cellStyle =
          headerStyle;
    }
    row++;

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(rec, dt, isWeekend);
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;

      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = displayVal.isEmpty && rec != null;
      final amInStr = showTimes && rec.timeIn != null
          ? _formatTime(rec.timeIn)
          : (displayVal == 'ABSENT' ? 'ABSENT' : '');
      final amOutStr = showTimes ? _noon : '';
      final pmInStr = showTimes ? _pmIn : '';
      final pmOutStr = showTimes && rec.timeOut != null
          ? _formatTime(rec.timeOut)
          : '';

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        _formatDateWithDay(dt),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(
        amInStr,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(
        amOutStr,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = TextCellValue(
        pmInStr,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = TextCellValue(
        pmOutStr,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = TextCellValue(
        isWeekend ? '' : '$uh',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = TextCellValue(
        isWeekend ? '' : '$um',
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .cellStyle =
          cellStyle;
      for (var c = 1; c <= 4; c++) {
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
                .cellStyle =
            cellStyleCenter;
      }
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
              .cellStyle =
          cellStyleRight;
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
              .cellStyle =
          cellStyleRight;
      row++;
    }

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Total Undertime',
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
        .value = TextCellValue(
      '${totalUndertimeMin ~/ 60}',
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
        .value = TextCellValue(
      '${totalUndertimeMin % 60}',
    );
    for (var c = 0; c <= 4; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
              .cellStyle =
          totalStyle;
    }
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .cellStyle =
        totalStyleRight;
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
            .cellStyle =
        totalStyleRight;
    row += 2;

    final equivalentDay = _computeEquivalentDay(totalUndertimeMin);
    final footerCenterStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Equivalent Day (deduction, 8 hr/day): ${equivalentDay.toStringAsFixed(3)}',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        footerCenterStyle;
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        footerCenterStyle;
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Verified as to the prescribed office hours.',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        footerCenterStyle;
    row += 2;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'HON. GADWIN E. HANDUMON',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      fontSize: 9,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Municipal Mayor',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        footerCenterStyle;
    row += 2;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'MARCELO B. CAÑARES',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      fontSize: 9,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'Human Resource Mgt. and Dev\'t. Officer',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        footerCenterStyle;
    row++;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      '01/13 ON FIELD',
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        footerCenterStyle;

    final bytes = excel.encode();
    if (bytes == null) throw StateError('Excel encode failed');
    return Uint8List.fromList(bytes);
  }

  /// Generate HTML (Word-compatible) — matches reference DTR form design.
  static String generateWordHtml({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) {
    var totalUndertimeMin = 0;
    final sb = StringBuffer();
    sb.writeln(
      '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>DTR</title>',
    );
    sb.writeln(
      '<style>@page{size:letter;margin:0.4in;}body{font-family:Arial,sans-serif;font-size:7pt;margin:12px;line-height:1.2;}',
    );
    sb.writeln(
      '.dtr-table{border-collapse:collapse;width:100%;font-size:6.5pt;}',
    );
    sb.writeln(
      '.dtr-table th,.dtr-table td{border:1px solid #333;padding:2px 4px;}',
    );
    sb.writeln(
      '.dtr-table th{background:#d3d3d3;font-weight:bold;text-align:center;}',
    );
    sb.writeln('.dtr-table .total-row{background:#e8e8e8;font-weight:bold;}');
    sb.writeln('.center{text-align:center;}.right{text-align:right;}');
    sb.writeln(
      'h2{margin:4px 0 8px;font-size:11pt;text-align:center;font-weight:bold;}</style></head><body>',
    );
    sb.writeln('<h2>DAILY TIME RECORD</h2>');
    sb.writeln(
      '<div style="text-align:center;font-size:10pt;line-height:1.4;">',
    );
    sb.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Name :</strong> ${employeeName.toUpperCase()}</p>',
    );
    sb.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>PERIOD :</strong> ${_months[month - 1]} 1-${end.day}, $year</p>',
    );
    sb.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Official Hours:</strong> 8:00AM-12:00PM 01:00PM-5:00PM</p>',
    );
    sb.writeln('</div>');
    sb.writeln('<table class="dtr-table">');
    sb.writeln(
      '<thead><tr><th rowspan="2">Date</th><th colspan="2">AM</th><th colspan="2">PM</th><th colspan="2">UNDERTIME</th></tr>',
    );
    sb.writeln(
      '<tr><th>IN</th><th>OUT</th><th>IN</th><th>OUT</th><th>Hours</th><th>Min</th></tr></thead><tbody>',
    );

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(rec, dt, isWeekend);
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;
      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = displayVal.isEmpty && rec != null;
      final amIn = showTimes && rec.timeIn != null
          ? _formatTime(rec.timeIn)
          : (displayVal == 'ABSENT' ? 'ABSENT' : '');
      final amOut = showTimes ? _noon : '';
      final pmIn = showTimes ? _pmIn : '';
      final pmOut = showTimes && rec.timeOut != null
          ? _formatTime(rec.timeOut)
          : '';
      sb.writeln(
        '<tr><td>${_formatDateWithDay(dt)}</td><td class="center">$amIn</td><td class="center">$amOut</td><td class="center">$pmIn</td><td class="center">$pmOut</td><td class="right">${isWeekend ? '' : uh}</td><td class="right">${isWeekend ? '' : um}</td></tr>',
      );
    }

    final totalH = totalUndertimeMin ~/ 60;
    final totalM = totalUndertimeMin % 60;
    sb.writeln(
      '<tr class="total-row"><td>Total Undertime</td><td></td><td></td><td></td><td></td><td class="right">$totalH</td><td class="right">$totalM</td></tr>',
    );
    sb.writeln('</tbody></table>');

    final equivalentDay = _computeEquivalentDay(totalUndertimeMin);
    sb.writeln(
      '<div style="text-align:center;font-size:10pt;margin-top:12px;line-height:1.4;">',
    );
    sb.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">Equivalent Day (deduction, 8 hr/day): ${equivalentDay.toStringAsFixed(3)}</p>',
    );
    sb.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.</p>',
    );
    sb.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">Verified as to the prescribed office hours.</p>',
    );
    sb.writeln('</div>');
    sb.writeln(
      '<div style="text-align:center;margin-top:16px;font-size:10pt;line-height:1.4;">',
    );
    sb.writeln(
      '<p style="margin:0 0 16px;"><strong>HON. GADWIN E. HANDUMON</strong><br>Municipal Mayor</p>',
    );
    sb.writeln(
      '<p style="margin:0;"><strong>MARCELO B. CAÑARES</strong><br>Human Resource Mgt. and Dev\'t. Officer<br>01/13 ON FIELD</p>',
    );
    sb.writeln('</div>');
    sb.writeln('</body></html>');
    return sb.toString();
  }
}
