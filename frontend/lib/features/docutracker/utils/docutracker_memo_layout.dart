import 'dart:ui' show Color, Rect;

/// Fixed geometry of the official Municipality of Plaridel Memorandum, as
/// fractions of an A4 page. Shared by the builder sheet and the vector PDF so
/// both place the letterhead, closing block and signatures identically.
///
/// Letterhead artwork matches the official A4 form / locator-slip print
/// background (`assets/forms/a4_letter.pdf`).
abstract final class DocuTrackerMemoLayout {
  /// Raster of [letterheadSourcePdf] for the builder sheet and Memo PDF.
  static const String letterheadAsset =
      'assets/images/memo_official_letterhead.png';

  /// Source PDF used by forms, BI, and locator-style official prints.
  static const String letterheadSourcePdf = 'assets/forms/a4_letter.pdf';

  /// Legacy seal path kept for older references; letterhead image replaces it.
  static const String sealAsset = 'assets/images/PlaridelLogo.jpg';

  static const String republic = 'Republic of the Philippines';
  static const String province = 'PROVINCE OF MISAMIS OCCIDENTAL';
  static const String municipality = 'MUNICIPALITY OF PLARIDEL';
  static const String office =
      'Human Resource Management and Development Office';
  static const String title = 'MEMORANDUM';

  static const Color municipalityRed = Color(0xFFC62828);
  static const Color navy = Color(0xFF1F2A5A);

  /// Typography shared by the builder (logical pixels on the
  /// [pageWidthPx]-wide page) and the PDF (points, via [pointsPerPixel]).
  /// Both render the bundled Noto Sans so lines wrap at the same words.
  static const String fontFamily = 'NotoSans';
  static const double pageWidthPx = 794;
  static const double pointsPerPixel = 595.28 / pageWidthPx;
  static const double bodyFontSize = 16;
  static const double bodyLineHeight = 1.5;
  static const double listItemGap = 3;

  /// Quill's list indent: the marker column is twice the body font size.
  static const double listIndent = 2 * bodyFontSize;
  static const double metadataFontSize = 16;
  static const int toMaxLines = 6;
  static const int subjectMaxLines = 5;
  static const double metadataLabelWidth = 96;
  static const double metadataColonWidth = 28;
  static const double metadataRowGap = 6;

  /// Left/right text margin.
  static const double marginX = 0.11;

  /// Official letterhead header ends (~19%) and footer art begins (~75%).
  static const double letterheadHeaderBottom = 0.205;
  static const double letterheadFooterTop = 0.745;

  /// Repeated letterhead ends here; continuation-page body starts below it.
  static const double headerBottom = letterheadHeaderBottom;
  static const double titleTop = 0.215;
  static const double metadataTop = 0.262;

  /// Closing block (Prepared by, Noted by, release, Approved by, CC) on the
  /// last page. Kept above [letterheadFooterTop] so it never covers footer
  /// artwork.
  static const double closingTop = 0.50;
  static const double preparedLabelLeft = 0.11;
  static const double preparedLabelTop = 0.51;

  /// Fixed signatory blocks: signature area, signature line, printed name,
  /// position. Memo slots always render here, whatever geometry is stored.
  static const Rect preparedField = Rect.fromLTWH(0.13, 0.523, 0.3, 0.085);

  /// Department head, the person the workflow sends the memo to. Sits beside
  /// Prepared by. The release stamp stays above this block.
  static const double notedLabelLeft = 0.56;
  static const double notedLabelTop = 0.51;
  static const Rect notedField = Rect.fromLTWH(0.56, 0.523, 0.32, 0.085);
  static const Rect releaseBlock = Rect.fromLTWH(0.56, 0.40, 0.33, 0.10);
  static const double approvedLabelLeft = 0.43;
  static const double approvedLabelTop = 0.615;
  static const Rect approvedField = Rect.fromLTWH(0.5, 0.628, 0.38, 0.085);
  static const double signatoryNameFontSize = 13.5;
  static const double signatoryPositionFontSize = 12.5;
  static const double ccLeft = 0.11;
  static const double ccTop = 0.70;

  /// Ends before [approvedField] so a long Cc line never runs under it.
  static const double ccWidth = 0.38;
  static const int ccMaxLines = 4;

  /// Content must stop before letterhead footer art (used for PDF margins).
  static const Rect footerStrip = Rect.fromLTWH(
    0.0,
    letterheadFooterTop,
    1.0,
    1.0 - letterheadFooterTop,
  );

  static const String preparedFieldLabel = 'Prepared by';
  static const String notedFieldLabel = 'Noted by';
  static const String approvedFieldLabel = 'Approved by';
}
