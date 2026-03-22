import 'biometric_parsed_row.dart';

class BiometricImportPreview {
  const BiometricImportPreview({
    required this.fileName,
    required this.totalNonEmptyRows,
    required this.validParsedRows,
    required this.invalidRows,
    required this.uniqueBiometricUserIds,
    required this.uniqueBiometricUserIdList,
    required this.parsedRows,
    required this.earliestTimestamp,
    required this.latestTimestamp,
  });

  final String fileName;

  /// Count of all non-empty lines in the file.
  final int totalNonEmptyRows;

  /// Rows that contained at least 2 tab-separated columns and a valid timestamp.
  final int validParsedRows;

  /// Rows skipped due to missing columns, empty columns, or invalid timestamps.
  final int invalidRows;

  /// Unique biometric user ids extracted from valid rows.
  final int uniqueBiometricUserIds;

  /// List of unique biometric user ids for matching against users table.
  final List<String> uniqueBiometricUserIdList;

  /// Parsed rows for import (biometric_user_id, logged_at, raw_line, etc.).
  final List<BiometricParsedRow> parsedRows;

  final DateTime? earliestTimestamp;
  final DateTime? latestTimestamp;
}
