import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_import_preview.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_parsed_row.dart';
import 'package:hrms_plaridel/features/dtr/attendance/utils/biometric_log_format_detector.dart';

/// Parses supported text exports (.dat, .txt, and .csv).
class BiometricAttendanceLogParser {
  static const Duration _manilaUtcOffset = Duration(hours: 8);
  static const _englishMonths = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  static BiometricImportPreview parse({
    required String content,
    required String fileName,
  }) {
    final format = BiometricLogFormatDetector.detect(content);
    if (format == null) {
      throw const FormatException(
        'Unsupported or binary file. Use a tab-, comma-, or semicolon-separated text export.',
      );
    }

    final parsedRows = <BiometricParsedRow>[];
    final uniqueUserIds = <String>{};
    var total = 0;
    var invalid = 0;
    DateTime? earliest;
    DateTime? latest;

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      total++;
      final cols = BiometricLogFormatDetector.splitRow(line, format.delimiter);
      if (cols.length < 2) {
        invalid++;
        continue;
      }

      final userId = cols[0].trim();
      final timestamp = _tryParseDateTime(cols[1].trim());
      if (userId.isEmpty || timestamp == null) {
        invalid++;
        continue;
      }

      uniqueUserIds.add(userId);
      parsedRows.add(
        BiometricParsedRow(
          biometricUserId: userId,
          loggedAt: timestamp,
          rawLine: rawLine,
          verifyCode: cols.length > 2 ? _emptyToNull(cols[2]) : null,
          punchCode: cols.length > 3 ? _emptyToNull(cols[3]) : null,
          workCode: cols.length > 4 ? _emptyToNull(cols[4]) : null,
        ),
      );
      earliest = earliest == null || timestamp.isBefore(earliest)
          ? timestamp
          : earliest;
      latest = latest == null || timestamp.isAfter(latest) ? timestamp : latest;
    }

    return BiometricImportPreview(
      fileName: fileName,
      detectedFormat: format.label,
      totalNonEmptyRows: total,
      validParsedRows: parsedRows.length,
      invalidRows: invalid,
      uniqueBiometricUserIds: uniqueUserIds.length,
      uniqueBiometricUserIdList: uniqueUserIds.toList()..sort(),
      parsedRows: parsedRows,
      earliestTimestamp: earliest,
      latestTimestamp: latest,
    );
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _tryParseDateTime(String input) {
    final namedDate = RegExp(
      r'^(\d{1,2})\s+([a-z]+)\s+(\d{4})\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (namedDate != null) {
      final name = namedDate.group(2)!.toLowerCase();
      final monthIndex = _englishMonths.indexWhere(
        (month) => month == name || month.substring(0, 3) == name,
      );
      if (monthIndex == -1) return null;
      // Reuse strict calendar/time validation and the Manila-to-UTC conversion.
      // Invalid named dates must not fall through to permissive date parsing.
      return _parseManilaLocalTimestamp(
        '${namedDate.group(3)}-${monthIndex + 1}-${namedDate.group(1)} '
        '${namedDate.group(4)}',
      );
    }
    final local = _parseManilaLocalTimestamp(input);
    if (local != null) return local;
    return DateTime.tryParse(input)?.toUtc();
  }

  static DateTime? _parseManilaLocalTimestamp(String input) {
    if (RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(input)) {
      return null;
    }
    final match = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T]+'
      r'(\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,6}))?)?'
      r'(?:\s*(AM|PM))?$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (match == null) return null;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    var hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6) ?? '0');
    final fraction = (match.group(7) ?? '').padRight(3, '0');
    final millisecond = int.tryParse(
      fraction.isEmpty ? '0' : fraction.substring(0, 3),
    );
    final meridiem = match.group(8)?.toUpperCase();
    if ([year, month, day, hour, minute, second, millisecond].contains(null)) {
      return null;
    }

    if (meridiem != null) {
      if (hour! < 1 || hour > 12) return null;
      if (meridiem == 'PM' && hour < 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;
    }
    final candidate = DateTime.utc(
      year!,
      month!,
      day!,
      hour!,
      minute!,
      second!,
      millisecond!,
    );
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day ||
        candidate.hour != hour ||
        candidate.minute != minute ||
        candidate.second != second) {
      return null;
    }
    return candidate.subtract(_manilaUtcOffset);
  }
}
