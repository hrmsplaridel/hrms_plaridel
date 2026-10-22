import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Printable Mayor endorsement monitoring report (Phase 4).
class MayorEndorsementReportPdf {
  MayorEndorsementReportPdf._();

  static Future<Uint8List> build(Map<String, dynamic> report) async {
    final doc = pw.Document();
    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/UnityPillarLogo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      try {
        final data = await rootBundle.load('assets/images/PlaridelLogo.jpg');
        logoBytes = data.buffer.asUint8List();
      } catch (_) {}
    }

    final title = (report['report_title'] ?? 'Endorsement Report').toString();
    final period = Map<String, dynamic>.from(
      (report['reporting_period'] as Map?) ?? {},
    );
    final totals = Map<String, dynamic>.from((report['totals'] as Map?) ?? {});
    final rows = (report['rows'] as List?) ?? const [];
    final from = (period['from'] ?? '').toString();
    final to = (period['to'] ?? '').toString();
    final tz = (report['timezone'] ?? 'Asia/Manila').toString();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: 42,
                    height: 42,
                    margin: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'REPUBLIC OF THE PHILIPPINES',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'MUNICIPALITY OF PLARIDEL, BULACAN',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'UnityPillar HRMS — Office of the Municipal Mayor',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1.2),
            pw.SizedBox(height: 6),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Reporting period: $from to $to ($tz)',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Official monitoring report — excludes marked test records unless requested.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _statBox('Total Requests', totals['total_requests']),
              _statBox('Endorsed', totals['total_endorsed']),
              _statBox('Rejected', totals['total_rejected']),
              _statBox('Pending', totals['total_pending']),
            ],
          ),
          pw.SizedBox(height: 14),
          if (rows.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Text(
                'No endorsement activity for this reporting period.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Reference',
                'Applicant',
                'Destination Office',
                'Status',
                'Endorsement Date',
              ],
              data: [
                for (final raw in rows)
                  () {
                    final r = Map<String, dynamic>.from(raw as Map);
                    final endorsed = (r['endorsed_at'] ?? '').toString();
                    final endorsedDate = endorsed.length >= 10
                        ? endorsed.substring(0, 10)
                        : '—';
                    return [
                      (r['reference_number'] ?? '—').toString(),
                      (r['applicant_name'] ?? '—').toString(),
                      (r['destination_office'] ?? '—').toString(),
                      (r['status'] ?? '—').toString(),
                      r['status'] == 'endorsed' ? endorsedDate : '—',
                    ];
                  }(),
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF0B1F3A),
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
            ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _statBox(String label, Object? value) {
    return pw.Container(
      width: 110,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 2),
          pw.Text(
            '${value ?? 0}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static Future<void> previewAndPrint(Map<String, dynamic> report) async {
    final bytes = await build(report);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
