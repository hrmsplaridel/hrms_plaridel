import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Use project data models (same package)
import '../data/applicants_profile.dart';
import '../data/bi_form.dart';
import '../data/comparative_assessment.dart';
import '../data/individual_development_plan.dart';
import '../data/performance_evaluation_form.dart';
import '../data/promotion_certification.dart';
import '../data/action_brainstorming_coaching.dart';
import '../data/selection_lineup.dart';
import '../data/training_daily_report.dart';
import '../data/training_need_analysis.dart';
import '../data/turn_around_time.dart';

/// Builds PDF documents from RSP form entries and supports print / share.
/// Paper sizes match sample files: Letter.pdf (8.5"×11"), Long Letter.pdf (8.5"×14"), A4 Letter.pdf.
class FormPdf {
  FormPdf._();

  static Uint8List? _logoBytes;
  static Future<void>? _warmupFuture;

  /// Preloads logos, letterhead rasters, and IDP fonts so first Print is fast.
  static Future<void> warmupPrintAssets() {
    _warmupFuture ??= Future.wait([
      ensureLogoLoaded(),
      ensureA4LetterTemplateLoaded(),
      _ensureIdpPdfFonts(),
      _loadIdpBuildingImage(),
      _loadIdpTemplateBackground(),
    ]);
    return _warmupFuture!;
  }

  /// Official A4 letterhead PDF (Municipality of Plaridel) for BI form print/PDF.
  static const String _a4LetterAsset = 'assets/forms/a4_letter.pdf';
  static pw.MemoryImage? _a4LetterBackground;

  /// Mayor's Office Long Letter letterhead — background for IDP print.
  static const String _idpMayorLetterAsset = 'assets/forms/long_letter.pdf';
  static pw.MemoryImage? _idpMayorLetterBackground;
  static pw.Font? _idpPdfFont;
  static pw.Font? _idpPdfFontBold;
  static Uint8List? _idpBuildingBytes;
  static final PdfColor _idpMunicipalityRed = PdfColor.fromInt(0xFFC41E3A);

  /// Philippine long bond 8.5" × 13" (official IDP paper size).
  static final PdfPageFormat pagePhilippineLong = PdfPageFormat(
    8.5 * PdfPageFormat.inch,
    13.0 * PdfPageFormat.inch,
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0,
  );

  /// IDP always prints on Philippine long bond (8.5" × 13").
  static PdfPageFormat get idpPrintPageFormat => pagePhilippineLong;

  /// Content insets on [a4_letter.pdf] (header/footer are on the template).
  static const pw.EdgeInsets _biFormContentPadding = pw.EdgeInsets.fromLTRB(
    42,
    172,
    42,
    88,
  );

  /// Continuation pages (no form title — clear space below HRMDO line on letterhead).
  static const pw.EdgeInsets _biFormContinuationPadding = pw.EdgeInsets.fromLTRB(
    42,
    162,
    42,
    88,
  );

  /// Call before building any PDF so the Plaridel logo is available in headers.
  static Future<void> ensureLogoLoaded() async {
    if (_logoBytes != null) return;
    final data = await rootBundle.load('assets/images/Plaridel Logo.jpg');
    _logoBytes = data.buffer.asUint8List();
  }

  /// Rasterizes the first page of [a4_letter.pdf] for use as a print background.
  static Future<void> ensureA4LetterTemplateLoaded() async {
    if (_a4LetterBackground != null) return;
    try {
      final data = await rootBundle.load(_a4LetterAsset);
      final raster = Printing.raster(
        data.buffer.asUint8List(),
        pages: [0],
        dpi: 96,
      );
      await for (final page in raster) {
        final png = await page.toPng();
        _a4LetterBackground = pw.MemoryImage(png);
        break;
      }
    } catch (_) {
      // Fall back to programmatic header/footer in [buildBiFormPdf].
    }
  }

  /// Mayor IDP letterhead assets (logo, fonts, template background).
  static Future<void> _ensureIdpAssets() async {
    await Future.wait([
      ensureLogoLoaded(),
      _ensureIdpPdfFonts(),
      _loadIdpBuildingImage(),
      _loadIdpTemplateBackground(),
    ]);
  }

  static Future<void> _loadIdpBuildingImage() async {
    if (_idpBuildingBytes != null) return;
    try {
      final data = await rootBundle.load('assets/images/PlaridelBuildingC.png');
      _idpBuildingBytes = data.buffer.asUint8List();
    } catch (_) {
      _idpBuildingBytes = null;
    }
  }

  static Future<void> _loadIdpTemplateBackground() async {
    if (_idpMayorLetterBackground != null) return;
    try {
      final data = await rootBundle.load(_idpMayorLetterAsset);
      final raster = Printing.raster(
        data.buffer.asUint8List(),
        pages: [0],
        dpi: 96,
      );
      await for (final page in raster) {
        _idpMayorLetterBackground = pw.MemoryImage(await page.toPng());
        return;
      }
    } catch (_) {
      // Web/pdf.js may fail raster — programmatic header is used instead.
    }
    _idpMayorLetterBackground = null;
  }

  static Future<void> _ensureIdpPdfFonts() async {
    if (_idpPdfFont != null) return;
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    _idpPdfFont = pw.Font.ttf(regular);
    _idpPdfFontBold = pw.Font.ttf(bold);
  }

  static pw.ThemeData get _idpPdfTheme {
    final base = _idpPdfFont ?? pw.Font.helvetica();
    final bold = _idpPdfFontBold ?? pw.Font.helveticaBold();
    return pw.ThemeData.withFont(base: base, bold: bold).copyWith(
      defaultTextStyle: const pw.TextStyle(color: PdfColors.black),
    );
  }

  /// Content area on [long_letter.pdf] — below letterhead title, above footer bar.
  static const pw.EdgeInsets _idpTemplateContentPadding = pw.EdgeInsets.fromLTRB(
    38,
    178,
    38,
    92,
  );

  /// IDP print layout — letterhead background with form fields drawn on top.
  static pw.Widget _idpPageLayout(pw.Widget body) {
    if (_idpMayorLetterBackground != null) {
      // Match BI form: Stack + full-size foreground + Expanded so content actually paints.
      return pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Image(_idpMayorLetterBackground!, fit: pw.BoxFit.fill),
          ),
          pw.Positioned.fill(
            child: pw.Padding(
              padding: _idpTemplateContentPadding,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(child: body),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Programmatic fallback (no background PDF).
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(36, 28, 36, 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _idpMayorHeader(),
          pw.SizedBox(height: 8),
          pw.Expanded(child: body),
          _idpMayorFooter(),
        ],
      ),
    );
  }

  /// BI form body on official A4 letterhead, or [_formLayout] if template unavailable.
  static pw.Widget _biFormPageLayout(
    String formTitle,
    pw.Widget body, {
    bool showTitle = true,
  }) {
    if (_a4LetterBackground != null) {
      final padding =
          showTitle ? _biFormContentPadding : _biFormContinuationPadding;
      return pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Image(_a4LetterBackground!, fit: pw.BoxFit.fill),
          ),
          pw.Padding(
            padding: padding,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (!showTitle) pw.SizedBox(height: 6),
                if (showTitle && formTitle.isNotEmpty) ...[
                  pw.Center(
                    child: pw.Text(
                      formTitle,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _letterheadOrange,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],
                pw.Expanded(child: body),
              ],
            ),
          ),
        ],
      );
    }
    if (showTitle && formTitle.isNotEmpty) {
      return _formLayout(formTitle, body);
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _pdfHeader('BACKGROUND INVESTIGATION (BI FORM)'),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: body,
          ),
        ),
        _pdfFooter(),
      ],
    );
  }

  static pw.Widget _pdfCheckbox(bool checked) {
    return pw.Container(
      width: 9,
      height: 9,
      margin: const pw.EdgeInsets.only(right: 4, top: 1),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.6, color: PdfColors.grey800),
      ),
      alignment: pw.Alignment.center,
      child: checked
          ? pw.Text('/', style: const pw.TextStyle(fontSize: 8))
          : null,
    );
  }

  static pw.Widget _pdfFunctionalAreaRow(String label, bool checked) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfCheckbox(checked),
          pw.Expanded(
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfAnswerBlock(String? text, {int blankLines = 4}) {
    final value = text?.trim();
    if (value != null && value.isNotEmpty) {
      return pw.Text(value, style: const pw.TextStyle(fontSize: 9, height: 1.45));
    }
    return pw.Column(
      children: List.generate(
        blankLines,
        (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Container(
            width: double.infinity,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.4)),
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _biFormPage2Body(BiFormEntry e) {
    const options = BiFormEntry.functionalAreaOptions;
    const leftCount = 6;
    final left = options.take(leftCount).toList();
    final right = options.skip(leftCount).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'A. Functional Areas:',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Please check (/) the boxes opposite the functional area where the applicant can perform effectively.',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: left
                    .map(
                      (o) => _pdfFunctionalAreaRow(
                        o,
                        e.functionalAreas.contains(o),
                      ),
                    )
                    .toList(),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  ...right.map(
                    (o) => _pdfFunctionalAreaRow(
                      o,
                      e.functionalAreas.contains(o),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Other (Please specify)',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _s(e.otherFunctionalArea),
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'I. On performance and other relevant information.',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Please tell us about the work performance of the applicants in the last three (3) years. What are the applicant\'s outstanding accomplishments recognition received and significant contributions to your office if any?',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 4),
        _pdfAnswerBlock(e.performance3Years),
        pw.SizedBox(height: 10),
        pw.Text(
          'What do you think are the challenges or difficulties of the applicant in performing his/ her duties and responsibilities in his/ her position? How did the applicant cope with these challenges?',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 4),
        _pdfAnswerBlock(e.challengesCoping),
        pw.SizedBox(height: 10),
        pw.Text(
          'In terms of compliance with rules and regulation, please provide us information on the applicant\'s attendance to flag ceremonies/ retreats and other office programs and activities?',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 4),
        _pdfAnswerBlock(e.complianceAttendance),
      ],
    );
  }

  static pw.Widget _biFormPage3Body(BiFormEntry e) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Other relevant information/ data (critical incidents, family background, health profile habits, vices, membership in unions/ associations, or any derogatory records) about the applicants, if any.',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        _pdfAnswerBlock(e.otherRelevantInformation, blankLines: 12),
      ],
    );
  }

  /// Letter size: 8.5" × 11" (e.g. Letter.pdf)
  static final PdfPageFormat pageLetter =
      PdfPageFormat(612, 792, marginAll: 36);

  /// Long bond: 8.5" × 14" (e.g. Long Letter.pdf)
  static final PdfPageFormat pageLong =
      PdfPageFormat(612, 1008, marginAll: 36);

  /// A4: 210 × 297 mm (e.g. A4 Letter.pdf)
  static final PdfPageFormat pageA4 = PdfPageFormat.a4;

  /// Letter 8.5" × 11" landscape — wide RSP/L&D tables.
  static PdfPageFormat get pageLetterLandscape => pageLetter.landscape;

  /// Long bond 8.5" × 14" landscape — wide RSP board forms.
  static PdfPageFormat get pageLongLandscape => pageLong.landscape;

  static String _s(String? v) => v?.trim() ?? '—';

  /// Empty IDP fields stay blank (avoids missing-glyph squares from em dash).
  static String _idpField(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? '' : t;
  }

  static Future<void> printDocument(
    pw.Document doc, {
    String name = 'form.pdf',
    PdfPageFormat? format,
    bool dynamicLayout = true,
  }) async {
    final bytes = await doc.save();
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat _) async => bytes,
      name: name,
      format: format ?? PdfPageFormat.letter,
      dynamicLayout: dynamicLayout,
    );
  }

  /// Shows loading feedback, preloads assets, builds once, then opens the print dialog.
  static Future<void> printForm({
    required BuildContext context,
    required Future<pw.Document> Function() buildDocument,
    required String filename,
    PdfPageFormat? format,
    bool dynamicLayout = true,
  }) async {
    if (!context.mounted) return;

    var loadingShown = false;
    void showLoading() {
      if (!context.mounted || loadingShown) return;
      loadingShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => PopScope(
          canPop: false,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Preparing print…',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    void hideLoading() {
      if (!loadingShown || !context.mounted) return;
      loadingShown = false;
      Navigator.of(context, rootNavigator: true).pop();
    }

    showLoading();
    try {
      await warmupPrintAssets();
      final doc = await buildDocument();
      final bytes = await doc.save();
      hideLoading();
      if (!context.mounted) return;

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => bytes,
        name: filename,
        format: format ?? PdfPageFormat.letter,
        dynamicLayout: dynamicLayout,
      );
    } catch (e) {
      hideLoading();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
      rethrow;
    }
  }

  static PdfPageFormat get biPrintPageFormat => pageA4.copyWith(
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0,
      );

  static PdfPageFormat get idpLayoutPrintFormat => pagePhilippineLong.copyWith(
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0,
      );

  /// Print IDP on Philippine long bond (Mayor's office layout).
  static Future<void> printIdpPdf(
    BuildContext context,
    IdpEntry entry,
  ) async {
    await printForm(
      context: context,
      buildDocument: () => buildIdpPdf(entry),
      filename: 'Individual_Development_Plan.pdf',
      format: idpLayoutPrintFormat,
      dynamicLayout: false,
    );
  }

  static Future<void> sharePdf(
    pw.Document doc, {
    String name = 'form.pdf',
  }) async {
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  /// Design layout: wraps body with standard header and footer (matches sample Letter/Long/A4).
  static pw.Widget _formLayout(
    String formTitle,
    pw.Widget body, {
    bool useBoardHeader = false,
    String? officeName,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        useBoardHeader
            ? _pdfHeaderBoard(formTitle, officeName: officeName)
            : _pdfHeader(formTitle),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: body,
          ),
        ),
        _pdfFooter(),
      ],
    );
  }

  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );

  static Future<pw.Document> buildBiFormPdf(BiFormEntry e) async {
    await Future.wait([
      ensureLogoLoaded(),
      ensureA4LetterTemplateLoaded(),
    ]);
    final doc = pw.Document();
    const formTitle = 'BACKGROUND INVESTIGATION (BI FORM)';
    final pageFormat = _a4LetterBackground != null
        ? pageA4.copyWith(
            marginTop: 0,
            marginBottom: 0,
            marginLeft: 0,
            marginRight: 0,
          )
        : pageLetter;

    pw.Widget page1Body() => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'APPLICANT UNDER BI:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      _row('Name:', e.applicantName),
                      _row('Department:', _s(e.applicantDepartment)),
                      _row('Position:', _s(e.applicantPosition)),
                      _row(
                        'Position Applied for in LGU-Plaridel:',
                        _s(e.positionAppliedFor),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'RESPONDENTS:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      _row('Name:', e.respondentName),
                      _row('Position:', _s(e.respondentPosition)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Work relationship: ${e.respondentRelationship}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
              pw.SizedBox(height: 16),
              pw.Text(
                'I. ON COMPETENCIES',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Core and Organizational Competencies:',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Using the following rating guide please check (/) the appropriate box opposite each behavioral Indicator:',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.5),
                  1: pw.FlexColumnWidth(4),
                  2: pw.FlexColumnWidth(0.35),
                  3: pw.FlexColumnWidth(0.35),
                  4: pw.FlexColumnWidth(0.35),
                  5: pw.FlexColumnWidth(0.35),
                  6: pw.FlexColumnWidth(0.35),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children:
                        ['AREA', 'CORE DESCRIPTION', '5', '4', '3', '2', '1']
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  h,
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...List.generate(9, (i) {
                    final r = [
                      e.rating1,
                      e.rating2,
                      e.rating3,
                      e.rating4,
                      e.rating5,
                      e.rating6,
                      e.rating7,
                      e.rating8,
                      e.rating9,
                    ][i];
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            '${i + 1}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            BiFormEntry.competencyDescriptions[i],
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 5 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 4 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 3 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 2 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 1 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) => _biFormPageLayout(formTitle, page1Body()),
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) => _biFormPageLayout(
          '',
          _biFormPage2Body(e),
          showTitle: false,
        ),
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) => _biFormPageLayout(
          '',
          _biFormPage3Body(e),
          showTitle: false,
        ),
      ),
    );
    return doc;
  }

  static final PdfColor _letterheadNavy = PdfColor.fromInt(0xFF1A237E);
  static final PdfColor _letterheadOrange = PdfColor.fromInt(0xFFE85D04);

  static pw.Widget _pdfHeader(String formTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _logoBytes != null
                ? pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _letterheadNavy, width: 1.5),
                    ),
                    child: pw.ClipOval(
                      child: pw.SizedBox(
                        width: 52,
                        height: 52,
                        child: pw.Image(
                          pw.MemoryImage(_logoBytes!),
                          fit: pw.BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                : pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _letterheadNavy, width: 1.5),
                      color: PdfColors.white,
                    ),
                  ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'Republic of the Philippines',
                  style: pw.TextStyle(fontSize: 9, color: _letterheadNavy),
                ),
                pw.Text(
                  'PROVINCE OF MISAMIS OCCIDENTAL',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _letterheadNavy,
                  ),
                ),
                pw.Text(
                  'MUNICIPALITY OF PLARIDEL',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _letterheadNavy,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Container(
                  width: 180,
                  height: 2,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _letterheadOrange,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          formTitle,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadOrange,
          ),
        ),
        pw.SizedBox(height: 14),
      ],
    );
  }

  static pw.Widget _pdfFooter() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  _pdfFooterIcon(),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    '(088) 3448-200',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(width: 12),
                  _pdfFooterIcon(),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    '(088) 3448-358',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  _pdfFooterIcon(),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    'plaridel_misocc@yahoo.com',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'Asenso',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  fontWeight: pw.FontWeight.bold,
                  color: _letterheadNavy,
                ),
              ),
              pw.Text(
                'PLARIDEL',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _letterheadOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooterIcon() {
    return pw.Container(
      width: 14,
      height: 14,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: _letterheadNavy,
      ),
    );
  }

  static Future<pw.Document> buildPerformanceEvaluationPdf(
    PerformanceEvaluationEntry e,
  ) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'Performance / Functional Evaluation',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
              'A. Functional Areas:',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Please check (/) the boxes opposite the functional area where the applicant can perform effectively.',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              e.functionalAreas.isEmpty ? '—' : e.functionalAreas.join(', '),
              style: const pw.TextStyle(fontSize: 9),
            ),
            _row('Other (Please specify)', _s(e.otherFunctionalArea)),
            pw.SizedBox(height: 12),
            pw.Text(
              'I. On performance and other relevant information.',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Work performance in the last 3 years, accomplishments, recognition, contributions:',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              _s(e.performance3Years),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Challenges/difficulties and how the applicant coped:',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              _s(e.challengesCoping),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Compliance with rules; attendance at flag ceremonies, retreats, office programs:',
              style: const pw.TextStyle(fontSize: 8),
            ),
              pw.Text(
                _s(e.complianceAttendance),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static pw.Widget _idpLabeledLine(String label, String? value, {double labelWidth = 78}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: labelWidth,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(left: 4, bottom: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
              ),
              child: pw.Text(
                _idpField(value),
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _idpCheckboxOption(String label, bool checked) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 8, bottom: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _pdfCheckbox(checked),
          pw.SizedBox(width: 3),
          pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      ),
    );
  }

  static pw.Widget _idpLogoSeal({double size = 46}) {
    if (_logoBytes == null) return pw.SizedBox(width: size, height: size);
    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.ClipOval(
        child: pw.Image(pw.MemoryImage(_logoBytes!), fit: pw.BoxFit.cover),
      ),
    );
  }

  static pw.Widget _idpMayorHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _idpLogoSeal(),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Republic of the Philippines',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 8, color: _letterheadNavy),
                  ),
                  pw.Text(
                    'PROVINCE OF MISAMIS OCCIDENTAL',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _letterheadNavy,
                    ),
                  ),
                  pw.Text(
                    'MUNICIPALITY OF PLARIDEL',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _idpMunicipalityRed,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Container(width: 150, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'OFFICE OF THE MUNICIPAL MAYOR',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _letterheadNavy,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 46),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Center(
          child: pw.Text(
            'INDIVIDUAL DEVELOPMENT PLAN',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _letterheadNavy,
            ),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'LOCAL GOVERNMENT UNIT OF PLARIDEL',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  static pw.Widget _idpPersonalQualifications(IdpEntry e) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _idpLabeledLine('NAME', e.name),
              _idpLabeledLine('POSITION', e.position),
              _idpLabeledLine('CATEGORY', e.category),
              _idpLabeledLine('DIVISION', e.division),
              _idpLabeledLine('DEPARTMENT', e.department),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'QUALIFICATIONS',
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              _idpLabeledLine('EDUCATION', e.education, labelWidth: 72),
              _idpLabeledLine('EXPERIENCE', e.experience, labelWidth: 72),
              _idpLabeledLine('TRAINING', e.training, labelWidth: 72),
              _idpLabeledLine('ELIGIBILITY', e.eligibility, labelWidth: 72),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _idpUnderlineField(String text, {double minHeight = 14}) {
    return pw.Container(
      width: double.infinity,
      constraints: pw.BoxConstraints(minHeight: minHeight),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
      ),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  static pw.Widget _idpInlineRatingLine({
    required String avg,
    required String opcr,
    required String ipcr,
  }) {
    pw.Widget slot(String label, String value) {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
          pw.SizedBox(width: 4),
          pw.Container(
            width: 52,
            padding: const pw.EdgeInsets.only(bottom: 1),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 7.5)),
          ),
        ],
      );
    }

    return pw.Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: pw.WrapCrossAlignment.end,
      children: [
        slot('Average Rating:', avg),
        slot('OPCR', opcr),
        slot('IPCR', ipcr),
      ],
    );
  }

  static pw.Widget _idpSuccessionBlock(IdpEntry e) {
    final perf = e.performanceRating;
    final comp = e.competenceRating;
    final succ = e.successionPriorityRating;
    final accomplishments = e.significantAccomplishments?.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SIGNIFICANT ACCOMPLISHMENTS:',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        _idpUnderlineField(
          accomplishments != null && accomplishments.isNotEmpty
              ? accomplishments
              : ' ',
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'SUCCESSION ANALYSIS (RESULTS OF THE COMPETENCY-BASED SUCCESSION PRIORITY MATRIX)',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'TARGET POSITIONS:',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8, top: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Text('1.', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: _idpUnderlineField(_idpField(e.targetPosition1)),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text('2.', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: _idpUnderlineField(_idpField(e.targetPosition2)),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'REQUIRED QUALIFICATIONS:',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, top: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '1.',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '* BACHELOR\'S DEGREE related to management/admin',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                    pw.Text(
                      '* Five years\' experience in Management and Administration work',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                    pw.Text(
                      '* 40 hours relevant training',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                    pw.Text(
                      '* 1st Level Eligibility',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '2. Performance, average 2 latest previous SPMS-IPCR Rating (PLEASE ATTACHED)',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
              pw.SizedBox(height: 3),
              _idpInlineRatingLine(
                avg: _idpField(e.avgRating),
                opcr: _idpField(e.opcr),
                ipcr: _idpField(e.ipcr),
              ),
              pw.Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  _idpCheckboxOption('Poor', perf == 'poor'),
                  _idpCheckboxOption('Unsatisfactory', perf == 'unsatisfactory'),
                  _idpCheckboxOption(
                    'Very Satisfactory',
                    perf == 'very_satisfactory',
                  ),
                  _idpCheckboxOption('Outstanding', perf == 'outstanding'),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '3. Competence, Assessment on Identified Key Position Average',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Text('Competency:', style: const pw.TextStyle(fontSize: 7.5)),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: _idpUnderlineField(_idpField(e.competencyDescription)),
                  ),
                ],
              ),
              pw.Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  _idpCheckboxOption('Basic', comp == 'basic'),
                  _idpCheckboxOption('Immediate', comp == 'immediate'),
                  _idpCheckboxOption('Advanced', comp == 'advanced'),
                  _idpCheckboxOption('Superior', comp == 'superior'),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '4. Succession Priority Rating Total Score:',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
              if (e.successionPriorityScore?.trim().isNotEmpty == true) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  _idpField(e.successionPriorityScore),
                  style: const pw.TextStyle(fontSize: 7.5),
                ),
              ],
              pw.Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  _idpCheckboxOption('Priority', succ == 'priority'),
                  _idpCheckboxOption('Priority 2', succ == 'priority_2'),
                  _idpCheckboxOption('Priority 3', succ == 'priority_3'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<IdpPlanRow> _idpPlanRowsForPrint(IdpEntry e) {
    final rows = List<IdpPlanRow>.from(e.developmentPlanRows);
    while (rows.length < 2) {
      rows.add(const IdpPlanRow());
    }
    return rows.take(2).toList();
  }

  static pw.Widget _idpDevelopmentTable(IdpEntry e) {
    final rows = _idpPlanRowsForPrint(e);
    pw.Widget cell(String text, {bool header = false, bool center = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: header ? 7.5 : 7,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: 56,
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.5, color: PdfColors.grey800),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Short Term\n(6 months)',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.4),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(0.9),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cell('OBJECTIVES', header: true, center: true),
                  cell('L & D PROGRAM', header: true, center: true),
                  cell('REQUIREMENTS', header: true, center: true),
                  cell('TIME FRAME', header: true, center: true),
                ],
              ),
              ...rows.map(
                (r) => pw.TableRow(
                  children: [
                    cell(_idpField(r.objectives)),
                    cell(_idpField(r.ldProgram)),
                    cell(_idpField(r.requirements)),
                    cell(_idpField(r.timeFrame)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _idpSignatureBlock({
    required String role,
    required String? name,
    required String title,
    String? fixedNameBelow,
    bool nameOnSignatureLine = true,
  }) {
    final lineName = name?.trim() ?? '';
    final printedName = fixedNameBelow?.trim() ?? '';
    final onLine = nameOnSignatureLine ? lineName : '';
    final belowLine =
        nameOnSignatureLine ? '' : (lineName.isNotEmpty ? lineName : printedName);
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            role,
            style: const pw.TextStyle(fontSize: 7),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Container(
            width: double.infinity,
            height: 26,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            alignment: pw.Alignment.bottomCenter,
            child: onLine.isNotEmpty
                ? pw.Text(
                    onLine,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  )
                : null,
          ),
          if (belowLine.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              belowLine,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
          if (title.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: belowLine.isNotEmpty
                    ? pw.FontWeight.normal
                    : pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _idpMayorFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: 5,
          color: _letterheadNavy,
        ),
        pw.Container(
          height: 52,
          color: _letterheadNavy,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Row(
                      children: [
                        _pdfFooterIcon(),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          '(088) 3448-200',
                          style: pw.TextStyle(fontSize: 7.5, color: PdfColors.white),
                        ),
                        pw.SizedBox(width: 12),
                        _pdfFooterIcon(),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          '(088) 3448-358',
                          style: pw.TextStyle(fontSize: 7.5, color: PdfColors.white),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        _pdfFooterIcon(),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          'asensoplaridel@gmail.com',
                          style: pw.TextStyle(fontSize: 7.5, color: PdfColors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_idpBuildingBytes != null)
                pw.Container(
                  width: 88,
                  height: 40,
                  child: pw.Image(
                    pw.MemoryImage(_idpBuildingBytes!),
                    fit: pw.BoxFit.cover,
                  ),
                )
              else
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Asenso',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontStyle: pw.FontStyle.italic,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      'PLARIDEL',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: _letterheadOrange,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        pw.Container(height: 4, color: _letterheadOrange),
      ],
    );
  }

  static pw.Widget _idpSignatures(IdpEntry e) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _idpSignatureBlock(
          role: 'Prepared by:',
          name: e.preparedBy,
          title: 'Employee',
        ),
        pw.SizedBox(width: 8),
        _idpSignatureBlock(
          role: 'Reviewed by:',
          name: e.reviewedBy,
          title: 'Department Head',
        ),
        pw.SizedBox(width: 8),
        _idpSignatureBlock(
          role: 'Noted by:',
          name: e.notedBy,
          title: IdpEntry.defaultNotedByTitle,
          fixedNameBelow: IdpEntry.defaultNotedByName,
          nameOnSignatureLine: false,
        ),
        pw.SizedBox(width: 8),
        _idpSignatureBlock(
          role: 'Approved by:',
          name: e.approvedBy,
          title: IdpEntry.defaultApprovedByTitle,
          fixedNameBelow: IdpEntry.defaultApprovedByName,
          nameOnSignatureLine: false,
        ),
      ],
    );
  }

  static Future<pw.Document> buildIdpPdf(IdpEntry e) async {
    await _ensureIdpAssets();
    final doc = pw.Document(theme: _idpPdfTheme);

    // Use zero margins so the background image fills the full page edge-to-edge.
    final pageFormat = pagePhilippineLong.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );

    final body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _idpPersonalQualifications(e),
        pw.SizedBox(height: 5),
        _idpSuccessionBlock(e),
        pw.SizedBox(height: 5),
        _idpDevelopmentTable(e),
        pw.SizedBox(height: 10),
        _idpSignatures(e),
      ],
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) => _idpPageLayout(body),
      ),
    );
    return doc;
  }

  static Future<pw.Document> buildApplicantsProfilePdf(ApplicantsProfileEntry e) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLongLandscape,
        build: (ctx) => _formLayout(
          'APPLICANTS PROFILE',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row('Position Applied for:', _s(e.positionAppliedFor)),
            _row('Minimum Requirements:', _s(e.minimumRequirements)),
            _row('Date of Posting:', _s(e.dateOfPosting)),
            _row('Closing Date:', _s(e.closingDate)),
            pw.SizedBox(height: 12),
            if (e.applicants.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(0.4),
                  4: const pw.FlexColumnWidth(0.4),
                  5: const pw.FlexColumnWidth(0.8),
                  6: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'NAME',
                              'COURSE',
                              'ADDRESS',
                              'SEX',
                              'AGE',
                              'CIVIL STATUS',
                              'REMARK (DISABILITY)',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 8),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.applicants.map(
                    (a) => pw.TableRow(
                      children:
                          [
                                _s(a.name),
                                _s(a.course),
                                _s(a.address),
                                _s(a.sex),
                                _s(a.age),
                                _s(a.civilStatus),
                                _s(a.remarkDisability),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 8),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _row('Prepared by:', _s(e.preparedBy)),
              _row('Checked by:', _s(e.checkedBy)),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static pw.Widget _pdfHeaderBoard(String formTitle, {String? officeName}) {
    final textBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          'Republic of the Philippines',
          style: pw.TextStyle(fontSize: 9, color: _letterheadNavy),
        ),
        pw.Text(
          'PROVINCE OF MISAMIS OCCIDENTAL',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadNavy,
          ),
        ),
        pw.Text(
          'MUNICIPALITY OF PLARIDEL',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadNavy,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          width: 160,
          height: 1.5,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'HUMAN RESOURCE MERIT PROMOTION AND SELECTION BOARD',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadOrange,
          ),
        ),
        if (officeName != null && officeName.isNotEmpty)
          pw.Text(
            officeName,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
      ],
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _logoBytes != null
                ? pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _letterheadNavy, width: 1.5),
                    ),
                    child: pw.ClipOval(
                      child: pw.SizedBox(
                        width: 52,
                        height: 52,
                        child: pw.Image(
                          pw.MemoryImage(_logoBytes!),
                          fit: pw.BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                : pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _letterheadNavy, width: 1.5),
                      color: PdfColors.white,
                    ),
                  ),
            pw.SizedBox(width: 12),
            textBlock,
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          formTitle,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadOrange,
          ),
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  static Future<pw.Document> buildComparativeAssessmentPdf(
    ComparativeAssessmentEntry e,
  ) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLongLandscape,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeaderBoard(
              'COMPARATIVE ASSESSMENT OF CANDIDATES FOR PROMOTION',
            ),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'POSITION TO BE FILLED:',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
            pw.Text(
              _s(e.positionToBeFilled),
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'MINIMUM REQUIREMENTS:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            _row('EDUCATION :', _s(e.minReqEducation)),
            _row('EXPERIENCE :', _s(e.minReqExperience)),
            _row('ELIGIBILITY :', _s(e.minReqEligibility)),
            _row('TRAINING :', _s(e.minReqTraining)),
            pw.SizedBox(height: 10),
            if (e.candidates.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(0.8),
                  3: const pw.FlexColumnWidth(0.5),
                  4: const pw.FlexColumnWidth(0.8),
                  5: const pw.FlexColumnWidth(0.6),
                  6: const pw.FlexColumnWidth(0.5),
                  7: const pw.FlexColumnWidth(0.8),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'CANDIDATES',
                              'Present Position/Salary Grade/Monthly Salary',
                              'EDUCATION',
                              'No. of hrs. Related Training',
                              'Related Experienced',
                              'Eligibility',
                              'Performance Rating',
                              'REMARKS',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(3),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.candidates.map(
                    (c) => pw.TableRow(
                      children:
                          [
                                _s(c.candidateName),
                                _s(c.presentPositionSalary),
                                _s(c.education),
                                _s(c.trainingHrs),
                                _s(c.relatedExperience),
                                _s(c.eligibility),
                                _s(c.performanceRating),
                                _s(c.remarks),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
          _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  static Future<pw.Document> buildPromotionCertificationPdf(
    PromotionCertificationEntry e,
  ) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'Promotion Certification / Screening',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row('Position for promotion:', _s(e.positionForPromotion)),
            pw.SizedBox(height: 10),
            if (e.candidates.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: ['Name', '1', '2', '3', '4', '5']
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              h,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  ...e.candidates.map(
                    (c) => pw.TableRow(
                      children:
                          [
                                _s(c.name),
                                _s(c.col1),
                                _s(c.col2),
                                _s(c.col3),
                                _s(c.col4),
                                _s(c.col5),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 8),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            pw.Text(
              'We hereby certify that the above candidate(s) have been screened and found to be qualified for promotion to the above position.',
              style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Done this ${_s(e.dateDay)} day of ${_s(e.dateMonth)}, ${_s(e.dateYear)}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              _s(e.signatoryName),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _s(e.signatoryTitle),
              style: const pw.TextStyle(fontSize: 9),
            ),
              pw.Text('Secretariat', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static Future<pw.Document> buildSelectionLineupPdf(SelectionLineupEntry e) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetterLandscape,
        build: (ctx) => _formLayout(
          'SELECTION LINE-UP',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Date: ${_s(e.date)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            _row('Name of Agency/Office:', _s(e.nameOfAgencyOffice)),
            _row('Vacant Position:', _s(e.vacantPosition)),
            _row('Item No.:', _s(e.itemNo)),
            pw.SizedBox(height: 10),
            if (e.applicants.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'NAME OF APPLICANTS',
                              'EDUCATION',
                              'EXPERIENCE',
                              'TRAINING',
                              'ELIGIBILITY',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(3),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.applicants.map(
                    (a) => pw.TableRow(
                      children:
                          [
                                _s(a.name),
                                _s(a.education),
                                _s(a.experience),
                                _s(a.training),
                                _s(a.eligibility),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Prepared by:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _s(e.preparedByName),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
              pw.Text(
                _s(e.preparedByTitle),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static Future<pw.Document> buildTurnAroundTimePdf(TurnAroundTimeEntry e) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLongLandscape,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeaderBoard(
              'TURN-AROUND TIME',
              officeName: 'MGO-Plaridel, Misamis Occidental',
            ),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _row('Position:', _s(e.position)),
            _row('Office:', _s(e.office)),
            _row('No. of Vacant Position:', _s(e.noOfVacantPosition)),
            _row('Date of Publication:', _s(e.dateOfPublication)),
            _row('End Search:', _s(e.endSearch)),
            _row('Q.S.:', _s(e.qs)),
            pw.SizedBox(height: 10),
            if (e.applicants.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(0.6),
                  2: const pw.FlexColumnWidth(0.6),
                  3: const pw.FlexColumnWidth(0.6),
                  4: const pw.FlexColumnWidth(0.5),
                  5: const pw.FlexColumnWidth(0.5),
                  6: const pw.FlexColumnWidth(0.6),
                  7: const pw.FlexColumnWidth(0.6),
                  8: const pw.FlexColumnWidth(0.5),
                  9: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'Name of Applicant',
                              'Date of Initial Assesment',
                              'Date of Contract for trade and written exam',
                              'Skills Trade/ Exam Result',
                              'Date of Deliberation',
                              'Date of Job Offer',
                              'Acceptance date of Job Offer',
                              'Date of Assumption to Duty',
                              'No. of Days to Fill-Up Position',
                              'Overall Cost per hire',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(2),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 6),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.applicants.map(
                    (a) => pw.TableRow(
                      children:
                          [
                                _s(a.name),
                                _s(a.dateInitialAssessment),
                                _s(a.dateContractExam),
                                _s(a.skillsTradeExamResult),
                                _s(a.dateDeliberation),
                                _s(a.dateJobOffer),
                                _s(a.acceptanceDate),
                                _s(a.dateAssumptionToDuty),
                                _s(a.noOfDaysToFillUp),
                                _s(a.overallCostPerHire),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(2),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 6),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Prepared by:',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        _s(e.preparedByName),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _s(e.preparedByTitle),
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Noted by:',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        _s(e.notedByName),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _s(e.notedByTitle),
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
                  ],
                ),
              ),
            ),
            _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  /// Training Need Analysis and Consolidated Report (L&D) — header with CY and Department, then 6-column table.
  static Future<pw.Document> buildTrainingNeedAnalysisPdf(TrainingNeedAnalysisEntry e) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetterLandscape,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeader('TRAINING NEED ANALYSIS'),
            pw.Text(
              'AND CONSOLIDATED REPORT',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('FOR CY ${_s(e.cyYear)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('DEPARTMENT: ${_s(e.department)}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 14),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: e.rows.isEmpty
                    ? pw.Text('—', style: const pw.TextStyle(fontSize: 10))
                    : pw.Table(
                        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.2),
                          1: pw.FlexColumnWidth(1),
                          2: pw.FlexColumnWidth(1),
                          3: pw.FlexColumnWidth(1),
                          4: pw.FlexColumnWidth(1),
                          5: pw.FlexColumnWidth(1.2),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            children: [
                              'NAME/POSITION',
                              'GOAL',
                              'BEHAVIOR',
                              'SKILLS/KNOWLEDGE',
                              'NEED FOR TRAINING',
                              'TRAINING RECOMMENDATIONS',
                            ]
                                .map(
                                  (h) => pw.Padding(
                                    padding: const pw.EdgeInsets.all(4),
                                    child: pw.Text(
                                      h,
                                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          ...e.rows.map(
                            (r) => pw.TableRow(
                              children: [
                                _s(r.namePosition),
                                _s(r.goal),
                                _s(r.behavior),
                                _s(r.skillsKnowledge),
                                _s(r.needForTraining),
                                _s(r.trainingRecommendations),
                              ]
                                  .map(
                                    (v) => pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(v, style: const pw.TextStyle(fontSize: 8)),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  /// Action Brainstorming and Coaching Worksheet (L&D) — DEPARTMENT, DATE, instruction, 7-column table, Certified by / Date.
  static Future<pw.Document> buildActionBrainstormingCoachingPdf(ActionBrainstormingEntry e) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetterLandscape,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeader('ACTION BRAINSTORMING AND COACHING WORKSHEET'),
            _row('DEPARTMENT:', _s(e.department)),
            _row('DATE:', _s(e.date)),
            pw.SizedBox(height: 8),
            pw.Text(
              'Instruction: Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: e.rows.isEmpty
                    ? pw.Text('—', style: const pw.TextStyle(fontSize: 10))
                    : pw.Table(
                        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(0.4),
                          1: pw.FlexColumnWidth(1),
                          2: pw.FlexColumnWidth(1),
                          3: pw.FlexColumnWidth(1),
                          4: pw.FlexColumnWidth(1),
                          5: pw.FlexColumnWidth(1),
                          6: pw.FlexColumnWidth(1),
                          7: pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            children: [
                              '#',
                              'NAME',
                              'STOP DOING',
                              'DO LESS OF',
                              'KEEP DOING',
                              'DO MORE OF',
                              'START DOING',
                              'GOAL',
                            ]
                                .map(
                                  (h) => pw.Padding(
                                    padding: const pw.EdgeInsets.all(3),
                                    child: pw.Text(
                                      h,
                                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          ...e.rows.asMap().entries.map(
                                (entry) {
                                  final i = entry.key + 1;
                                  final r = entry.value;
                                  return pw.TableRow(
                                    children: [
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.all(3),
                                        child: pw.Text('$i', style: const pw.TextStyle(fontSize: 8)),
                                      ),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.name), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.stopDoing), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.doLessOf), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.keepDoing), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.doMoreOf), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.startDoing), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.goal), style: const pw.TextStyle(fontSize: 7))),
                                    ],
                                  );
                                },
                              ),
                        ],
                      ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Certified by:', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(_s(e.certifiedBy), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Department Head', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Date:', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(_s(e.certificationDate), style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  /// Simple printable summary for employee training daily reports (L&D).
  static Future<void> printTrainingDailyReport(TrainingDailyReport r) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'TRAINING DAILY REPORT',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row('Employee:', _s(r.employeeName)),
              _row('Title:', _s(r.title)),
              pw.SizedBox(height: 8),
              pw.Text('Description', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(_s(r.description), style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 8),
              _row('Status:', _s(r.status)),
              _row('Submitted:', r.submittedAt.toLocal().toString()),
              if (r.attachmentName != null && r.attachmentName!.trim().isNotEmpty)
                _row('Attachment:', _s(r.attachmentName)),
            ],
          ),
        ),
      ),
    );
    await printDocument(doc, name: 'training-daily-report.pdf');
  }
}
