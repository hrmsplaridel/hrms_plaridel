import '../models/biometric_import_preview.dart';
import '../models/biometric_parsed_row.dart';

/// Parses a biometric `.dat` export file into a preview summary and parsed rows.
///
/// Parsing rules:
/// - Split rows by newline.
/// - Ignore empty/whitespace-only lines.
/// - Split columns by tab.
/// - Require at least 2 columns: col1=biometric_user_id, col2=timestamp.
/// - Optional cols 3,4,5 = verify_code, punch_code, work_code.
/// - If timestamp cannot be parsed, the row is counted as invalid/skipped.
class BiometricDatParser {
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
      parsedRows.add(BiometricParsedRow(
        biometricUserId: biometricUserId,
        loggedAt: parsedTs,
        rawLine: rawLine,
        verifyCode: cols.length > 2 ? _emptyToNull(cols[2]) : null,
        punchCode: cols.length > 3 ? _emptyToNull(cols[3]) : null,
        workCode: cols.length > 4 ? _emptyToNull(cols[4]) : null,
      ));

      earliest = earliest == null ? parsedTs : parsedTs.isBefore(earliest) ? parsedTs : earliest;
      latest = latest == null ? parsedTs : parsedTs.isAfter(latest) ? parsedTs : latest;
    }

    return BiometricImportPreview(
      fileName: fileName,
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
    // Primary: ISO8601 and other formats supported by DateTime.tryParse.
    final direct = DateTime.tryParse(input);
    if (direct != null) return direct;

    // Fallback: common "YYYY-MM-DD HH:mm:ss" variant.
    if (!input.contains('T') && input.contains(' ')) {
      return DateTime.tryParse(input.replaceFirst(' ', 'T'));
    }

    return null;
  }
}

