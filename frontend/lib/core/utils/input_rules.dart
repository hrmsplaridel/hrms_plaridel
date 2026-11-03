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

  /// Score / points: digits and one decimal separator.
  static final RegExp decimalScoreChar = RegExp(r'[0-9.,]');

  static const int emailMaxLength = 254;
  static const int phoneMinDigits = 10;
  static const int phoneMaxDigits = 15;
  static const int personNameMaxLength = 80;

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

  static List<TextInputFormatter> get personNameFormatters => [
        FilteringTextInputFormatter.allow(personNameChar),
        LengthLimitingTextInputFormatter(personNameMaxLength),
      ];

  static List<TextInputFormatter> get digitsOnlyFormatters => [
        FilteringTextInputFormatter.digitsOnly,
      ];

  /// Phone: digits and common phone punctuation (+, spaces, dashes, parentheses).
  static List<TextInputFormatter> get phoneFormatters => [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
        LengthLimitingTextInputFormatter(20),
      ];

  static List<TextInputFormatter> get decimalScoreFormatters => [
        FilteringTextInputFormatter.allow(decimalScoreChar),
      ];

  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static bool isValidPersonName(String? raw, {bool required = true}) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return !required;
    if (t.length > personNameMaxLength) return false;
    return personNameFull.hasMatch(t);
  }

  static String? personNameError(String? raw, {String label = 'Name', bool required = true}) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
      return required ? '$label is required.' : null;
    }
    if (!personNameFull.hasMatch(t)) {
      return '$label may only contain letters, spaces, hyphens, apostrophes, and periods.';
    }
    return null;
  }

  static bool isValidEmail(String? raw) {
    final e = (raw ?? '').trim();
    if (e.isEmpty || e.length > emailMaxLength) return false;
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
