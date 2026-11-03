import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/dtr_reports.dart';

class _Printer extends PrintingPlatform {
  final printed = Completer<Uint8List>();
  final shared = Completer<Uint8List>();
  PdfPageFormat? initialPrintFormat;

  @override
  Future<PrintingInfo> info() async => const PrintingInfo(
    canPrint: true,
    canShare: true,
    canRaster: true,
    dynamicLayout: true,
  );

  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {}

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    initialPrintFormat = format;
    // Simulate changing the system printer from Long/Legal to A4.
    printed.complete(await onLayout(PdfPageFormat.a4));
    return true;
  }

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    shared.complete(bytes);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _expectPaper(Uint8List bytes, PdfPageFormat format, int pages) {
  final source = latin1.decode(bytes);
  expect(RegExp(r'/Type\s*/Page\b').allMatches(source).length, pages);
  final boxes = RegExp(
    r'/MediaBox\s*\[0 0 ([\d.]+) ([\d.]+)\]',
  ).allMatches(source);
  expect(boxes.length, pages);
  for (final box in boxes) {
    expect(double.parse(box.group(1)!), closeTo(format.width, .001));
    expect(double.parse(box.group(2)!), closeTo(format.height, .001));
  }
}

void main() {
  for (final paper in {
    'Long': const PdfPageFormat(
      8.5 * PdfPageFormat.inch,
      13 * PdfPageFormat.inch,
    ),
    'Legal': PdfPageFormat.legal,
  }.entries) {
    for (final bulk in [false, true]) {
      testWidgets(
        '${paper.key} ${bulk ? 'bulk' : 'single'} preview, print and share use the matching paper',
        (tester) async {
          final printer = _Printer();
          final previousPrinter = PrintingPlatform.instance;
          PrintingPlatform.instance = printer;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            PrintingPlatform.instance = previousPrinter;
          });
          final requested = <PdfPageFormat>[];
          Future<Uint8List> build(PdfPageFormat format) async {
            requested.add(format);
            if (bulk) {
              return DtrExport.generateBulkPdf(
                items: const [
                  DtrExportItem(
                    employeeName: 'Employee One',
                    recordsByDate: {},
                  ),
                  DtrExportItem(
                    employeeName: 'Employee Two',
                    recordsByDate: {},
                  ),
                ],
                year: 2026,
                month: 7,
                start: DateTime(2026, 7, 1),
                end: DateTime(2026, 7, 31),
                signatories: DtrExportSignatories.empty,
                pageFormat: format,
              );
            }
            return DtrExport.generatePdf(
              employeeName: 'Employee One',
              year: 2026,
              month: 7,
              start: DateTime(2026, 7, 1),
              end: DateTime(2026, 7, 31),
              recordsByDate: const {},
              signatories: DtrExportSignatories.empty,
              pageFormat: format,
            );
          }

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DtrPdfPreviewPanel(
                  filename: 'dtr.pdf',
                  pageFormat: paper.value,
                  buildPdf: build,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
          expect(preview.initialPageFormat, paper.value);
          expect(preview.pageFormats.values, contains(paper.value));
          final initialBytes = await tester.runAsync(
            () async => await preview.build(paper.value),
          );
          _expectPaper(initialBytes!, paper.value, bulk ? 2 : 1);

          await tester.tap(find.byIcon(Icons.print));
          await tester.pump();
          final printBytes = await tester.runAsync(
            () => printer.printed.future.timeout(const Duration(seconds: 10)),
          );
          expect(printer.initialPrintFormat!.width, paper.value.width);
          expect(printer.initialPrintFormat!.height, paper.value.height);
          _expectPaper(printBytes!, PdfPageFormat.a4, bulk ? 2 : 1);
          expect(requested, contains(PdfPageFormat.a4));

          await tester.tap(find.byIcon(Icons.share));
          await tester.pump();
          final shareBytes = await tester.runAsync(
            () => printer.shared.future.timeout(const Duration(seconds: 10)),
          );
          _expectPaper(shareBytes!, paper.value, bulk ? 2 : 1);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
