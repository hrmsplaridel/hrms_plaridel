/// Result of a biometric logs import operation.
class BiometricImportResult {
  const BiometricImportResult({
    required this.totalParsedRows,
    required this.matchedRowsAttempted,
    required this.inserted,
    required this.duplicatesSkipped,
    required this.unmatchedRows,
    required this.invalidRows,
    required this.summariesInserted,
    required this.summariesUpdated,
  });

  final int totalParsedRows;
  final int matchedRowsAttempted;
  final int inserted;
  final int duplicatesSkipped;
  final int unmatchedRows;
  final int invalidRows;
  final int summariesInserted;
  final int summariesUpdated;

  factory BiometricImportResult.fromJson(Map<String, dynamic> json) {
    return BiometricImportResult(
      totalParsedRows: (json['total_parsed_rows'] as num?)?.toInt() ?? 0,
      matchedRowsAttempted: (json['matched_rows_attempted'] as num?)?.toInt() ?? 0,
      inserted: (json['inserted'] as num?)?.toInt() ?? 0,
      duplicatesSkipped: (json['duplicates_skipped'] as num?)?.toInt() ?? 0,
      unmatchedRows: (json['unmatched_rows'] as num?)?.toInt() ?? 0,
      invalidRows: (json['invalid_rows'] as num?)?.toInt() ?? 0,
      summariesInserted: (json['summaries_inserted'] as num?)?.toInt() ?? 0,
      summariesUpdated: (json['summaries_updated'] as num?)?.toInt() ?? 0,
    );
  }
}
