import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';

void main() {
  testWidgets('form preview opens an in-app PDF viewer without print actions', (
    tester,
  ) async {
    final document = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Form')));
    final bytes = await document.save();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFormPdfPreview(
                context: context,
                bytes: bytes,
                title: 'Form Preview',
                filename: 'form.pdf',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Form Preview'), findsOneWidget);
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    expect(preview.allowPrinting, isFalse);
    expect(preview.allowSharing, isFalse);
  });
}
