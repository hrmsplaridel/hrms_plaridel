import 'package:flutter/services.dart';

/// Shared typing + validation rules for Landing / RSP / L&D scoped forms.
class InputRules {
  InputRules._();

  /// Letters, Filipino Ñ/ñ, spaces, hyphen, apostrophe, and `.` (Jr./Sr.).
  static final RegExp personNameChar = RegExp(r"[A-Za-zÑñ\s\-'.]");
  static final RegExp personNameFull =
      RegExp(r"^[A-Za-zÑñ]+(?:[ \-'.][A-Za-zÑñ]+)*\.?$");

  static final RegExp emailFull = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  /// Email local/domain typing (no spaces, no emoji).
  static final RegExp emailChar = RegExp(r'[A-Za-z0-9._%+\-@]');

  /// Score / points: digits and one decimal separator.
  static final RegExp decimalScoreChar = RegExp(r'[0-9.,]');

  /// Business / form prose: Latin + Ñ/ñ, digits, whitespace, common punctuation.
  /// Blocks emoji and other pictographs by allow-list.
  static final RegExp plainTextChar = RegExp(
    r"""[A-Za-zÑñ0-9\s\-.,;:!?'"()\[\]{}/\\@#%&+*=_]""",
  );

  /// Emoji / pictographs / joiner / skin-tone modifiers (deny list).
  /// Explicit ranges (avoid `\p{...}` so analyzer `valid_regexps` stays clean).
  static final RegExp forbiddenGlyphs = RegExp(
    '[\\u{1F300}-\\u{1FAFF}' // misc symbols & pictographs, supplemental
    '\\u{1F1E0}-\\u{1F1FF}' // flags
    '\\u{1F600}-\\u{1F64F}' // emoticons
    '\\u{1F680}-\\u{1F6FF}' // transport
    '\\u{1F900}-\\u{1F9FF}' // supplemental symbols
    '\\u{2600}-\\u{27BF}' // misc symbols / dingbats
    '\\u{2300}-\\u{23FF}' // misc technical (some emoji)
    '\\u{2B50}\\u{2B55}' // star / circle
    '\\u{FE0F}\\u{200D}\\u{20E3}' // VS16, ZWJ, keycap
    '\\u{1F3FB}-\\u{1F3FF}' // skin tones
    '\\u{1F9B0}-\\u{1F9B3}' // hair components
    ']'
    '|[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F]',
    unicode: true,
  );

  static const int emailMaxLength = 254;
  static const int phoneMinDigits = 10;
  static const int phoneMaxDigits = 15;
  static const int personNameMaxLength = 80;
  static const int plainTextDefaultMaxLength = 2000;

  static const int trainingDailyTitleMax = 200;
  static const int trainingDailyDescriptionMax = 4000;
  static const int trainingRequirementTitleMax = 300;

  static const int rspApplicationPdfMaxBytes = 15 * 1024 * 1024;
  static const int trainingDailyAttachmentMaxBytes = 10 * 1024 * 1024;
  static const int trainingRequirementPdfMaxBytes = 15 * 1024 * 1024;

  static const List<String> sexAllowlist = ['Male', 'Female'];
  static const List<String> civilStatusAllowlist = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Legally Separated',
    'Annulled',
    'Divorced',
    'Live-in / Common-law',
  ];

  /// Always strip emoji / control glyphs first, then apply [extra].
  static List<TextInputFormatter> withNoEmoji([
    List<TextInputFormatter> extra = const [],
  ]) =>
      [
        FilteringTextInputFormatter.deny(forbiddenGlyphs),
        ...extra,
      ];

  static List<TextInputFormatter> get noEmojiFormatters => withNoEmoji();

  /// General free-text fields (titles, addresses, notes, course, etc.).
  static List<TextInputFormatter> plainTextFormatters({
    int maxLength = plainTextDefaultMaxLength,
    bool allowNewlines = true,
  }) {
    final allowed = allowNewlines
        ? plainTextChar
        : RegExp(r"""[A-Za-zÑñ0-9 \t\-.,;:!?'"()\[\]{}/\\@#%&+*=_]""");
    return withNoEmoji([
      FilteringTextInputFormatter.allow(allowed),
      LengthLimitingTextInputFormatter(maxLength),
    ]);
  }

  static List<TextInputFormatter> get personNameFormatters => withNoEmoji([
        FilteringTextInputFormatter.allow(personNameChar),
        LengthLimitingTextInputFormatter(personNameMaxLength),
      ]);

  static List<TextInputFormatter> get digitsOnlyFormatters => withNoEmoji([
        FilteringTextInputFormatter.digitsOnly,
      ]);

  /// Phone: digits and common phone punctuation (+, spaces, dashes, parentheses).
  static List<TextInputFormatter> get phoneFormatters => withNoEmoji([
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
        LengthLimitingTextInputFormatter(20),
      ]);

  static List<TextInputFormatter> get decimalScoreFormatters => withNoEmoji([
        FilteringTextInputFormatter.allow(decimalScoreChar),
      ]);

  static List<TextInputFormatter> get emailFormatters => withNoEmoji([
        FilteringTextInputFormatter.allow(emailChar),
        LengthLimitingTextInputFormatter(emailMaxLength),
      ]);

  /// Use field-specific formatters when provided; otherwise plain text (no emoji).
  static List<TextInputFormatter> merge(
    List<TextInputFormatter>? existing, {
    List<TextInputFormatter>? fallback,
  }) {
    if (existing != null && existing.isNotEmpty) return existing;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return plainTextFormatters();
  }

  static bool isValidPlainText(String raw) {
    if (raw.isEmpty) return true;
    if (containsForbiddenGlyphs(raw)) return false;
    for (final r in raw.runes) {
      if (!plainTextChar.hasMatch(String.fromCharCode(r))) return false;
    }
    return true;
  }

  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static String stripForbiddenGlyphs(String raw) =>
      raw.replaceAll(forbiddenGlyphs, '');

  static bool containsForbiddenGlyphs(String? raw) {
    final t = raw ?? '';
    if (t.isEmpty) return false;
    return forbiddenGlyphs.hasMatch(t);
  }

  static bool isValidPersonName(String? raw, {bool required = true}) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return !required;
    if (t.length > personNameMaxLength) return false;
    if (containsForbiddenGlyphs(t)) return false;
    return personNameFull.hasMatch(t);
  }

  static String? personNameError(
    String? raw, {
    String label = 'Name',
    bool required = true,
  }) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
      return required ? '$label is required.' : null;
    }
    if (containsForbiddenGlyphs(t) || !personNameFull.hasMatch(t)) {
      return '$label may only contain letters, spaces, hyphens, apostrophes, and periods.';
    }
    return null;
  }

  static String? plainTextError(
    String? raw, {
    String label = 'This field',
    bool required = false,
    int maxLength = plainTextDefaultMaxLength,
  }) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
      return required ? '$label is required.' : null;
    }
    if (t.length > maxLength) {
      return '$label must be at most $maxLength characters.';
    }
    if (!isValidPlainText(t)) {
      return '$label cannot contain emoji or special symbols.';
    }
    return null;
  }

  static bool isValidEmail(String? raw) {
    final e = (raw ?? '').trim();
    if (e.isEmpty || e.length > emailMaxLength) return false;
    if (containsForbiddenGlyphs(e)) return false;
    return emailFull.hasMatch(e);
  }

  static bool isValidPhone(String? raw) {
    final d = digitsOnly(raw ?? '');
    return d.length >= phoneMinDigits && d.length <= phoneMaxDigits;
  }

  static bool isWholeNumber(String? raw, {bool allowEmpty = false}) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return allowEmpty;
    return RegExp(r'^\d+$').hasMatch(t);
  }

  /// Parses a score; returns null if invalid / out of range.
  static double? parseScore0to100(String? raw) {
    final t = (raw ?? '').trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0 || v > 100) return null;
    return v;
  }

  static String formatBytesLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  static bool isWithinMaxBytes(int size, int maxBytes) =>
      size >= 0 && size <= maxBytes;
}
