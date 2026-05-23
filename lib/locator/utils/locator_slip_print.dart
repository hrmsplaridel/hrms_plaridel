import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class LocatorSlipPrint {
  const LocatorSlipPrint._();

  static Future<void> printForm({
    required BuildContext context,
    required String? id,
    required String employeeName,
    required String dateText,
    required String office,
    required String remarks,
    required bool amIn,
    required bool amOut,
    required bool pmIn,
    required bool pmOut,
  }) async {
    final doc = pw.Document();
    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load(
        'assets/images/Plaridel Logo.jpg',
      );
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      // Keep layout intact if logo asset is missing at runtime.
    }

    pw.Widget paperCheck(bool checked) => pw.Container(
      width: 10,
      height: 10,
      alignment: pw.Alignment.center,
      child: checked
          ? pw.InkList(
              points: [
                [PdfPoint(1.6, 5.4), PdfPoint(4.1, 8.1)],
                [PdfPoint(4.1, 8.1), PdfPoint(8.9, 1.7)],
              ],
              strokeWidth: 0.95,
            )
          : null,
    );

    pw.Widget segmentMark(String label, bool checked) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          '$label (',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
        paperCheck(checked),
        pw.Text(
          ')',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
      ],
    );

    pw.Widget lineField({
      required String label,
      required String value,
      double labelWidth = 135,
    }) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: labelWidth,
            child: pw.Text(
              '$label :',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              height: 20,
              alignment: pw.Alignment.bottomLeft,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 1)),
              ),
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(left: 4, bottom: 2),
                child: pw.Text(value, style: const pw.TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(16, 14, 16, 12),
        build: (ctx) => pw.Center(
          child: pw.Container(
            width: 760,
            height: 370,
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              if (logoImage != null) ...[
                                pw.Container(
                                  width: 34,
                                  height: 34,
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(width: 0.8),
                                    shape: pw.BoxShape.circle,
                                  ),
                                  child: pw.Center(
                                    child: pw.Image(
                                      logoImage,
                                      width: 28,
                                      height: 28,
                                      fit: pw.BoxFit.contain,
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: 10),
                              ],
                              pw.Text(
                                'LOCATOR SLIP OF EMPLOYEES',
                                style: pw.TextStyle(
                                  fontSize: 23,
                                  fontWeight: pw.FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 10),
                          pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'Date:',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                pw.Container(
                                  width: 180,
                                  margin: const pw.EdgeInsets.only(left: 6),
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(
                                      bottom: pw.BorderSide(width: 1),
                                    ),
                                  ),
                                  child: pw.Padding(
                                    padding: const pw.EdgeInsets.only(
                                      left: 4,
                                      bottom: 2,
                                    ),
                                    child: pw.Text(
                                      dateText,
                                      style: const pw.TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 14),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'AM',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    segmentMark('IN', amIn),
                    pw.SizedBox(width: 26),
                    segmentMark('OUT', amOut),
                    pw.SizedBox(width: 90),
                    pw.Text(
                      'PM',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    segmentMark('IN', pmIn),
                    pw.SizedBox(width: 26),
                    segmentMark('OUT', pmOut),
                  ],
                ),
                pw.SizedBox(height: 16),
                lineField(label: 'Name', value: employeeName),
                pw.SizedBox(height: 10),
                lineField(label: 'Office', value: office),
                pw.SizedBox(height: 10),
                lineField(label: 'Remarks/Reasons', value: remarks),
                pw.SizedBox(height: 34),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Container(
                            width: double.infinity,
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                bottom: pw.BorderSide(width: 1),
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Authorized Representative',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          pw.Text(
                            '(Head of Office)',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 56),
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Container(
                            width: double.infinity,
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                bottom: pw.BorderSide(width: 1),
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            '(Signature Over Printed Name)',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 26),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 100),
                  child: pw.Text(
                    'Noted:',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Container(
                    width: 420,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 1)),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Center(
                  child: pw.Text(
                    'MARCELO B. CANARES',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    'Human Resource Management and Development Officer',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: 'Locator_Slip_${id ?? 'form'}.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }
}
