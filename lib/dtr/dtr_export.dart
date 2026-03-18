import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../api/client.dart';
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

class _ExportAttendancePolicy {
  const _ExportAttendancePolicy({
    required this.workHoursPerDay,
    required this.useEquivalentDayConversion,
    required this.deductLate,
    required this.deductUndertime,
    required this.combineLateAndUndertime,
    required this.deductionMultiplier,
  });

  final double workHoursPerDay;
  final bool useEquivalentDayConversion;
  final bool deductLate;
  final bool deductUndertime;
  final bool combineLateAndUndertime;
  final double deductionMultiplier;

  static const defaults = _ExportAttendancePolicy(
    workHoursPerDay: 8,
    useEquivalentDayConversion: true,
    deductLate: false,
    deductUndertime: true,
    combineLateAndUndertime: false,
    deductionMultiplier: 1.0,
  );
}

class _ExportTotals {
  const _ExportTotals({
    required this.totalLateMinutes,
    required this.totalUndertimeMinutes,
    required this.totalDeductionMinutes,
    required this.equivalentDay,
    required this.adjustedEquivalentDay,
  });

  final int totalLateMinutes;
  final int totalUndertimeMinutes;
  final int totalDeductionMinutes;
  final double equivalentDay;
  final double adjustedEquivalentDay;
}

/// DTR export to PDF, Excel, and Word (HTML) — single page, matches official form.
class DtrExport {
  DtrExport._();

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// Time for print form (lowercase am/pm like reference).
  static String _formatTimePrint(DateTime? dt) {
    if (dt == null) return '-';
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
      if (status == 'holiday') return r.holidayName ?? 'Holiday';
    }
    return ''; // Show times in AM/PM columns
  }

  /// Row-level remark for print (holiday, leave, suspension, absent, or custom remarks).
  static String _getRowRemark(TimeRecord? r, DateTime dt, bool isWeekend) {
    if (r == null) return isWeekend ? '' : 'ABSENT';
    if (r.timeIn == null) {
      final s = r.status;
      if (s == 'holiday') return r.holidayName ?? 'HOLIDAY';
      if (s == 'on_leave') return 'SICK LEAVE';
      if (s != null && s.isNotEmpty) return s.toUpperCase();
      return 'ABSENT';
    }
    final remark = r.remarks?.trim();
    if (remark != null && remark.isNotEmpty) return remark.toUpperCase();
    final att = r.attendanceRemark?.trim();
    if (att != null &&
        att.isNotEmpty &&
        att != 'On Time' &&
        att != 'Late' &&
        att != 'Undertime') {
      return att.toUpperCase();
    }
    return '';
  }

  static const String _noon = '12:00pm';
  static const String _pmIn = '01:00pm';

  /// Returns (hours, minutes) of undertime. Absent = 8h 0m. Weekend / Holiday = 0.
  static (int, int) _computeUndertime(
    TimeRecord? r,
    DateTime dt,
    bool isWeekend,
    double workHoursPerDay,
  ) {
    if (isWeekend) return (0, 0);
    if (r != null && r.status == 'holiday') return (0, 0);
    final wh = workHoursPerDay > 0 ? workHoursPerDay : 8.0;

    // Absent: use configured work hours per day.
    if (r == null || r.timeIn == null) {
      final h = wh.floor();
      final m = ((wh - h) * 60).round();
      return (h, m);
    }

    // Prefer backend-calculated undertime_minutes when available.
    final undertimeMinutes = r.undertimeMinutes;
    if (undertimeMinutes != null) {
      return (undertimeMinutes ~/ 60, undertimeMinutes % 60);
    }

    // Fallback: derive from total hours.
    final actual = r.totalHours ?? 0;
    final undertime = (wh - actual).clamp(0.0, wh);
    final h = undertime.floor();
    final m = ((undertime - h) * 60).round();
    return (h, m);
  }

  static double _round3(double x) => (x * 1000).roundToDouble() / 1000;

  static (double equivalentDay, double adjustedEquivalentDay)
  _computeEquivalentDay({
    required int minutes,
    required double workHoursPerDay,
    required bool useEquivalentDayConversion,
    required double deductionMultiplier,
  }) {
    if (!useEquivalentDayConversion) return (0, 0);
    final wh = workHoursPerDay > 0 ? workHoursPerDay : 8.0;
    final eq = _round3(minutes / (wh * 60.0));
    final mult = deductionMultiplier > 0 ? deductionMultiplier : 1.0;
    final adj = _round3(eq * mult);
    return (eq, adj);
  }

  static Future<_ExportAttendancePolicy> _loadDefaultAttendancePolicy() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/attendance-policies',
        queryParameters: {'status': 'Active'},
      );
      final data = res.data ?? [];
      final items = data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (items.isEmpty) return _ExportAttendancePolicy.defaults;

      final m = items.firstWhere(
        (x) => (x['is_default'] as bool?) == true,
        orElse: () => items.first,
      );

      double toDouble(dynamic v, double fallback) {
        if (v == null) return fallback;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? fallback;
      }

      bool toBool(dynamic v, bool fallback) {
        if (v == null) return fallback;
        if (v is bool) return v;
        final s = v.toString().trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
        return fallback;
      }

      return _ExportAttendancePolicy(
        workHoursPerDay: toDouble(m['work_hours_per_day'], 8),
        useEquivalentDayConversion: toBool(
          m['use_equivalent_day_conversion'],
          true,
        ),
        deductLate: toBool(m['deduct_late'], false),
        deductUndertime: toBool(m['deduct_undertime'], true),
        combineLateAndUndertime: toBool(m['combine_late_and_undertime'], false),
        deductionMultiplier: toDouble(m['deduction_multiplier'], 1.0),
      );
    } catch (_) {
      return _ExportAttendancePolicy.defaults;
    }
  }

  /// Government-style form footer: certification, verified, signature line, officers, notes.
  static pw.Widget _buildFormFooter(
    _ExportTotals totals,
    _ExportAttendancePolicy policy, {
    List<String> noteLines = const [],
  }) {
    const double lineWidth = 170;

    final whLabel = policy.workHoursPerDay % 1 == 0
        ? policy.workHoursPerDay.toStringAsFixed(0)
        : policy.workHoursPerDay.toStringAsFixed(2);
    final hasMultiplier = (policy.deductionMultiplier - 1.0).abs() > 0.0001;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Equivalent Day (deduction, $whLabel hr/day): ${totals.equivalentDay.toStringAsFixed(3)}'
          '${hasMultiplier ? '  |  Adjusted: ${totals.adjustedEquivalentDay.toStringAsFixed(3)}' : ''}',
          style: const pw.TextStyle(fontSize: 6),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Total Late: ${totals.totalLateMinutes} min    Total Undertime: ${totals.totalUndertimeMinutes} min    Total Deduction Minutes: ${totals.totalDeductionMinutes} min',
          style: const pw.TextStyle(fontSize: 5.5),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.',
          style: const pw.TextStyle(fontSize: 5.5),
        ),
        // Extra space for handwritten signature above the "Verified" text.
        pw.SizedBox(height: 8),
        // Line for certifying officer (above the "Verified" text, like the handwritten signature line).
        pw.Container(width: lineWidth, height: 1, color: PdfColors.black),
        // Extra space for handwritten signature above MEEDO A-Manager.
        pw.SizedBox(height: 8),
        pw.Text(
          'Verified as to the prescribed office hours.',
          style: const pw.TextStyle(fontSize: 5.5),
        ),
        pw.SizedBox(height: 6),
        // First signature block: line above MEEDO A-Manager.
        pw.Container(width: lineWidth, height: 1, color: PdfColors.black),
        // Extra space for handwritten signature above HR officer title.
        pw.SizedBox(height: 8),
        pw.Text(
          'JACYNTH MARIE T. RABOSA',
          style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('MEEDO A-Manager', style: const pw.TextStyle(fontSize: 5.5)),
        pw.SizedBox(height: 6),
        // Second signature block: line above Human Resource Mgt. and Dev't. Officer.
        pw.Container(width: lineWidth, height: 1, color: PdfColors.black),
        pw.SizedBox(height: 3),
        pw.Text(
          'MARCELO B. CAÑARES',
          style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Human Resource Mgt. and Dev\'t. Officer',
          style: const pw.TextStyle(fontSize: 5.5),
        ),
        if (noteLines.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            noteLines.join('   '),
            style: const pw.TextStyle(fontSize: 5.5),
          ),
        ],
      ],
    );
  }

  /// Generate PDF bytes — single page, matches official DTR form design.
  /// [reportTitle] — e.g. "Daily Time Record Report" for print; null uses "DAILY TIME RECORD".
  /// [department] and [position] — optional, shown when provided (e.g. for print).
  static Future<Uint8List> generatePdf({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? reportTitle,
    String? department,
    String? position,
  }) async {
    final policy = await _loadDefaultAttendancePolicy();
    final (formRows, totals) = _buildFormTableRows(
      year: year,
      month: month,
      end: end,
      recordsByDate: recordsByDate,
      policy: policy,
    );

    final noteLines = <String>[];
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final remark = rec?.remarks?.trim();
      if (remark != null && remark.isNotEmpty) {
        noteLines.add(
          '${month.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')} $remark',
        );
      }
    }

    final title = reportTitle ?? 'DAILY TIME RECORD';
    final oneCopy = _buildOneDtrForm(
      employeeName: employeeName,
      year: year,
      month: month,
      end: end,
      tableRows: formRows,
      totals: totals,
      policy: policy,
      reportTitle: title,
      department: department,
      position: position,
      noteLines: noteLines,
    );

    // Unicode-safe theme so names (e.g. CAÑARES), remarks, and accents render.
    // Prefer TTF from assets; fallback to OpenSans from printing package.
    pw.ThemeData theme;
    try {
      final base = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      );
      theme = pw.ThemeData.withFont(base: base, bold: bold);
    } catch (_) {
      final base = await PdfGoogleFonts.openSansRegular();
      final bold = await PdfGoogleFonts.openSansBold();
      theme = pw.ThemeData.withFont(base: base, bold: bold);
    }

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        build: (context) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: oneCopy),
            pw.SizedBox(width: 8),
            pw.Expanded(child: oneCopy),
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

  // Fixed column widths (points) shared between header and body table.
  static const double _wDate = 66;
  static const double _wAmIn = 45;
  static const double _wAmOut = 45;
  static const double _wPmIn = 45;
  static const double _wPmOut = 45;
  static const double _wHours = 21;
  static const double _wMin = 21;

  static const double _headerFontSize = 5.0;
  static const pw.BorderSide _headerBorder = pw.BorderSide(
    width: 0.5,
    color: PdfColors.black,
  );

  /// Merged-looking header built only with Container/Row/Column and fixed sizes.
  static pw.Widget _buildMergedHeader() {
    const double topHeight = 11;
    const double bottomHeight = 9;
    const double dateHeight = topHeight + bottomHeight + 0.5;

    final double amGroupWidth = _wAmIn + _wAmOut;
    final double pmGroupWidth = _wPmIn + _wPmOut;
    final double undertimeGroupWidth = _wHours + _wMin;

    pw.Widget groupCell(String text, double width) {
      return pw.Container(
        width: width,
        height: topHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(border: pw.Border(right: _headerBorder)),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: _headerFontSize,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      );
    }

    pw.Widget subCell(String text, double width, {bool isLast = false}) {
      return pw.Container(
        width: width,
        height: bottomHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(border: pw.Border(right: _headerBorder)),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: _headerFontSize,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.grey300,
        border: pw.Border(
          top: _headerBorder,
          left: _headerBorder,
          right: _headerBorder,
        ),
      ),
      child: pw.Row(
        children: [
          // Date cell spanning both header rows.
          pw.Container(
            width: _wDate,
            height: dateHeight,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              border: pw.Border(right: _headerBorder),
            ),
            child: pw.Text(
              'Date',
              style: pw.TextStyle(
                fontSize: _headerFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          // Right side with AM / PM / Undertime groups over sub-cells.
          // Its width is exactly the sum of the body columns on the right so
          // vertical borders line up with the table below.
          pw.Container(
            width: amGroupWidth + pmGroupWidth + undertimeGroupWidth,
            height: dateHeight,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                // Top group row.
                pw.Row(
                  children: [
                    groupCell('AM', amGroupWidth),
                    groupCell('PM', pmGroupWidth),
                    // Single Undertime group cell – no vertical line through the title.
                    groupCell('Undertime', undertimeGroupWidth),
                  ],
                ),
                // Horizontal divider between group titles and sub-headers.
                pw.Container(height: 0.5, color: PdfColors.black),
                // Second row: IN / OUT / IN / OUT / Hours / Min.
                pw.Row(
                  children: [
                    subCell('IN', _wAmIn),
                    subCell('OUT', _wAmOut),
                    subCell('IN', _wPmIn),
                    subCell('OUT', _wPmOut),
                    subCell('Hours', _wHours),
                    subCell('Min', _wMin, isLast: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build table rows: body rows only + total row (header built separately).
  static (List<pw.TableRow>, _ExportTotals) _buildFormTableRows({
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    required _ExportAttendancePolicy policy,
  }) {
    var totalUndertimeMin = 0;
    var totalLateMin = 0;
    const fs = 5.0;
    final rows = <pw.TableRow>[];

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(
        rec,
        dt,
        isWeekend,
        policy.workHoursPerDay,
      );
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;
      if (!isWeekend) totalLateMin += (rec?.lateMinutes ?? 0);

      final remark = _getRowRemark(rec, dt, isWeekend);
      final displayVal = _getDisplayValue(rec, isWeekend);
      final showTimes = remark.isEmpty && displayVal.isEmpty && rec != null;

      String amInStr;
      String amOutStr;
      String pmInStr;
      String pmOutStr;
      if (showTimes) {
        amInStr = rec.timeIn != null ? _formatTimePrint(rec.timeIn) : '';
        amOutStr = rec.breakOut != null
            ? _formatTimePrint(rec.breakOut)
            : '12:00pm';
        pmInStr = rec.breakIn != null
            ? _formatTimePrint(rec.breakIn)
            : '01:00pm';
        pmOutStr = rec.timeOut != null ? _formatTimePrint(rec.timeOut) : '';
      } else {
        amInStr = remark.isNotEmpty
            ? remark
            : (displayVal == 'ABSENT' ? 'ABSENT' : '');
        amOutStr = '';
        pmInStr = '';
        pmOutStr = '';
      }

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

    final undertimeDeductMin = policy.deductUndertime ? totalUndertimeMin : 0;
    final lateDeductMin = policy.deductLate ? totalLateMin : 0;
    final totalDeductMin = undertimeDeductMin + lateDeductMin;

    final (eq, adj) = _computeEquivalentDay(
      minutes: totalDeductMin,
      workHoursPerDay: policy.workHoursPerDay,
      useEquivalentDayConversion: policy.useEquivalentDayConversion,
      deductionMultiplier: policy.deductionMultiplier,
    );

    return (
      rows,
      _ExportTotals(
        totalLateMinutes: totalLateMin,
        totalUndertimeMinutes: totalUndertimeMin,
        totalDeductionMinutes: totalDeductMin,
        equivalentDay: eq,
        adjustedEquivalentDay: adj,
      ),
    );
  }

  /// One copy of the government-style DTR form (for two-column print).
  static pw.Widget _buildOneDtrForm({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required List<pw.TableRow> tableRows,
    required _ExportTotals totals,
    required _ExportAttendancePolicy policy,
    required String reportTitle,
    String? department,
    String? position,
    String officialHours = '8:00AM-12:00PM 01:00PM-5:00PM',
    List<String> noteLines = const [],
  }) {
    const fsHeader = 7.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                reportTitle,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Name : ${employeeName.toUpperCase()}',
                style: const pw.TextStyle(fontSize: fsHeader),
              ),
              if (department != null && department.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  'Department : $department',
                  style: const pw.TextStyle(fontSize: fsHeader),
                ),
              ],
              if (position != null && position.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  'Position : $position',
                  style: const pw.TextStyle(fontSize: fsHeader),
                ),
              ],
              pw.SizedBox(height: 1),
              pw.Text(
                'PERIOD : ${_months[month - 1]} 1-${end.day}, $year',
                style: const pw.TextStyle(fontSize: fsHeader),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'Official Hours : $officialHours',
                style: const pw.TextStyle(fontSize: 6),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        _buildMergedHeader(),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.black),
          columnWidths: {
            0: const pw.FixedColumnWidth(_wDate),
            1: const pw.FixedColumnWidth(_wAmIn),
            2: const pw.FixedColumnWidth(_wAmOut),
            3: const pw.FixedColumnWidth(_wPmIn),
            4: const pw.FixedColumnWidth(_wPmOut),
            5: const pw.FixedColumnWidth(_wHours),
            6: const pw.FixedColumnWidth(_wMin),
          },
          children: tableRows,
        ),
        pw.SizedBox(height: 4),
        _buildFormFooter(totals, policy, noteLines: noteLines),
      ],
    );
  }

  /// Generate Excel bytes — same layout as PDF (title, merged header, footer with JACYNTH/MEEDO + MARCELO/HR).
  static Future<Uint8List> generateExcel({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? reportTitle,
    String? department,
    String? position,
  }) async {
    final policy = await _loadDefaultAttendancePolicy();
    final noteLines = <String>[];
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final remark = rec?.remarks?.trim();
      if (remark != null && remark.isNotEmpty) {
        noteLines.add(
          '${month.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')} $remark',
        );
      }
    }
    var totalUndertimeMin = 0;
    var totalLateMin = 0;
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

    // Column widths: first copy (0-6), gap (7), second copy (8-14) — two side-by-side copies like PDF
    for (var c = 0; c <= 6; c++) {
      sheet.setColumnWidth(c, c == 0 ? 12.0 : (c <= 4 ? 10.0 : 6.0));
    }
    sheet.setColumnWidth(7, 2.0);
    for (var c = 8; c <= 14; c++) {
      sheet.setColumnWidth(c, c == 8 ? 12.0 : (c <= 12 ? 10.0 : 6.0));
    }

    void setCellBoth(
      int col,
      int rowIdx,
      TextCellValue value,
      CellStyle? style,
    ) {
      for (final offset in [0, 8]) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: offset + col,
            rowIndex: rowIdx,
          ),
        );
        cell.value = value;
        if (style != null) cell.cellStyle = style;
      }
    }

    void mergeBoth(int c1, int r1, int c2, int r2) {
      for (final offset in [0, 8]) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: offset + c1, rowIndex: r1),
          CellIndex.indexByColumnRow(columnIndex: offset + c2, rowIndex: r2),
        );
      }
    }

    final title = reportTitle ?? 'DAILY TIME RECORD';
    int row = 0;
    setCellBoth(
      0,
      row,
      TextCellValue(title),
      CellStyle(
        fontSize: 11,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      ),
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('Name : ${employeeName.toUpperCase()}'),
      CellStyle(fontSize: 9, horizontalAlign: HorizontalAlign.Center),
    );
    mergeBoth(0, row, 6, row);
    row++;
    if (department != null && department.isNotEmpty) {
      setCellBoth(
        0,
        row,
        TextCellValue('Department : $department'),
        CellStyle(fontSize: 9, horizontalAlign: HorizontalAlign.Center),
      );
      mergeBoth(0, row, 6, row);
      row++;
    }
    if (position != null && position.isNotEmpty) {
      setCellBoth(
        0,
        row,
        TextCellValue('Position : $position'),
        CellStyle(fontSize: 9, horizontalAlign: HorizontalAlign.Center),
      );
      mergeBoth(0, row, 6, row);
      row++;
    }
    setCellBoth(
      0,
      row,
      TextCellValue('PERIOD : ${_months[month - 1]} 1-${end.day}, $year'),
      CellStyle(fontSize: 9, horizontalAlign: HorizontalAlign.Center),
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('Official Hours: 8:00AM-12:00PM 01:00PM-5:00PM'),
      CellStyle(fontSize: 9, horizontalAlign: HorizontalAlign.Center),
    );
    mergeBoth(0, row, 6, row);
    row += 2;

    // Merged two-row header (same as PDF): Date spans 2 rows; AM, PM, UNDERTIME span 2 cols each
    final headerRow1 = row;
    setCellBoth(0, headerRow1, TextCellValue('Date'), headerStyle);
    mergeBoth(0, headerRow1, 0, headerRow1 + 1);
    setCellBoth(1, headerRow1, TextCellValue('AM'), headerStyle);
    mergeBoth(1, headerRow1, 2, headerRow1);
    setCellBoth(3, headerRow1, TextCellValue('PM'), headerStyle);
    mergeBoth(3, headerRow1, 4, headerRow1);
    setCellBoth(5, headerRow1, TextCellValue('Undertime'), headerStyle);
    mergeBoth(5, headerRow1, 6, headerRow1);
    row = headerRow1 + 1;
    final headerRow2Labels = ['IN', 'OUT', 'IN', 'OUT', 'Hours', 'Min'];
    for (var c = 0; c < headerRow2Labels.length; c++) {
      setCellBoth(c + 1, row, TextCellValue(headerRow2Labels[c]), headerStyle);
    }
    row++;

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(
        rec,
        dt,
        isWeekend,
        policy.workHoursPerDay,
      );
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;
      if (!isWeekend) totalLateMin += (rec?.lateMinutes ?? 0);

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

      setCellBoth(0, row, TextCellValue(_formatDateWithDay(dt)), cellStyle);
      setCellBoth(1, row, TextCellValue(amInStr), cellStyleCenter);
      setCellBoth(2, row, TextCellValue(amOutStr), cellStyleCenter);
      setCellBoth(3, row, TextCellValue(pmInStr), cellStyleCenter);
      setCellBoth(4, row, TextCellValue(pmOutStr), cellStyleCenter);
      setCellBoth(
        5,
        row,
        TextCellValue(isWeekend ? '' : '$uh'),
        cellStyleRight,
      );
      setCellBoth(
        6,
        row,
        TextCellValue(isWeekend ? '' : '$um'),
        cellStyleRight,
      );
      row++;
    }

    setCellBoth(0, row, TextCellValue('Total Undertime'), totalStyle);
    setCellBoth(1, row, TextCellValue(''), totalStyle);
    setCellBoth(2, row, TextCellValue(''), totalStyle);
    setCellBoth(3, row, TextCellValue(''), totalStyle);
    setCellBoth(4, row, TextCellValue(''), totalStyle);
    setCellBoth(
      5,
      row,
      TextCellValue('${totalUndertimeMin ~/ 60}'),
      totalStyleRight,
    );
    setCellBoth(
      6,
      row,
      TextCellValue('${totalUndertimeMin % 60}'),
      totalStyleRight,
    );
    row += 2;

    final undertimeDeductMin = policy.deductUndertime ? totalUndertimeMin : 0;
    final lateDeductMin = policy.deductLate ? totalLateMin : 0;
    final totalDeductMin = undertimeDeductMin + lateDeductMin;
    final (equivalentDay, adjustedEquivalentDay) = _computeEquivalentDay(
      minutes: totalDeductMin,
      workHoursPerDay: policy.workHoursPerDay,
      useEquivalentDayConversion: policy.useEquivalentDayConversion,
      deductionMultiplier: policy.deductionMultiplier,
    );
    final whLabel = policy.workHoursPerDay % 1 == 0
        ? policy.workHoursPerDay.toStringAsFixed(0)
        : policy.workHoursPerDay.toStringAsFixed(2);
    final hasMultiplier = (policy.deductionMultiplier - 1.0).abs() > 0.0001;
    final footerCenterStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
    );
    setCellBoth(
      0,
      row,
      TextCellValue(
        'Equivalent Day (deduction, $whLabel hr/day): ${equivalentDay.toStringAsFixed(3)}'
        '${hasMultiplier ? '  |  Adjusted: ${adjustedEquivalentDay.toStringAsFixed(3)}' : ''}',
      ),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue(
        'I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.',
      ),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('_________________________'),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('Verified as to the prescribed office hours.'),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    row += 2;
    setCellBoth(
      0,
      row,
      TextCellValue('_________________________'),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('JACYNTH MARIE T. RABOSA'),
      CellStyle(
        fontSize: 9,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      ),
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(0, row, TextCellValue('MEEDO A-Manager'), footerCenterStyle);
    mergeBoth(0, row, 6, row);
    row += 2;
    setCellBoth(
      0,
      row,
      TextCellValue('_________________________'),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('MARCELO B. CAÑARES'),
      CellStyle(
        fontSize: 9,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      ),
    );
    mergeBoth(0, row, 6, row);
    row++;
    setCellBoth(
      0,
      row,
      TextCellValue('Human Resource Mgt. and Dev\'t. Officer'),
      footerCenterStyle,
    );
    mergeBoth(0, row, 6, row);
    if (noteLines.isNotEmpty) {
      row++;
      setCellBoth(
        0,
        row,
        TextCellValue(noteLines.join('   ')),
        footerCenterStyle,
      );
      mergeBoth(0, row, 6, row);
    }

    final bytes = excel.encode();
    if (bytes == null) throw StateError('Excel encode failed');
    return Uint8List.fromList(bytes);
  }

  /// Generate HTML (Word-compatible) — same layout as PDF: two side-by-side copies (original + duplicate).
  /// Async so it can load the default Attendance Policy for equivalent-day totals.
  static Future<String> generateWordHtml({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? reportTitle,
    String? department,
    String? position,
  }) async {
    final policy = await _loadDefaultAttendancePolicy();
    final noteLines = <String>[];
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final remark = rec?.remarks?.trim();
      if (remark != null && remark.isNotEmpty) {
        noteLines.add(
          '${month.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')} $remark',
        );
      }
    }
    var totalUndertimeMin = 0;
    var totalLateMin = 0;
    final title = reportTitle ?? 'DAILY TIME RECORD';
    final oneCopy = StringBuffer();
    oneCopy.writeln('<h2>$title</h2>');
    oneCopy.writeln(
      '<div style="text-align:center;font-size:10pt;line-height:1.4;">',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Name :</strong> ${employeeName.toUpperCase()}</p>',
    );
    if (department != null && department.isNotEmpty) {
      oneCopy.writeln(
        '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Department :</strong> $department</p>',
      );
    }
    if (position != null && position.isNotEmpty) {
      oneCopy.writeln(
        '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Position :</strong> $position</p>',
      );
    }
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>PERIOD :</strong> ${_months[month - 1]} 1-${end.day}, $year</p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Official Hours:</strong> 8:00AM-12:00PM 01:00PM-5:00PM</p>',
    );
    oneCopy.writeln('</div>');
    oneCopy.writeln('<table class="dtr-table">');
    oneCopy.writeln(
      '<thead><tr><th rowspan="2">Date</th><th colspan="2">AM</th><th colspan="2">PM</th><th colspan="2">UNDERTIME</th></tr>',
    );
    oneCopy.writeln(
      '<tr><th>IN</th><th>OUT</th><th>IN</th><th>OUT</th><th>Hours</th><th>Min</th></tr></thead><tbody>',
    );

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(
        rec,
        dt,
        isWeekend,
        policy.workHoursPerDay,
      );
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;
      if (!isWeekend) totalLateMin += (rec?.lateMinutes ?? 0);
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
      oneCopy.writeln(
        '<tr><td>${_formatDateWithDay(dt)}</td><td class="center">$amIn</td><td class="center">$amOut</td><td class="center">$pmIn</td><td class="center">$pmOut</td><td class="right">${isWeekend ? '' : uh}</td><td class="right">${isWeekend ? '' : um}</td></tr>',
      );
    }

    final totalH = totalUndertimeMin ~/ 60;
    final totalM = totalUndertimeMin % 60;
    oneCopy.writeln(
      '<tr class="total-row"><td>Total Undertime</td><td></td><td></td><td></td><td></td><td class="right">$totalH</td><td class="right">$totalM</td></tr>',
    );
    oneCopy.writeln('</tbody></table>');

    final undertimeDeductMin = policy.deductUndertime ? totalUndertimeMin : 0;
    final lateDeductMin = policy.deductLate ? totalLateMin : 0;
    final totalDeductMin = undertimeDeductMin + lateDeductMin;
    final (equivalentDay, adjustedEquivalentDay) = _computeEquivalentDay(
      minutes: totalDeductMin,
      workHoursPerDay: policy.workHoursPerDay,
      useEquivalentDayConversion: policy.useEquivalentDayConversion,
      deductionMultiplier: policy.deductionMultiplier,
    );
    final whLabel = policy.workHoursPerDay % 1 == 0
        ? policy.workHoursPerDay.toStringAsFixed(0)
        : policy.workHoursPerDay.toStringAsFixed(2);
    final hasMultiplier = (policy.deductionMultiplier - 1.0).abs() > 0.0001;
    oneCopy.writeln(
      '<div style="text-align:center;font-size:10pt;margin-top:12px;line-height:1.4;">',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">Equivalent Day (deduction, $whLabel hr/day): ${equivalentDay.toStringAsFixed(3)}${hasMultiplier ? '  |  Adjusted: ${adjustedEquivalentDay.toStringAsFixed(3)}' : ''}</p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.</p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;margin:8px 0 4px;"><span style="border-top:1px solid #000;display:inline-block;width:180px;"></span></p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">Verified as to the prescribed office hours.</p>',
    );
    oneCopy.writeln('</div>');
    oneCopy.writeln(
      '<div style="text-align:center;margin-top:16px;font-size:10pt;line-height:1.4;">',
    );
    oneCopy.writeln(
      '<p style="margin:0 0 4px;border-top:1px solid #000;width:180px;margin-left:auto;margin-right:auto;"></p>',
    );
    oneCopy.writeln(
      '<p style="margin:0 0 16px;"><strong>JACYNTH MARIE T. RABOSA</strong><br>MEEDO A-Manager</p>',
    );
    oneCopy.writeln(
      '<p style="margin:0 0 4px;border-top:1px solid #000;width:180px;margin-left:auto;margin-right:auto;"></p>',
    );
    oneCopy.writeln(
      '<p style="margin:0;"><strong>MARCELO B. CAÑARES</strong><br>Human Resource Mgt. and Dev\'t. Officer</p>',
    );
    if (noteLines.isNotEmpty) {
      oneCopy.writeln(
        '<p style="margin:8px 0 0;">${noteLines.join('   ')}</p>',
      );
    }
    oneCopy.writeln('</div>');

    final oneCopyHtml = oneCopy.toString();
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
      'h2{margin:4px 0 8px;font-size:11pt;text-align:center;font-weight:bold;}',
    );
    sb.writeln(
      '.dtr-copy{flex:1;min-width:0;box-sizing:border-box;padding:0 6px;}</style></head><body>',
    );
    sb.writeln('<div style="display:flex;gap:12px;align-items:flex-start;">');
    sb.writeln('<div class="dtr-copy">$oneCopyHtml</div>');
    sb.writeln('<div class="dtr-copy">$oneCopyHtml</div>');
    sb.writeln('</div>');
    sb.writeln('</body></html>');
    return sb.toString();
  }

  /// Backward-compatible sync wrapper (uses defaults).
  static String generateWordHtmlSync({
    required String employeeName,
    required int year,
    required int month,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? reportTitle,
    String? department,
    String? position,
  }) {
    final policy = _ExportAttendancePolicy.defaults;
    final noteLines = <String>[];
    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final remark = rec?.remarks?.trim();
      if (remark != null && remark.isNotEmpty) {
        noteLines.add(
          '${month.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')} $remark',
        );
      }
    }
    var totalUndertimeMin = 0;
    var totalLateMin = 0;
    final title = reportTitle ?? 'DAILY TIME RECORD';
    final oneCopy = StringBuffer();
    oneCopy.writeln('<h2>$title</h2>');
    oneCopy.writeln(
      '<div style="text-align:center;font-size:10pt;line-height:1.4;">',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Name :</strong> ${employeeName.toUpperCase()}</p>',
    );
    if (department != null && department.isNotEmpty) {
      oneCopy.writeln(
        '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Department :</strong> $department</p>',
      );
    }
    if (position != null && position.isNotEmpty) {
      oneCopy.writeln(
        '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Position :</strong> $position</p>',
      );
    }
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>PERIOD :</strong> ${_months[month - 1]} 1-${end.day}, $year</p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;"><strong>Official Hours:</strong> 8:00AM-12:00PM 01:00PM-5:00PM</p>',
    );
    oneCopy.writeln('</div>');
    oneCopy.writeln('<table class="dtr-table">');
    oneCopy.writeln(
      '<thead><tr><th rowspan="2">Date</th><th colspan="2">AM</th><th colspan="2">PM</th><th colspan="2">UNDERTIME</th></tr>',
    );
    oneCopy.writeln(
      '<tr><th>IN</th><th>OUT</th><th>IN</th><th>OUT</th><th>Hours</th><th>Min</th></tr></thead><tbody>',
    );

    for (var d = 1; d <= end.day; d++) {
      final dt = DateTime(year, month, d);
      final rec = recordsByDate[dt];
      final isWeekend =
          dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
      final (uh, um) = _computeUndertime(
        rec,
        dt,
        isWeekend,
        policy.workHoursPerDay,
      );
      if (!isWeekend) totalUndertimeMin += uh * 60 + um;
      if (!isWeekend) totalLateMin += (rec?.lateMinutes ?? 0);
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
      oneCopy.writeln(
        '<tr><td>${_formatDateWithDay(dt)}</td><td class="center">$amIn</td><td class="center">$amOut</td><td class="center">$pmIn</td><td class="center">$pmOut</td><td class="right">${isWeekend ? '' : uh}</td><td class="right">${isWeekend ? '' : um}</td></tr>',
      );
    }

    final totalH = totalUndertimeMin ~/ 60;
    final totalM = totalUndertimeMin % 60;
    oneCopy.writeln(
      '<tr class="total-row"><td>Total Undertime</td><td></td><td></td><td></td><td></td><td class="right">$totalH</td><td class="right">$totalM</td></tr>',
    );
    oneCopy.writeln('</tbody></table>');

    final undertimeDeductMin = policy.deductUndertime ? totalUndertimeMin : 0;
    final lateDeductMin = policy.deductLate ? totalLateMin : 0;
    final totalDeductMin = undertimeDeductMin + lateDeductMin;
    final (equivalentDay, adjustedEquivalentDay) = _computeEquivalentDay(
      minutes: totalDeductMin,
      workHoursPerDay: policy.workHoursPerDay,
      useEquivalentDayConversion: policy.useEquivalentDayConversion,
      deductionMultiplier: policy.deductionMultiplier,
    );
    final whLabel = policy.workHoursPerDay % 1 == 0
        ? policy.workHoursPerDay.toStringAsFixed(0)
        : policy.workHoursPerDay.toStringAsFixed(2);
    final hasMultiplier = (policy.deductionMultiplier - 1.0).abs() > 0.0001;
    oneCopy.writeln(
      '<div style="text-align:center;font-size:10pt;margin-top:12px;line-height:1.4;">',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">Equivalent Day (deduction, $whLabel hr/day): ${equivalentDay.toStringAsFixed(3)}${hasMultiplier ? '  |  Adjusted: ${adjustedEquivalentDay.toStringAsFixed(3)}' : ''}</p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">I certify on my honor that the above is a true and correct report of the hours of work performed, record of which was made daily at the time of arrival and departure from office.</p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;margin:8px 0 4px;"><span style="border-top:1px solid #000;display:inline-block;width:180px;"></span></p>',
    );
    oneCopy.writeln(
      '<p style="text-align:center;font-size:10pt;margin:4px 0;">Verified as to the prescribed office hours.</p>',
    );
    oneCopy.writeln('</div>');
    oneCopy.writeln(
      '<div style="text-align:center;margin-top:16px;font-size:10pt;line-height:1.4;">',
    );
    oneCopy.writeln(
      '<p style="margin:0 0 4px;border-top:1px solid #000;width:180px;margin-left:auto;margin-right:auto;"></p>',
    );
    oneCopy.writeln(
      '<p style="margin:0 0 16px;"><strong>JACYNTH MARIE T. RABOSA</strong><br>MEEDO A-Manager</p>',
    );
    oneCopy.writeln(
      '<p style="margin:0 0 4px;border-top:1px solid #000;width:180px;margin-left:auto;margin-right:auto;"></p>',
    );
    oneCopy.writeln(
      '<p style="margin:0;"><strong>MARCELO B. CAÑARES</strong><br>Human Resource Mgt. and Dev\'t. Officer</p>',
    );
    if (noteLines.isNotEmpty) {
      oneCopy.writeln(
        '<p style="margin:8px 0 0;">${noteLines.join('   ')}</p>',
      );
    }
    oneCopy.writeln('</div>');

    final oneCopyHtml = oneCopy.toString();
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
      '.dtr-table th,.dtr-table td{border:1px solid #000;padding:3px;}',
    );
    sb.writeln(
      '.dtr-table th{background:#d3d3d3;font-weight:bold;text-align:center;}',
    );
    sb.writeln('.center{text-align:center;}.right{text-align:right;}');
    sb.writeln(
      '.total-row td{background:#e6e6e6;font-weight:bold;}',
    );
    sb.writeln(
      '.two-col{display:flex;gap:20px;align-items:flex-start;}.col{flex:1;}h2{text-align:center;margin:0 0 6px;font-size:12pt;}',
    );
    sb.writeln('</style></head><body>');
    sb.writeln('<div class="two-col"><div class="col">$oneCopyHtml</div><div class="col">$oneCopyHtml</div></div>');
    sb.writeln('</body></html>');
    return sb.toString();
  }
}
