import '../../api/client.dart';
import '../models/biometric_matched_employee.dart';

/// Response from import API.
class BiometricImportApiResponse {
  const BiometricImportApiResponse({
    required this.inserted,
    required this.duplicatesSkipped,
    required this.summariesInserted,
    required this.summariesUpdated,
  });

  final int inserted;
  final int duplicatesSkipped;
  final int summariesInserted;
  final int summariesUpdated;

  factory BiometricImportApiResponse.fromJson(Map<String, dynamic> json) {
    return BiometricImportApiResponse(
      inserted: (json['inserted'] as num?)?.toInt() ?? 0,
      duplicatesSkipped: (json['duplicates_skipped'] as num?)?.toInt() ?? 0,
      summariesInserted: (json['summaries_inserted'] as num?)?.toInt() ?? 0,
      summariesUpdated: (json['summaries_updated'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Repository for biometric import-related API calls.
class BiometricImportRepository {
  const BiometricImportRepository();

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
        .map((e) => BiometricMatchedEmployee.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .where((e) => e.biometricUserId.isNotEmpty && e.id.isNotEmpty)
        .toList();
  }

  /// Imports matched biometric logs. Returns inserted and duplicates_skipped counts.
  Future<BiometricImportApiResponse> importBiometricLogs({
    required List<Map<String, dynamic>> rows,
    required String sourceFileName,
  }) async {
    if (rows.isEmpty) {
      return const BiometricImportApiResponse(
        inserted: 0,
        duplicatesSkipped: 0,
        summariesInserted: 0,
        summariesUpdated: 0,
      );
    }

    final res = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/biometric-attendance-logs/import',
      data: {
        'rows': rows,
        'source_file_name': sourceFileName,
      },
    );

    final data = res.data ?? {};
    return BiometricImportApiResponse.fromJson(
      Map<String, dynamic>.from(data),
    );
  }
}
