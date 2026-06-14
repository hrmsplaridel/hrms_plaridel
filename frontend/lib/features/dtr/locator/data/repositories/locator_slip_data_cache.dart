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
  final Map<bool, _LocatorCacheEntry<List<LocatorRequestType>>> _typeCache = {};
  _LocatorCacheEntry<bool>? _departmentHeadCache;

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

  Future<bool> checkIsDepartmentHead({bool forceRefresh = false}) async {
    final cached = _departmentHeadCache;
    if (!forceRefresh && cached != null && cached.isFresh(_referenceCacheTtl)) {
      return cached.value;
    }

    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/locator-slips/department-head/check',
    );
    final value = res.data?['isDeptHead'] == true;
    _departmentHeadCache = _LocatorCacheEntry<bool>(value, DateTime.now());
    return value;
  }

  Future<List<Map<String, dynamic>>> listMyRequests({
    bool forceRefresh = false,
  }) {
    return _listRequestRows(
      key: 'my',
      path: '/api/locator-slips/my',
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Map<String, dynamic>>> listDepartmentHeadRequests({
    bool forceRefresh = false,
  }) {
    return _listRequestRows(
      key: 'department-head',
      path: '/api/locator-slips/department-head',
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Map<String, dynamic>>> listAdminRequests({
    Map<String, String> query = const {},
    bool forceRefresh = false,
  }) {
    final path = Uri(
      path: '/api/locator-slips/admin',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _listRequestRows(
      key: _requestCacheKey('admin', query),
      path: path,
      forceRefresh: forceRefresh,
    );
  }

  void invalidateRequests() => _requestCache.clear();

  void invalidateTypes() => _typeCache.clear();

  void invalidateReferenceData() => _departmentHeadCache = null;

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

  static String _requestCacheKey(String scope, Map<String, String> query) {
    if (query.isEmpty) return scope;
    final entries = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final queryText = entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '$scope?$queryText';
  }
}

class _LocatorCacheEntry<T> {
  const _LocatorCacheEntry(this.value, this.cachedAt);

  final T value;
  final DateTime cachedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(cachedAt) < ttl;
}
