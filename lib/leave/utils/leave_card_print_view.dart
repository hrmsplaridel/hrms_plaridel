import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/leave_request.dart';
import '../models/leave_type.dart';

/// Builds and prints a formal Employee Leave Card PDF.
class LeaveCardPrintView {
  LeaveCardPrintView._();

  static final PdfPageFormat _legalPage = PdfPageFormat(
    612, // 8.5in * 72
    1008, // 14in * 72
    marginLeft: 18,
    marginRight: 18,
    marginTop: 18,
    marginBottom: 18,
  );

  static Future<void> print({
    required String employeeName,
    required String officeDepartment,
    DateTime? firstDayOfService,
    required List<LeaveRequest> requests,
  }) async {
    final sorted = [...requests]
      ..sort((a, b) {
        final aDate = a.startDate ?? a.dateFiled ?? DateTime(1900);
        final bDate = b.startDate ?? b.dateFiled ?? DateTime(1900);
        return aDate.compareTo(bDate);
      });
    final doc = pw.Document(title: "Employee's Leave Card");
    final rows = _buildRows(sorted);
    const rowsPerPage = 34;
    final chunks = <List<_LeaveCardRow>>[];
    for (var i = 0; i < rows.length; i += rowsPerPage) {
      final end = (i + rowsPerPage) > rows.length
          ? rows.length
          : (i + rowsPerPage);
      chunks.add(rows.sublist(i, end));
    }

    for (var i = 0; i < chunks.length; i++) {
      final isLastPage = i == chunks.length - 1;
      doc.addPage(
        pw.Page(
          pageFormat: _legalPage,
          build: (_) => pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildDocumentHeader(
                  employeeName: employeeName,
                  officeDepartment: officeDepartment,
                  firstDayOfService: firstDayOfService,
                ),
                pw.SizedBox(height: 6),
                pw.Expanded(child: _buildOfficialGrid(chunks[i])),
                if (isLastPage) ...[
                  pw.SizedBox(height: 12),
                  _buildPreparedBy(),
                ],
              ],
            ),
          ),
        ),
      );
    }

    await Printing.layoutPdf(
      name: "employee_leave_card_${employeeName.replaceAll(' ', '_')}.pdf",
      onLayout: (_) async => doc.save(),
    );
  }

  static pw.Widget _buildDocumentHeader({
    required String employeeName,
    required String officeDepartment,
    required DateTime? firstDayOfService,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'MUNICIPAL GOVERNMENT OF PLARIDEL',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Center(
          child: pw.Text(
            "EMPLOYEE'S LEAVE CARD",
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Divider(height: 1, thickness: 0.8, color: PdfColors.black),
        pw.SizedBox(height: 2),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _lineField('NAME', employeeName),
                  pw.SizedBox(height: 1),
                  _lineField('SERVICE', ''),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 3,
              child: _lineField('DIVISION / OFFICE', officeDepartment),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 2,
              child: _lineField(
                'FIRST DAY OF',
                firstDayOfService != null ? _fmtDate(firstDayOfService) : '',
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _lineField(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 1),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
          ),
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 8.8)),
        ),
      ],
    );
  }

  static pw.Widget _buildOfficialGrid(List<_LeaveCardRow> rows) {
    const periodFlex = 17;
    const particularsFlex = 22;
    const vacationGroupFlex = 36;
    const sickGroupFlex = 36;
    const dateTakenFlex = 16;
    const topHeaderHeight = 22.0;
    const subHeaderHeight = 28.0;
    const baseRowHeight = 21.5;

    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints!.maxHeight;
        final headerHeight = topHeaderHeight + subHeaderHeight;
        final bodyHeight = (availableHeight - headerHeight).clamp(
          0,
          double.infinity,
        );
        final estimatedRows = bodyHeight > 0
            ? (bodyHeight / baseRowHeight).floor()
            : 0;
        final targetRows = [
          rows.length,
          estimatedRows,
          16,
        ].reduce((a, b) => a > b ? a : b);
        final dynamicRowHeight = targetRows > 0
            ? (bodyHeight / targetRows).clamp(14.0, baseRowHeight)
            : baseRowHeight;
        final filledRows = [
          ...rows,
          ...List.generate(
            targetRows > rows.length ? targetRows - rows.length : 0,
            (_) => const _LeaveCardRow.empty(),
          ),
        ];

        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.8, color: PdfColors.black),
          ),
          child: pw.Column(
            children: [
              pw.SizedBox(
                height: topHeaderHeight + subHeaderHeight,
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: periodFlex,
                      child: _mergedHeaderCell('PERIOD', showRightBorder: true),
                    ),
                    pw.Expanded(
                      flex: particularsFlex,
                      child: _mergedHeaderCell(
                        'PARTICULARS',
                        showRightBorder: true,
                      ),
                    ),
                    pw.Expanded(
                      flex: vacationGroupFlex,
                      child: pw.Column(
                        children: [
                          _groupTitleCell('VACATION LEAVE', topHeaderHeight),
                          _gridRow(
                            cells: const [
                              _CellData('EARNED', 10),
                              _CellData('ABSENCE UNDER TIME WITH PAY', 12),
                              _CellData('ABSENCE UNDER TIME WITHOUT PAY', 14),
                            ],
                            height: subHeaderHeight,
                            fontSize: 6.8,
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: sickGroupFlex,
                      child: pw.Column(
                        children: [
                          _groupTitleCell('SICK LEAVE', topHeaderHeight),
                          _gridRow(
                            cells: const [
                              _CellData('EARNED', 10),
                              _CellData('ABSENCE UNDER TIME WITH PAY', 12),
                              _CellData('ABSENCE UNDER TIME WITHOUT PAY', 14),
                            ],
                            height: subHeaderHeight,
                            fontSize: 6.8,
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: dateTakenFlex,
                      child: _mergedHeaderCell(
                        'DATE TAKEN ON\nAPPLICATION',
                        showRightBorder: false,
                        showLeftBorder: true,
                      ),
                    ),
                  ],
                ),
              ),
              ...filledRows.map(
                (row) => _gridRow(
                  cells: [
                    _CellData(row.period, 17),
                    _CellData(row.particulars, 22, align: pw.TextAlign.left),
                    _CellData(row.vacEarned, 10),
                    _CellData(row.vacWithPay, 12),
                    _CellData(row.vacWithoutPay, 14),
                    _CellData(row.slEarned, 10),
                    _CellData(row.slWithPay, 12),
                    _CellData(row.slWithoutPay, 14),
                    _CellData(row.dateTakenOnApplication, 16),
                  ],
                  height: dynamicRowHeight,
                  fontSize: 7.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static pw.Widget _mergedHeaderCell(
    String text, {
    required bool showRightBorder,
    bool showLeftBorder = false,
  }) {
    return pw.Container(
      height: double.infinity,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: showLeftBorder
              ? const pw.BorderSide(width: 0.8)
              : pw.BorderSide.none,
          right: showRightBorder
              ? const pw.BorderSide(width: 0.8)
              : pw.BorderSide.none,
          top: const pw.BorderSide(width: 0.8),
        ),
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _groupTitleCell(String text, double height) {
    return pw.Container(
      height: height,
      alignment: pw.Alignment.center,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(width: 0.8),
          top: pw.BorderSide(width: 0.8),
          bottom: pw.BorderSide(width: 0.8),
        ),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _gridRow({
    required List<_CellData> cells,
    required double height,
    double fontSize = 8,
    bool bold = false,
  }) {
    return pw.SizedBox(
      height: height,
      child: pw.Row(
        children: cells
            .map(
              (cell) => pw.Expanded(
                flex: cell.flex,
                child: pw.Container(
                  height: double.infinity,
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(width: 0.8),
                      top: pw.BorderSide(width: 0.8),
                    ),
                  ),
                  child: pw.Text(
                    cell.text,
                    textAlign: cell.align,
                    style: pw.TextStyle(
                      fontSize: fontSize,
                      fontWeight: bold
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  static pw.Widget _buildPreparedBy() {
    return pw.Row(
      children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 180,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('Prepared by:', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 28),
              pw.Divider(height: 1, thickness: 0.7),
              pw.SizedBox(height: 4),
              pw.Text(
                '(In-Charge)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<_LeaveCardRow> _buildRows(List<LeaveRequest> requests) {
    if (requests.isEmpty) {
      return List.generate(16, (_) => const _LeaveCardRow.empty());
    }
    final rows = requests.map((request) {
      final start = request.startDate;
      final end = request.endDate;
      final period = (start != null && end != null)
          ? '${_fmtDate(start)} - ${_fmtDate(end)}'
          : (start != null ? _fmtDate(start) : '');
      final withPay =
          request.approvedDaysWithPay ?? request.workingDaysApplied ?? 0;
      final withoutPay = request.approvedDaysWithoutPay ?? 0;
      final isSick = request.leaveType == LeaveType.sickLeave;
      final isVacation =
          request.leaveType == LeaveType.vacationLeave ||
          request.leaveType == LeaveType.mandatoryForcedLeave;
      return _LeaveCardRow(
        period: period,
        particulars: request.leaveType.displayName,
        vacEarned: '',
        vacWithPay: isVacation ? _fmtNum(withPay) : '',
        vacWithoutPay: isVacation ? _fmtNum(withoutPay) : '',
        slEarned: '',
        slWithPay: isSick ? _fmtNum(withPay) : '',
        slWithoutPay: isSick ? _fmtNum(withoutPay) : '',
        dateTakenOnApplication: request.dateFiled != null
            ? _fmtDate(request.dateFiled!)
            : '',
      );
    }).toList();
    if (rows.length < 16) {
      rows.addAll(
        List.generate(16 - rows.length, (_) => const _LeaveCardRow.empty()),
      );
    }
    return rows;
  }

  static String _fmtNum(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  static String _fmtDate(DateTime value) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '$mm/$dd/${value.year}';
  }
}

class _CellData {
  const _CellData(this.text, this.flex, {this.align = pw.TextAlign.center});

  final String text;
  final int flex;
  final pw.TextAlign align;
}

class _LeaveCardRow {
  const _LeaveCardRow({
    required this.period,
    required this.particulars,
    required this.vacEarned,
    required this.vacWithPay,
    required this.vacWithoutPay,
    required this.slEarned,
    required this.slWithPay,
    required this.slWithoutPay,
    required this.dateTakenOnApplication,
  });

  const _LeaveCardRow.empty()
    : period = '',
      particulars = '',
      vacEarned = '',
      vacWithPay = '',
      vacWithoutPay = '',
      slEarned = '',
      slWithPay = '',
      slWithoutPay = '',
      dateTakenOnApplication = '';

  final String period;
  final String particulars;
  final String vacEarned;
  final String vacWithPay;
  final String vacWithoutPay;
  final String slEarned;
  final String slWithPay;
  final String slWithoutPay;
  final String dateTakenOnApplication;
}
