import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/services/dtr_report_document_actions.dart';

class _Printer extends PrintingPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int calls = 0;
  PdfPageFormat? paper;
  String? filename;
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
    calls++;
    paper = format;
    filename = name;
    return true;
  }
}

void main() {
  for (final preview in [false, true]) {
    testWidgets(
      'cancelling ${preview ? 'preview' : 'print'} setup produces no document',
      (tester) async {
        final printer = _Printer();
        final old = PrintingPlatform.instance;
        PrintingPlatform.instance = printer;
        addTearDown(() => PrintingPlatform.instance = old);
        final actions = DtrReportDocumentActions(
          year: 2026,
          month: 2,
          signatories: DtrExportSignatories.empty,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    if (preview) {
                      actions.previewDtrReport(
                        context,
                        selectedName: 'Test Employee',
                        start: DateTime(2026, 2),
                        end: DateTime(2026, 2, 28),
                        recordsByDate: const {},
                      );
                    } else {
                      actions.printDtrReport(
                        context,
                        selectedName: 'Test Employee',
                        start: DateTime(2026, 2),
                        end: DateTime(2026, 2, 28),
                        recordsByDate: const {},
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Print setup'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(printer.calls, 0);
        expect(find.byType(PdfPreview), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'print uses the selected paper and historical employee filename',
    (tester) async {
      final printer = _Printer();
      final old = PrintingPlatform.instance;
      PrintingPlatform.instance = printer;
      addTearDown(() => PrintingPlatform.instance = old);
      final actions = DtrReportDocumentActions(
        year: 2026,
        month: 2,
        signatories: DtrExportSignatories.empty,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => actions.printDtrReport(
                  context,
                  selectedName: 'Test Employee',
                  start: DateTime(2026, 2),
                  end: DateTime(2026, 2, 28),
                  recordsByDate: const {},
                ),
                child: const Text('Print'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Legal'));
      await tester.pumpAndSettle();
      expect(printer.calls, 1);
      expect(printer.paper!.height, PdfPageFormat.legal.height);
      expect(printer.filename, 'DTR_Test_Employee_February_2026');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('DTR sent to print'), findsOneWidget);
    },
  );
}
