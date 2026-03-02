import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/time_record.dart';

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
    }
    return ''; // Show times in AM/PM columns
  }

  static const String _noon = '12:00pm';
  static const String _pmIn = '01:00pm';

  /// Returns (hours, minutes) of undertime. Absent = 8h 0m. Weekend = 0.
  static (int, int) _computeUndertime(TimeRecord? r, DateTime dt, bool isWeekend) {
    if (isWeekend) return (0, 0);
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
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                'I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.',
                style: const pw.TextStyle(fontSize: 5),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Equivalent Day (deduction, 8 hr/day): ${equivalentDay.toStringAsFixed(3)}',
                    style: const pw.TextStyle(fontSize: 6)),
                pw.SizedBox(height: 2),
                pw.Text('Verified as to the prescribed office hours.', style: const pw.TextStyle(fontSize: 5)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Text('HON. GADWIN E. HANDUMON', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
              pw.Text('Municipal Mayor', style: const pw.TextStyle(fontSize: 5)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Text('MARCELO B. CAÑARES', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
              pw.Text('Human Resource Mgt. and Dev\'t. Officer', style: const pw.TextStyle(fontSize: 5)),
              pw.Text('01/13 ON FIELD', style: const pw.TextStyle(fontSize: 5)),
            ]),
          ],
        ),
      ],
    );
  }

  /// Generate PDF bytes — single page, matches official form.
  static Future<Uint8List> generatePdf({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) async {
    var totalUndertimeMin = 0;
    final rows = <pw.TableRow>[];
    const fs = 5.0;

    // Two-row header (matches official DTR form)
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Date', fs, bold: true),
          _cell('AM', fs, bold: true),
          _cell('AM', fs, bold: true),
          _cell('PM', fs, bold: true),
          _cell('PM', fs, bold: true),
          _cell('UNDERTIME', fs, bold: true),
          _cell('UNDERTIME', fs, bold: true),
        ],
      ),
    );
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Date', fs, bold: true),
          _cell('IN', fs, bold: true),
          _cell('OUT', fs, bold: true),
          _cell('IN', fs, bold: true),
          _cell('OUT', fs, bold: true),
          _cell('Hours', fs, bold: true),
          _cell('Min', fs, bold: true),
        ],
      ),
    );

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(rec, dt, isWeekend);
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;

      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = displayVal.isEmpty && rec != null;

      final amInStr = showTimes && rec.timeIn != null ? _formatTime(rec.timeIn) : (displayVal == 'ABSENT' ? 'ABSENT' : '');
      final amOutStr = showTimes ? _noon : '';
      final pmInStr = showTimes ? _pmIn : '';
      final pmOutStr = showTimes && rec.timeOut != null ? _formatTime(rec.timeOut) : '';

      rows.add(
        pw.TableRow(
          children: [
            _cell(_formatDateWithDay(dt), fs),
            _cell(amInStr, fs),
            _cell(amOutStr, fs),
            _cell(pmInStr, fs),
            _cell(pmOutStr, fs),
            _cell(isWeekend ? '' : '$uh', fs),
            _cell(isWeekend ? '' : '$um', fs),
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
          _cell('$totalH', fs, bold: true),
          _cell('$totalM', fs, bold: true),
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
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('DAILY TIME RECORD', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 2),
            pw.Text('Name: ${employeeName.toUpperCase()}', style: const pw.TextStyle(fontSize: 7)),
            pw.Text('PERIOD: ${_months[month - 1]} 1-${end.day}, $year', style: const pw.TextStyle(fontSize: 7)),
            pw.Text('Official Hours: 8:00AM-12:00PM 01:00PM-5:00PM', style: const pw.TextStyle(fontSize: 6)),
            pw.SizedBox(height: 4),
            pw.Transform.scale(
              scale: 0.62,
              alignment: pw.Alignment.topLeft,
              child: pw.Table(
                border: pw.TableBorder.all(width: 0.4),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.8),
                  1: const pw.FlexColumnWidth(0.7),
                  2: const pw.FlexColumnWidth(0.7),
                  3: const pw.FlexColumnWidth(0.7),
                  4: const pw.FlexColumnWidth(0.7),
                  5: const pw.FlexColumnWidth(0.4),
                  6: const pw.FlexColumnWidth(0.4),
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

  static pw.Widget _cell(String text, double fs, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(1),
      child: pw.Text(text, style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null)),
    );
  }

  /// Generate Excel bytes — single page format.
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
    final headerStyle = CellStyle(fontSize: 7, bold: true);
    final cellStyle = CellStyle(fontSize: 6);

    int row = 0;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('DAILY TIME RECORD');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = headerStyle;
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Name: ${employeeName.toUpperCase()}');
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('PERIOD: ${_months[month - 1]} 1-${end.day}, $year');
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Official Hours: 8:00AM-12:00PM 01:00PM-5:00PM');
    row += 2;

    // Two-row header (matches official DTR form)
    final headerRow1 = ['Date', 'AM', 'AM', 'PM', 'PM', 'UNDERTIME', 'UNDERTIME'];
    for (var c = 0; c <= 6; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value = TextCellValue(headerRow1[c]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = headerStyle;
    }
    row++;
    final headerRow2 = ['Date', 'IN', 'OUT', 'IN', 'OUT', 'Hours', 'Min'];
    for (var c = 0; c <= 6; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value = TextCellValue(headerRow2[c]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = headerStyle;
    }
    row++;

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(rec, dt, isWeekend);
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;

      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = displayVal.isEmpty && rec != null;
      final amInStr = showTimes && rec.timeIn != null ? _formatTime(rec.timeIn) : (displayVal == 'ABSENT' ? 'ABSENT' : '');
      final amOutStr = showTimes ? _noon : '';
      final pmInStr = showTimes ? _pmIn : '';
      final pmOutStr = showTimes && rec.timeOut != null ? _formatTime(rec.timeOut) : '';

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(_formatDateWithDay(dt));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(amInStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(amOutStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(pmInStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(pmOutStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(isWeekend ? '' : '$uh');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = TextCellValue(isWeekend ? '' : '$um');
      for (var c = 0; c <= 6; c++) sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = cellStyle;
      row++;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Total Undertime');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue('${totalUndertimeMin ~/ 60}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = TextCellValue('${totalUndertimeMin % 60}');
    for (var c = 0; c <= 6; c++) sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = headerStyle;
    row += 2;

    final equivalentDay = _computeEquivalentDay(totalUndertimeMin);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Equivalent Day (deduction, 8 hr/day): ${equivalentDay.toStringAsFixed(3)}');
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.');
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Verified as to the prescribed office hours.');
    row += 2;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('HON. GADWIN E. HANDUMON');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = headerStyle;
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Municipal Mayor');
    row += 2;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('MARCELO B. CAÑARES');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = headerStyle;
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Human Resource Mgt. and Dev\'t. Officer');
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('01/13 ON FIELD');

    final bytes = excel.encode();
    if (bytes == null) throw StateError('Excel encode failed');
    return Uint8List.fromList(bytes);
  }

  /// Generate HTML (Word-compatible) — single page.
  static String generateWordHtml({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) {
    var totalUndertimeMin = 0;
    final sb = StringBuffer();
    sb.writeln('<!DOCTYPE html><html><head><meta charset="UTF-8"><title>DTR</title>');
    sb.writeln('<style>@page{size:letter;margin:0.4in;}body{font-family:Arial,sans-serif;font-size:7px;margin:8px;line-height:1.1;}');
    sb.writeln('table{border-collapse:collapse;width:100%;font-size:6px;}th,td{border:1px solid #000;padding:1px 2px;}th{background:#ddd;}');
    sb.writeln('h4{margin:2px 0;font-size:9px;}</style></head><body>');
    sb.writeln('<h4 style="text-align:center;">DAILY TIME RECORD</h4>');
    sb.writeln('<p><strong>Name: ${employeeName.toUpperCase()}</strong></p>');
    sb.writeln('<p>PERIOD: ${_months[month - 1]} 1-${end.day}, $year</p>');
    sb.writeln('<p>Official Hours: 8:00AM-12:00PM 01:00PM-5:00PM</p>');
    sb.writeln('<table>');
    sb.writeln('<tr><th>Date</th><th colspan="2">AM</th><th colspan="2">PM</th><th colspan="2">UNDERTIME</th></tr>');
    sb.writeln('<tr><th>Date</th><th>IN</th><th>OUT</th><th>IN</th><th>OUT</th><th>Hours</th><th>Min</th></tr>');

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(rec, dt, isWeekend);
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;
      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = displayVal.isEmpty && rec != null;
      final amIn = showTimes && rec.timeIn != null ? _formatTime(rec.timeIn) : (displayVal == 'ABSENT' ? 'ABSENT' : '');
      final amOut = showTimes ? _noon : '';
      final pmIn = showTimes ? _pmIn : '';
      final pmOut = showTimes && rec.timeOut != null ? _formatTime(rec.timeOut) : '';
      sb.writeln('<tr><td>${_formatDateWithDay(dt)}</td><td>$amIn</td><td>$amOut</td><td>$pmIn</td><td>$pmOut</td><td>${isWeekend ? '' : uh}</td><td>${isWeekend ? '' : um}</td></tr>');
    }

    final totalH = totalUndertimeMin ~/ 60;
    final totalM = totalUndertimeMin % 60;
    sb.writeln('<tr style="background:#eee;"><td colspan="5"><strong>Total Undertime</strong></td><td><strong>$totalH</strong></td><td><strong>$totalM</strong></td></tr>');
    sb.writeln('</table>');

    final equivalentDay = _computeEquivalentDay(totalUndertimeMin);
    sb.writeln('<table style="border:none;width:100%;margin-top:8px;"><tr>');
    sb.writeln('<td style="border:none;font-size:6px;width:55%;vertical-align:top;">I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.</td>');
    sb.writeln('<td style="border:none;font-size:6px;width:45%;text-align:right;vertical-align:top;">Equivalent Day (deduction, 8 hr/day): ${equivalentDay.toStringAsFixed(3)}<br>Verified as to the prescribed office hours.</td>');
    sb.writeln('</tr></table>');
    sb.writeln('<table style="border:none;width:100%;margin-top:12px;"><tr>');
    sb.writeln('<td style="border:none;text-align:center;width:50%;"><strong>HON. GADWIN E. HANDUMON</strong><br>Municipal Mayor</td>');
    sb.writeln('<td style="border:none;text-align:center;width:50%;"><strong>MARCELO B. CAÑARES</strong><br>Human Resource Mgt. and Dev\'t. Officer<br>01/13 ON FIELD</td>');
    sb.writeln('</tr></table>');
    sb.writeln('</body></html>');
    return sb.toString();
  }
}
