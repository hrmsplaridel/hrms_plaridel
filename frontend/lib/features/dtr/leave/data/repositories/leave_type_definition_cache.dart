import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

class LeaveTypeDefinitionCache {
  LeaveTypeDefinitionCache._();

  static final LeaveTypeDefinitionCache instance = LeaveTypeDefinitionCache._();
  static const Duration _ttl = Duration(minutes: 5);

  List<LeaveTypeDefinition>? _activeEmployeeTypes;
  DateTime? _activeEmployeeTypesAt;
  List<LeaveTypeDefinition>? _allTypes;
  DateTime? _allTypesAt;

  bool _isFresh(DateTime? cachedAt) =>
      cachedAt != null && DateTime.now().difference(cachedAt) < _ttl;

  Future<List<LeaveTypeDefinition>> listActiveEmployeeTypes({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _activeEmployeeTypes != null &&
        _isFresh(_activeEmployeeTypesAt)) {
      return List<LeaveTypeDefinition>.from(_activeEmployeeTypes!);
    }
    final rows = await _fetch(includeInactive: false);
    final filtered = rows
        .where(
          (item) => item.isActive && item.employeeCanFile && !item.adminOnly,
        )
        .toList();
    _activeEmployeeTypes = List<LeaveTypeDefinition>.unmodifiable(filtered);
    _activeEmployeeTypesAt = DateTime.now();
    return List<LeaveTypeDefinition>.from(filtered);
  }

  Future<List<LeaveTypeDefinition>> listAll({
    bool includeInactive = true,
    bool forceRefresh = false,
  }) async {
    if (includeInactive &&
        !forceRefresh &&
        _allTypes != null &&
        _isFresh(_allTypesAt)) {
      return List<LeaveTypeDefinition>.from(_allTypes!);
    }
    final rows = await _fetch(includeInactive: includeInactive);
    if (includeInactive) {
      _allTypes = List<LeaveTypeDefinition>.unmodifiable(rows);
      _allTypesAt = DateTime.now();
    }
    return List<LeaveTypeDefinition>.from(rows);
  }

  void invalidate() {
    _activeEmployeeTypes = null;
    _activeEmployeeTypesAt = null;
    _allTypes = null;
    _allTypesAt = null;
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
