import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';

void main() {
  for (final title in ['Leave Form Preview', 'Locator Form Preview']) {
    for (final config in [
      (size: const Size(390, 844), scale: 1.0, systemBack: false),
      (size: const Size(320, 844), scale: 1.6, systemBack: true),
      (size: const Size(740, 390), scale: 1.0, systemBack: false),
    ]) {
      testWidgets('$title covers mobile dashboard chrome: $config', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = config.size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bytes =
            await (pw.Document()
                  ..addPage(pw.Page(build: (_) => pw.Text('Original form'))))
                .save();
        final inner = GlobalKey<NavigatorState>();
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(config.scale),
                padding: const EdgeInsets.only(bottom: 24),
              ),
              child: child!,
            ),
            home: Scaffold(
              bottomNavigationBar: const SizedBox(
                height: 80,
                child: Text('Dashboard navigation'),
              ),
              body: Stack(
                children: [
                  Navigator(
                    key: inner,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () async {
                            await showFormPdfPreview(
                              context: context,
                              bytes: bytes,
                              title: title,
                              filename: 'original.pdf',
                              format: PdfPageFormat.a4,
                            );
                            closed = true;
                          },
                          child: const Text('Preview request'),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      onPressed: () {},
                      label: const Text('File Leave'),
                    ),
                  ),
                  const Positioned(
                    right: 16,
                    bottom: 90,
                    child: Text('Chatbot launcher'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preview request'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(title), findsOneWidget);
        expect(find.text('File Leave'), findsNothing);
        expect(find.text('Chatbot launcher'), findsNothing);
        expect(find.text('Dashboard navigation'), findsNothing);
        expect(inner.currentState!.canPop(), isFalse);
        final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
        expect(preview.allowPrinting, isTrue);
        expect(preview.allowSharing, isTrue);
        expect(preview.pdfFileName, 'original.pdf');
        expect(await preview.build(PdfPageFormat.a4), bytes);
        final bounds = tester.getRect(find.byType(PdfPreview));
        expect(bounds.left, 0);
        expect(bounds.width, config.size.width);
        expect(bounds.bottom, closeTo(config.size.height - 24, 1));
        if (config.systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byTooltip('Close preview'));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(closed, isTrue);
        expect(inner.currentState!.canPop(), isFalse);
        expect(find.text('File Leave'), findsOneWidget);
        expect(find.text('Dashboard navigation'), findsOneWidget);
        expect(find.text('Chatbot launcher'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('form preview opens an in-app PDF viewer with print and share', (
    tester,
  ) async {
    final document = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Form')));
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
    expect(preview.allowPrinting, isTrue);
    expect(preview.allowSharing, isTrue);
    expect(preview.dpi, 144);
    expect(await preview.build(const PdfPageFormat(300, 400)), bytes);
  });
}
