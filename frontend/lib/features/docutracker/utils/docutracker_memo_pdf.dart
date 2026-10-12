import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Color, Rect;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

/// Official artwork for the Memo PDF. Missing files leave their slots blank.
class DocuTrackerMemoPdfAssets {
  const DocuTrackerMemoPdfAssets({
    this.seal,
    this.asensoLogo,
    this.bagongPilipinasLogo,
    this.footerStrip,
  });

  final Uint8List? seal;
  final Uint8List? asensoLogo;
  final Uint8List? bagongPilipinasLogo;
  final Uint8List? footerStrip;

  static Future<DocuTrackerMemoPdfAssets> load() async {
    Future<Uint8List?> read(String path) async {
      try {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        return null;
      }
    }

    return DocuTrackerMemoPdfAssets(
      seal: await read(DocuTrackerMemoLayout.sealAsset),
      asensoLogo: await read(DocuTrackerMemoLayout.asensoLogoAsset),
      bagongPilipinasLogo: await read(
        DocuTrackerMemoLayout.bagongPilipinasLogoAsset,
      ),
      footerStrip: await read(DocuTrackerMemoLayout.footerStripAsset),
    );
  }
}

pw.ThemeData? _memoTheme;

/// The bundled Noto Sans (same family the builder renders), so the official
/// PDF never depends on a network font download. Falls back to the PDF's
/// built-in Helvetica (null) only if the bundled files cannot be read.
Future<pw.ThemeData?> loadDocuTrackerMemoPdfTheme() async {
  if (_memoTheme != null) return _memoTheme;
  try {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    return _memoTheme = pw.ThemeData.withFont(base: base, bold: bold);
  } catch (_) {
    return null;
  }
}

double _points(double pixels) => pixels * DocuTrackerMemoLayout.pointsPerPixel;

final double _bodyPointSize = _points(DocuTrackerMemoLayout.bodyFontSize);

/// Noto Sans hhea line extent (ascender 1069 + descender 293 per 1000 em);
/// the PDF adds `lineSpacing` on top of it, Flutter scales to `height`.
const double _notoLineExtent = 1.362;

final double _bodyLineSpacing =
    (DocuTrackerMemoLayout.bodyLineHeight - _notoLineExtent) * _bodyPointSize;
const PdfColor _ink = PdfColor.fromInt(0xFF111827);
const PdfColor _releaseInk = PdfColor.fromInt(0xFF1D4ED8);

PdfColor _pdfColor(Color color) => PdfColor.fromInt(color.toARGB32());

/// Vector A4 Memorandum. Text and logos stay sharp; the letterhead and footer
/// repeat on every page, the body flows onto extra pages, and the closing
/// block (signatures, release, CC) is anchored to the last page at the same
/// page fractions the builder uses.
Future<Uint8List> buildDocuTrackerMemoPdf({
  required DocuTrackerMemoTemplate memo,
  required List<Map<String, dynamic>> body,
  required List<DocuTrackerSignatureField> signatureFields,
  DocuTrackerMemoRelease? release,
  DocuTrackerMemoPdfAssets assets = const DocuTrackerMemoPdfAssets(),
  pw.ThemeData? theme,
  @visibleForTesting bool compress = true,
}) async {
  const format = PdfPageFormat.a4;
  final width = format.width;
  final height = format.height;
  final marginX = DocuTrackerMemoLayout.marginX * width;
  final footerTop = DocuTrackerMemoLayout.footerStrip.top * height;
  final bottomMargin = height - footerTop + 10;
  // Body may never pass the closing block, matching the builder's body area.
  final closingReserve =
      footerTop - 10 - (DocuTrackerMemoLayout.closingTop - 0.01) * height;

  pw.ImageProvider? image(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  final seal = image(assets.seal);
  final asenso = image(assets.asensoLogo);
  final bagongPilipinas = image(assets.bagongPilipinasLogo);
  final footerStrip = image(assets.footerStrip);

  pw.Widget placed(Rect fraction, pw.Widget child) => pw.Positioned(
    left: fraction.left * width,
    top: fraction.top * height,
    child: pw.SizedBox(
      width: fraction.width * width,
      height: fraction.height * height,
      child: child,
    ),
  );

  pw.Widget background(pw.Context context) => pw.FullPage(
    ignoreMargins: true,
    child: pw.Stack(
      children: [
        if (seal != null)
          placed(
            DocuTrackerMemoLayout.seal,
            pw.Image(seal, fit: pw.BoxFit.contain),
          ),
        pw.Positioned(
          left: DocuTrackerMemoLayout.headingLeft * width,
          top: DocuTrackerMemoLayout.headingTop * height,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                DocuTrackerMemoLayout.republic,
                style: const pw.TextStyle(fontSize: 9.4, color: _ink),
              ),
              pw.Text(
                DocuTrackerMemoLayout.province,
                style: pw.TextStyle(
                  fontSize: 9.4,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.Text(
                DocuTrackerMemoLayout.municipality,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfColor(DocuTrackerMemoLayout.municipalityRed),
                ),
              ),
              pw.Text(
                DocuTrackerMemoLayout.office,
                style: pw.TextStyle(
                  fontSize: 9.4,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfColor(DocuTrackerMemoLayout.navy),
                ),
              ),
            ],
          ),
        ),
        if (asenso != null)
          placed(
            DocuTrackerMemoLayout.asensoLogo,
            pw.Image(asenso, fit: pw.BoxFit.contain),
          ),
        if (bagongPilipinas != null)
          placed(
            DocuTrackerMemoLayout.bagongPilipinasLogo,
            pw.Image(bagongPilipinas, fit: pw.BoxFit.contain),
          ),
        placed(
          DocuTrackerMemoLayout.peachBand,
          pw.Container(
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                begin: pw.Alignment.topCenter,
                end: pw.Alignment.bottomCenter,
                colors: [
                  _pdfColor(DocuTrackerMemoLayout.peach),
                  PdfColors.white,
                ],
              ),
            ),
          ),
        ),
        placed(
          DocuTrackerMemoLayout.footerStrip,
          footerStrip == null
              ? pw.Container(
                  color: _pdfColor(DocuTrackerMemoLayout.reservedArtwork),
                )
              : pw.Image(footerStrip, fit: pw.BoxFit.cover),
        ),
        placed(
          DocuTrackerMemoLayout.sloganBar,
          pw.Container(
            color: _pdfColor(DocuTrackerMemoLayout.sloganBand),
            alignment: pw.Alignment.center,
            child: pw.Text(
              DocuTrackerMemoLayout.slogan,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 9.75,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
                color: PdfColors.white,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  final metadataStyle = pw.TextStyle(
    fontSize: _points(DocuTrackerMemoLayout.metadataFontSize),
  );
  pw.Widget metadataRow(String label, List<String> lines, {int? maxLines}) =>
      pw.Padding(
        padding: pw.EdgeInsets.only(
          bottom: _points(DocuTrackerMemoLayout.metadataRowGap),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: _points(DocuTrackerMemoLayout.metadataLabelWidth),
              child: pw.Text(label, style: metadataStyle),
            ),
            pw.SizedBox(
              width: _points(DocuTrackerMemoLayout.metadataColonWidth),
              child: pw.Text(':', style: metadataStyle),
            ),
            pw.Expanded(
              child: pw.Text(
                lines.join('\n'),
                maxLines: maxLines,
                style: metadataStyle,
              ),
            ),
          ],
        ),
      );

  pw.Widget header(pw.Context context) {
    if (context.pageNumber != 1) return pw.SizedBox(height: 10);
    final titleGap =
        (DocuTrackerMemoLayout.titleTop - DocuTrackerMemoLayout.headerBottom) *
        height;
    const titleSize = 19.5;
    final metadataGap =
        (DocuTrackerMemoLayout.metadataTop - DocuTrackerMemoLayout.titleTop) *
            height -
        titleSize * 1.2;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: titleGap),
        pw.Text(
          DocuTrackerMemoLayout.title,
          style: pw.TextStyle(
            fontSize: titleSize,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 6,
          ),
        ),
        pw.SizedBox(height: metadataGap),
        metadataRow(
          'To',
          DocuTrackerMemoTemplate.lines(memo.to),
          maxLines: DocuTrackerMemoLayout.toMaxLines,
        ),
        metadataRow(
          'Subject',
          DocuTrackerMemoTemplate.lines(memo.subject),
          maxLines: DocuTrackerMemoLayout.subjectMaxLines,
        ),
        metadataRow(
          'Date',
          DocuTrackerMemoTemplate.lines(memo.date),
          maxLines: 1,
        ),
        pw.SizedBox(height: 3),
        pw.Container(height: 1.8, color: _ink),
        pw.SizedBox(height: 10),
      ],
    );
  }

  pw.Widget signature(DocuTrackerSignatureField field) {
    final name = (field.signerName ?? field.assignedSignerName ?? '').trim();
    final mark = field.isSigned ? image(field.signatureImageBytes) : null;
    return pw.Column(
      children: [
        pw.Expanded(
          child: mark == null
              ? pw.SizedBox()
              : pw.Image(mark, fit: pw.BoxFit.contain),
        ),
        pw.Container(
          width: double.infinity,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.6)),
          ),
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            name.toUpperCase(),
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (field.isSigned && field.signedAt != null)
          pw.Text(
            'Signed ${docuTrackerReleaseTimestamp(field.signedAt!)}',
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
          ),
      ],
    );
  }

  /// Same block as the builder: signature, line, printed name, position.
  /// An unassigned slot keeps its blank line and prints no placeholder.
  pw.Widget signatory(DocuTrackerMemoSignatory signatory) {
    final field = signatory.field;
    final mark = signatory.isSigned ? image(field?.signatureImageBytes) : null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: mark == null
              ? pw.SizedBox()
              : pw.Image(mark, fit: pw.BoxFit.contain),
        ),
        pw.Container(height: 0.75, color: _ink),
        pw.SizedBox(height: 1.5),
        pw.Text(
          signatory.printedName ?? '',
          maxLines: 1,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: _points(DocuTrackerMemoLayout.signatoryNameFontSize),
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          signatory.position ?? '',
          maxLines: 1,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: _points(DocuTrackerMemoLayout.signatoryPositionFontSize),
          ),
        ),
      ],
    );
  }

  final preparedBy = DocuTrackerMemoSignatory.resolve(
    DocuTrackerMemoSlot.preparedBy,
    signatureFields,
  );
  final approvedBy = DocuTrackerMemoSignatory.resolve(
    DocuTrackerMemoSlot.approvedBy,
    signatureFields,
  );
  final otherFields = signatureFields
      .where((field) => !DocuTrackerMemoSignatory.isSlotField(field))
      .toList(growable: false);

  pw.Widget releaseBlock(DocuTrackerMemoRelease release) {
    const style = pw.TextStyle(fontSize: 8.6, color: _releaseInk);
    final remarks = release.remarks;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _releaseInk, width: 1.2),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'RELEASED',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 2,
              color: _releaseInk,
            ),
          ),
          pw.Text(
            'Released to: ${release.departmentName}',
            maxLines: 1,
            style: style,
          ),
          pw.Text(
            'Released by: ${release.releasedByName}',
            maxLines: 1,
            style: style,
          ),
          pw.Text(
            'Date: ${docuTrackerReleaseTimestamp(release.releasedAt)}',
            maxLines: 1,
            style: style,
          ),
          if (remarks != null)
            pw.Text('Remarks: $remarks', maxLines: 1, style: style),
        ],
      ),
    );
  }

  pw.Widget closing(pw.Context context) {
    if (context.pageNumber != context.pagesCount) return pw.SizedBox();
    final labelStyle = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );
    final cc = DocuTrackerMemoTemplate.lines(
      memo.cc,
    ).take(DocuTrackerMemoLayout.ccMaxLines).toList(growable: false);
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: DocuTrackerMemoLayout.preparedLabelLeft * width,
            top: DocuTrackerMemoLayout.preparedLabelTop * height,
            child: pw.Text('Prepared by:', style: labelStyle),
          ),
          pw.Positioned(
            left: DocuTrackerMemoLayout.approvedLabelLeft * width,
            top: DocuTrackerMemoLayout.approvedLabelTop * height,
            child: pw.Text('Approved by:', style: labelStyle),
          ),
          pw.Positioned(
            left: DocuTrackerMemoLayout.ccLeft * width,
            top: DocuTrackerMemoLayout.ccTop * height,
            child: pw.SizedBox(
              width: DocuTrackerMemoLayout.ccWidth * width,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 33,
                    child: pw.Text('Cc:', style: labelStyle),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      cc.join('\n'),
                      style: const pw.TextStyle(fontSize: 9.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (release != null)
            placed(DocuTrackerMemoLayout.releaseBlock, releaseBlock(release)),
          placed(DocuTrackerMemoLayout.preparedField, signatory(preparedBy)),
          placed(DocuTrackerMemoLayout.approvedField, signatory(approvedBy)),
          for (final field in otherFields)
            placed(
              Rect.fromLTWH(field.x, field.y, field.width, field.height),
              signature(field),
            ),
        ],
      ),
    );
  }

  final document = pw.Document(
    compress: compress,
    title: memo.subject.trim().isEmpty ? 'Memorandum' : memo.subject.trim(),
  );
  document.addPage(
    pw.MultiPage(
      maxPages: 50,
      pageTheme: pw.PageTheme(
        pageFormat: format,
        theme: theme,
        margin: pw.EdgeInsets.fromLTRB(
          marginX,
          DocuTrackerMemoLayout.headerBottom * height,
          marginX,
          bottomMargin,
        ),
        buildBackground: background,
        buildForeground: closing,
      ),
      header: header,
      build: (_) =>
          _withClosingSpace(docuTrackerMemoBodyWidgets(body), closingReserve),
    ),
  );
  return document.save();
}

/// Longest final paragraph (in characters) that is kept with the closing
/// block; it always fits on one page together with the reserved space.
const int _keepWithClosingMaxChars = 600;

/// Appends the space reserved for the closing block. The final paragraph
/// moves with it, so a page never carries signatures without memo text.
List<pw.Widget> _withClosingSpace(List<pw.Widget> body, double reserve) {
  final space = pw.SizedBox(height: reserve);
  if (body.isEmpty || _plainLength(body.last) > _keepWithClosingMaxChars) {
    return [...body, space];
  }
  return [
    ...body.take(body.length - 1),
    // A horizontal Row never splits across pages, unlike Column/Container.
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [body.last, space],
          ),
        ),
      ],
    ),
  ];
}

int _plainLength(pw.Widget widget) {
  if (widget is! pw.RichText) return 0;
  var length = 0;
  widget.text.visitChildren(
    (span, _, _) {
      if (span is pw.TextSpan) length += span.text?.length ?? 0;
      return true;
    },
    null,
    null,
  );
  return length;
}

/// Converts the Memo body's Quill delta into flowing PDF paragraphs.
/// Supports bold, italic, underline, strike, size, headings, alignment and
/// bullet/numbered lists; embeds are not part of the Memo body.
List<pw.Widget> docuTrackerMemoBodyWidgets(List<Map<String, dynamic>> delta) {
  final widgets = <pw.Widget>[];
  var spans = <pw.InlineSpan>[];
  var ordered = 0;
  var trailingBlankLines = 0;

  void endLine(Map<String, dynamic> lineAttributes) {
    final header = (lineAttributes['header'] as num?)?.toInt();
    final list = lineAttributes['list']?.toString();
    final scale = switch (header) {
      1 => 1.6,
      2 => 1.35,
      3 => 1.15,
      _ => 1.0,
    };
    final align = switch (lineAttributes['align']?.toString()) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      'justify' => pw.TextAlign.justify,
      _ => pw.TextAlign.left,
    };
    ordered = list == 'ordered' ? ordered + 1 : 0;
    final lineSpans = spans;
    spans = <pw.InlineSpan>[];
    final style = pw.TextStyle(
      fontSize: _bodyPointSize * scale,
      lineSpacing: _bodyLineSpacing * scale,
      fontWeight: header == null ? null : pw.FontWeight.bold,
    );
    if (lineSpans.isEmpty && list == null) {
      // A blank paragraph keeps one line of space, as it does in the builder.
      widgets.add(
        pw.SizedBox(
          height: _bodyPointSize * scale * DocuTrackerMemoLayout.bodyLineHeight,
        ),
      );
      trailingBlankLines++;
      return;
    }
    trailingBlankLines = 0;
    if (list == 'bullet' || list == 'ordered') {
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(
            bottom: _points(DocuTrackerMemoLayout.listItemGap),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: _points(DocuTrackerMemoLayout.listIndent),
                alignment: pw.Alignment.topRight,
                padding: pw.EdgeInsets.only(right: _bodyPointSize / 2),
                child: pw.Text(
                  list == 'bullet' ? '•' : '$ordered.',
                  style: style,
                ),
              ),
              pw.Expanded(
                child: pw.RichText(
                  textAlign: align,
                  text: pw.TextSpan(style: style, children: lineSpans),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    widgets.add(
      pw.RichText(
        textAlign: align,
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(style: style, children: lineSpans),
      ),
    );
  }

  pw.TextStyle inline(Map<String, dynamic> attributes) {
    final size = switch (attributes['size']) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value),
      _ => null,
    };
    final decorations = <pw.TextDecoration>[
      if (attributes['underline'] == true) pw.TextDecoration.underline,
      if (attributes['strike'] == true) pw.TextDecoration.lineThrough,
    ];
    return pw.TextStyle(
      // Builder sizes are logical pixels on a 794px-wide A4 page.
      fontSize: size == null ? null : size * PdfPageFormat.a4.width / 794,
      fontWeight: attributes['bold'] == true ? pw.FontWeight.bold : null,
      fontStyle: attributes['italic'] == true ? pw.FontStyle.italic : null,
      decoration: decorations.isEmpty
          ? null
          : pw.TextDecoration.combine(decorations),
    );
  }

  for (final operation in delta) {
    final insert = operation['insert'];
    if (insert is! String) continue;
    final raw = operation['attributes'];
    final attributes = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    final parts = insert.split('\n');
    for (var index = 0; index < parts.length; index++) {
      final text = parts[index];
      if (text.isNotEmpty) {
        spans.add(pw.TextSpan(text: text, style: inline(attributes)));
      }
      if (index < parts.length - 1) endLine(attributes);
    }
  }
  if (spans.isNotEmpty) endLine(const <String, dynamic>{});
  // Trailing blank paragraphs would only push the closing block down.
  return widgets.sublist(0, widgets.length - trailingBlankLines);
}
