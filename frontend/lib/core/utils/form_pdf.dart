import 'dart:async';
import 'dart:math' as math;

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
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/features/forms/data/form_paper_preference.dart';
import 'package:hrms_plaridel/features/forms/data/form_print_template_repo.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

/// Bytes and paper size produced by the existing printable form templates.
class PreparedFormPdf {
  const PreparedFormPdf({
    required this.bytes,
    required this.format,
    this.bindError,
    this.paperSizeId,
  });

  final Uint8List bytes;
  final PdfPageFormat format;
  final String? bindError;
  final String? paperSizeId;
}

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

  /// Content band on the BI A4 letterhead (595 × 842 pt).
  /// Header artwork ends near 105 pt; the footer curve enters near 726 pt.
  /// Page 1 starts a little higher so the title can sit under the letterhead.
  static const pw.EdgeInsets _biFormContentPadding = pw.EdgeInsets.fromLTRB(
    36,
    132,
    36,
    128,
  );

  /// Pages 2 and 3 share a lower start so the body is not against the header.
  static const pw.EdgeInsets _biFormContinuationPadding =
      pw.EdgeInsets.fromLTRB(36, 156, 36, 128);

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

  /// Forms that scale their layout to whatever paper the user picks.
  static const Map<String, String> _paperAdjustableForms = {
    'rsp|bi': 'a4',
    'rsp|applicants_profile': 'long_13',
    'rsp|selection_lineup': 'letter',
    'rsp|computation_of_points': 'letter',
    'rsp|work_experience': 'letter',
    'rsp|turn_around_time': 'letter',
    'rsp|ojt_work_immersion': 'letter',
    'ld|training_need_analysis': 'letter',
    'ld|action_brainstorming': 'letter',
    'ld|idp': 'long_13',
    'ld|learning_application_plan': 'letter',
  };

  static bool supportsPaperChoice(String? module, String? formKey) =>
      module != null &&
      formKey != null &&
      _paperAdjustableForms.containsKey('$module|$formKey');

  /// HR only uses Long (8.5 x 13), Short (letter) and A4. Older Legal ids map
  /// to Long.
  static String? normalizePaperId(String? id) {
    switch (id) {
      case 'a4':
      case 'a4_landscape':
        return 'a4';
      case 'letter':
      case 'letter_landscape':
        return 'letter';
      case 'long_13':
      case 'long_13_landscape':
      case 'long_14':
      case 'long_landscape':
        return 'long_13';
    }
    return null;
  }

  static PdfPageFormat? _paperOverrideBase;
  static PdfPageFormat? _lastPaperTarget;
  static PdfPageFormat? _applicantsProfileTarget;
  static String? _applicantsProfilePaperId;
  static PdfPageFormat? _ojtTarget;
  static String? _ojtPaperId;

  static const double _ptPerMm = 72 / 25.4;

  /// Native sheet for Applicants Profile: F4 landscape, 330 mm × 216 mm.
  static final double applicantsProfileMasterWidth = 330 * _ptPerMm;
  static final double applicantsProfileMasterHeight = 216 * _ptPerMm;

  /// Native sheet for OJT/Work Immersion Evaluation: F4 portrait, 216 × 330 mm.
  static final double ojtMasterWidth = 216 * _ptPerMm;
  static final double ojtMasterHeight = 330 * _ptPerMm;

  static const applicantsProfilePaperIds = <String>[
    'f4_landscape',
    'f4',
    'legal_landscape',
    'legal',
    'a4_landscape',
    'a4',
    'letter_landscape',
    'letter',
  ];

  static const applicantsProfileFamilies = <String>[
    'f4',
    'legal',
    'a4',
    'letter',
  ];

  static String applicantsProfileFamily(String id) {
    if (id.startsWith('legal')) return 'legal';
    if (id.startsWith('a4')) return 'a4';
    if (id.startsWith('letter')) return 'letter';
    return 'f4';
  }

  static bool applicantsProfileIsLandscape(String id) =>
      id.contains('landscape');

  static String applicantsProfileCompose(String family, bool landscape) {
    if (!applicantsProfileFamilies.contains(family)) family = 'f4';
    return landscape ? '${family}_landscape' : family;
  }

  static String resolveApplicantsProfilePaper({
    String? requested,
    String? saved,
  }) {
    if (requested != null && applicantsProfilePaperIds.contains(requested)) {
      return requested;
    }
    switch (saved) {
      case 'f4':
      case 'f4_landscape':
      case 'legal':
      case 'legal_landscape':
      case 'a4':
      case 'a4_landscape':
      case 'letter':
      case 'letter_landscape':
        return saved!;
      case 'long_14':
        return 'legal';
      case 'long_landscape':
      case 'long_13':
      case 'long_13_landscape':
        return 'f4_landscape';
    }
    return 'f4_landscape';
  }

  /// OJT defaults to F4 portrait. Explicit F4/Legal/A4/Letter choices are kept.
  static String resolveOjtPaper({String? requested, String? saved}) {
    if (requested != null && applicantsProfilePaperIds.contains(requested)) {
      return requested;
    }
    switch (saved) {
      case 'f4':
      case 'f4_landscape':
      case 'legal':
      case 'legal_landscape':
      case 'a4':
      case 'a4_landscape':
      case 'letter':
      case 'letter_landscape':
        return saved!;
      case 'long_13':
      case 'long_13_landscape':
      case 'long_14':
      case 'long_landscape':
        return 'f4';
    }
    return 'f4';
  }

  static String ojtFamilyLabel(String family) {
    if (family == 'f4') return 'F4 / Folio (216 × 330 mm)';
    return applicantsProfileFamilyLabel(family);
  }

  static PdfPageFormat applicantsProfilePage(String id) {
    final resolved = applicantsProfilePaperIds.contains(id)
        ? id
        : 'f4_landscape';
    final family = applicantsProfileFamily(resolved);
    final landscape = applicantsProfileIsLandscape(resolved);
    final (double shortMm, double longMm) = switch (family) {
      'legal' => (216.0, 356.0),
      'a4' => (210.0, 297.0),
      'letter' => (216.0, 279.0),
      _ => (216.0, 330.0),
    };
    final shortPt = shortMm * _ptPerMm;
    final longPt = longMm * _ptPerMm;
    return PdfPageFormat(
      landscape ? longPt : shortPt,
      landscape ? shortPt : longPt,
      marginAll: 0,
    );
  }

  static String applicantsProfileFamilyLabel(String family) {
    switch (family) {
      case 'legal':
        return 'Legal';
      case 'a4':
        return 'A4';
      case 'letter':
        return 'Letter';
      default:
        return 'F4';
    }
  }

  static String applicantsProfileFamilyDimensions(String family) {
    switch (family) {
      case 'legal':
        return '216 × 356 mm / 8.5 × 14 in';
      case 'a4':
        return '210 × 297 mm';
      case 'letter':
        return '216 × 279 mm / 8.5 × 11 in';
      default:
        return '216 × 330 mm / 8.5 × 13 in';
    }
  }

  static String applicantsProfilePaperLabel(String id) {
    final family = applicantsProfileFamily(id);
    final orient = applicantsProfileIsLandscape(id) ? 'Landscape' : 'Portrait';
    return '${applicantsProfileFamilyLabel(family)} $orient';
  }

  /// Application safety margins so office printers do not clip the sheet edge.
  /// Bottom is larger because physical tests clip there first.
  static const double safeMarginTopMm = 5;
  static const double safeMarginRightMm = 5;
  static const double safeMarginBottomMm = 7;
  static const double safeMarginLeftMm = 5;

  /// Fit to Printable Area is the default. Actual Size leaves the master at 1:1.
  static bool fitToPrintableArea = true;

  /// One scale for the whole composition, centered inside the printer-safe area.
  static pw.Widget _fitComposition({
    required double pageWidth,
    required double pageHeight,
    required double templateWidth,
    required double templateHeight,
    required pw.Widget child,
    bool? fit,
  }) {
    final composition = pw.SizedBox(
      width: templateWidth,
      height: templateHeight,
      child: child,
    );
    final useFit = fit ?? fitToPrintableArea;
    if (!useFit) return pw.Center(child: composition);
    final left = safeMarginLeftMm * _ptPerMm;
    final top = safeMarginTopMm * _ptPerMm;
    final right = safeMarginRightMm * _ptPerMm;
    final bottom = safeMarginBottomMm * _ptPerMm;
    final availW = math.max(1.0, pageWidth - left - right);
    final availH = math.max(1.0, pageHeight - top - bottom);
    final scale = math.min(availW / templateWidth, availH / templateHeight);
    return pw.Center(
      child: pw.SizedBox(
        width: templateWidth * scale,
        height: templateHeight * scale,
        child: pw.FittedBox(fit: pw.BoxFit.fill, child: composition),
      ),
    );
  }

  /// Places the Applicants Profile master on the selected sheet.
  ///
  /// One uniform scale fits the whole composition inside the safe area.
  /// Leftover width or height is split evenly, so the form is centered.
  /// The page margin stays 0 so this inset is not applied twice.
  static pw.Widget _fitApplicantsMaster(
    PdfPageFormat page,
    pw.Widget master, {
    double? masterWidth,
    double? masterHeight,
  }) {
    final masterW = masterWidth ?? applicantsProfileMasterWidth;
    final masterH = masterHeight ?? applicantsProfileMasterHeight;
    final composition = pw.SizedBox(
      width: masterW,
      height: masterH,
      child: master,
    );
    if (!fitToPrintableArea) {
      return pw.SizedBox(
        width: page.width,
        height: page.height,
        child: pw.Center(child: composition),
      );
    }
    final left = safeMarginLeftMm * _ptPerMm;
    final top = safeMarginTopMm * _ptPerMm;
    final right = safeMarginRightMm * _ptPerMm;
    final bottom = safeMarginBottomMm * _ptPerMm;
    final availW = math.max(1.0, page.width - left - right);
    final availH = math.max(1.0, page.height - top - bottom);
    final scale = math.min(availW / masterW, availH / masterH);
    final renderedW = masterW * scale;
    final renderedH = masterH * scale;
    // PDF origin is the bottom-left. offsetY is the bottom of the composition.
    final offsetX = left + (availW - renderedW) / 2;
    final offsetY = bottom + (availH - renderedH) / 2;
    return pw.SizedBox(
      width: page.width,
      height: page.height,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: offsetX,
            bottom: offsetY,
            child: pw.SizedBox(
              width: renderedW,
              height: renderedH,
              child: pw.FittedBox(fit: pw.BoxFit.fill, child: composition),
            ),
          ),
        ],
      ),
    );
  }

  /// Page stays the selected physical size. The whole composition, including
  /// an uploaded background, is scaled once into the printer-safe area.
  static pw.Page _fitPage({
    required PdfPageFormat pageFormat,
    required pw.Widget Function(pw.Context) build,
  }) {
    final chosen = _paperOverrideFor(pageFormat);
    final page =
        chosen ??
        PdfPageFormat(pageFormat.width, pageFormat.height, marginAll: 0);
    if (chosen != null) _lastPaperTarget = page;
    return pw.Page(
      pageFormat: page,
      build: (ctx) => _fitComposition(
        pageWidth: page.width,
        pageHeight: page.height,
        templateWidth: pageFormat.width,
        templateHeight: pageFormat.height,
        child: pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(
            pageFormat.marginLeft,
            pageFormat.marginTop,
            pageFormat.marginRight,
            pageFormat.marginBottom,
          ),
          child: build(ctx),
        ),
      ),
    );
  }

  /// Zero-margin page of the chosen paper, oriented like [natural]; null when
  /// the form should keep its built-in size.
  static PdfPageFormat? _paperOverrideFor(PdfPageFormat natural) {
    final base = _paperOverrideBase;
    if (base == null) return null;
    final short = base.width < base.height ? base.width : base.height;
    final long = base.width < base.height ? base.height : base.width;
    final landscape = natural.width >= natural.height;
    return PdfPageFormat(
      landscape ? long : short,
      landscape ? short : long,
      marginAll: 0,
    );
  }

  /// Catalog portrait id (a4, letter, long_13, long_14) matching [f], if any.
  static String? paperChoiceIdFor(PdfPageFormat f) {
    final short = f.width < f.height ? f.width : f.height;
    final long = f.width < f.height ? f.height : f.width;
    for (final p in FormPrintCatalog.paperSizes) {
      final ps = p.widthPt < p.heightPt ? p.widthPt : p.heightPt;
      final pl = p.widthPt < p.heightPt ? p.heightPt : p.widthPt;
      if ((ps - short).abs() < 2 && (pl - long).abs() < 2) {
        return normalizePaperId(p.id);
      }
    }
    return null;
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

  static pw.Widget _printPage(pw.Widget child, {pw.EdgeInsets? padding}) {
    final bg = _lockedPrintBg ?? _activeCustomBg;
    if (bg == null) return child;
    return pw.Stack(
      children: [
        pw.Positioned.fill(child: pw.Image(bg, fit: pw.BoxFit.fill)),
        pw.Positioned.fill(
          child: pw.Padding(
            padding: padding ?? _customPrintContentPadding,
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

  /// Content band on the IDP long-letter template (8.5" × 13", 612 × 936 pt).
  ///
  /// Measured on assets/forms/long_letter.pdf: header artwork ends near 110 pt
  /// and the decorative footer enters the center near 811 pt. Text starts just
  /// under the letterhead and stops before the footer, with no screen scaling.
  static const pw.EdgeInsets _idpTemplateContentPadding =
      pw.EdgeInsets.fromLTRB(40, 118, 40, 158);

  /// IDP print layout — letterhead background with form fields drawn on top.
  static pw.Widget _idpPageLayout(pw.Widget body) {
    final letterhead =
        _lockedPrintBg ?? _activeCustomBg ?? _idpMayorLetterBackground;
    if (letterhead != null) {
      // Match BI form: Stack + full-size foreground + Expanded so content actually paints.
      return pw.Stack(
        children: [
          pw.Positioned.fill(child: pw.Image(letterhead, fit: pw.BoxFit.fill)),
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

  /// BI form body. The letterhead image is drawn only when a print background
  /// has been uploaded for this form.
  static pw.Widget _biFormPageLayout(
    String formTitle,
    pw.Widget body, {
    bool showTitle = true,
  }) {
    final letterhead = _lockedPrintBg ?? _activeCustomBg;
    final padding = showTitle
        ? _biFormContentPadding
        : _biFormContinuationPadding;
    final content = pw.Padding(
      padding: padding,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (showTitle && formTitle.isNotEmpty) ...[
            pw.Center(
              child: pw.Text(
                formTitle,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  color: _letterheadNavy,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          pw.Expanded(child: body),
        ],
      ),
    );
    if (letterhead == null) return content;
    return pw.Stack(
      children: [
        pw.Positioned.fill(child: pw.Image(letterhead, fit: pw.BoxFit.fill)),
        content,
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

  static const pw.TableBorder _biTableBorder = pw.TableBorder(
    left: pw.BorderSide(width: 0.7, color: PdfColors.black),
    right: pw.BorderSide(width: 0.7, color: PdfColors.black),
    top: pw.BorderSide(width: 0.7, color: PdfColors.black),
    bottom: pw.BorderSide(width: 0.7, color: PdfColors.black),
    horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.black),
    verticalInside: pw.BorderSide(width: 0.5, color: PdfColors.black),
  );

  static pw.Widget _biCell(
    pw.Widget child, {
    double minHeight = 16,
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      constraints: pw.BoxConstraints(minHeight: minHeight),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      alignment: alignment,
      child: child,
    );
  }

  static pw.Widget _biPlain(String text, {bool bold = false, double size = 8}) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
  }

  /// Fixed writing lines. Saved text sits on the lines; empty stays blank.
  static pw.Widget _biWritingLines(String? text, {required int lines}) {
    const lineHeight = 15.0;
    final value = _idpField(text);
    return pw.SizedBox(
      height: lines * lineHeight,
      child: pw.Stack(
        children: [
          pw.Column(
            children: [
              for (var i = 0; i < lines; i++)
                pw.Container(
                  height: lineHeight,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(width: 0.5, color: PdfColors.black),
                    ),
                  ),
                ),
            ],
          ),
          if (value.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 2, right: 2),
              child: pw.Text(
                value,
                maxLines: lines,
                style: const pw.TextStyle(fontSize: 8, height: 1.85),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _biCheckLabel(String label, bool checked) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _pdfCheckbox(checked),
          pw.Expanded(child: _biPlain(label, size: 7.5)),
        ],
      ),
    );
  }

  static pw.Widget _biFormPage2Body(BiFormEntry e) {
    const options = BiFormEntry.functionalAreaOptions;
    final left = options.take(6).toList();
    final right = <String>[
      ...options.skip(6),
      'Other (Please specify)',
      '',
      '',
    ];

    pw.Widget areaCell(String label) {
      if (label.isEmpty) return _biCell(pw.SizedBox(height: 10));
      final isOther = label.startsWith('Other');
      final checked = isOther
          ? _idpField(e.otherFunctionalArea).isNotEmpty
          : e.functionalAreas.contains(label);
      final extra = isOther ? _idpField(e.otherFunctionalArea) : '';
      return _biCell(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _biCheckLabel(label, checked),
            if (extra.isNotEmpty) _biPlain(extra, size: 7.5),
          ],
        ),
        minHeight: 18,
      );
    }

    pw.Widget question(String prompt, String? answer, {required int lines}) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _biPlain(prompt, size: 8),
          pw.SizedBox(height: 3),
          _biWritingLines(answer, lines: lines),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _biPlain('A. Functional Areas:', bold: true, size: 10),
        pw.SizedBox(height: 2),
        _biPlain(
          'Please check (/) the boxes opposite the functional area where the applicant can perform effectively.',
          size: 8,
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: _biTableBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                _biCell(
                  _biPlain('Functional Areas', bold: true, size: 8),
                  alignment: pw.Alignment.center,
                ),
                _biCell(
                  _biPlain('Functional Areas', bold: true, size: 8),
                  alignment: pw.Alignment.center,
                ),
              ],
            ),
            for (var i = 0; i < left.length; i++)
              pw.TableRow(
                children: [
                  areaCell(left[i]),
                  areaCell(i < right.length ? right[i] : ''),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        _biPlain(
          'I. On performance and other relevant information.',
          bold: true,
          size: 10,
        ),
        pw.SizedBox(height: 8),
        question(
          'Please tell us about the work performance of the applicants in the last three (3) years. What are the applicant\'s outstanding accomplishments recognition received and significant contributions to your office if any?',
          e.performance3Years,
          lines: 3,
        ),
        pw.SizedBox(height: 10),
        question(
          'What do you think are the challenges or difficulties of the applicant in performing his/ her duties and responsibilities in his/ her position? How did the applicant cope with these challenges?',
          e.challengesCoping,
          lines: 3,
        ),
        pw.SizedBox(height: 10),
        question(
          'In terms of compliance with rules and regulation, please provide us information on the applicant\'s attendance to flag ceremonies/ retreats and other office programs and activities?',
          e.complianceAttendance,
          lines: 4,
        ),
      ],
    );
  }

  static pw.Widget _biFormPage3Body(BiFormEntry e) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _biPlain(
          'Other relevant information/ data (critical incidents, family background, health profile habits, vices, membership in unions/ associations, or any derogatory records) about the applicants, if any.',
          bold: true,
          size: 9,
        ),
        pw.SizedBox(height: 8),
        _biWritingLines(e.otherRelevantInformation, lines: 4),
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
  static Future<void> _pdfGate = Future<void>.value();

  /// Runs PDF capture one at a time so print backgrounds are not mixed.
  static Future<T> _withPdfGate<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pdfGate = _pdfGate.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Builds the same PDF bytes used for printing, including saved form backgrounds.
  static Future<PreparedFormPdf> captureFormPdf({
    required Future<pw.Document> Function() buildDocument,
    PdfPageFormat? format,
    String? printModule,
    String? printFormKey,
    String? paperSizeId,
  }) {
    return _withPdfGate(() async {
      try {
        try {
          await warmupPrintAssets();
        } catch (_) {}

        _paperOverrideBase = null;
        _lastPaperTarget = null;
        _applicantsProfileTarget = null;
        _applicantsProfilePaperId = null;
        _ojtTarget = null;
        _ojtPaperId = null;
        if (printModule != null && printFormKey != null) {
          await _bindCustomTemplate(printModule, printFormKey);
          if (printModule == 'rsp' && printFormKey == 'applicants_profile') {
            final saved = await FormPaperPreference.load(
              printModule,
              printFormKey,
            );
            _applicantsProfilePaperId = resolveApplicantsProfilePaper(
              requested: paperSizeId,
              saved: saved,
            );
            _applicantsProfileTarget = applicantsProfilePage(
              _applicantsProfilePaperId!,
            );
          } else if (printModule == 'rsp' &&
              printFormKey == 'ojt_work_immersion') {
            final saved = await FormPaperPreference.load(
              printModule,
              printFormKey,
            );
            _ojtPaperId = resolveOjtPaper(requested: paperSizeId, saved: saved);
            _ojtTarget = applicantsProfilePage(_ojtPaperId!);
          } else if (supportsPaperChoice(printModule, printFormKey)) {
            final saved = await FormPaperPreference.load(
              printModule,
              printFormKey,
            );
            final templateFormat = _activeCustomFormat;
            final chosen =
                normalizePaperId(paperSizeId) ??
                normalizePaperId(saved) ??
                (templateFormat == null
                    ? null
                    : paperChoiceIdFor(templateFormat)) ??
                _paperAdjustableForms['$printModule|$printFormKey'];
            final paper = chosen == null
                ? null
                : FormPrintCatalog.paperById(chosen);
            if (paper != null) {
              _paperOverrideBase = PdfPageFormat(paper.widthPt, paper.heightPt);
            }
          }
        }

        final bindError = _customTemplateError;
        final doc = await buildDocument();
        final scaledTarget = _lastPaperTarget;
        final fixedPaperId = _applicantsProfilePaperId ?? _ojtPaperId;
        final printFormat = fixedPaperId != null && scaledTarget != null
            ? scaledTarget
            : scaledTarget != null
            ? _catalogFormatMatching(scaledTarget)
            : _catalogFormatMatching(
                _activeCustomFormat ?? format ?? PdfPageFormat.letter,
              );
        final bytes = await doc.save();
        return PreparedFormPdf(
          bytes: bytes,
          format: printFormat,
          bindError: bindError,
          paperSizeId: fixedPaperId,
        );
      } finally {
        _activeCustomBg = null;
        _lockedPrintBg = null;
        _activeCustomFormat = null;
        _paperOverrideBase = null;
        _lastPaperTarget = null;
        _applicantsProfileTarget = null;
        _applicantsProfilePaperId = null;
        _ojtTarget = null;
        _ojtPaperId = null;
      }
    });
  }

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
    String? chosenPaper;
    if (printFormKey == 'applicants_profile') {
      final saved = await FormPaperPreference.load(
        printModule ?? 'rsp',
        printFormKey!,
      );
      if (!context.mounted) return;
      final picked = await showApplicantsProfilePrintSetup(
        context: context,
        initialId: resolveApplicantsProfilePaper(saved: saved),
        families: applicantsProfileFamilies,
        familyOf: applicantsProfileFamily,
        isLandscape: applicantsProfileIsLandscape,
        compose: applicantsProfileCompose,
        familyLabel: applicantsProfileFamilyLabel,
        familyDimensions: applicantsProfileFamilyDimensions,
        initialFit: fitToPrintableArea,
        writeFit: (fit) => fitToPrintableArea = fit,
      );
      if (picked == null || !context.mounted) return;
      await FormPaperPreference.save(
        printModule ?? 'rsp',
        printFormKey,
        picked,
      );
      chosenPaper = picked;
    } else if (printFormKey == 'ojt_work_immersion') {
      final saved = await FormPaperPreference.load(
        printModule ?? 'rsp',
        printFormKey!,
      );
      if (!context.mounted) return;
      final picked = await showApplicantsProfilePrintSetup(
        context: context,
        title: 'OJT/Work Immersion Evaluation',
        initialId: resolveOjtPaper(saved: saved),
        families: applicantsProfileFamilies,
        familyOf: applicantsProfileFamily,
        isLandscape: applicantsProfileIsLandscape,
        compose: applicantsProfileCompose,
        familyLabel: ojtFamilyLabel,
        familyDimensions: applicantsProfileFamilyDimensions,
        initialFit: fitToPrintableArea,
        writeFit: (fit) => fitToPrintableArea = fit,
      );
      if (picked == null || !context.mounted) return;
      await FormPaperPreference.save(
        printModule ?? 'rsp',
        printFormKey,
        picked,
      );
      chosenPaper = picked;
    }
    _printInFlight = true;

    OverlayEntry? busy;
    void showBusy() {
      if (!context.mounted || busy != null) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      busy = OverlayEntry(
        builder: (_) => const IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 28),
                child: Material(
                  elevation: 4,
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  child: Padding(
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
                        Text('Preparing document...'),
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
      final prepared = await captureFormPdf(
        buildDocument: buildDocument,
        format: format,
        printModule: printModule,
        printFormKey: printFormKey,
        paperSizeId: chosenPaper,
      );
      hideBusy();
      if (!context.mounted) return;

      if (prepared.bindError != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(prepared.bindError!)));
      }

      await SchedulerBinding.instance.endOfFrame;
      if (!context.mounted) return;

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => prepared.bytes,
        name: filename,
        format: prepared.format,
        dynamicLayout: dynamicLayout,
        forceCustomPrintPaper: true,
      );
    } catch (_) {
      hideBusy();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to prepare the document for printing.'),
          ),
        );
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
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
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

  static Future<pw.Document> buildBiFormPdf(BiFormEntry e) async {
    await ensureLogoLoaded();
    await _bindCustomTemplate('rsp', 'bi');
    final doc = pw.Document();
    const formTitle = 'BACKGROUND INVESTIGATION (BI FORM)';
    final pageFormat = _printPageFormat(biPrintPageFormat);

    pw.Widget fieldLine(String label, String? value) {
      return pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: label,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(
              text: ' ${_idpField(value)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );
    }

    final relationship = e.respondentRelationship.trim().toLowerCase();

    pw.Widget page1Body() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(
          border: _biTableBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.15),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                _biCell(_biPlain('APPLICANT UNDER BI:', bold: true, size: 9)),
                _biCell(_biPlain('RESPONDENTS:', bold: true, size: 9)),
              ],
            ),
            pw.TableRow(
              children: [
                _biCell(fieldLine('Name:', e.applicantName)),
                _biCell(fieldLine('Name:', e.respondentName)),
              ],
            ),
            pw.TableRow(
              children: [
                _biCell(fieldLine('Department:', e.applicantDepartment)),
                _biCell(fieldLine('Position:', e.respondentPosition)),
              ],
            ),
            pw.TableRow(
              children: [
                _biCell(fieldLine('Position:', e.applicantPosition)),
                _biCell(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _biPlain(
                        'Work relationship to the applicants:',
                        bold: true,
                        size: 8,
                      ),
                      _biPlain('(Kindly check the appropriate box)', size: 7.5),
                    ],
                  ),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _biCell(
                  fieldLine(
                    'Position Applied for in LGU-Plaridel:',
                    e.positionAppliedFor,
                  ),
                ),
                _biCell(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _biCheckLabel(
                        'Applicants Supervisor',
                        relationship == 'supervisor',
                      ),
                      _biCheckLabel(
                        'Applicants Peer/Co-Employee',
                        relationship == 'peer',
                      ),
                      _biCheckLabel(
                        'Applicants Subordinates',
                        relationship == 'subordinate',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _biPlain('I. ON COMPETENCIES', bold: true, size: 10),
                  _biPlain('Core and Organizational Competencies:', size: 8),
                  _biPlain(
                    'Using the following rating guide please check (/) the appropriate box opposite each behavioral Indicator:',
                    size: 7.5,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.SizedBox(
              width: 148,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _biPlain('Rating Guide:', bold: true, size: 8),
                  _biPlain('5 - Shows Strength', size: 7.5),
                  _biPlain('4 - Very Proficient', size: 7.5),
                  _biPlain('3 - Proficient', size: 7.5),
                  _biPlain('2 - Minimal Development', size: 7.5),
                  _biPlain('1 - Much Development Needed', size: 7.5),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: _biTableBorder,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: pw.FixedColumnWidth(28),
            1: pw.FlexColumnWidth(1),
            2: pw.FixedColumnWidth(20),
            3: pw.FixedColumnWidth(20),
            4: pw.FixedColumnWidth(20),
            5: pw.FixedColumnWidth(20),
            6: pw.FixedColumnWidth(20),
          },
          children: [
            pw.TableRow(
              children: [
                for (final heading in [
                  'AREA',
                  'CORE DESCRIPTION',
                  '5',
                  '4',
                  '3',
                  '2',
                  '1',
                ])
                  _biCell(
                    _biPlain(heading, bold: true, size: 7),
                    alignment: pw.Alignment.center,
                    minHeight: 16,
                  ),
              ],
            ),
            for (var i = 0; i < 9; i++)
              pw.TableRow(
                children: [
                  _biCell(
                    _biPlain('${i + 1}', size: 7.5),
                    alignment: pw.Alignment.center,
                    minHeight: 28,
                  ),
                  _biCell(
                    _biPlain(BiFormEntry.competencyDescriptions[i], size: 7),
                    minHeight: 28,
                  ),
                  for (final score in [5, 4, 3, 2, 1])
                    _biCell(
                      _biPlain(
                        [
                                  e.rating1,
                                  e.rating2,
                                  e.rating3,
                                  e.rating4,
                                  e.rating5,
                                  e.rating6,
                                  e.rating7,
                                  e.rating8,
                                  e.rating9,
                                ][i] ==
                                score
                            ? '/'
                            : '',
                        size: 9,
                      ),
                      alignment: pw.Alignment.center,
                      minHeight: 28,
                    ),
                ],
              ),
          ],
        ),
      ],
    );

    doc.addPage(
      _fitPage(
        pageFormat: pageFormat,
        build: (ctx) => _biFormPageLayout(formTitle, page1Body()),
      ),
    );
    doc.addPage(
      _fitPage(
        pageFormat: pageFormat,
        build: (ctx) =>
            _biFormPageLayout('', _biFormPage2Body(e), showTitle: false),
      ),
    );
    doc.addPage(
      _fitPage(
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
      _fitPage(
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
      padding: const pw.EdgeInsets.only(bottom: 2),
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
      padding: const pw.EdgeInsets.only(right: 10, bottom: 2),
      child: pw.Text(
        checked ? '(✓) $label' : '( ) $label',
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  static pw.Widget _idpFormTitle() {
    return pw.Column(
      children: [
        pw.Center(
          child: pw.Text(
            'INDIVIDUAL DEVELOPMENT PLAN',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Center(
          child: pw.Text(
            'LOCAL GOVERNMENT UNIT OF PLARIDEL',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
      ],
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
              _idpLabeledLine('QUALIFICATIONS', null, labelWidth: 88),
              _idpLabeledLine('EDUCATION', e.education, labelWidth: 88),
              _idpLabeledLine('EXPERIENCE', e.experience, labelWidth: 88),
              _idpLabeledLine('TRAINING', e.training, labelWidth: 88),
              _idpLabeledLine('ELIGIBILITY', e.eligibility, labelWidth: 88),
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
        pw.SizedBox(height: 2),
        _idpUnderlineField(
          accomplishments != null && accomplishments.isNotEmpty
              ? accomplishments
              : ' ',
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'SUCCESSION ANALYSIS',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '(RESULTS OF THE COMPETENCY-BASED SUCCESSION PRIORITY MATRIX)',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
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
        pw.SizedBox(height: 4),
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
              pw.SizedBox(height: 3),
              pw.Text(
                '(PLEASE ATTACHED)',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '2. Performance, average 2 latest previous SPMS-IPCR Rating',
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
              pw.SizedBox(height: 4),
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
              pw.SizedBox(height: 4),
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
                  _idpCheckboxOption('Priority 1', succ == 'priority'),
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
    const headers = <String>[
      'OBJECTIVES',
      'L & D PROGRAM',
      'REQUIREMENTS',
      'TIME FRAME',
    ];

    pw.Widget cells(List<String> texts, {required bool header}) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < texts.length; i++)
            pw.Expanded(
              flex: i == 0 ? 14 : 12,
              child: pw.Container(
                alignment: header ? pw.Alignment.center : pw.Alignment.topLeft,
                padding: const pw.EdgeInsets.all(3),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    left: i == 0
                        ? pw.BorderSide.none
                        : const pw.BorderSide(
                            width: 0.6,
                            color: PdfColors.black,
                          ),
                  ),
                ),
                child: pw.Text(
                  texts[i],
                  textAlign: header ? pw.TextAlign.center : pw.TextAlign.left,
                  maxLines: header ? 2 : 4,
                  style: pw.TextStyle(
                    fontSize: header ? 7.5 : 7.5,
                    fontWeight: header
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.7, color: PdfColors.black),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: 68,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.all(3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(width: 0.6, color: PdfColors.black),
              ),
            ),
            child: pw.Text(
              'Short Term\n(6 months)',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.SizedBox(height: 22, child: cells(headers, header: true)),
                for (final row in rows)
                  pw.Expanded(
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(
                            width: 0.6,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                      child: cells([
                        _idpField(row.objectives),
                        _idpField(row.ldProgram),
                        _idpField(row.requirements),
                        _idpField(row.timeFrame),
                      ], header: false),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
        isSigned
            ? _signatureImage(signature, height: 26)
            : pw.SizedBox(height: 26),
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
    pw.Widget slot({
      required String role,
      required String? name,
      required String title,
      required DocuTrackerSourceSignature? signature,
      String? fixedNameBelow,
      bool nameOnSignatureLine = true,
    }) {
      return pw.Expanded(
        child: _idpSignatureBlock(
          role: role,
          name: name,
          title: title,
          signature: signature,
          fixedNameBelow: fixedNameBelow,
          nameOnSignatureLine: nameOnSignatureLine,
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        slot(
          role: 'Prepared by:',
          name: e.preparedBy,
          title: 'Employee',
          signature: signatures?.signatureFor('prepared_by'),
        ),
        pw.SizedBox(width: 8),
        slot(
          role: 'Reviewed by:',
          name: e.reviewedBy,
          title: 'Department Head',
          signature: signatures?.signatureFor('reviewed_by'),
        ),
        pw.SizedBox(width: 8),
        slot(
          role: 'Noted by:',
          name: e.notedBy,
          title: IdpEntry.defaultNotedByTitle,
          signature: signatures?.signatureFor('noted_by'),
          fixedNameBelow: IdpEntry.defaultNotedByName,
          nameOnSignatureLine: false,
        ),
        pw.SizedBox(width: 8),
        slot(
          role: 'Approved by:',
          name: e.approvedBy,
          title: IdpEntry.defaultApprovedByTitle,
          signature: signatures?.signatureFor('approved_by'),
          fixedNameBelow: IdpEntry.defaultApprovedByName,
          nameOnSignatureLine: false,
        ),
      ],
    );
  }

  static Future<pw.Document> buildIdpPdf(
    IdpEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await _ensureIdpAssets();
    // This form uses the Mayor's Office long-letter template, not an uploaded
    // HRMDO background from another official form.
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
    final doc = pw.Document(theme: _idpPdfTheme);
    final pageFormat = idpLayoutPrintFormat;

    // Signatories are non-flex so they are measured first and stay above the
    // letterhead footer. The rest of the form uses remaining space.
    final body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (_idpMayorLetterBackground != null) _idpFormTitle(),
              _idpPersonalQualifications(e),
              pw.SizedBox(height: 4),
              _idpSuccessionBlock(e),
              pw.SizedBox(height: 6),
              pw.Expanded(child: _idpDevelopmentTable(e)),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        _idpSignatures(e, signatures),
      ],
    );

    doc.addPage(
      _fitPage(pageFormat: pageFormat, build: (ctx) => _idpPageLayout(body)),
    );
    return doc;
  }

  static Future<pw.Document> buildApplicantsProfilePdf(
    ApplicantsProfileEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await Future.wait([ensureLogoLoaded(), _ensureIdpPdfFonts()]);
    await _bindCustomTemplate('rsp', 'applicants_profile');
    // Keep the uploaded letterhead, but do not let its portrait paper size
    // turn this wide table back into a portrait page.
    _activeCustomFormat = null;
    final doc = pw.Document(theme: _idpPdfTheme);
    const perPage = ApplicantsProfileEntry.applicantsPerFormPage;
    final applicants = e.applicants;
    final pageCount = applicants.isEmpty
        ? 1
        : ((applicants.length - 1) ~/ perPage) + 1;
    const border = pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.black),
      right: pw.BorderSide(width: 0.6, color: PdfColors.black),
      top: pw.BorderSide(width: 0.6, color: PdfColors.black),
      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
      horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.black),
      verticalInside: pw.BorderSide(width: 0.5, color: PdfColors.black),
    );
    const labelStyle = pw.TextStyle(fontSize: 9);
    const valueStyle = pw.TextStyle(fontSize: 9);

    String blank(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return '';
      return _pdfSafe(text);
    }

    pw.Widget vacancyLine(String label, String? value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1.5),
        child: pw.Row(
          children: [
            pw.SizedBox(width: 128, child: pw.Text(label, style: labelStyle)),
            pw.Text(': ', style: labelStyle),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 1),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                  ),
                ),
                child: pw.Text(
                  blank(value).isEmpty ? ' ' : blank(value),
                  style: valueStyle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget tableCell(
      String text, {
      required double height,
      bool header = false,
      bool center = false,
    }) {
      return pw.Container(
        height: height,
        alignment: center || header
            ? pw.Alignment.center
            : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        child: pw.Text(
          text,
          textAlign: center || header ? pw.TextAlign.center : pw.TextAlign.left,
          maxLines: header ? 2 : 2,
          style: pw.TextStyle(
            fontSize: header ? 7 : 7.5,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    pw.Widget applicantsTable(
      List<ApplicantsProfileApplicant?> rows, {
      double rowHeight = 18,
    }) {
      pw.TableRow dataRow(int number, ApplicantsProfileApplicant? applicant) {
        final values = <String>[
          '$number',
          blank(applicant?.name),
          blank(applicant?.course),
          blank(formatStoredAddressForDisplay(applicant?.address)),
          blank(applicant?.sex),
          blank(applicant?.age),
          blank(applicant?.civilStatus),
          blank(applicant?.remarkDisability),
        ];
        return pw.TableRow(
          children: [
            for (var i = 0; i < values.length; i++)
              tableCell(
                values[i],
                height: rowHeight,
                center: i == 0 || i == 4 || i == 5,
              ),
          ],
        );
      }

      return pw.Table(
        border: border,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: pw.FlexColumnWidth(0.38),
          1: pw.FlexColumnWidth(2.35),
          2: pw.FlexColumnWidth(1.65),
          3: pw.FlexColumnWidth(2.45),
          4: pw.FlexColumnWidth(0.55),
          5: pw.FlexColumnWidth(0.48),
          6: pw.FlexColumnWidth(0.95),
          7: pw.FlexColumnWidth(1.25),
        },
        children: [
          pw.TableRow(
            children: [
              tableCell('', height: 26, header: true),
              tableCell('NAME', height: 26, header: true),
              tableCell('COURSE', height: 26, header: true),
              tableCell('ADDRESS', height: 26, header: true),
              tableCell('SEX', height: 26, header: true),
              tableCell('AGE', height: 26, header: true),
              tableCell('CIVIL\nSTATUS', height: 26, header: true),
              tableCell('REMARK\n(DISABILITY)', height: 26, header: true),
            ],
          ),
          for (var i = 0; i < perPage; i++) dataRow(i + 1, rows[i]),
        ],
      );
    }

    pw.Widget signatory({
      required String label,
      required String? stored,
      required String defaultName,
      required String defaultTitle,
      required DocuTrackerSourceSignature? signature,
    }) {
      final storedName = _signatureName(signature, blank(stored));
      final useOfficial = storedName.isEmpty;
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: labelStyle),
          _signatureImage(signature, height: 28),
          pw.Text(
            useOfficial ? defaultName : storedName,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (useOfficial)
            pw.Text(defaultTitle, style: const pw.TextStyle(fontSize: 8)),
        ],
      );
    }

    pw.Widget profileForm(
      List<ApplicantsProfileApplicant?> rows,
      double rowHeight,
    ) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'APPLICANTS PROFILE',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 14),
          vacancyLine('Position Applied for', e.positionAppliedFor),
          vacancyLine('Minimum Requirements', e.minimumRequirements),
          vacancyLine('Date of Posting', e.dateOfPosting),
          vacancyLine('Closing Date', e.closingDate),
          pw.SizedBox(height: 8),
          applicantsTable(rows, rowHeight: rowHeight),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: signatory(
                  label: 'Prepared by:',
                  stored: e.preparedBy,
                  defaultName: 'WILMAMAE JOY S. MUTIA',
                  defaultTitle: 'HRMDO Staff',
                  signature: signatures?.signatureFor('prepared_by'),
                ),
              ),
              pw.Expanded(
                child: signatory(
                  label: 'Checked by:',
                  stored: e.checkedBy,
                  defaultName: 'MARCELO B. CAÑARES',
                  defaultTitle: 'HRMDO',
                  signature: signatures?.signatureFor('checked_by'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    pw.Widget pageBody(List<ApplicantsProfileApplicant?> rows) {
      final form = profileForm(rows, 18);
      if (_useCustomPrintBg) {
        final bg = _lockedPrintBg ?? _activeCustomBg;
        return pw.Stack(
          children: [
            if (bg != null)
              pw.Positioned.fill(child: pw.Image(bg, fit: pw.BoxFit.fill)),
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(42, 118, 42, 64),
                child: form,
              ),
            ),
          ],
        );
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeader(''),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16),
                child: form,
              ),
            ),
            _pdfFooter(),
          ],
        ),
      );
    }

    final page =
        _applicantsProfileTarget ??
        PdfPageFormat(
          applicantsProfileMasterWidth,
          applicantsProfileMasterHeight,
          marginAll: 0,
        );
    _lastPaperTarget = page;

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final start = pageIndex * perPage;
      final end = (start + perPage).clamp(0, applicants.length);
      final rows = List<ApplicantsProfileApplicant?>.filled(perPage, null);
      if (applicants.isNotEmpty) {
        final chunk = applicants.sublist(start, end);
        for (var i = 0; i < chunk.length; i++) {
          rows[i] = chunk[i];
        }
      }
      final sheet = pageBody(rows);
      doc.addPage(
        pw.Page(
          pageFormat: page,
          margin: pw.EdgeInsets.zero,
          build: (ctx) => _fitApplicantsMaster(page, sheet),
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
      _fitPage(
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
      _fitPage(
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

  /// One sheet holds 3–5 applicants. A sixth name starts the next page.
  static const int _selectionLineupRowsPerPage = 5;

  static const pw.EdgeInsets _selectionLineupPadding = pw.EdgeInsets.fromLTRB(
    34,
    96,
    34,
    52,
  );

  /// Drops the letterhead below the page edge on this form only.
  static const double _selectionLineupLetterheadDrop = 22;

  static Future<pw.Document> buildSelectionLineupPdf(
    SelectionLineupEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await Future.wait([ensureLogoLoaded(), _ensureIdpPdfFonts()]);
    await _bindCustomTemplate('rsp', 'selection_lineup');
    final doc = pw.Document(theme: _idpPdfTheme);
    final pageFormat = pageLetterLandscape.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
    final applicants = e.applicants;
    final pageCount = applicants.isEmpty
        ? 1
        : ((applicants.length - 1) ~/ _selectionLineupRowsPerPage) + 1;
    const border = pw.TableBorder(
      left: pw.BorderSide(width: 0.7, color: PdfColors.black),
      right: pw.BorderSide(width: 0.7, color: PdfColors.black),
      top: pw.BorderSide(width: 0.7, color: PdfColors.black),
      bottom: pw.BorderSide(width: 0.7, color: PdfColors.black),
      horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.black),
      verticalInside: pw.BorderSide(width: 0.5, color: PdfColors.black),
    );

    pw.Widget sheet(
      List<SelectionLineupApplicant?> rows,
      int startNumber,
      bool lastPage,
    ) {
      final rowHeight = rows.length <= 3
          ? 58.0
          : rows.length == 4
          ? 46.0
          : 38.0;
      final bodyLines = rows.length <= 3 ? 5 : 3;
      final preparedName = _signatureName(
        signatures?.signatureFor('prepared_by'),
        _idpField(e.preparedByName).isEmpty
            ? 'MARCELO B. CAÑARES'
            : _idpField(e.preparedByName),
      );
      final preparedTitle = _idpField(e.preparedByTitle).isEmpty
          ? 'Administrative Officer V / HRMDO'
          : _idpField(e.preparedByTitle);

      pw.Widget cell(
        String text, {
        required double height,
        bool header = false,
      }) {
        return pw.Container(
          height: height,
          alignment: header ? pw.Alignment.center : pw.Alignment.topLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(
            text,
            textAlign: header ? pw.TextAlign.center : pw.TextAlign.left,
            maxLines: header ? 2 : bodyLines,
            style: pw.TextStyle(
              fontSize: 8,
              height: 1.15,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }

      final form = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'SELECTION LINE-UP',
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 210,
                    alignment: pw.Alignment.centerLeft,
                    padding: const pw.EdgeInsets.only(bottom: 1),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          width: 0.6,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                    child: pw.Text(
                      _idpField(e.nameOfAgencyOffice).isEmpty
                          ? ' '
                          : _idpField(e.nameOfAgencyOffice),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Text(
                    'Name of Agency/Office',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.SizedBox(
                width: 120,
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: double.infinity,
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.only(bottom: 1),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            width: 0.6,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                      child: pw.Text(
                        _idpField(e.date).isEmpty ? ' ' : _idpField(e.date),
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                    pw.Text('Date', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Vacant Position:  ',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Container(
                width: 250,
                padding: const pw.EdgeInsets.only(bottom: 1),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                  ),
                ),
                child: pw.Text(
                  _idpField(e.vacantPosition).isEmpty
                      ? ' '
                      : _idpField(e.vacantPosition),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 108, top: 2),
            child: pw.Text(
              'Item No: ${_idpField(e.itemNo)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: border,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: pw.FlexColumnWidth(21),
              1: pw.FlexColumnWidth(15),
              2: pw.FlexColumnWidth(19),
              3: pw.FlexColumnWidth(27),
              4: pw.FlexColumnWidth(18),
            },
            children: [
              pw.TableRow(
                children: [
                  cell('NAME OF APPLICANTS', height: 26, header: true),
                  cell('EDUCATION', height: 26, header: true),
                  cell('EXPERIENCE', height: 26, header: true),
                  cell('TRAINING', height: 26, header: true),
                  cell('ELIGIBILITY', height: 26, header: true),
                ],
              ),
              for (var i = 0; i < rows.length; i++)
                pw.TableRow(
                  children: [
                    cell(
                      '${startNumber + i}. ${_idpField(rows[i]?.name)}',
                      height: rowHeight,
                    ),
                    cell(_idpField(rows[i]?.education), height: rowHeight),
                    cell(_idpField(rows[i]?.experience), height: rowHeight),
                    cell(_idpField(rows[i]?.training), height: rowHeight),
                    cell(_idpField(rows[i]?.eligibility), height: rowHeight),
                  ],
                ),
            ],
          ),
          if (lastPage) ...[
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.SizedBox(
                width: 210,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'Prepared by:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    _signatureImage(
                      signatures?.signatureFor('prepared_by'),
                      height: 28,
                    ),
                    pw.Text(
                      preparedName,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      preparedTitle,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );

      final bg = _lockedPrintBg ?? _activeCustomBg;
      if (bg == null) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(height: _selectionLineupLetterheadDrop),
            _pdfHeader(''),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 18),
                child: form,
              ),
            ),
          ],
        );
      }
      // Shift the shared letterhead down on this form only, and cover the
      // contact strip. The asset and other forms stay as they are.
      return pw.Stack(
        children: [
          pw.Positioned(
            top: _selectionLineupLetterheadDrop,
            left: 0,
            right: 0,
            bottom: -_selectionLineupLetterheadDrop,
            child: pw.Image(bg, fit: pw.BoxFit.fill),
          ),
          pw.Positioned.fill(
            child: pw.Padding(padding: _selectionLineupPadding, child: form),
          ),
          pw.Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: pw.Container(height: 96, color: PdfColors.white),
          ),
        ],
      );
    }

    for (var page = 0; page < pageCount; page++) {
      final start = page * _selectionLineupRowsPerPage;
      final rows = <SelectionLineupApplicant?>[];
      if (applicants.isEmpty) {
        rows.add(null);
      } else {
        final end = (start + _selectionLineupRowsPerPage).clamp(
          0,
          applicants.length,
        );
        rows.addAll(applicants.sublist(start, end));
      }
      doc.addPage(
        _fitPage(
          pageFormat: pageFormat,
          build: (ctx) => sheet(rows, start + 1, page == pageCount - 1),
        ),
      );
    }
    return doc;
  }

  static const int _computationOfPointsRowsPerPage = 5;

  static Future<pw.Document> buildComputationOfPointsPdf(
    ComputationOfPointsEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await Future.wait([ensureLogoLoaded(), _ensureIdpPdfFonts()]);
    // This sheet is the mayor's office form, not the HRMDO letterhead.
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
    final doc = pw.Document(theme: _idpPdfTheme);
    final pageFormat = pageLetterLandscape.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
    final candidates = e.candidates;
    final pageCount = candidates.isEmpty
        ? 1
        : ((candidates.length - 1) ~/ _computationOfPointsRowsPerPage) + 1;
    const border = pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.black),
      right: pw.BorderSide(width: 0.6, color: PdfColors.black),
      top: pw.BorderSide(width: 0.6, color: PdfColors.black),
      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
      horizontalInside: pw.BorderSide(width: 0.4, color: PdfColors.grey700),
      verticalInside: pw.BorderSide(width: 0.4, color: PdfColors.grey700),
    );
    final level = _idpField(e.positionLevel).isEmpty
        ? 'Second Level Position'
        : _idpField(e.positionLevel);

    pw.Widget underlineField(String label, String? value, double labelWidth) {
      final text = _idpField(value);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: labelWidth,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
            ),
            pw.Expanded(
              child: pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                  ),
                ),
                padding: const pw.EdgeInsets.only(left: 3, bottom: 1),
                child: pw.Text(
                  text.isEmpty ? ' ' : text,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget headerCell(String text) {
      return pw.Container(
        height: 36,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
        ),
      );
    }

    pw.Widget candidateCell(int number, ComputationOfPointsCandidate? c) {
      String line(String label, String? value) {
        final text = _idpField(value);
        return text.isEmpty ? label : '$label $text';
      }

      return pw.Container(
        height: 46,
        alignment: pw.Alignment.topLeft,
        padding: const pw.EdgeInsets.fromLTRB(3, 2, 2, 1),
        child: pw.Text(
          '$number  ${line('Name :', c?.name)}\n'
          '     ${line('Position :', c?.position)}\n'
          '     ${line('Salary Grade :', c?.salaryGrade)}\n'
          '     ${line('Rate :', c?.rate)}',
          maxLines: 4,
          style: const pw.TextStyle(fontSize: 7, height: 1.15),
        ),
      );
    }

    pw.Widget scoreCell(String? value) {
      final text = _idpField(value);
      return pw.Container(
        height: 46,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(2),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          maxLines: 3,
          style: const pw.TextStyle(fontSize: 8),
        ),
      );
    }

    pw.Widget sheet(List<ComputationOfPointsCandidate?> rows, int startNumber) {
      final seal = _logoBytes == null
          ? pw.SizedBox(width: 42, height: 42)
          : pw.Container(
              width: 42,
              height: 42,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: _letterheadNavy, width: 0.8),
              ),
              child: pw.ClipOval(
                child: pw.Image(
                  pw.MemoryImage(_logoBytes!),
                  fit: pw.BoxFit.cover,
                ),
              ),
            );

      return pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(26, 18, 26, 22),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  seal,
                  pw.SizedBox(width: 8),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Republic of the Philippines',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: _letterheadNavy,
                        ),
                      ),
                      pw.Text(
                        'PROVINCE OF MISAMIS OCCIDENTAL',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: _letterheadNavy,
                        ),
                      ),
                      pw.Text(
                        'MUNICIPALITY OF PLARIDEL',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: _letterheadNavy,
                        ),
                      ),
                      pw.Text(
                        'OFFICE OF THE MUNICIPAL MAYOR',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: _letterheadNavy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'COMPUTATION OF POINTS',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Personnel Selection Board',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date: ', style: const pw.TextStyle(fontSize: 8)),
                  pw.Container(
                    width: 110,
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.only(bottom: 1),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          width: 0.6,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                    child: pw.Text(
                      _idpField(e.date).isEmpty ? ' ' : _idpField(e.date),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ],
              ),
            ),
            pw.Center(
              child: pw.Text(
                '($level)',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      underlineField('POSITION :', e.position, 78),
                      underlineField('SALARY GRADE :', e.salaryGrade, 78),
                      underlineField('RATE :', e.rate, 78),
                      underlineField('OFFICE :', e.office, 78),
                    ],
                  ),
                ),
                pw.SizedBox(width: 28),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      underlineField('EDUCATION :', e.minEducation, 72),
                      underlineField('TRAINING :', e.minTraining, 72),
                      underlineField('EXPERIENCE :', e.minExperience, 72),
                      underlineField('ELIGIBILITY :', e.minEligibility, 72),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: border,
              columnWidths: const {
                0: pw.FlexColumnWidth(2.55),
                1: pw.FlexColumnWidth(0.78),
                2: pw.FlexColumnWidth(0.82),
                3: pw.FlexColumnWidth(0.82),
                4: pw.FlexColumnWidth(0.72),
                5: pw.FlexColumnWidth(0.9),
                6: pw.FlexColumnWidth(0.78),
                7: pw.FlexColumnWidth(0.78),
                8: pw.FlexColumnWidth(0.62),
                9: pw.FlexColumnWidth(0.48),
              },
              children: [
                pw.TableRow(
                  children: [
                    headerCell('NAME OF\nCANDIDATES'),
                    headerCell('EDUCATION\n(25%)'),
                    headerCell('ELIGIBILITY\n(20%)'),
                    headerCell('EXPERIENCE\n(15%)'),
                    headerCell('TRAINING\n(10%)'),
                    headerCell('PERFORMANCE\n(10%)'),
                    headerCell('POTENTIAL\n(10%)'),
                    headerCell('WORK\nATTITUDE\n(10%)'),
                    headerCell('TOTAL\n(100%)'),
                    headerCell('RANK'),
                  ],
                ),
                for (var i = 0; i < rows.length; i++)
                  pw.TableRow(
                    children: [
                      candidateCell(startNumber + i, rows[i]),
                      scoreCell(rows[i]?.education),
                      scoreCell(rows[i]?.eligibility),
                      scoreCell(rows[i]?.experience),
                      scoreCell(rows[i]?.training),
                      scoreCell(rows[i]?.performance),
                      scoreCell(rows[i]?.potential),
                      scoreCell(rows[i]?.workAttitude),
                      scoreCell(rows[i]?.total),
                      scoreCell(rows[i]?.rank),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Prepared by:',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  _signatureImage(
                    signatures?.signatureFor('prepared_by'),
                    height: 26,
                    width: 200,
                  ),
                  pw.Container(
                    width: 200,
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.only(bottom: 1),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          width: 0.6,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                    child: pw.Text(
                      _signatureName(
                        signatures?.signatureFor('prepared_by'),
                        _idpField(e.preparedByName),
                      ),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '(Printed Name/Over Signature)',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    for (var page = 0; page < pageCount; page++) {
      final start = page * _computationOfPointsRowsPerPage;
      final rows = List<ComputationOfPointsCandidate?>.filled(
        _computationOfPointsRowsPerPage,
        null,
      );
      if (candidates.isNotEmpty) {
        final end = (start + _computationOfPointsRowsPerPage).clamp(
          0,
          candidates.length,
        );
        for (var i = start; i < end; i++) {
          rows[i - start] = candidates[i];
        }
      }
      doc.addPage(
        _fitPage(
          pageFormat: pageFormat,
          build: (ctx) => sheet(rows, start + 1),
        ),
      );
    }
    return doc;
  }

  static Future<pw.Document> buildWorkExperienceSheetPdf(
    WorkExperienceSheetEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await _ensureIdpPdfFonts();
    await _bindCustomTemplate('rsp', 'work_experience');
    // Stay landscape. The uploaded background image is left as the page layer.
    _activeCustomFormat = null;
    final doc = pw.Document(theme: _idpPdfTheme);
    final pageFormat = pageLetterLandscape.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
    const contentPadding = pw.EdgeInsets.fromLTRB(40, 102, 40, 84);

    pw.Widget underlineField(String label, String? value) {
      final text = _idpField(value);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(width: 6),
            pw.Container(
              width: 148,
              alignment: pw.Alignment.bottomLeft,
              padding: const pw.EdgeInsets.only(left: 3, bottom: 1),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                ),
              ),
              child: pw.Text(
                text.isEmpty ? ' ' : text,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
      );
    }

    final jobText = _idpField(e.jobDescriptionLastWork);

    doc.addPage(
      _fitPage(
        pageFormat: pageFormat,
        build: (ctx) {
          final foreground = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  'WORK EXPERIENCE SHEET',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        underlineField(
                          'POSITION APPLIED FOR :',
                          e.positionAppliedFor,
                        ),
                        underlineField('DEPARTMENT :', e.department),
                        pw.Text(
                          '4 MINIMUM STANDARDS :',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 18),
                          child: pw.Column(
                            children: [
                              underlineField('1. Education :', e.minEducation),
                              underlineField(
                                '2. Experience :',
                                e.minExperience,
                              ),
                              underlineField('3. Training :', e.minTraining),
                              underlineField(
                                '4. Eligibility :',
                                e.minEligibility,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 22),
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
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
                          height: 168,
                          width: double.infinity,
                          padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 4),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                              width: 0.8,
                              color: PdfColors.black,
                            ),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  jobText,
                                  maxLines: 9,
                                  style: const pw.TextStyle(
                                    fontSize: 9,
                                    height: 1.2,
                                  ),
                                ),
                              ),
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
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2, right: 6),
                      child: pw.Text(
                        'Submitted by:',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Column(
                      children: [
                        _signatureImage(
                          signatures?.signatureFor('applicant'),
                          height: 26,
                          width: 160,
                        ),
                        pw.Container(
                          width: 160,
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.only(bottom: 1),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                width: 0.6,
                                color: PdfColors.black,
                              ),
                            ),
                          ),
                          child: pw.Text(
                            _signatureName(
                              signatures?.signatureFor('applicant'),
                              _idpField(e.applicantName),
                            ),
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Name of Applicant',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          if (_useCustomPrintBg) {
            return _printPage(foreground, padding: contentPadding);
          }
          return pw.Padding(padding: contentPadding, child: foreground);
        },
      ),
    );
    return doc;
  }

  static const int _turnAroundRowsPerPage = 5;

  static Future<pw.Document> buildTurnAroundTimePdf(
    TurnAroundTimeEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await Future.wait([ensureLogoLoaded(), _ensureIdpPdfFonts()]);
    _activeCustomBg = null;
    _lockedPrintBg = null;
    _activeCustomFormat = null;
    final doc = pw.Document(theme: _idpPdfTheme);
    final pageFormat = pageLetterLandscape.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
    final applicants = e.applicants;
    final pageCount = applicants.isEmpty
        ? 1
        : ((applicants.length - 1) ~/ _turnAroundRowsPerPage) + 1;
    const border = pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.black),
      right: pw.BorderSide(width: 0.6, color: PdfColors.black),
      top: pw.BorderSide(width: 0.6, color: PdfColors.black),
      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
      horizontalInside: pw.BorderSide(width: 0.4, color: PdfColors.black),
      verticalInside: pw.BorderSide(width: 0.4, color: PdfColors.black),
    );
    final preparedTitle = _idpField(e.preparedByTitle).isEmpty
        ? TurnAroundTimeEntry.defaultPreparedByTitle
        : _idpField(e.preparedByTitle);
    final notedName = _signatureName(
      signatures?.signatureFor('noted_by'),
      _idpField(e.notedByName).isEmpty
          ? TurnAroundTimeEntry.defaultNotedByName
          : _idpField(e.notedByName),
    );
    final notedTitle = _idpField(e.notedByTitle).isEmpty
        ? TurnAroundTimeEntry.defaultNotedByTitle
        : _idpField(e.notedByTitle);
    final preparedName = _signatureName(
      signatures?.signatureFor('prepared_by'),
      _idpField(e.preparedByName),
    );

    pw.Widget infoLine(String label, String? value, {double indent = 0}) {
      final text = _idpField(value);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (indent > 0) pw.SizedBox(width: indent),
            if (label.isNotEmpty)
              pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
            if (label.isNotEmpty) pw.SizedBox(width: 4),
            pw.Expanded(
              child: pw.Container(
                height: 14,
                alignment: pw.Alignment.bottomLeft,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                  ),
                ),
                padding: const pw.EdgeInsets.only(left: 3, bottom: 1),
                child: pw.Text(
                  text.isEmpty ? ' ' : text,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget headerCell(String text) {
      return pw.Container(
        height: 46,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
        ),
      );
    }

    pw.Widget bodyCell(String text, {bool center = true}) {
      return pw.Container(
        height: 22,
        alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: pw.Text(
          text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          maxLines: 2,
          style: const pw.TextStyle(fontSize: 7),
        ),
      );
    }

    pw.Widget signBlock(
      String label,
      String name,
      String title,
      DocuTrackerSourceSignature? signature,
    ) {
      return pw.SizedBox(
        width: 180,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
            _signatureImage(signature, height: 22, width: 160),
            pw.Container(
              width: 160,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                ),
              ),
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Text(' ', style: const pw.TextStyle(fontSize: 8)),
            ),
            if (name.isNotEmpty)
              pw.Text(
                name,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.Text(title, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );
    }

    pw.Widget sheet(List<TurnAroundTimeApplicant?> rows) {
      return pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'HUMAN RESOURCE MERIT PROMOTION AND SELECTION BOARD',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'MGO-Plaridel, Misamis Occidental',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'TURN-AROUND TIME',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    children: [
                      infoLine('Position :', e.position),
                      infoLine('Office :', e.office),
                      infoLine(
                        'No. of Vacant Position :',
                        e.noOfVacantPosition,
                      ),
                      infoLine('Date of Publication :', e.dateOfPublication),
                      infoLine('End Search :', e.endSearch),
                    ],
                  ),
                ),
                pw.SizedBox(width: 36),
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    children: [
                      infoLine('Q.S. :', e.qs),
                      infoLine('', null, indent: 28),
                      infoLine('', null, indent: 28),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: border,
              columnWidths: const {
                0: pw.FixedColumnWidth(18),
                1: pw.FlexColumnWidth(1.45),
                2: pw.FlexColumnWidth(0.85),
                3: pw.FlexColumnWidth(0.95),
                4: pw.FlexColumnWidth(0.75),
                5: pw.FlexColumnWidth(0.78),
                6: pw.FlexColumnWidth(0.7),
                7: pw.FlexColumnWidth(0.82),
                8: pw.FlexColumnWidth(0.82),
                9: pw.FlexColumnWidth(0.78),
                10: pw.FlexColumnWidth(1.35),
              },
              children: [
                pw.TableRow(
                  children: [
                    headerCell(''),
                    headerCell('Name of\nApplicant'),
                    headerCell('Date of Initial\nAssessment'),
                    headerCell('Date of Contract\nfor trade and\nwritten exam'),
                    headerCell('Skills Trade/\nExam Result'),
                    headerCell('Date of\nDeliberation'),
                    headerCell('Date of Job\nOffer'),
                    headerCell('Acceptance\ndate of Job\nOffer'),
                    headerCell('Date of\nAssumption\nto Duty'),
                    headerCell('No. of Days\nto Fill-Up\nPosition'),
                    headerCell(
                      'Overall Cost per hire\n(Advertising Referral.\nBonus if any, new\nhired salary and\nbenefits)',
                    ),
                  ],
                ),
                for (var i = 0; i < rows.length; i++)
                  pw.TableRow(
                    children: [
                      bodyCell('${i + 1}'),
                      bodyCell(_idpField(rows[i]?.name), center: false),
                      bodyCell(_idpField(rows[i]?.dateInitialAssessment)),
                      bodyCell(_idpField(rows[i]?.dateContractExam)),
                      bodyCell(_idpField(rows[i]?.skillsTradeExamResult)),
                      bodyCell(_idpField(rows[i]?.dateDeliberation)),
                      bodyCell(_idpField(rows[i]?.dateJobOffer)),
                      bodyCell(_idpField(rows[i]?.acceptanceDate)),
                      bodyCell(_idpField(rows[i]?.dateAssumptionToDuty)),
                      bodyCell(_idpField(rows[i]?.noOfDaysToFillUp)),
                      bodyCell(_idpField(rows[i]?.overallCostPerHire)),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                signBlock(
                  'Prepared by:',
                  preparedName,
                  preparedTitle,
                  signatures?.signatureFor('prepared_by'),
                ),
                pw.Spacer(),
                signBlock(
                  'Noted by:',
                  notedName,
                  notedTitle,
                  signatures?.signatureFor('noted_by'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    for (var page = 0; page < pageCount; page++) {
      final start = page * _turnAroundRowsPerPage;
      final rows = List<TurnAroundTimeApplicant?>.filled(
        _turnAroundRowsPerPage,
        null,
      );
      if (applicants.isNotEmpty) {
        final end = (start + _turnAroundRowsPerPage).clamp(
          0,
          applicants.length,
        );
        for (var i = start; i < end; i++) {
          rows[i - start] = applicants[i];
        }
      }
      doc.addPage(
        _fitPage(pageFormat: pageFormat, build: (ctx) => sheet(rows)),
      );
    }
    return doc;
  }

  /// Training Need Analysis and Consolidated Report (L&D).
  /// One official landscape page holds 6 tall rows.
  static Future<pw.Document> buildTrainingNeedAnalysisPdf(
    TrainingNeedAnalysisEntry e,
  ) async {
    await Future.wait([ensureLogoLoaded(), _ensureIdpPdfFonts()]);
    await _bindCustomTemplate('ld', 'training_need_analysis');
    final doc = pw.Document(theme: _idpPdfTheme);
    const perPage = 6;
    final rows = e.rows;
    final pageCount = rows.isEmpty ? 1 : ((rows.length - 1) ~/ perPage) + 1;
    const border = pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.black),
      right: pw.BorderSide(width: 0.6, color: PdfColors.black),
      top: pw.BorderSide(width: 0.6, color: PdfColors.black),
      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
      horizontalInside: pw.BorderSide(width: 0.45, color: PdfColors.black),
      verticalInside: pw.BorderSide(width: 0.45, color: PdfColors.black),
    );

    String blank(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return '';
      return _pdfSafe(text);
    }

    String namePositionCell(String? raw) {
      final text = blank(raw);
      final splitAt = text.indexOf(' / ');
      if (splitAt <= 0) return text;
      final name = text.substring(0, splitAt).trim();
      final position = text.substring(splitAt + 3).trim();
      if (name.isEmpty) return position;
      if (position.isEmpty) return name;
      return '$name\n$position';
    }

    pw.Widget tableCell(
      String text, {
      required double height,
      bool header = false,
    }) {
      return pw.Container(
        height: height,
        alignment: header ? pw.Alignment.center : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          textAlign: header ? pw.TextAlign.center : pw.TextAlign.left,
          maxLines: header ? 2 : 5,
          style: pw.TextStyle(
            fontSize: header ? 7 : 8,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    pw.Widget analysisTable(List<TrainingNeedAnalysisRow?> pageRows) {
      return pw.Table(
        border: border,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: pw.FlexColumnWidth(1.55),
          1: pw.FlexColumnWidth(1.05),
          2: pw.FlexColumnWidth(1.05),
          3: pw.FlexColumnWidth(1.15),
          4: pw.FlexColumnWidth(1.15),
          5: pw.FlexColumnWidth(1.55),
        },
        children: [
          pw.TableRow(
            children: [
              tableCell('NAME/POSITION', height: 28, header: true),
              tableCell('GOAL', height: 28, header: true),
              tableCell('BEHAVIOR', height: 28, header: true),
              tableCell('SKILLS/KNOWLEDGE', height: 28, header: true),
              tableCell('NEED FOR\nTRAINING', height: 28, header: true),
              tableCell('TRAINING\nRECOMMENDATIONS', height: 28, header: true),
            ],
          ),
          for (var i = 0; i < perPage; i++)
            pw.TableRow(
              children: [
                tableCell(
                  namePositionCell(pageRows[i]?.namePosition),
                  height: 46,
                ),
                tableCell(blank(pageRows[i]?.goal), height: 46),
                tableCell(blank(pageRows[i]?.behavior), height: 46),
                tableCell(blank(pageRows[i]?.skillsKnowledge), height: 46),
                tableCell(blank(pageRows[i]?.needForTraining), height: 46),
                tableCell(
                  blank(pageRows[i]?.trainingRecommendations),
                  height: 46,
                ),
              ],
            ),
        ],
      );
    }

    pw.Widget sheet(List<TrainingNeedAnalysisRow?> pageRows) {
      final year = blank(e.cyYear);
      final department = blank(e.department);
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'TRAINING NEED ANALYSIS',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'AND CONSOLIDATED REPORT',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              year.isEmpty ? 'FOR CY' : 'FOR CY $year',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              department.isEmpty ? 'DEPARTMENT:' : 'DEPARTMENT: $department',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          analysisTable(pageRows),
        ],
      );
    }

    for (var page = 0; page < pageCount; page++) {
      final start = page * perPage;
      final end = (start + perPage).clamp(0, rows.length);
      final pageRows = List<TrainingNeedAnalysisRow?>.filled(perPage, null);
      if (rows.isNotEmpty) {
        final chunk = rows.sublist(start, end);
        for (var i = 0; i < chunk.length; i++) {
          pageRows[i] = chunk[i];
        }
      }
      doc.addPage(
        _fitPage(
          pageFormat: _printPageFormat(pageLetterLandscape),
          build: (ctx) {
            final body = sheet(pageRows);
            if (_useCustomPrintBg) {
              return _printPage(
                body,
                padding: const pw.EdgeInsets.fromLTRB(32, 100, 32, 62),
              );
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _pdfHeader(''),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                    child: body,
                  ),
                ),
                _pdfFooter(),
              ],
            );
          },
        ),
      );
    }
    return doc;
  }

  /// Action Brainstorming and Coaching Worksheet (L&D).
  /// One official landscape page holds 15 numbered rows.
  static Future<pw.Document> buildActionBrainstormingCoachingPdf(
    ActionBrainstormingEntry e, {
    DocuTrackerSourceSignatureBundle? signatures,
  }) async {
    await Future.wait([ensureLogoLoaded(), _ensureIdpPdfFonts()]);
    await _bindCustomTemplate('ld', 'action_brainstorming');
    final doc = pw.Document(theme: _idpPdfTheme);
    const perPage = 15;
    final rows = e.rows;
    final pageCount = rows.isEmpty ? 1 : ((rows.length - 1) ~/ perPage) + 1;
    const border = pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.black),
      right: pw.BorderSide(width: 0.6, color: PdfColors.black),
      top: pw.BorderSide(width: 0.6, color: PdfColors.black),
      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
      horizontalInside: pw.BorderSide(width: 0.45, color: PdfColors.black),
      verticalInside: pw.BorderSide(width: 0.45, color: PdfColors.black),
    );
    final labelStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    );
    const valueStyle = pw.TextStyle(fontSize: 9);

    String blank(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return '';
      return _pdfSafe(text);
    }

    pw.Widget metaLine(String label, String? value) {
      final text = blank(value);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.SizedBox(width: 92, child: pw.Text(label, style: labelStyle)),
            pw.Container(
              width: 230,
              padding: const pw.EdgeInsets.only(bottom: 1),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                ),
              ),
              child: pw.Text(text.isEmpty ? ' ' : text, style: valueStyle),
            ),
          ],
        ),
      );
    }

    pw.Widget tableCell(
      String text, {
      required double height,
      bool header = false,
      bool center = false,
    }) {
      return pw.Container(
        height: height,
        alignment: center || header
            ? pw.Alignment.center
            : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
        child: pw.Text(
          text,
          textAlign: center || header ? pw.TextAlign.center : pw.TextAlign.left,
          maxLines: header ? 2 : 2,
          style: pw.TextStyle(
            fontSize: header ? 6.5 : 6.5,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    pw.Widget worksheetTable(List<ActionBrainstormingRow?> pageRows) {
      pw.TableRow dataRow(int number, ActionBrainstormingRow? row) {
        final values = <String>[
          '$number.',
          blank(row?.name),
          blank(row?.stopDoing),
          blank(row?.doLessOf),
          blank(row?.keepDoing),
          blank(row?.doMoreOf),
          blank(row?.startDoing),
          blank(row?.goal),
        ];
        return pw.TableRow(
          children: [
            for (var i = 0; i < values.length; i++)
              tableCell(values[i], height: 16, center: i == 0),
          ],
        );
      }

      return pw.Table(
        border: border,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: pw.FlexColumnWidth(0.36),
          1: pw.FlexColumnWidth(1.35),
          2: pw.FlexColumnWidth(1.15),
          3: pw.FlexColumnWidth(1.1),
          4: pw.FlexColumnWidth(1.1),
          5: pw.FlexColumnWidth(1.1),
          6: pw.FlexColumnWidth(1.15),
          7: pw.FlexColumnWidth(1.25),
        },
        children: [
          pw.TableRow(
            children: [
              tableCell('', height: 20, header: true),
              tableCell('NAME', height: 20, header: true),
              tableCell('STOP DOING', height: 20, header: true),
              tableCell('DO LESS OF', height: 20, header: true),
              tableCell('KEEP DOING', height: 20, header: true),
              tableCell('DO MORE OF', height: 20, header: true),
              tableCell('START DOING', height: 20, header: true),
              tableCell('GOAL', height: 20, header: true),
            ],
          ),
          for (var i = 0; i < perPage; i++) dataRow(i + 1, pageRows[i]),
        ],
      );
    }

    pw.Widget certification() {
      final signature = signatures?.signatureFor('certified_by');
      final name = _signatureName(signature, blank(e.certifiedBy));
      final signedDate = blank(e.certificationDate);
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Certified by:  ', style: labelStyle),
                  pw.Column(
                    children: [
                      _signatureImage(signature, height: 16, width: 170),
                      pw.Container(
                        width: 170,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(
                              width: 0.6,
                              color: PdfColors.black,
                            ),
                          ),
                        ),
                        child: pw.Text(
                          name.isEmpty ? ' ' : name,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 78, top: 2),
                child: pw.Text(
                  'Department Head',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 14, right: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Date:  ', style: labelStyle),
                pw.Container(
                  width: 150,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                    ),
                  ),
                  child: pw.Text(
                    signedDate.isEmpty ? ' ' : signedDate,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    pw.Widget sheet(List<ActionBrainstormingRow?> pageRows) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'ACTION BRAINSTORMING AND COACHING WORKSHEET',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Column(
              children: [
                metaLine('DEPARTMENT:', e.department),
                metaLine('DATE:', e.date),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Instruction:  Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 5),
          worksheetTable(pageRows),
          pw.SizedBox(height: 8),
          certification(),
        ],
      );
    }

    for (var page = 0; page < pageCount; page++) {
      final start = page * perPage;
      final end = (start + perPage).clamp(0, rows.length);
      final pageRows = List<ActionBrainstormingRow?>.filled(perPage, null);
      if (rows.isNotEmpty) {
        final chunk = rows.sublist(start, end);
        for (var i = 0; i < chunk.length; i++) {
          pageRows[i] = chunk[i];
        }
      }
      doc.addPage(
        _fitPage(
          pageFormat: _printPageFormat(pageLetterLandscape),
          build: (ctx) {
            final body = sheet(pageRows);
            if (_useCustomPrintBg) {
              return _printPage(
                body,
                padding: const pw.EdgeInsets.fromLTRB(36, 108, 36, 68),
              );
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _pdfHeader(''),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                    child: body,
                  ),
                ),
                _pdfFooter(),
              ],
            );
          },
        ),
      );
    }
    return doc;
  }

  /// Simple printable summary for employee training daily reports (L&D).
  static Future<pw.Document> buildTrainingDailyReportPdf(
    TrainingDailyReport r,
  ) async {
    await ensureLogoLoaded();
    final doc = pw.Document();
    doc.addPage(
      _fitPage(
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
    return doc;
  }

  static Future<void> printTrainingDailyReport(TrainingDailyReport r) async {
    final doc = await buildTrainingDailyReportPdf(r);
    await printDocument(doc, name: 'training-daily-report.pdf');
  }

  /// Learning Application Plan (L&D) — official landscape letterhead form.
  static pw.Widget _lapMemoLine(String label, String? value) {
    final text = _idpField(value);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 108,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(': ', style: const pw.TextStyle(fontSize: 8)),
          pw.Container(
            width: 280,
            padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.6)),
            ),
            child: pw.Text(
              text.isEmpty ? ' ' : text,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _lapHeader() {
    if (_useCustomPrintBg) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Center(
          child: pw.Text(
            'LEARNING APPLICATION PLAN',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
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

  static pw.Widget _lapTable(LearningApplicationPlanEntry e) {
    const flexes = <int>[115, 115, 135, 125, 85, 110, 115];
    const headers = <String>[
      'LEARNING',
      'OBJECTIVES',
      'COMPETENCY\nGAPS\nADDRESSED',
      'REAP\nIMPLEMENTATION',
      'TIMELINE',
      'PERSONS\nINVOLVED',
      'EVIDENCE',
    ];
    final rows = e.entries.where((row) => !row.isBlank).toList();
    final body = rows.isEmpty
        ? const <LearningApplicationPlanRow?>[null]
        : rows;

    List<String> valuesOf(LearningApplicationPlanRow? row) {
      return [
        _idpField(row?.learning),
        _idpField(row?.objectives),
        _idpField(row?.competencyGapsAddressed),
        _idpField(row?.reapImplementation),
        _idpField(row?.timeline),
        _idpField(row?.personsInvolved),
        _idpField(row?.evidence),
      ];
    }

    pw.Widget band(
      List<String> texts, {
      required bool header,
      bool expand = false,
    }) {
      final row = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < texts.length; i++)
            pw.Expanded(
              flex: flexes[i],
              child: pw.Container(
                alignment: header ? pw.Alignment.center : pw.Alignment.topLeft,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 2,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    left: i == 0
                        ? pw.BorderSide.none
                        : const pw.BorderSide(
                            width: 0.6,
                            color: PdfColors.black,
                          ),
                  ),
                ),
                child: pw.Text(
                  texts[i],
                  textAlign: header ? pw.TextAlign.center : pw.TextAlign.left,
                  maxLines: header ? 3 : 8,
                  style: pw.TextStyle(
                    fontSize: header ? 7 : 8,
                    fontWeight: header
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      );
      final boxed = pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 0.6, color: PdfColors.black),
          ),
        ),
        child: expand ? row : pw.SizedBox(height: 34, child: row),
      );
      return expand ? pw.Expanded(child: boxed) : boxed;
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.7, color: PdfColors.black),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          band(headers, header: true),
          for (final row in body)
            band(valuesOf(row), header: false, expand: true),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(6, 3, 6, 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(width: 0.6, color: PdfColors.black),
              ),
            ),
            child: pw.Text(
              'TYPES OF REAP: ORIENTATION, ENCODING, COACHING, MENTORING, ETC.',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
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
      _fitPage(
        pageFormat: _printPageFormat(
          pageLetterLandscape.copyWith(
            marginTop: 22,
            marginBottom: 0,
            marginLeft: 28,
            marginRight: 28,
          ),
        ),
        build: (ctx) => _printPage(
          pw.Column(
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
              pw.SizedBox(height: 6),
              pw.Expanded(child: _lapTable(e)),
              pw.SizedBox(height: 8),
              _lapSignatures(e),
              pw.SizedBox(height: 6),
              _lapFooter(),
            ],
          ),
          padding: _useCustomPrintBg
              ? const pw.EdgeInsets.fromLTRB(36, 102, 36, 78)
              : null,
        ),
      ),
    );
    return doc;
  }

  /// Clears the municipal header and footer on the F4 portrait letterhead.
  static const pw.EdgeInsets _ojtContentPadding = pw.EdgeInsets.fromLTRB(
    40,
    118,
    40,
    108,
  );

  static final pw.TextStyle _ojtLabel = pw.TextStyle(
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
  );

  static pw.Widget _ojtWriteLine(String? value, {double? width}) {
    final text = _idpField(value);
    final line = pw.Container(
      width: width,
      height: 16,
      alignment: pw.Alignment.bottomLeft,
      padding: const pw.EdgeInsets.only(left: 4, right: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.8, color: PdfColors.black),
        ),
      ),
      child: pw.Text(
        text.isEmpty ? ' ' : text,
        maxLines: 1,
        style: const pw.TextStyle(fontSize: 11),
      ),
    );
    if (width != null) return line;
    return pw.Expanded(child: line);
  }

  static pw.Widget _ojtLabeledLine(
    String label,
    String? value, {
    double? lineWidth,
    bool bullet = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(bullet ? '•  $label :' : '$label :', style: _ojtLabel),
          pw.SizedBox(width: 6),
          _ojtWriteLine(value, width: lineWidth),
        ],
      ),
    );
  }

  static pw.Widget _ojtRatingScale() {
    const lines = [
      '1. Unsatisfactory: Fails to meet the basic expectations or provide relevant examples.',
      '2. Marginal: Partially meets criteria; weak or vague examples.',
      '3. Competent: Solidly meet job requirements with clear examples.',
      '4. Above average: Exceeds standard expectations, strong evidence of skill.',
      '5. Exceptional: Outstanding proficiency, deeply relevant expertise.',
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('(Rating Scale)', style: _ojtLabel.copyWith(fontSize: 12)),
        pw.SizedBox(height: 4),
        for (final line in lines) ...[
          pw.Text(line, style: const pw.TextStyle(fontSize: 9.5, height: 1.2)),
          pw.SizedBox(height: 2),
        ],
      ],
    );
  }

  static pw.Widget _ojtCriterion({
    required int number,
    required String title,
    required String prompt,
    required int? score,
    required String? notes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$number. $title',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: '•  Question Prompt: ',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.TextSpan(
                      text: '"$prompt"',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontStyle: pw.FontStyle.italic,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('•  Score (1-5) :', style: _ojtLabel),
                  pw.SizedBox(width: 6),
                  _ojtWriteLine(score?.toString(), width: 88),
                ],
              ),
              pw.SizedBox(height: 3),
              _ojtLabeledLine('Evidence/Notes', notes, bullet: true),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _ojtFormBody(OjtWorkImmersionEvaluation e) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'OJT/WORK IMMERSION EVALUATION',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        _ojtLabeledLine('OJT/IMMERSION', e.ojtImmersion),
        _ojtLabeledLine('SCHOOL', e.school),
        _ojtLabeledLine('DATE OF INTERVIEW', e.interviewDate),
        pw.SizedBox(height: 4),
        _ojtRatingScale(),
        pw.SizedBox(height: 6),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 6),
        pw.Text(
          'EVALUATION CRITERIA',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        _ojtCriterion(
          number: 1,
          title: 'Problem Solving and Decision Making',
          prompt:
              'Tell me about a time you had to make a difficult decision quickly with limited information.',
          score: e.problemSolvingScore,
          notes: e.problemSolvingNotes,
        ),
        pw.SizedBox(height: 6),
        _ojtCriterion(
          number: 2,
          title: 'Communication and Clarity',
          prompt:
              'How do you explain a complex concept or project update to a non-technical stakeholder?',
          score: e.communicationScore,
          notes: e.communicationNotes,
        ),
        pw.SizedBox(height: 6),
        _ojtCriterion(
          number: 3,
          title: 'Teamwork and Collaboration',
          prompt:
              'Describe a time you worked with a difficult team member to reach a shared goal.',
          score: e.teamworkScore,
          notes: e.teamworkNotes,
        ),
        pw.SizedBox(height: 6),
        _ojtCriterion(
          number: 4,
          title: 'Adaptability and Resilience',
          prompt:
              'How do you handle sudden priority shifts or project changes under tight deadlines?',
          score: e.adaptabilityScore,
          notes: e.adaptabilityNotes,
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'SUMMARY AND RECOMMENDATIONS',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('•  TOTAL SCORE :', style: _ojtLabel),
            pw.SizedBox(width: 6),
            _ojtWriteLine(e.totalScore?.toString(), width: 72),
            pw.SizedBox(width: 6),
            pw.Text(
              '/20',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        _ojtLabeledLine(
          'OVERALL RECOMMENDATION',
          e.overallRecommendation,
          bullet: true,
        ),
        _ojtLabeledLine('KEY STRENGTHS', e.keyStrengths, bullet: true),
        _ojtLabeledLine('KEY CONCERNS', e.keyConcerns, bullet: true),
        _ojtLabeledLine('INTERVIEWER SIGNATURE', e.interviewer, bullet: true),
      ],
    );
  }

  static Future<pw.Document> buildOjtWorkImmersionEvaluationPdf(
    OjtWorkImmersionEvaluation e,
  ) async {
    await _ensureIdpPdfFonts();
    await _bindCustomTemplate('rsp', 'ojt_work_immersion');
    _activeCustomFormat = null;
    final doc = pw.Document(theme: _idpPdfTheme);
    final page =
        _ojtTarget ??
        PdfPageFormat(ojtMasterWidth, ojtMasterHeight, marginAll: 0);
    _lastPaperTarget = page;
    final body = _ojtFormBody(e);
    final sheet = _useCustomPrintBg
        ? _printPage(body, padding: _ojtContentPadding)
        : pw.Padding(padding: _ojtContentPadding, child: body);

    doc.addPage(
      pw.Page(
        pageFormat: page,
        margin: pw.EdgeInsets.zero,
        build: (ctx) => _fitApplicantsMaster(
          page,
          sheet,
          masterWidth: ojtMasterWidth,
          masterHeight: ojtMasterHeight,
        ),
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
