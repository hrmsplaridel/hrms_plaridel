import 'package:hrms_plaridel/core/api/client.dart';

Future<List<Map<String, dynamic>>> loadLeaveAdjustmentEmployees() async {
  final rows = <Map<String, dynamic>>[];
  var offset = 0;
  while (true) {
    final response = await ApiClient.instance.get<dynamic>(
      '/api/employees',
      queryParameters: {
        'status': 'Active',
        'credit_adjustment': 'true',
        'limit': 100,
        'offset': offset,
      },
    );
    final payload = response.data;
    final batch = payload is Map
        ? (payload['employees'] as List? ?? const [])
        : (payload is List ? payload : const []);
    rows.addAll(
      batch
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (e) =>
                e['leave_credit_eligible'] != false &&
                !['job_order', 'contract_of_service'].contains(
                  e['employment_type']?.toString().trim().toLowerCase(),
                ),
          ),
    );
    offset += batch.length;
    final total = payload is Map ? payload['total'] as num? : null;
    if (batch.isEmpty || total == null || offset >= total) break;
  }
  return rows;
}
