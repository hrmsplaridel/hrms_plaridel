import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';

class LocatorSlipDataCache {
  LocatorSlipDataCache._();

  static final LocatorSlipDataCache instance = LocatorSlipDataCache._();

  static const Duration _requestCacheTtl = Duration(seconds: 30);
  static const Duration _typeCacheTtl = Duration(minutes: 5);
  static const Duration _referenceCacheTtl = Duration(minutes: 5);

  final Map<String, _LocatorCacheEntry<List<Map<String, dynamic>>>>
  _requestCache = {};
  final Map<String, _LocatorCacheEntry<LocatorAdminRequestPage>>
  _adminRequestCache = {};
  final Map<bool, _LocatorCacheEntry<List<LocatorRequestType>>> _typeCache = {};
  final Map<String, _LocatorCacheEntry<bool>> _departmentHeadCache = {};

  Future<List<LocatorRequestType>> listTypes({
    bool includeInactive = false,
    bool forceRefresh = false,
  }) async {
    final cached = _typeCache[includeInactive];
    if (!forceRefresh && cached != null && cached.isFresh(_typeCacheTtl)) {
      return List<LocatorRequestType>.from(cached.value);
    }

    final path = includeInactive
        ? '/api/locator-slips/types?include_inactive=true'
        : '/api/locator-slips/types';
    final res = await ApiClient.instance.get<List<dynamic>>(path);
    final items = (res.data ?? const [])
        .whereType<Map>()
        .map((e) => LocatorRequestType.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _typeCache[includeInactive] = _LocatorCacheEntry<List<LocatorRequestType>>(
      List<LocatorRequestType>.from(items),
      DateTime.now(),
    );
    return items;
  }

  Future<bool> checkIsDepartmentHead({
    required String userId,
    String? role,
    bool forceRefresh = false,
  }) async {
    final cacheKey = requestCacheKeyForUser(
      scope: 'department-head-check',
      userId: userId,
      role: role,
    );
    final cached = _departmentHeadCache[cacheKey];
    if (!forceRefresh && cached != null && cached.isFresh(_referenceCacheTtl)) {
      return cached.value;
    }

    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/locator-slips/department-head/check',
    );
    final value = res.data?['isDeptHead'] == true;
    _departmentHeadCache[cacheKey] = _LocatorCacheEntry<bool>(
      value,
      DateTime.now(),
    );
    return value;
  }

  Future<List<Map<String, dynamic>>> listMyRequests({
    required String userId,
    String? role,
    bool forceRefresh = false,
  }) {
    return _listRequestRows(
      key: requestCacheKeyForUser(scope: 'my', userId: userId, role: role),
      path: '/api/locator-slips/my',
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Map<String, dynamic>>> listDepartmentHeadRequests({
    required String userId,
    String? role,
    bool forceRefresh = false,
  }) {
    return _listRequestRows(
      key: requestCacheKeyForUser(
        scope: 'department-head',
        userId: userId,
        role: role,
      ),
      path: '/api/locator-slips/department-head',
      forceRefresh: forceRefresh,
    );
  }

  Future<LocatorAdminRequestPage> listAdminRequests({
    required String userId,
    required String role,
    Map<String, String> query = const {},
    bool forceRefresh = false,
  }) async {
    final path = Uri(
      path: '/api/locator-slips/admin',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    final key = requestCacheKeyForUser(
      scope: 'admin',
      userId: userId,
      role: role,
      query: query,
    );
    final cached = _adminRequestCache[key];
    if (!forceRefresh && cached != null && cached.isFresh(_requestCacheTtl)) {
      return cached.value.copy();
    }

    final res = await ApiClient.instance.get<dynamic>(path);
    final result = LocatorAdminRequestPage.fromData(res.data);
    _adminRequestCache[key] = _LocatorCacheEntry<LocatorAdminRequestPage>(
      result.copy(),
      DateTime.now(),
    );
    return result;
  }

  void invalidateRequests() {
    _requestCache.clear();
    _adminRequestCache.clear();
  }

  void invalidateTypes() => _typeCache.clear();

  void invalidateReferenceData() => _departmentHeadCache.clear();

  void invalidateAll() {
    invalidateRequests();
    invalidateTypes();
    invalidateReferenceData();
  }

  Future<List<Map<String, dynamic>>> _listRequestRows({
    required String key,
    required String path,
    required bool forceRefresh,
  }) async {
    final cached = _requestCache[key];
    if (!forceRefresh && cached != null && cached.isFresh(_requestCacheTtl)) {
      return _copyRows(cached.value);
    }

    final res = await ApiClient.instance.get<List<dynamic>>(path);
    final rows = (res.data ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _requestCache[key] = _LocatorCacheEntry<List<Map<String, dynamic>>>(
      _copyRows(rows),
      DateTime.now(),
    );
    return rows;
  }

  static List<Map<String, dynamic>> _copyRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static String requestCacheKeyForUser({
    required String scope,
    required String userId,
    String? role,
    Map<String, String> query = const {},
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'A user ID is required');
    }
    final normalizedRole = (role ?? '').trim().toLowerCase();
    final baseKey =
        '${scope.trim()}|user=$normalizedUserId|role=${normalizedRole.isEmpty ? 'unknown' : normalizedRole}';
    if (query.isEmpty) return baseKey;
    final entries = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final queryText = entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '$baseKey?$queryText';
  }
}

class LocatorAdminRequestPage {
  const LocatorAdminRequestPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.pageCount,
    required this.departments,
    required this.employees,
  });

  final List<Map<String, dynamic>> items;
  final int page;
  final int pageSize;
  final int total;
  final int pageCount;
  final List<LocatorAdminFilterOption> departments;
  final List<LocatorAdminFilterOption> employees;

  factory LocatorAdminRequestPage.fromData(dynamic data) {
    if (data is List) {
      final items = _rowsFrom(data);
      return LocatorAdminRequestPage(
        items: items,
        page: 1,
        pageSize: items.isEmpty ? 10 : items.length,
        total: items.length,
        pageCount: 1,
        departments: const [],
        employees: const [],
      );
    }

    final body = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    final pagination = body['pagination'] is Map
        ? Map<String, dynamic>.from(body['pagination'] as Map)
        : const <String, dynamic>{};
    final filterOptions = body['filter_options'] is Map
        ? Map<String, dynamic>.from(body['filter_options'] as Map)
        : const <String, dynamic>{};
    final items = _rowsFrom(body['items']);
    final pageSize = _positiveInt(pagination['page_size'], fallback: 10);
    final total = _nonnegativeInt(pagination['total'], fallback: items.length);
    final pageCount = _positiveInt(
      pagination['page_count'],
      fallback: total == 0 ? 1 : (total / pageSize).ceil(),
    );

    return LocatorAdminRequestPage(
      items: items,
      page: _positiveInt(pagination['page'], fallback: 1),
      pageSize: pageSize,
      total: total,
      pageCount: pageCount,
      departments: _optionsFrom(filterOptions['departments']),
      employees: _optionsFrom(filterOptions['employees']),
    );
  }

  LocatorAdminRequestPage copy() => LocatorAdminRequestPage(
    items: items.map((item) => Map<String, dynamic>.from(item)).toList(),
    page: page,
    pageSize: pageSize,
    total: total,
    pageCount: pageCount,
    departments: departments.map((option) => option.copy()).toList(),
    employees: employees.map((option) => option.copy()).toList(),
  );

  static List<Map<String, dynamic>> _rowsFrom(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static List<LocatorAdminFilterOption> _optionsFrom(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map(
          (item) => LocatorAdminFilterOption.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((option) => option.id.isNotEmpty && option.name.isNotEmpty)
        .toList();
  }

  static int _positiveInt(dynamic value, {required int fallback}) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  static int _nonnegativeInt(dynamic value, {required int fallback}) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : fallback;
  }
}

class LocatorAdminFilterOption {
  const LocatorAdminFilterOption({
    required this.id,
    required this.name,
    this.departmentIds = const [],
  });

  final String id;
  final String name;
  final List<String> departmentIds;

  factory LocatorAdminFilterOption.fromJson(Map<String, dynamic> json) {
    final rawDepartmentIds = json['department_ids'];
    return LocatorAdminFilterOption(
      id: (json['id'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
      departmentIds: rawDepartmentIds is List
          ? rawDepartmentIds
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList()
          : const [],
    );
  }

  LocatorAdminFilterOption copy() => LocatorAdminFilterOption(
    id: id,
    name: name,
    departmentIds: List<String>.from(departmentIds),
  );
}

class _LocatorCacheEntry<T> {
  const _LocatorCacheEntry(this.value, this.cachedAt);

  final T value;
  final DateTime cachedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(cachedAt) < ttl;
}
