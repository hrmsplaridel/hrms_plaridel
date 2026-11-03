import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';

String _pageContent(List<int> bytes) {
  final raw = latin1.decode(bytes);
  final content = StringBuffer();
  for (final match in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', match.end);
    if (end < 0) continue;
    try {
      final stream = latin1.decode(zlib.decode(bytes.sublist(match.end, end)));
      if (stream.contains('BT') && stream.contains(' Tf')) {
        content.write(stream);
      }
    } on FormatException {
      // Font/image streams are not page drawing commands.
    }
  }
  return content.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);
  final records = <DateTime, TimeRecord>{
    for (var day = 1; day <= 31; day++)
      DateTime(2026, 7, day): TimeRecord(
        userId: 'employee',
        recordDate: DateTime(2026, 7, day),
        timeIn: DateTime.utc(2026, 7, day, 0),
        breakOut: DateTime.utc(2026, 7, day, 4),
        breakIn: DateTime.utc(2026, 7, day, 5),
        timeOut: DateTime.utc(2026, 7, day, 9),
        totalHours: 8,
        undertimeMinutes: 0,
        lateMinutes: 0,
        status: 'present',
        remarks: 'Bulk full-day DTR entry',
      ),
  };
  final item = DtrExportItem(
    employeeName: 'Sample Employee',
    department: 'Human Resources',
    position: 'HR Manager',
    recordsByDate: records,
    workingDays: const [1, 2, 3, 4, 5, 6, 7],
    reportableThrough: end,
  );

  for (final paper in {
    'legal': PdfPageFormat.legal,
    'a4': PdfPageFormat.a4,
    'letter': PdfPageFormat.letter,
    'long': const PdfPageFormat(
      8.5 * PdfPageFormat.inch,
      13 * PdfPageFormat.inch,
    ),
  }.entries) {
    for (final bulk in [false, true]) {
      test(
        '31-day ${paper.key} ${bulk ? 'bulk' : 'single'} DTR keeps two copies with 8pt table text',
        () async {
          final bytes = bulk
              ? await DtrExport.generateBulkPdf(
                  items: [item, item],
                  year: 2026,
                  month: 7,
                  start: start,
                  end: end,
                  signatories: DtrExportSignatories.empty,
                  pageFormat: paper.value,
                )
              : await DtrExport.generatePdf(
                  employeeName: item.employeeName,
                  year: 2026,
                  month: 7,
                  start: start,
                  end: end,
                  recordsByDate: records,
                  department: item.department,
                  position: item.position,
                  workingDays: item.workingDays,
                  reportableThrough: end,
                  signatories: DtrExportSignatories.empty,
                  pageFormat: paper.value,
                );
          final outputDir = Platform.environment['DTR_PDF_TEST_OUTPUT_DIR'];
          if (outputDir != null) {
            await Directory(outputDir).create(recursive: true);
            await File(
              '$outputDir/${paper.key}-${bulk ? 'bulk' : 'single'}.pdf',
            ).writeAsBytes(bytes);
          }
          final pages = bulk ? 2 : 1;
          expect(
            RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
            pages,
          );
          final drawing = _pageContent(bytes);
          expect(
            RegExp(r'/F\d+\s+8(?:\.0)?\s+Tf').allMatches(drawing).length,
            greaterThanOrEqualTo(31 * 4 * 2 * pages),
            reason:
                'Each time entry in both copies must use the larger table font',
          );
          expect(
            RegExp(r'/F\d+\s+5(?:\.0)?\s+Tf').allMatches(drawing),
            isEmpty,
            reason:
                'The old 5pt date/time and column labels should be replaced',
          );
        },
      );
    }
  }
}
