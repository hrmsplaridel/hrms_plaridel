import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/reference_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

class LeaveTypeDefinitionCache {
  LeaveTypeDefinitionCache._();

  static final LeaveTypeDefinitionCache instance = LeaveTypeDefinitionCache._();
  final _types = ReferenceDataCache<bool, List<LeaveTypeDefinition>>(
    ttl: const Duration(minutes: 5),
  );

  Future<List<LeaveTypeDefinition>> listActiveEmployeeTypes({
    bool forceRefresh = false,
  }) async {
    final rows = await listAll(
      includeInactive: false,
      forceRefresh: forceRefresh,
    );
    final filtered = rows
        .where(
          (item) => item.isActive && item.employeeCanFile && !item.adminOnly,
        )
        .toList();
    return List<LeaveTypeDefinition>.from(filtered);
  }

  Future<List<LeaveTypeDefinition>> listAll({
    bool includeInactive = true,
    bool forceRefresh = false,
  }) async {
    final rows = await _types.get(
      includeInactive,
      () => _fetch(includeInactive: includeInactive),
      forceRefresh: forceRefresh,
    );
    return List<LeaveTypeDefinition>.from(rows);
  }

  void invalidate() {
    _types.invalidate();
  }

  Future<List<LeaveTypeDefinition>> _fetch({
    required bool includeInactive,
  }) async {
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/leave/types',
      queryParameters: includeInactive ? const {'include_inactive': '1'} : null,
    );
    return (res.data ?? const [])
        .map(
          (item) => LeaveTypeDefinition.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }
}
