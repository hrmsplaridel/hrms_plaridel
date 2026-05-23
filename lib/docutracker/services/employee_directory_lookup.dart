import 'package:dio/dio.dart';

import '../../api/client.dart';

/// Cached name + department for user ids (from [GET /api/employees] list rows).
class EmployeeDirectoryEntry {
  const EmployeeDirectoryEntry({
    required this.id,
    required this.fullName,
    this.departmentName,
    this.positionName,
  });

  final String id;
  final String fullName;
  final String? departmentName;
  final String? positionName;

  /// "Full Name · Department" (department omitted if unknown).
  String get nameAndDepartment {
    final d = departmentName?.trim();
    if (d == null || d.isEmpty) return fullName;
    return '$fullName · $d';
  }
}

/// Loads active employees once and resolves [user id → display line] for admin UIs.
class EmployeeDirectoryLookup {
  final Map<String, EmployeeDirectoryEntry> _byId = {};

  bool isLoaded = false;

  EmployeeDirectoryEntry? operator [](String id) => _byId[id];

  /// One batched request (paged). Safe for typical org sizes; extend with backend `ids=` if needed.
  Future<void> load({int limit = 4000}) async {
    try {
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: <String, dynamic>{
          'status': 'Active',
          'role': 'All',
          'limit': limit,
          'offset': 0,
          'sort': 'full_name',
          'order': 'asc',
        },
      );
      final data = res.data;
      List<dynamic> list;
      if (data is Map && data['employees'] is List) {
        list = data['employees'] as List<dynamic>;
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }
      _byId.clear();
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        _byId[id] = EmployeeDirectoryEntry(
          id: id,
          fullName: m['full_name']?.toString() ?? 'Unknown',
          departmentName: m['current_department_name']?.toString(),
          positionName: m['current_position_name']?.toString(),
        );
      }
      isLoaded = true;
    } on DioException catch (_) {
      isLoaded = false;
    } catch (_) {
      isLoaded = false;
    }
  }

  /// Fills missing ids via [GET /api/employees/:id] (includes department after backend update).
  Future<void> ensureIds(Iterable<String> ids) async {
    final need = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).where((id) => !_byId.containsKey(id)).toSet();
    for (final id in need) {
      try {
        final res = await ApiClient.instance.get<Map<String, dynamic>>('/api/employees/$id');
        final m = res.data;
        if (m == null) continue;
        _byId[id] = EmployeeDirectoryEntry(
          id: id,
          fullName: m['full_name']?.toString() ?? 'Unknown',
          departmentName: m['current_department_name']?.toString(),
          positionName: m['current_position_name']?.toString(),
        );
      } catch (_) {}
    }
  }

  String formatUserLine(String userId) {
    final e = _byId[userId];
    if (e == null) return userId;
    return e.nameAndDepartment;
  }
}
