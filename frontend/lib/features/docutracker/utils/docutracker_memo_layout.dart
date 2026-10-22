import 'dart:ui' show Color, Rect;

/// Fixed geometry of the official Municipality of Plaridel Memorandum, as
/// fractions of an A4 page. Shared by the builder sheet and the vector PDF so
/// both place the letterhead, closing block and signatures identically.
abstract final class DocuTrackerMemoLayout {
  static const String sealAsset = 'assets/images/Plaridel Logo.jpg';

  /// Official artwork not yet in the project. Their slots stay blank until the
  /// files are added at these paths (no code change needed).
  static const String asensoLogoAsset =
      'assets/images/memo_asenso_plaridel.png';
  static const String bagongPilipinasLogoAsset =
      'assets/images/memo_bagong_pilipinas.png';
  static const String footerStripAsset = 'assets/images/memo_footer_strip.png';

  static const String republic = 'Republic of the Philippines';
  static const String province = 'PROVINCE OF MISAMIS OCCIDENTAL';
  static const String municipality = 'MUNICIPALITY OF PLARIDEL';
  static const String office =
      'Human Resource Management and Development Office';
  static const String title = 'MEMORANDUM';
  static const String slogan =
      'Misamisnon Magpuyong Malinawon, Malambuon ug Malipayon';

  static const Color municipalityRed = Color(0xFFC62828);
  static const Color navy = Color(0xFF1F2A5A);
  static const Color peach = Color(0xFFF6C7A6);
  static const Color sloganBand = Color(0xFFE4572E);
  static const Color reservedArtwork = Color(0xFFFDF2EA);

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

  // Everything printed stays at least 10 mm (0.034 of the height, 0.048 of
  // the width) inside the sheet so office printers never clip it.
  static const Rect seal = Rect.fromLTWH(0.075, 0.034, 0.1, 0.0707);
  static const double headingLeft = 0.19;
  static const double headingTop = 0.036;
  static const Rect asensoLogo = Rect.fromLTWH(0.72, 0.034, 0.085, 0.06);
  static const Rect bagongPilipinasLogo = Rect.fromLTWH(
    0.815,
    0.034,
    0.1,
    0.06,
  );
  static const Rect peachBand = Rect.fromLTWH(0.09, 0.116, 0.82, 0.036);

  /// Repeated letterhead ends here; continuation-page body starts below it.
  static const double headerBottom = 0.155;
  static const double titleTop = 0.165;
  static const double metadataTop = 0.212;

  /// Closing block (Prepared by, release, Approved by, CC) on the last page.
  static const double closingTop = 0.575;
  static const double preparedLabelLeft = 0.11;
  static const double preparedLabelTop = 0.585;

  /// Fixed signatory blocks: signature area, signature line, printed name,
  /// position. Memo slots always render here, whatever geometry is stored.
  static const Rect preparedField = Rect.fromLTWH(0.13, 0.598, 0.3, 0.092);
  static const Rect releaseBlock = Rect.fromLTWH(0.56, 0.585, 0.33, 0.108);
  static const double approvedLabelLeft = 0.43;
  static const double approvedLabelTop = 0.695;
  static const Rect approvedField = Rect.fromLTWH(0.5, 0.708, 0.38, 0.09);
  static const double signatoryNameFontSize = 13.5;
  static const double signatoryPositionFontSize = 12.5;
  static const double ccLeft = 0.11;
  static const double ccTop = 0.8;

  /// Ends before [approvedField] so a long Cc line never runs under it.
  static const double ccWidth = 0.38;
  static const int ccMaxLines = 4;

  /// Decorative footer strip and slogan band, repeated on every page.
  static const Rect footerStrip = Rect.fromLTWH(0.048, 0.872, 0.904, 0.068);
  static const Rect sloganBar = Rect.fromLTWH(0.048, 0.94, 0.904, 0.026);

  static const String preparedFieldLabel = 'Prepared by';
  static const String approvedFieldLabel = 'Approved by';
}
