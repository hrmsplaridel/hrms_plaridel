/// A rejected entry's position in the submitted batch, rather than the source file.
class BiometricImportRowError {
  const BiometricImportRowError({required this.row, required this.error});

  final int row;
  final String error;

  factory BiometricImportRowError.fromJson(Map<String, dynamic> json) {
    return BiometricImportRowError(
      row: (json['row'] as num?)?.toInt() ?? 0,
      error: json['error'] as String? ?? 'Invalid log entry',
    );
  }
}

/// Result of a biometric logs import operation.
class BiometricImportResult {
  const BiometricImportResult({
    required this.totalParsedRows,
    required this.matchedRowsAttempted,
    required this.inserted,
    required this.duplicatesSkipped,
    required this.skippedUnmatched,
    required this.skippedIdentityMismatch,
    required this.skippedOutsideEmployment,
    required this.skippedNoSchedule,
    required this.skippedHoliday,
    required this.skippedLeave,
    required this.skippedAfterShiftFirstPunch,
    required this.skippedInvalidTimestamp,
    this.skippedInvalidRows = 0,
    this.rowErrors = const [],
    this.rowsExcluded = 0,
    required this.unmatchedRows,
    required this.invalidRows,
    required this.summariesInserted,
    required this.summariesUpdated,
  });

  final int totalParsedRows;
  final int matchedRowsAttempted;
  final int inserted;
  final int duplicatesSkipped;
  final int skippedUnmatched;
  final int skippedIdentityMismatch;
  final int skippedOutsideEmployment;
  final int skippedNoSchedule;
  final int skippedHoliday;
  final int skippedLeave;
  final int skippedAfterShiftFirstPunch;
  final int skippedInvalidTimestamp;
  final int skippedInvalidRows;
  final List<BiometricImportRowError> rowErrors;
  final int rowsExcluded;
  final int unmatchedRows;
  final int invalidRows;
  final int summariesInserted;
  final int summariesUpdated;

  factory BiometricImportResult.fromJson(Map<String, dynamic> json) {
    return BiometricImportResult(
      totalParsedRows: (json['total_parsed_rows'] as num?)?.toInt() ?? 0,
      matchedRowsAttempted:
          (json['matched_rows_attempted'] as num?)?.toInt() ?? 0,
      inserted: (json['inserted'] as num?)?.toInt() ?? 0,
      duplicatesSkipped: (json['duplicates_skipped'] as num?)?.toInt() ?? 0,
      skippedUnmatched: (json['skipped_unmatched'] as num?)?.toInt() ?? 0,
      skippedIdentityMismatch:
          (json['skipped_identity_mismatch'] as num?)?.toInt() ?? 0,
      skippedOutsideEmployment:
          (json['skipped_outside_employment'] as num?)?.toInt() ?? 0,
      skippedNoSchedule: (json['skipped_no_schedule'] as num?)?.toInt() ?? 0,
      skippedHoliday: (json['skipped_holiday'] as num?)?.toInt() ?? 0,
      skippedLeave: (json['skipped_leave'] as num?)?.toInt() ?? 0,
      skippedAfterShiftFirstPunch:
          (json['skipped_after_shift_first_punch'] as num?)?.toInt() ?? 0,
      skippedInvalidTimestamp:
          (json['skipped_invalid_timestamp'] as num?)?.toInt() ?? 0,
      skippedInvalidRows: (json['skipped_invalid_row'] as num?)?.toInt() ?? 0,
      rowsExcluded: (json['rows_excluded'] as num?)?.toInt() ?? 0,
      rowErrors: (json['row_errors'] as List? ?? [])
          .map(
            (entry) => BiometricImportRowError.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
      unmatchedRows: (json['unmatched_rows'] as num?)?.toInt() ?? 0,
      invalidRows: (json['invalid_rows'] as num?)?.toInt() ?? 0,
      summariesInserted: (json['summaries_inserted'] as num?)?.toInt() ?? 0,
      summariesUpdated: (json['summaries_updated'] as num?)?.toInt() ?? 0,
    );
  }
}
