import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_import_review.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_matched_employee.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/biometric_import_result.dart'
    show BiometricImportRowError;

/// Response from import API.
class BiometricImportApiResponse {
  const BiometricImportApiResponse({
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
    required this.summariesInserted,
    required this.summariesUpdated,
  });

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
  final int summariesInserted;
  final int summariesUpdated;

  factory BiometricImportApiResponse.fromJson(Map<String, dynamic> json) {
    return BiometricImportApiResponse(
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
      summariesInserted: (json['summaries_inserted'] as num?)?.toInt() ?? 0,
      summariesUpdated: (json['summaries_updated'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Repository for biometric import-related API calls.
class BiometricImportRepository {
  const BiometricImportRepository();

  Future<BiometricImportReview> previewImport({
    required List<Map<String, dynamic>> rows,
    required String sourceFileName,
  }) async {
    final response = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/biometric-attendance-logs/import/preview',
      data: {'rows': rows, 'source_file_name': sourceFileName},
    );
    return BiometricImportReview.fromJson(response.data ?? {});
  }

  /// Fetches employees whose [biometric_user_id] matches any of the given IDs.
  Future<List<BiometricMatchedEmployee>> findEmployeesByBiometricIds(
    List<String> biometricUserIds,
  ) async {
    if (biometricUserIds.isEmpty) return [];

    final idsParam = biometricUserIds.join(',');
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/employees',
      queryParameters: {'biometric_user_ids': idsParam},
    );

    final data = res.data ?? [];
    return data
        .map(
          (e) => BiometricMatchedEmployee.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .where((e) => e.biometricUserId.isNotEmpty && e.id.isNotEmpty)
        .toList();
  }

  /// Imports matched biometric logs. Returns inserted and duplicates_skipped counts.
  Future<BiometricImportApiResponse> importBiometricLogs({
    required List<Map<String, dynamic>> rows,
    required String sourceFileName,
    bool warningsReviewed = false,
  }) async {
    if (rows.isEmpty) {
      return const BiometricImportApiResponse(
        inserted: 0,
        duplicatesSkipped: 0,
        skippedUnmatched: 0,
        skippedIdentityMismatch: 0,
        skippedOutsideEmployment: 0,
        skippedNoSchedule: 0,
        skippedHoliday: 0,
        skippedLeave: 0,
        skippedAfterShiftFirstPunch: 0,
        skippedInvalidTimestamp: 0,
        summariesInserted: 0,
        summariesUpdated: 0,
      );
    }

    final res = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/biometric-attendance-logs/import',
      data: {
        'rows': rows,
        'source_file_name': sourceFileName,
        'warnings_reviewed': warningsReviewed,
      },
    );

    final data = res.data ?? {};
    return BiometricImportApiResponse.fromJson(Map<String, dynamic>.from(data));
  }
}
