import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/models/biometric_attendance_log.dart';

class BiometricAttendanceLogRepository {
  const BiometricAttendanceLogRepository();

  Future<BiometricAttendanceLogPage> list({
    required int limit,
    required int offset,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final response = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/biometric-attendance-logs',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (dateFrom != null) 'date_from': dateOnly(dateFrom),
        if (dateTo != null) 'date_to': dateOnly(dateTo),
      },
    );
    return BiometricAttendanceLogPage.fromJson(response.data ?? const {});
  }
}
