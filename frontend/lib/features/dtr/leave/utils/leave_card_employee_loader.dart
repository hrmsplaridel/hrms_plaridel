import 'package:hrms_plaridel/core/api/client.dart';

Future<List<Map<String, dynamic>>> loadLeaveCardEmployees() async {
  final rows = <Map<String, dynamic>>[];
  while (true) {
    final response = await ApiClient.instance.get<dynamic>(
      '/api/employees',
      queryParameters: {
        'status': 'Active',
        'leave_card': 'true',
        'limit': 100,
        'offset': rows.length,
      },
    );
    final payload = response.data;
    final batch = payload is Map
        ? (payload['employees'] as List? ?? const [])
        : (payload is List ? payload : const []);
    rows.addAll(batch.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    final total = payload is Map ? payload['total'] as num? : null;
    if (batch.isEmpty || total == null || rows.length >= total) break;
  }
  return rows;
}
