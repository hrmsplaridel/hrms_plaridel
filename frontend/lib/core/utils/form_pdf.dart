import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Use project data models (same package)
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/features/learning_development/models/comparative_assessment.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/learning_application_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/learning_development/models/performance_evaluation_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/promotion_certification.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_need_analysis.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/forms/data/form_print_template_repo.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

/// Builds PDF documents from RSP form entries and supports print / share.
/// Paper sizes match sample files: Letter.pdf (8.5"×11"), Long Letter.pdf (8.5"×14"), A4 Letter.pdf.
class FormPdf {
  FormPdf._();

  static Uint8List? _logoBytes;
  static Future<void>? _warmupFuture;

  /// Preloads logos, letterhead rasters, and IDP fonts so first Print is fast.
  /// If a previous attempt failed (e.g. plugin not ready on first web load),
  /// the cached future is cleared so the next call retries cleanly.
  static Future<void> warmupPrintAssets() {
    _warmupFuture ??=
        Future.wait([
          ensureLogoLoaded(),
          ensureA4LetterTemplateLoaded(),
          _ensureIdpPdfFonts(),
          _loadIdpBuildingImage(),
          _loadIdpTemplateBackground(),
        ]).catchError((Object e, StackTrace st) {
          _warmupFuture = null; // reset so the next call retries
          Error.throwWithStackTrace(e, st);
        });
    return _warmupFuture!;
  }

  /// Warm letterheads, then prefetch saved backgrounds without blocking Print.
  static void warmupThenPrefetchBackgrounds() {
    unawaited(warmupPrintAssets().then((_) => prefetchSavedBackgrounds()));
  }

  /// Loads saved form backgrounds in the background (needs an authenticated API).
  static Future<void> prefetchSavedBackgrounds() async {
    try {
      final list = await FormPrintTemplateRepo.instance.list();
      final have = <String>{};
      for (final t in list) {
        have.add('${t.module}|${t.formKey}');
        await _bindCustomTemplate(t.module, t.formKey);
      }
      for (final module in const ['rsp', 'ld']) {
        for (final f in FormPrintCatalog.formsFor(module)) {
          final key = '$module|${f.key}';
          if (have.contains(key)) continue;
          _customTemplateCache.putIfAbsent(key, () => const _CustomPrintBind());
        }
      }
    } catch (_) {}
  }

  /// Official A4 letterhead PDF (Municipality of Plaridel) for BI form print/PDF.
  static const String _a4LetterAsset = 'assets/forms/a4_letter.pdf';
  static pw.MemoryImage? _a4LetterBackground;

  /// Mayor's Office Long Letter letterhead — background for IDP print.
  static const String _idpMayorLetterAsset = 'assets/forms/long_letter.pdf';
  static pw.MemoryImage? _idpMayorLetterBackground;
  static final Map<String, _CustomPrintBind> _customTemplateCache = {};
  static pw.MemoryImage? _activeCustomBg;
  static pw.MemoryImage? _lockedPrintBg;
  static PdfPageFormat? _activeCustomFormat;
  static String? _customTemplateError;
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
  static const pw.EdgeInsets _biFormContinuationPadding =
      pw.EdgeInsets.fromLTRB(42, 162, 42, 88);

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

  static bool get _useCustomPrintBg =>
      _lockedPrintBg != null || _activeCustomBg != null;

  static const pw.EdgeInsets _customPrintContentPadding =
      pw.EdgeInsets.fromLTRB(42, 150, 42, 72);

  /// Drops a cached upload so the next print reloads from the API.
  static void invalidateCustomTemplate(String module, String formKey) {
    _customTemplateCache.remove('$module|$formKey');
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
  }

  static PdfPageFormat _printPageFormat(PdfPageFormat fallback) {
    return _activeCustomFormat ?? fallback;
  }

  static PdfPageFormat _pdfFormatFromPaperSize(String id) {
    final paper = FormPrintCatalog.paperById(id);
    return PdfPageFormat(
      paper?.widthPt ?? 612,
      paper?.heightPt ?? 792,
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
  }

  static PdfPageFormat _catalogFormatMatching(PdfPageFormat f) {
    for (final s in FormPrintCatalog.paperSizes) {
      if ((s.widthPt - f.width).abs() < 2 &&
          (s.heightPt - f.height).abs() < 2) {
        return _pdfFormatFromPaperSize(s.id);
      }
    }
    return PdfPageFormat(
      f.width,
      f.height,
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
  }

  static pw.Widget _formTitleOnly(String title) {
    if (title.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Center(
        child: pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
  }

  static pw.Widget _printPage(pw.Widget child) {
    final bg = _lockedPrintBg ?? _activeCustomBg;
    if (bg == null) return child;
    return pw.Stack(
      children: [
        pw.Positioned.fill(child: pw.Image(bg, fit: pw.BoxFit.fill)),
        pw.Positioned.fill(
          child: pw.Padding(
            padding: _customPrintContentPadding,
            child: child,
          ),
        ),
      ],
    );
  }

  static Future<void> _bindCustomTemplate(String module, String formKey) async {
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
    _customTemplateError = null;
    final cacheKey = '$module|$formKey';
    final cached = _customTemplateCache[cacheKey];
    if (cached != null) {
      _activeCustomBg = cached.image;
      _lockedPrintBg = cached.image;
      _activeCustomFormat = cached.format;
      return;
    }
    try {
      final meta = await FormPrintTemplateRepo.instance.getMeta(
        module: module,
        formKey: formKey,
      );
      if (meta == null) {
        _customTemplateCache[cacheKey] = const _CustomPrintBind();
        return;
      }
      final bytes = await FormPrintTemplateRepo.instance.fetchFileBytes(
        module: module,
        formKey: formKey,
      );
      if (bytes == null || bytes.isEmpty) {
        _customTemplateError =
            'Saved background file is missing. Re-upload it in Forms → Print background.';
        return;
      }
      if (bytes[0] == 0x3C) {
        _customTemplateError =
            'Could not download the saved background. Try printing again.';
        return;
      }
      final image = await _memoryImageFromTemplateBytes(
        bytes,
        meta.mimeType,
        meta.originalFilename,
      );
      if (image == null) {
        _customTemplateError =
            'Could not read the uploaded file for print. Use PDF, PNG, or JPG.';
        return;
      }
      final bind = _CustomPrintBind(
        image: image,
        format: _pdfFormatFromPaperSize(meta.paperSize),
      );
      _customTemplateCache[cacheKey] = bind;
      _activeCustomBg = bind.image;
      _lockedPrintBg = bind.image;
      _activeCustomFormat = bind.format;
    } catch (e) {
      _customTemplateError =
          'Could not load the saved form background. Printing with the default letterhead.';
      debugPrint('Form background bind failed ($module/$formKey): $e');
    }
  }

  static Future<pw.MemoryImage?> _memoryImageFromTemplateBytes(
    List<int> bytes,
    String? mimeType,
    String? filename,
  ) async {
    final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final lowerName = (filename ?? '').toLowerCase();
    final mime = (mimeType ?? '').toLowerCase();
    final isPdf =
        mime.contains('pdf') ||
        lowerName.endsWith('.pdf') ||
        (raw.length >= 5 &&
            raw[0] == 0x25 &&
            raw[1] == 0x50 &&
            raw[2] == 0x44 &&
            raw[3] == 0x46 &&
            raw[4] == 0x2D);
    if (!isPdf) {
      return pw.MemoryImage(raw);
    }
    await for (final page in Printing.raster(raw, pages: const [0], dpi: 96)) {
      return pw.MemoryImage(await page.toPng());
    }
    return null;
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
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
    ).copyWith(defaultTextStyle: const pw.TextStyle(color: PdfColors.black));
  }

  /// Content area on [long_letter.pdf] — below letterhead title, above footer bar.
  static const pw.EdgeInsets _idpTemplateContentPadding =
      pw.EdgeInsets.fromLTRB(38, 178, 38, 92);

  /// IDP print layout — letterhead background with form fields drawn on top.
  static pw.Widget _idpPageLayout(pw.Widget body) {
    final letterhead = _lockedPrintBg ?? _activeCustomBg ?? _idpMayorLetterBackground;
    if (letterhead != null) {
      // Match BI form: Stack + full-size foreground + Expanded so content actually paints.
      return pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Image(letterhead, fit: pw.BoxFit.fill),
          ),
          pw.Positioned.fill(
            child: pw.Padding(
              padding: _idpTemplateContentPadding,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [pw.Expanded(child: body)],
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
    final letterhead = _lockedPrintBg ?? _activeCustomBg ?? _a4LetterBackground;
    if (letterhead != null) {
      final padding = showTitle
          ? _biFormContentPadding
          : _biFormContinuationPadding;
      return pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Image(letterhead, fit: pw.BoxFit.fill),
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
      return pw.Text(
        value,
        style: const pw.TextStyle(fontSize: 9, height: 1.45),
      );
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
                    (o) =>
                        _pdfFunctionalAreaRow(o, e.functionalAreas.contains(o)),
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
  static final PdfPageFormat pageLetter = PdfPageFormat(
    612,
    792,
    marginAll: 36,
  );

  /// Long bond: 8.5" × 14" (e.g. Long Letter.pdf)
  static final PdfPageFormat pageLong = PdfPageFormat(612, 1008, marginAll: 36);

  /// A4: 210 × 297 mm (e.g. A4 Letter.pdf)
  static final PdfPageFormat pageA4 = PdfPageFormat.a4;

  /// Letter 8.5" × 11" landscape — wide RSP/L&D tables.
  static PdfPageFormat get pageLetterLandscape => pageLetter.landscape;

  /// Long bond 8.5" × 14" landscape — wide RSP board forms.
  static PdfPageFormat get pageLongLandscape => pageLong.landscape;

  /// Helvetica (built-in PDF font) cannot draw Unicode dashes such as U+2014.
  static String _pdfSafe(String v) => v
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2212', '-')
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u2026', '...');

  static String _s(String? v) {
    final t = v?.trim();
    if (t == null || t.isEmpty) return '-';
    return _pdfSafe(t);
  }

  /// Empty IDP fields stay blank (avoids missing-glyph squares from em dash).
  static String _idpField(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? '' : _pdfSafe(t);
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

  static bool _printInFlight = false;

  /// Builds the PDF then opens the system/browser print dialog.
  /// Saved Form Backgrounds paper size (including 8.5" × 13") is used as the page size.
  static Future<void> printForm({
    required BuildContext context,
    required Future<pw.Document> Function() buildDocument,
    required String filename,
    PdfPageFormat? format,
    bool dynamicLayout = false,
    String? printModule,
    String? printFormKey,
  }) async {
    if (!context.mounted || _printInFlight) return;
    _printInFlight = true;

    OverlayEntry? busy;
    void showBusy() {
      if (!context.mounted || busy != null) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      busy = OverlayEntry(
        builder: (_) => IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Material(
                  elevation: 4,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Opening print…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(busy!);
    }

    void hideBusy() {
      busy?.remove();
      busy = null;
    }

    showBusy();
    try {
      await SchedulerBinding.instance.endOfFrame;
      try {
        await warmupPrintAssets();
      } catch (_) {}

      if (printModule != null && printFormKey != null) {
        await _bindCustomTemplate(printModule, printFormKey);
      }

      final bindError = _customTemplateError;
      final doc = await buildDocument();
      final printFormat = _catalogFormatMatching(
        _activeCustomFormat ?? format ?? PdfPageFormat.letter,
      );
      final bytes = await doc.save();
      _activeCustomBg = null;
      _lockedPrintBg = null;
      _activeCustomFormat = null;
      hideBusy();
      if (!context.mounted) return;

      if (bindError != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(bindError)));
      }

      await SchedulerBinding.instance.endOfFrame;
      if (!context.mounted) return;

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => bytes,
        name: filename,
        format: printFormat,
        dynamicLayout: false,
        forceCustomPrintPaper: true,
      );
    } catch (e) {
      hideBusy();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    } finally {
      hideBusy();
      _printInFlight = false;
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
    IdpEntry entry, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await printForm(
      context: context,
      buildDocument: () => buildIdpPdf(entry, signatures: signatures),
      filename: 'Individual_Development_Plan.pdf',
      format: idpLayoutPrintFormat,
      dynamicLayout: false,
      printModule: 'ld',
      printFormKey: 'idp',
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
    if (_useCustomPrintBg) {
      return _printPage(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (formTitle.isNotEmpty) _formTitleOnly(formTitle),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: body,
              ),
            ),
          ],
        ),
      );
    }
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

  /// Signature block used side-by-side (Prepared by / Checked by): label on
  /// top, centered signature, then the signer's name below.
  static pw.Widget _signatureBlock(
    String label,
    String value, {
    DocuTrackerSourceSignature? signature,
  }) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      ),
      _signatureImage(signature, height: 28),
      pw.Text(
        _signatureName(signature, value),
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 10),
      ),
    ],
  );

  static String _signatureName(
    DocuTrackerSourceSignature? signature,
    String fallback,
  ) {
    final signerName = signature?.signerName?.trim();
    if (signerName != null && signerName.isNotEmpty) return signerName;
    final assignedSignerName = signature?.assignedSignerName?.trim();
    return assignedSignerName == null || assignedSignerName.isEmpty
        ? fallback
        : assignedSignerName;
  }

  /// Renders cropped signature ink without expanding to the parent width.
  ///
  /// When [width] is set (e.g. matching a printed-name line), the ink is
  /// centered inside that band so it sits over the name instead of the
  /// full column (which previously made signatures look shifted right).
  static pw.Widget _signatureImage(
    DocuTrackerSourceSignature? signature, {
    double height = 26,
    double? width,
  }) {
    if (signature?.isSigned != true) {
      return pw.SizedBox(height: height, width: width);
    }
    final image = pw.Image(
      pw.MemoryImage(signature!.signatureImageBytes!),
      fit: pw.BoxFit.contain,
      height: height,
    );
    if (width != null) {
      return pw.SizedBox(
        width: width,
        height: height,
        child: pw.Center(child: image),
      );
    }
    return pw.SizedBox(height: height, child: image);
  }

  /// Signature line with extra blank space for a pen signature, a printed
  /// name on the line, and a caption below (e.g. Printed Name/Over Signature).
  static pw.Widget _signatureLineBlock(
    String label,
    String name, {
    String? caption,
    double lineWidth = 220,
    DocuTrackerSourceSignature? signature,
  }) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      _signatureImage(signature, height: 30, width: lineWidth),
      pw.Container(
        width: lineWidth,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
        ),
        child: pw.Text(
          _signatureName(signature, name),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if (caption != null) ...[
        pw.SizedBox(height: 4),
        pw.SizedBox(
          width: lineWidth,
          child: pw.Text(caption, style: const pw.TextStyle(fontSize: 8)),
        ),
      ],
    ],
  );

  static Future<pw.Document> buildBiFormPdf(BiFormEntry e) async {
    await Future.wait([ensureLogoLoaded(), ensureA4LetterTemplateLoaded()]);
    await _bindCustomTemplate('rsp', 'bi');
    final doc = pw.Document();
    const formTitle = 'BACKGROUND INVESTIGATION (BI FORM)';
    final pageFormat = _printPageFormat(
      _a4LetterBackground != null
          ? pageA4.copyWith(
              marginTop: 0,
              marginBottom: 0,
              marginLeft: 0,
              marginRight: 0,
            )
          : pageLetter,
    );

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
              children: ['AREA', 'CORE DESCRIPTION', '5', '4', '3', '2', '1']
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
        build: (ctx) =>
            _biFormPageLayout('', _biFormPage2Body(e), showTitle: false),
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) =>
            _biFormPageLayout('', _biFormPage3Body(e), showTitle: false),
      ),
    );
    return doc;
  }

  static final PdfColor _letterheadNavy = PdfColor.fromInt(0xFF1A237E);
  static final PdfColor _letterheadOrange = PdfColor.fromInt(0xFFE85D04);

  static pw.Widget _pdfHeader(String formTitle) {
    if (_useCustomPrintBg) return _formTitleOnly(formTitle);
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
                pw.Container(width: 180, height: 2, color: PdfColors.black),
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
    if (_useCustomPrintBg) return pw.SizedBox();
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
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
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
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Please check (/) the boxes opposite the functional area where the applicant can perform effectively.',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                e.functionalAreas.isEmpty ? '-' : e.functionalAreas.join(', '),
                style: const pw.TextStyle(fontSize: 9),
              ),
              _row('Other (Please specify)', _s(e.otherFunctionalArea)),
              pw.SizedBox(height: 12),
              pw.Text(
                'I. On performance and other relevant information.',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
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

  static pw.Widget _idpLabeledLine(
    String label,
    String? value, {
    double labelWidth = 78,
  }) {
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
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.black,
                ),
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
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
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
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
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
                  _idpCheckboxOption(
                    'Unsatisfactory',
                    perf == 'unsatisfactory',
                  ),
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
                  pw.Text(
                    'Competency:',
                    style: const pw.TextStyle(fontSize: 7.5),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: _idpUnderlineField(
                      _idpField(e.competencyDescription),
                    ),
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
    // Official paper has two short-term rows; extra screen rows stay in the
    // saved record but must not push the signatories off the printed page.
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
    DocuTrackerSourceSignature? signature,
    String? fixedNameBelow,
    bool nameOnSignatureLine = true,
  }) {
    final lineName = name?.trim() ?? '';
    final printedName = fixedNameBelow?.trim() ?? '';
    final isSigned = signature?.isSigned == true;
    final resolvedName = _signatureName(
      signature,
      lineName.isNotEmpty ? lineName : printedName,
    );
    final onLine = isSigned ? '' : (nameOnSignatureLine ? lineName : '');
    final belowLine = isSigned
        ? resolvedName
        : nameOnSignatureLine
        ? ''
        : (lineName.isNotEmpty ? lineName : printedName);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            role,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ),
        // Blank strip for a physical pen signature (Applicants Profile pattern).
        isSigned ? _signatureImage(signature, height: 26) : pw.SizedBox(height: 26),
        pw.Container(
          width: double.infinity,
          constraints: const pw.BoxConstraints(minHeight: 12),
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
              : pw.SizedBox(height: 10),
        ),
        if (belowLine.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            belowLine,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (title.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 7.5),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ],
    );
  }

  static pw.Widget _idpMayorFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 5, color: _letterheadNavy),
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
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        _pdfFooterIcon(),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          '(088) 3448-358',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.white,
                          ),
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
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.white,
                          ),
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

  static pw.Widget _idpSignatures(
    IdpEntry e,
    DocuTrackerSourceSignatureBundle? signatures,
  ) {
    pw.Widget pair(pw.Widget left, pw.Widget right) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: left),
          pw.SizedBox(width: 28),
          pw.Expanded(child: right),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pair(
          _idpSignatureBlock(
            role: 'Prepared by:',
            name: e.preparedBy,
            title: 'Employee',
            signature: signatures?.signatureFor('prepared_by'),
          ),
          _idpSignatureBlock(
            role: 'Reviewed by:',
            name: e.reviewedBy,
            title: 'Department Head',
            signature: signatures?.signatureFor('reviewed_by'),
          ),
        ),
        pw.SizedBox(height: 14),
        pair(
          _idpSignatureBlock(
            role: 'Noted by:',
            name: e.notedBy,
            title: IdpEntry.defaultNotedByTitle,
            signature: signatures?.signatureFor('noted_by'),
            fixedNameBelow: IdpEntry.defaultNotedByName,
            nameOnSignatureLine: false,
          ),
          _idpSignatureBlock(
            role: 'Approved by:',
            name: e.approvedBy,
            title: IdpEntry.defaultApprovedByTitle,
            signature: signatures?.signatureFor('approved_by'),
            fixedNameBelow: IdpEntry.defaultApprovedByName,
            nameOnSignatureLine: false,
          ),
        ),
      ],
    );
  }

  static Future<pw.Document> buildIdpPdf(
    IdpEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await _ensureIdpAssets();
    await _bindCustomTemplate('ld', 'idp');
    final doc = pw.Document(theme: _idpPdfTheme);

    // Use zero margins so the background image fills the full page edge-to-edge.
    final pageFormat = _printPageFormat(
      pagePhilippineLong.copyWith(
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0,
      ),
    );

    // Signatories are non-flex so they are measured first and stay above the
    // letterhead footer. The rest of the form uses remaining space.
    final body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _idpPersonalQualifications(e),
              pw.SizedBox(height: 5),
              _idpSuccessionBlock(e),
              pw.SizedBox(height: 6),
              pw.Expanded(child: _idpDevelopmentTable(e)),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        _idpSignatures(e, signatures),
      ],
    );

    doc.addPage(
      pw.Page(pageFormat: pageFormat, build: (ctx) => _idpPageLayout(body)),
    );
    return doc;
  }

  static Future<pw.Document> buildApplicantsProfilePdf(
    ApplicantsProfileEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('rsp', 'applicants_profile');
    final doc = pw.Document();
    final perPage = ApplicantsProfileEntry.applicantsPerFormPage;
    final applicants = e.applicants;
    final pageCount = applicants.isEmpty
        ? 1
        : ((applicants.length - 1) ~/ perPage) + 1;

    pw.Widget applicantsTable(List<ApplicantsProfileApplicant> chunk) {
      if (chunk.isEmpty) {
        return pw.Text('-', style: const pw.TextStyle(fontSize: 10));
      }
      return pw.Table(
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
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
          ...chunk.map(
            (a) => pw.TableRow(
              children:
                  [
                        _s(a.name),
                        _s(a.course),
                        _s(formatStoredAddressForDisplay(a.address)),
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
      );
    }

    for (var page = 0; page < pageCount; page++) {
      final start = page * perPage;
      final end = (start + perPage).clamp(0, applicants.length);
      final chunk = applicants.isEmpty
          ? const <ApplicantsProfileApplicant>[]
          : applicants.sublist(start, end);
      final title = page == 0
          ? 'APPLICANTS PROFILE'
          : 'APPLICANTS PROFILE (Continuation - Form ${page + 1})';

      doc.addPage(
        pw.Page(
          pageFormat: _printPageFormat(pageLongLandscape),
          build: (ctx) => _formLayout(
            title,
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (page == 0) ...[
                  _row('Position Applied for:', _s(e.positionAppliedFor)),
                  _row('Minimum Requirements:', _s(e.minimumRequirements)),
                  _row('Date of Posting:', _s(e.dateOfPosting)),
                  _row('Closing Date:', _s(e.closingDate)),
                ] else ...[
                  _row('Position Applied for:', _s(e.positionAppliedFor)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Continuation of applicants list (rows ${start + 1}–${end == 0 ? start : end}).',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
                pw.SizedBox(height: 12),
                applicantsTable(chunk),
                pw.SizedBox(height: 12),
                if (page == pageCount - 1) ...[
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: _signatureBlock(
                          'Prepared by:',
                          _idpField(e.preparedBy),
                          signature: signatures?.signatureFor('prepared_by'),
                        ),
                      ),
                      pw.SizedBox(width: 32),
                      pw.Expanded(
                        child: _signatureBlock(
                          'Checked by:',
                          _idpField(e.checkedBy),
                          signature: signatures?.signatureFor('checked_by'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return doc;
  }

  static pw.Widget _pdfHeaderBoard(String formTitle, {String? officeName}) {
    if (_useCustomPrintBg) return _formTitleOnly(formTitle);
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
        pw.Container(width: 160, height: 1.5, color: PdfColors.black),
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
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
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
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'POSITION TO BE FILLED:',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _s(e.positionToBeFilled),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'MINIMUM REQUIREMENTS:',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    _row('EDUCATION :', _s(e.minReqEducation)),
                    _row('EXPERIENCE :', _s(e.minReqExperience)),
                    _row('ELIGIBILITY :', _s(e.minReqEligibility)),
                    _row('TRAINING :', _s(e.minReqTraining)),
                    pw.SizedBox(height: 10),
                    if (e.candidates.isEmpty)
                      pw.Text('-', style: const pw.TextStyle(fontSize: 10))
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
                                          style: const pw.TextStyle(
                                            fontSize: 7,
                                          ),
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
                                            style: const pw.TextStyle(
                                              fontSize: 7,
                                            ),
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
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
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
                pw.Text('-', style: const pw.TextStyle(fontSize: 10))
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
                style: pw.TextStyle(
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Done this ${_s(e.dateDay)} day of ${_s(e.dateMonth)}, ${_s(e.dateYear)}.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                _s(e.signatoryName),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
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

  static Future<pw.Document> buildSelectionLineupPdf(
    SelectionLineupEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('rsp', 'selection_lineup');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(pageLetterLandscape),
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
                pw.Text('-', style: const pw.TextStyle(fontSize: 10))
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
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  _signatureImage(signatures?.signatureFor('prepared_by')),
                  pw.Text(
                    _signatureName(
                      signatures?.signatureFor('prepared_by'),
                      _idpField(e.preparedByName),
                    ),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _idpField(e.preparedByTitle),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static Future<pw.Document> buildComputationOfPointsPdf(
    ComputationOfPointsEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('rsp', 'computation_of_points');
    final doc = pw.Document();

    pw.Widget candidateCell(ComputationOfPointsCandidate c) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '1. Name of Candidate',
              style: const pw.TextStyle(fontSize: 5.5),
            ),
            pw.Text(_s(c.name), style: const pw.TextStyle(fontSize: 6.5)),
            pw.SizedBox(height: 2),
            pw.Text('2. Position', style: const pw.TextStyle(fontSize: 5.5)),
            pw.Text(_s(c.position), style: const pw.TextStyle(fontSize: 6.5)),
            pw.SizedBox(height: 2),
            pw.Text(
              '3. Salary Grade',
              style: const pw.TextStyle(fontSize: 5.5),
            ),
            pw.Text(
              _s(c.salaryGrade),
              style: const pw.TextStyle(fontSize: 6.5),
            ),
            pw.SizedBox(height: 2),
            pw.Text('4. Rate', style: const pw.TextStyle(fontSize: 5.5)),
            pw.Text(_s(c.rate), style: const pw.TextStyle(fontSize: 6.5)),
          ],
        ),
      );
    }

    pw.Widget scoreCell(String? v) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Center(
        child: pw.Text(_s(v), style: const pw.TextStyle(fontSize: 7)),
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(pageLetterLandscape),
        build: (ctx) => _printPage(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeaderMayorOffice('COMPUTATION OF POINTS'),
            pw.Center(
              child: pw.Text(
                'Personnel Selection Board',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Date: ${_s(e.date)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.Center(
              child: pw.Text(
                '(${_s(e.positionLevel).isEmpty ? "Second Level Position" : _s(e.positionLevel)})',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _row('POSITION :', _s(e.position)),
                      _row('SALARY GRADE :', _s(e.salaryGrade)),
                      _row('RATE :', _s(e.rate)),
                      _row('OFFICE :', _s(e.office)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _row('EDUCATION :', _s(e.minEducation)),
                      _row('TRAINING :', _s(e.minTraining)),
                      _row('EXPERIENCE :', _s(e.minExperience)),
                      _row('ELIGIBILITY :', _s(e.minEligibility)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            if (e.candidates.isEmpty)
              pw.Text('-', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.2),
                  1: const pw.FlexColumnWidth(0.55),
                  2: const pw.FlexColumnWidth(0.55),
                  3: const pw.FlexColumnWidth(0.55),
                  4: const pw.FlexColumnWidth(0.55),
                  5: const pw.FlexColumnWidth(0.55),
                  6: const pw.FlexColumnWidth(0.55),
                  7: const pw.FlexColumnWidth(0.55),
                  8: const pw.FlexColumnWidth(0.55),
                  9: const pw.FlexColumnWidth(0.45),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'NAME OF CANDIDATES',
                              'EDUCATION (25%)',
                              'ELIGIBILITY (20%)',
                              'EXPERIENCE (15%)',
                              'TRAINING (10%)',
                              'PERFORMANCE (10%)',
                              'POTENTIAL (10%)',
                              'WORK ATTITUDE (10%)',
                              'TOTAL (100%)',
                              'RANK',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(3),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 5.5),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.candidates.map(
                    (c) => pw.TableRow(
                      children: [
                        candidateCell(c),
                        scoreCell(c.education),
                        scoreCell(c.eligibility),
                        scoreCell(c.experience),
                        scoreCell(c.training),
                        scoreCell(c.performance),
                        scoreCell(c.potential),
                        scoreCell(c.workAttitude),
                        scoreCell(c.total),
                        scoreCell(c.rank),
                      ],
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            _signatureLineBlock(
              'Prepared by:',
              _idpField(e.preparedByName),
              caption: '(Printed Name/Over Signature)',
              signature: signatures?.signatureFor('prepared_by'),
            ),
            pw.Spacer(),
            _pdfFooter(),
          ],
        )),
      ),
    );
    return doc;
  }

  static pw.Widget _pdfHeaderMayorOffice(String formTitle) {
    if (_useCustomPrintBg) return _formTitleOnly(formTitle);
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _logoBytes != null
                ? pw.Container(
                    width: 48,
                    height: 48,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _letterheadNavy, width: 1),
                    ),
                    child: pw.ClipOval(
                      child: pw.Image(
                        pw.MemoryImage(_logoBytes!),
                        fit: pw.BoxFit.cover,
                      ),
                    ),
                  )
                : pw.SizedBox(width: 48, height: 48),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Republic of the Philippines',
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'PROVINCE OF MISAMIS OCCIDENTAL',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'MUNICIPALITY OF PLARIDEL',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'OFFICE OF THE MUNICIPAL MAYOR',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    formTitle,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 48),
          ],
        ),
        pw.SizedBox(height: 6),
      ],
    );
  }

  static Future<pw.Document> buildWorkExperienceSheetPdf(
    WorkExperienceSheetEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('rsp', 'work_experience');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(PdfPageFormat.letter),
        build: (ctx) => _formLayout(
          'WORK EXPERIENCE SHEET',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'Human Resource Management and Development Office',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _row(
                          'POSITION APPLIED FOR :',
                          _s(e.positionAppliedFor),
                        ),
                        _row('DEPARTMENT :', _s(e.department)),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          '4 MINIMUM STANDARDS :',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        _row('1. Education :', _s(e.minEducation)),
                        _row('2. Experience :', _s(e.minExperience)),
                        _row('3. Training :', _s(e.minTraining)),
                        _row('4. Eligibility :', _s(e.minEligibility)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Job Description of Last Work',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          height: 200,
                          padding: const pw.EdgeInsets.all(6),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(width: 0.5),
                          ),
                          child: pw.Text(
                            _s(e.jobDescriptionLastWork),
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Note: With COE with detail position description details',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 28),
              pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Submitted by:',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    _signatureImage(
                      signatures?.signatureFor('applicant'),
                      height: 28,
                      width: 220,
                    ),
                    pw.Container(
                      width: 220,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                      ),
                      child: pw.Text(
                        _signatureName(
                          signatures?.signatureFor('applicant'),
                          _s(e.applicantName),
                        ),
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.SizedBox(
                      width: 220,
                      child: pw.Text(
                        'Name of Applicant',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static Future<pw.Document> buildTurnAroundTimePdf(
    TurnAroundTimeEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('rsp', 'turn_around_time');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(pageLongLandscape),
        build: (ctx) => _printPage(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeaderBoard(
              'TURN-AROUND TIME',
              officeName: 'MGO-Plaridel, Misamis Occidental',
            ),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
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
                      pw.Text('-', style: const pw.TextStyle(fontSize: 10))
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
                                          style: const pw.TextStyle(
                                            fontSize: 6,
                                          ),
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
                                            style: const pw.TextStyle(
                                              fontSize: 6,
                                            ),
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
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Align(
                                alignment: pw.Alignment.centerLeft,
                                child: pw.Text(
                                  'Prepared by:',
                                  style: const pw.TextStyle(fontSize: 9),
                                ),
                              ),
                              _signatureImage(
                                signatures?.signatureFor('prepared_by'),
                              ),
                              pw.Text(
                                _signatureName(
                                  signatures?.signatureFor('prepared_by'),
                                  _s(e.preparedByName),
                                ),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                _s(e.preparedByTitle),
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Align(
                                alignment: pw.Alignment.centerLeft,
                                child: pw.Text(
                                  'Noted by:',
                                  style: const pw.TextStyle(fontSize: 9),
                                ),
                              ),
                              _signatureImage(
                                signatures?.signatureFor('noted_by'),
                              ),
                              pw.Text(
                                _signatureName(
                                  signatures?.signatureFor('noted_by'),
                                  _s(e.notedByName),
                                ),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                _s(e.notedByTitle),
                                textAlign: pw.TextAlign.center,
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
        )),
      ),
    );
    return doc;
  }

  /// Training Need Analysis and Consolidated Report (L&D) — header with CY and Department, then 6-column table.
  static Future<pw.Document> buildTrainingNeedAnalysisPdf(
    TrainingNeedAnalysisEntry e,
  ) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('ld', 'training_need_analysis');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(pageLetterLandscape),
        build: (ctx) => _printPage(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeader('TRAINING NEED ANALYSIS'),
            pw.Text(
              'AND CONSOLIDATED REPORT',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'FOR CY ${_s(e.cyYear)}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'DEPARTMENT: ${_s(e.department)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 14),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: e.rows.isEmpty
                    ? pw.Text('-', style: const pw.TextStyle(fontSize: 10))
                    : pw.Table(
                        border: pw.TableBorder.all(
                          width: 0.5,
                          color: PdfColors.grey800,
                        ),
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
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.grey300,
                            ),
                            children:
                                [
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
                                          style: pw.TextStyle(
                                            fontSize: 7,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                          ...e.rows.map(
                            (r) => pw.TableRow(
                              children:
                                  [
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
                                          child: pw.Text(
                                            v,
                                            style: const pw.TextStyle(
                                              fontSize: 8,
                                            ),
                                          ),
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
        )),
      ),
    );
    return doc;
  }

  /// Action Brainstorming and Coaching Worksheet (L&D) — DEPARTMENT, DATE, instruction, 7-column table, Certified by / Date.
  static Future<pw.Document> buildActionBrainstormingCoachingPdf(
    ActionBrainstormingEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('ld', 'action_brainstorming');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(pageLetterLandscape),
        build: (ctx) => _printPage(pw.Column(
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
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: e.rows.isEmpty
                    ? pw.Text('-', style: const pw.TextStyle(fontSize: 10))
                    : pw.Table(
                        border: pw.TableBorder.all(
                          width: 0.5,
                          color: PdfColors.grey800,
                        ),
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
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.grey300,
                            ),
                            children:
                                [
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
                                          style: pw.TextStyle(
                                            fontSize: 7,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                          ...e.rows.asMap().entries.map((entry) {
                            final i = entry.key + 1;
                            final r = entry.value;
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    '$i',
                                    style: const pw.TextStyle(fontSize: 8),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.name),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.stopDoing),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.doLessOf),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.keepDoing),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.doMoreOf),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.startDoing),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    _s(r.goal),
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _signatureLineBlock(
                    'Certified by:',
                    _idpField(e.certifiedBy),
                    caption: 'Department Head',
                    signature: signatures?.signatureFor('certified_by'),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Date:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _idpField(e.certificationDate),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            _pdfFooter(),
          ],
        )),
      ),
    );
    return doc;
  }

  /// Simple printable summary for employee training daily reports (L&D).
  static Future<void> printTrainingDailyReport(TrainingDailyReport r) async {
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
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
              pw.Text(
                'Description',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                _s(r.description),
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              _row('Status:', _s(r.status)),
              _row('Submitted:', r.submittedAt.toLocal().toString()),
              if (r.attachmentName != null &&
                  r.attachmentName!.trim().isNotEmpty)
                _row('Attachment:', _s(r.attachmentName)),
            ],
          ),
        ),
      ),
    );
    await printDocument(doc, name: 'training-daily-report.pdf');
  }

  /// Learning Application Plan (L&D) — official landscape letterhead form.
  static pw.Widget _lapMemoLine(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 122,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(':  ', style: const pw.TextStyle(fontSize: 9)),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
              ),
              child: pw.Text(
                _idpField(value),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _lapHeader() {
    if (_useCustomPrintBg) {
      return _formTitleOnly('LEARNING APPLICATION PLAN');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _idpLogoSeal(size: 48),
            pw.Expanded(
              child: pw.Column(
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
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _idpMunicipalityRed,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Human Resource Management and Development Office',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 48, height: 48),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 5, color: PdfColor.fromInt(0xFFF0B27A)),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'LEARNING APPLICATION PLAN',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static List<LearningApplicationPlanRow> _lapRowsForPrint(
    LearningApplicationPlanEntry e,
  ) {
    final rows = List<LearningApplicationPlanRow>.from(e.entries);
    while (rows.length < 4) {
      rows.add(const LearningApplicationPlanRow());
    }
    return rows;
  }

  static pw.Widget _lapTable(LearningApplicationPlanEntry e) {
    final rows = _lapRowsForPrint(e);
    pw.Widget cell(String text, {bool header = false}) {
      return pw.Container(
        constraints: pw.BoxConstraints(minHeight: header ? 16 : 42),
        padding: const pw.EdgeInsets.all(4),
        alignment: header ? pw.Alignment.center : pw.Alignment.topLeft,
        child: pw.Text(
          text,
          textAlign: header ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: header ? 7 : 7.5,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.7, color: PdfColors.black),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      columnWidths: const {
        0: pw.FlexColumnWidth(1.15),
        1: pw.FlexColumnWidth(1.15),
        2: pw.FlexColumnWidth(1.35),
        3: pw.FlexColumnWidth(1.25),
        4: pw.FlexColumnWidth(0.85),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(1.15),
      },
      children: [
        pw.TableRow(
          children: [
            cell('LEARNING', header: true),
            cell('OBJECTIVES', header: true),
            cell('COMPETENCY GAPS ADDRESSED', header: true),
            cell('REAP IMPLEMENTATION', header: true),
            cell('TIMELINE', header: true),
            cell('PERSONS INVOLVED', header: true),
            cell('EVIDENCE', header: true),
          ],
        ),
        ...rows.map(
          (r) => pw.TableRow(
            children: [
              cell(_idpField(r.learning)),
              cell(_idpField(r.objectives)),
              cell(_idpField(r.competencyGapsAddressed)),
              cell(_idpField(r.reapImplementation)),
              cell(_idpField(r.timeline)),
              cell(_idpField(r.personsInvolved)),
              cell(_idpField(r.evidence)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _lapSignatures(LearningApplicationPlanEntry e) {
    final reported = e.reportedBy?.trim() ?? '';
    final received = (e.receivedBy?.trim().isNotEmpty ?? false)
        ? e.receivedBy!.trim()
        : LearningApplicationPlanEntry.defaultReceivedByName;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Reported by:',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 26),
              pw.Container(
                width: 220,
                constraints: const pw.BoxConstraints(minHeight: 12),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                ),
                alignment: pw.Alignment.bottomCenter,
                child: reported.isNotEmpty
                    ? pw.Text(
                        reported,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      )
                    : pw.SizedBox(height: 10),
              ),
              pw.SizedBox(height: 3),
              pw.SizedBox(
                width: 220,
                child: pw.Text(
                  'Employee Attended Training',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'Received by:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 26),
                    pw.Container(
                      width: 220,
                      constraints: const pw.BoxConstraints(minHeight: 12),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                      ),
                      child: pw.SizedBox(height: 10),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      received,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      LearningApplicationPlanEntry.defaultReceivedByTitle,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _lapFooter() {
    if (_useCustomPrintBg) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: 46,
          color: _letterheadNavy,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Asenso PLARIDEL',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      '(088) 3448-200  ·  (088) 3448-358',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (_idpBuildingBytes != null)
                pw.Container(
                  width: 120,
                  height: 34,
                  child: pw.Image(
                    pw.MemoryImage(_idpBuildingBytes!),
                    fit: pw.BoxFit.cover,
                  ),
                ),
            ],
          ),
        ),
        pw.Container(
          height: 16,
          color: _idpMunicipalityRed,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Misamisnon Magnayong Malinawon',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ],
    );
  }

  static Future<pw.Document> buildLearningApplicationPlanPdf(
    LearningApplicationPlanEntry e,
  ) async {
    await Future.wait([
      ensureLogoLoaded(),
      _ensureIdpPdfFonts(),
      _loadIdpBuildingImage(),
    ]);
    await _bindCustomTemplate('ld', 'learning_application_plan');
    final doc = pw.Document(theme: _idpPdfTheme);
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(
          pageLetterLandscape.copyWith(
            marginTop: 22,
            marginBottom: 0,
            marginLeft: 28,
            marginRight: 28,
          ),
        ),
        build: (ctx) => _printPage(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _lapHeader(),
            _lapMemoLine('MEMO REPORT TO', e.memoReportTo),
            _lapMemoLine('FROM', e.from),
            _lapMemoLine('THRU', e.thru),
            _lapMemoLine('SUBJECT', e.subject),
            _lapMemoLine('TITLE', e.title),
            _lapMemoLine('DATE', e.date),
            _lapMemoLine('VENUE', e.venue),
            _lapMemoLine('COST', e.cost),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _lapTable(e),
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        for (final flex in <int>[115, 115, 135, 125, 85, 110, 115])
                          pw.Expanded(
                            flex: flex,
                            child: pw.Container(
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(
                                  left: pw.BorderSide(width: 0.7),
                                  bottom: pw.BorderSide(width: 0.7),
                                ),
                              ),
                            ),
                          ),
                        pw.Container(
                          width: 0.7,
                          color: PdfColors.black,
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(width: 0.7),
                        right: pw.BorderSide(width: 0.7),
                        bottom: pw.BorderSide(width: 0.7),
                      ),
                    ),
                    child: pw.Text(
                      'TYPES OF REAP: ORIENTATION, ENCODING, COACHING, MENTORING, ETC.',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            _lapSignatures(e),
            pw.SizedBox(height: 10),
            _lapFooter(),
          ],
        )),
      ),
    );
    return doc;
  }

  static pw.Widget _ojtEvalLine(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 128,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1, left: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
              ),
              child: pw.Text(
                _idpField(value),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _ojtEvalHeader() {
    if (_useCustomPrintBg) {
      return _formTitleOnly('OJT/WORK IMMERSION EVALUATION');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _idpLogoSeal(size: 46),
            pw.Expanded(
              child: pw.Column(
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
                      color: _letterheadNavy,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Human Resource Management and Development Office',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 46, height: 46),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'OJT/WORK IMMERSION EVALUATION',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _ojtEvalCriterion({
    required int number,
    required String title,
    required String prompt,
    required int? score,
    required String? notes,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$number. $title',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Question Prompt: "$prompt"',
            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 3),
          _ojtEvalLine('Score (1-5)', score?.toString()),
          _ojtEvalLine('Evidence/Notes', notes),
        ],
      ),
    );
  }

  static Future<pw.Document> buildOjtWorkImmersionEvaluationPdf(
    OjtWorkImmersionEvaluation e,
  ) async {
    await Future.wait([
      ensureLogoLoaded(),
      _ensureIdpPdfFonts(),
      _loadIdpBuildingImage(),
    ]);
    await _bindCustomTemplate('rsp', 'ojt_work_immersion');
    final doc = pw.Document(theme: _idpPdfTheme);
    final total = e.totalScore;
    doc.addPage(
      pw.Page(
        pageFormat: _printPageFormat(
          pageLetter.copyWith(
            marginTop: 24,
            marginBottom: 0,
            marginLeft: 32,
            marginRight: 32,
          ),
        ),
        build: (ctx) => _printPage(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _ojtEvalHeader(),
            _ojtEvalLine('OJT/IMMERSION', e.ojtImmersion),
            _ojtEvalLine('SCHOOL', e.school),
            _ojtEvalLine('DATE OF INTERVIEW', e.interviewDate),
            pw.SizedBox(height: 8),
            pw.Text(
              '(Rating Scale)',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              '1. Unsatisfactory: Fails to meet the basic expectations or provide relevant examples.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            pw.Text(
              '2. Marginal: Partially meets criteria; weak or vague examples.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            pw.Text(
              '3. Competent: Solidly meet job requirements with clear examples.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            pw.Text(
              '4. Above average: Exceeds standard expectations, strong evidence of skill.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            pw.Text(
              '5. Exceptional: Outstanding proficiency, deeply relevant expertise.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.6, color: PdfColors.black),
            pw.SizedBox(height: 6),
            _ojtEvalCriterion(
              number: 1,
              title: 'Problem Solving and Decision Making',
              prompt:
                  'Tell me about a time you had to make a difficult decision quickly with limited information.',
              score: e.problemSolvingScore,
              notes: e.problemSolvingNotes,
            ),
            _ojtEvalCriterion(
              number: 2,
              title: 'Communication and Clarity',
              prompt:
                  'How do you explain a complex concept or project update to a non-technical stakeholder?',
              score: e.communicationScore,
              notes: e.communicationNotes,
            ),
            _ojtEvalCriterion(
              number: 3,
              title: 'Teamwork and Collaboration',
              prompt:
                  'Describe a time you worked with a difficult team member to reach a shared goal.',
              score: e.teamworkScore,
              notes: e.teamworkNotes,
            ),
            _ojtEvalCriterion(
              number: 4,
              title: 'Adaptability and Resilience',
              prompt:
                  'How do you handle sudden priority shifts or project changes under tight deadlines?',
              score: e.adaptabilityScore,
              notes: e.adaptabilityNotes,
            ),
            pw.Divider(thickness: 0.6, color: PdfColors.black),
            pw.SizedBox(height: 6),
            pw.Text(
              'SUMMARY AND RECOMMENDATIONS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            _ojtEvalLine(
              'TOTAL SCORE',
              total == null ? '          /20' : '$total /20',
            ),
            _ojtEvalLine(
              'OVERALL RECOMMENDATION',
              e.overallRecommendation,
            ),
            _ojtEvalLine('KEY STRENGTHS', e.keyStrengths),
            _ojtEvalLine('KEY CONCERNS', e.keyConcerns),
            pw.SizedBox(height: 8),
            pw.Text(
              'INTERVIEWER SIGNATURE:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 22),
            pw.Container(
              width: 240,
              constraints: const pw.BoxConstraints(minHeight: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
              ),
              alignment: pw.Alignment.bottomCenter,
              child: (e.interviewer ?? '').trim().isNotEmpty
                  ? pw.Text(
                      e.interviewer!.trim(),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    )
                  : pw.SizedBox(height: 10),
            ),
            pw.Spacer(),
            pw.SizedBox(height: 8),
            _lapFooter(),
          ],
        )),
      ),
    );
    return doc;
  }
}

class _CustomPrintBind {
  const _CustomPrintBind({this.image, this.format});

  final pw.MemoryImage? image;
  final PdfPageFormat? format;
}
