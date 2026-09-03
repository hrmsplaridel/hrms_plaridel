import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_import_preview.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_parsed_row.dart';

/// Parses a biometric `.dat` export file into a preview summary and parsed rows.
///
/// Parsing rules:
/// - Split rows by newline.
/// - Ignore empty/whitespace-only lines.
/// - Split columns by tab.
/// - Require at least 2 columns: col1=biometric_user_id, col2=timestamp.
/// - Optional cols 3,4,5 = verify_code, punch_code, work_code.
/// - If timestamp cannot be parsed, the row is counted as invalid/skipped.
/// - Timestamps without an explicit timezone are treated as Asia/Manila local time.
class BiometricDatParser {
  static const Duration _manilaUtcOffset = Duration(hours: 8);

  static BiometricImportPreview parse({
    required String content,
    required String fileName,
  }) {
    final lines = content.split(RegExp(r'\r?\n'));

    int totalNonEmptyRows = 0;
    int validParsedRows = 0;
    int invalidRows = 0;
    final uniqueUserIds = <String>{};
    final parsedRows = <BiometricParsedRow>[];

    DateTime? earliest;
    DateTime? latest;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      totalNonEmptyRows++;

      final cols = line.split('\t');
      if (cols.length < 2) {
        invalidRows++;
        continue;
      }

      final biometricUserId = cols[0].trim();
      final tsString = cols[1].trim();

      if (biometricUserId.isEmpty || tsString.isEmpty) {
        invalidRows++;
        continue;
      }

      final parsedTs = _tryParseDateTime(tsString);
      if (parsedTs == null) {
        invalidRows++;
        continue;
      }

      validParsedRows++;
      uniqueUserIds.add(biometricUserId);
      parsedRows.add(
        BiometricParsedRow(
          biometricUserId: biometricUserId,
          loggedAt: parsedTs,
          rawLine: rawLine,
          verifyCode: cols.length > 2 ? _emptyToNull(cols[2]) : null,
          punchCode: cols.length > 3 ? _emptyToNull(cols[3]) : null,
          workCode: cols.length > 4 ? _emptyToNull(cols[4]) : null,
        ),
      );

      earliest = earliest == null
          ? parsedTs
          : parsedTs.isBefore(earliest)
          ? parsedTs
          : earliest;
      latest = latest == null
          ? parsedTs
          : parsedTs.isAfter(latest)
          ? parsedTs
          : latest;
    }

    return BiometricImportPreview(
      fileName: fileName,
      detectedFormat: 'Tab-separated',
      totalNonEmptyRows: totalNonEmptyRows,
      validParsedRows: validParsedRows,
      invalidRows: invalidRows,
      uniqueBiometricUserIds: uniqueUserIds.length,
      uniqueBiometricUserIdList: uniqueUserIds.toList()..sort(),
      parsedRows: parsedRows,
      earliestTimestamp: earliest,
      latestTimestamp: latest,
    );
  }

  static String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static DateTime? _tryParseDateTime(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) return null;

    final manilaLocal = _parseManilaLocalTimestamp(normalized);
    if (manilaLocal != null) return manilaLocal;

    final direct = DateTime.tryParse(normalized);
    if (direct != null) return direct.toUtc();

    return null;
  }

  static DateTime? _parseManilaLocalTimestamp(String input) {
    if (_hasExplicitTimezone(input)) return null;

    final match = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T]+'
      r'(\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,6}))?)?'
      r'(?:\s*(AM|PM))?$',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    var hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6) ?? '0');
    final millis = _parseFractionalMilliseconds(match.group(7));
    final meridiem = match.group(8)?.toUpperCase();

    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null ||
        millis == null) {
      return null;
    }

    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (meridiem == 'PM' && hour < 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;
    }

    if (!_isValidDateTimePart(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      millisecond: millis,
    )) {
      return null;
    }

    return DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millis,
    ).subtract(_manilaUtcOffset);
  }

  static bool _hasExplicitTimezone(String input) {
    return RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(input.trim());
  }

  static int? _parseFractionalMilliseconds(String? value) {
    if (value == null || value.isEmpty) return 0;
    final normalized = value.padRight(3, '0').substring(0, 3);
    return int.tryParse(normalized);
  }

  static bool _isValidDateTimePart({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int second,
    required int millisecond,
  }) {
    if (year < 1900 || year > 9999) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > _daysInMonth(year, month)) return false;
    if (hour < 0 || hour > 23) return false;
    if (minute < 0 || minute > 59) return false;
    if (second < 0 || second > 59) return false;
    if (millisecond < 0 || millisecond > 999) return false;
    return true;
  }

  static int _daysInMonth(int year, int month) {
    if (month == 2) return _isLeapYear(year) ? 29 : 28;
    const thirtyDayMonths = {4, 6, 9, 11};
    return thirtyDayMonths.contains(month) ? 30 : 31;
  }

  static bool _isLeapYear(int year) {
    if (year % 400 == 0) return true;
    if (year % 100 == 0) return false;
    return year % 4 == 0;
  }
}
