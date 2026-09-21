import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request_history.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

/// Credit balances and explicitly marked annual-entitlement summaries are shown.
/// Event, request, and compliance limits are not balance rows.
List<LeaveBalance> _filterDisplayBalances(List<LeaveBalance> raw) {
  return raw
      .where(
        (balance) =>
            balance.effectiveLeaveTypeName != 'others' &&
            (balance.isCreditBalance || balance.isAnnualEntitlement),
      )
      .toList();
}

class _LeaveCacheEntry<T> {
  const _LeaveCacheEntry(this.value, this.cachedAt);

  final T value;
  final DateTime cachedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(cachedAt) < ttl;
}

/// State management for the leave module.
///
/// The provider depends only on the [LeaveRepository] contract, so the UI can
/// stay unchanged if the backend later switches from Supabase to a custom API.
class LeaveProvider extends ChangeNotifier {
  LeaveProvider({required LeaveRepository repository, this.onMutation})
    : _repository = repository;

  final LeaveRepository _repository;
  int _authGeneration = 0;
  int _myLeaveLoadGeneration = 0;
  int _myRequestsLoadGeneration = 0;
  int _myBalancesLoadGeneration = 0;
  int _officialDateLoadGeneration = 0;
  int _adminReviewGeneration = 0;
  int _headReviewGeneration = 0;
  bool _disposed = false;

  bool _isCurrentAuthGeneration(int generation) =>
      !_disposed && generation == _authGeneration;

  /// Called after successful leave API actions so the UI can refresh in-app notifications (badge).
  final void Function()? onMutation;

  void _notifyMutation() {
    invalidateCachedLeaveData();
    try {
      onMutation?.call();
    } catch (_) {}
  }

  LeaveRepository get repository => _repository;

  List<LeaveRequest> _requests = [];
  List<LeaveRequest> _myRequests = [];
  List<LeaveRequest> _departmentHeadRequests = [];
  static const int _reviewPageSize = 200;
  int _adminReviewTotal = 0;
  int _headReviewTotal = 0;
  int _adminReviewNextOffset = 0;
  int _headReviewNextOffset = 0;
  bool _adminReviewHasMore = false;
  bool _headReviewHasMore = false;
  bool _adminReviewLoadingMore = false;
  bool _headReviewLoadingMore = false;
  String? _adminReviewLoadMoreError;
  String? _headReviewLoadMoreError;
  bool _adminReviewLoading = false;
  String? _adminReviewError;
  bool _adminReviewInitialLoadComplete = false;
  bool _adminReviewLoadAttempted = false;
  bool _headReviewLoading = false;
  String? _headReviewError;
  bool _headReviewInitialLoadComplete = false;
  bool _headReviewLoadAttempted = false;
  String? _adminReviewQueryKey;
  String? _headReviewQueryKey;
  List<LeaveBalance> _balances = [];
  LeaveRequest? _selectedRequest;
  static const Duration _requestCacheTtl = Duration(seconds: 30);
  static const int _myRequestsPageSize = 50;
  static const Duration _balanceCacheTtl = Duration(seconds: 60);
  static const Duration _ledgerCacheTtl = Duration(seconds: 60);
  static const Duration _referenceCacheTtl = Duration(minutes: 5);
  final Map<String, _LeaveCacheEntry<List<LeaveRequest>>> _requestCache = {};
  final Map<String, _LeaveCacheEntry<LeaveRequestPage>> _myRequestPageCache =
      {};
  final Map<String, _LeaveCacheEntry<List<LeaveBalance>>> _balanceCache = {};
  final Map<String, _LeaveCacheEntry<LeaveLedgerResult>> _ledgerCache = {};
  _LeaveCacheEntry<Map<String, dynamic>>? _deptHeadCheckCache;

  bool _loading = false;
  bool _submitting = false;
  bool _reviewing = false;
  String? _error;
  bool _myRequestsLoading = false;
  bool _myBalancesLoading = false;
  bool _myRequestsLoaded = false;
  bool _myBalancesLoaded = false;
  String? _myRequestsError;
  String? _myBalancesError;
  bool _myRequestsLoadingMore = false;
  String? _myRequestsLoadMoreError;
  int _myRequestsTotal = 0;
  int _myRequestsNextOffset = 0;
  bool _myRequestsHasMore = false;
  DateTime? _officialDate;
  bool _officialDateLoading = false;
  String? _officialDateError;

  LeaveRequestStatus? _filterStatus;
  LeaveType? _filterLeaveType;

  List<LeaveRequest> get requests => List.unmodifiable(_requests);
  List<LeaveRequest> get myRequests => List.unmodifiable(_myRequests);
  List<LeaveRequest> get departmentHeadRequests =>
      List.unmodifiable(_departmentHeadRequests);
  int reviewTotal({required bool departmentHead}) =>
      departmentHead ? _headReviewTotal : _adminReviewTotal;
  bool reviewHasMore({required bool departmentHead}) =>
      departmentHead ? _headReviewHasMore : _adminReviewHasMore;
  bool reviewLoadingMore({required bool departmentHead}) =>
      departmentHead ? _headReviewLoadingMore : _adminReviewLoadingMore;
  String? reviewLoadMoreError({required bool departmentHead}) =>
      departmentHead ? _headReviewLoadMoreError : _adminReviewLoadMoreError;
  bool reviewLoading({required bool departmentHead}) =>
      departmentHead ? _headReviewLoading : _adminReviewLoading;
  String? reviewError({required bool departmentHead}) =>
      departmentHead ? _headReviewError : _adminReviewError;
  bool reviewInitialLoadComplete({required bool departmentHead}) =>
      departmentHead
      ? _headReviewInitialLoadComplete
      : _adminReviewInitialLoadComplete;
  bool reviewLoadAttempted({required bool departmentHead}) =>
      departmentHead ? _headReviewLoadAttempted : _adminReviewLoadAttempted;
  List<LeaveBalance> get balances => List.unmodifiable(_balances);
  LeaveRequest? get selectedRequest => _selectedRequest;

  bool get loading => _loading;
  bool get submitting => _submitting;
  bool get reviewing => _reviewing;
  String? get error => _error;
  bool get myRequestsLoading => _myRequestsLoading;
  bool get myBalancesLoading => _myBalancesLoading;
  bool get myRequestsLoaded => _myRequestsLoaded;
  bool get myBalancesLoaded => _myBalancesLoaded;
  String? get myRequestsError => _myRequestsError;
  String? get myBalancesError => _myBalancesError;
  bool get myRequestsLoadingMore => _myRequestsLoadingMore;
  String? get myRequestsLoadMoreError => _myRequestsLoadMoreError;
  int get myRequestsTotal => _myRequestsTotal;
  bool get myRequestsHasMore => _myRequestsHasMore;
  DateTime? get officialDate => _officialDate;
  bool get officialDateLoading => _officialDateLoading;
  String? get officialDateError => _officialDateError;

  LeaveRequestStatus? get filterStatus => _filterStatus;
  LeaveType? get filterLeaveType => _filterLeaveType;

  List<LeaveRequest> get pendingRequests =>
      _myRequests.where((r) => r.status.isPending).toList();

  List<LeaveRequest> get approvedRequests => _myRequests
      .where((r) => r.status == LeaveRequestStatus.approved)
      .toList();

  List<LeaveRequest> get upcomingApprovedRequests {
    final startOfToday = _officialDate;
    if (startOfToday == null) return const [];
    return approvedRequests.where((r) {
      final start = r.startDate;
      if (start == null) return false;
      final end = r.endDate ?? start;
      final endDateOnly = DateTime(end.year, end.month, end.day);
      return !endDateOnly.isBefore(startOfToday);
    }).toList()..sort((a, b) {
      final aStart = a.startDate!;
      final bStart = b.startDate!;
      final aDate = DateTime(aStart.year, aStart.month, aStart.day);
      final bDate = DateTime(bStart.year, bStart.month, bStart.day);
      final aSortDate = aDate.isBefore(startOfToday) ? startOfToday : aDate;
      final bSortDate = bDate.isBefore(startOfToday) ? startOfToday : bDate;
      return aSortDate.compareTo(bSortDate);
    });
  }

  int get pendingCount => pendingRequests.length;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearReviewError({required bool departmentHead}) {
    if (departmentHead) {
      _headReviewError = null;
    } else {
      _adminReviewError = null;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedRequest = null;
    notifyListeners();
  }

  Future<List<LeaveRequestHistoryEntry>> loadMyRequestHistory(
    String requestId,
  ) async {
    final authGeneration = _authGeneration;
    final history = await _repository.listMyRequestHistory(requestId);
    if (!_isCurrentAuthGeneration(authGeneration)) {
      throw StateError('The authenticated session changed.');
    }
    return history;
  }

  void setFilters({LeaveRequestStatus? status, LeaveType? leaveType}) {
    _filterStatus = status;
    _filterLeaveType = leaveType;
    notifyListeners();
  }

  void resetFilters() {
    _filterStatus = null;
    _filterLeaveType = null;
    notifyListeners();
  }

  LeaveBalance? balanceForType(LeaveType leaveType) {
    try {
      final ledger = leaveType.balanceLedgerType;
      return _balances.firstWhere(
        (b) => b.effectiveLeaveTypeName == ledger.value,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _normalize(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _loadErrorMessage(Object error, String fallback) {
    final message = error.toString().replaceFirst(
      RegExp(r'^Exception:\s*'),
      '',
    );
    if (message.isEmpty || message.contains('DioException')) return fallback;
    return message;
  }

  static String _dateOnlyKey(DateTime? date) {
    if (date == null) return '';
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String _dateTimeKey(DateTime? date) =>
      date == null ? '' : date.toUtc().toIso8601String();

  static String _requestQueryKey(String scope, LeaveRequestQuery query) {
    return [
      scope,
      _normalize(query.userId) ?? '',
      _normalize(query.department) ?? '',
      query.status?.value ?? '',
      _normalize(query.leaveTypeName) ?? query.leaveType?.value ?? '',
      _dateOnlyKey(query.startDateFrom),
      _dateOnlyKey(query.startDateTo),
      _dateTimeKey(query.createdFrom),
      _dateTimeKey(query.createdTo),
      query.limit?.toString() ?? '',
      query.offset?.toString() ?? '',
    ].join('|');
  }

  static String _myRequestsKey(String userId, LeaveRequestStatus? status) {
    return ['my', _normalize(userId) ?? '', status?.value ?? ''].join('|');
  }

  static String _myRequestPageKey(String userId, int limit, int offset) {
    return ['my-page', _normalize(userId) ?? '', limit, offset].join('|');
  }

  static String _ledgerKey(LeaveLedgerQuery query) {
    return [
      _normalize(query.userId) ?? '',
      query.allUsers ? 'all' : 'self',
      _normalize(query.leaveType) ?? '',
      _normalize(query.action) ?? '',
      _normalize(query.affectedBucket) ?? '',
      _normalize(query.from) ?? '',
      _normalize(query.to) ?? '',
      query.limit.toString(),
      query.offset.toString(),
    ].join('|');
  }

  List<T>? _readListCache<T>(
    Map<String, _LeaveCacheEntry<List<T>>> cache,
    String key,
    Duration ttl,
  ) {
    final entry = cache[key];
    if (entry == null || !entry.isFresh(ttl)) return null;
    return List<T>.from(entry.value);
  }

  void _writeListCache<T>(
    Map<String, _LeaveCacheEntry<List<T>>> cache,
    String key,
    List<T> value,
  ) {
    cache[key] = _LeaveCacheEntry<List<T>>(
      List<T>.unmodifiable(value),
      DateTime.now(),
    );
  }

  void invalidateCachedLeaveData({bool notify = false}) {
    _requestCache.clear();
    _myRequestPageCache.clear();
    _balanceCache.clear();
    _ledgerCache.clear();
    _deptHeadCheckCache = null;
    _deptHeadCheck = null;
    if (notify) notifyListeners();
  }

  /// Called by the proxy provider whenever [AuthProvider] changes.
  String? _lastKnownUserId;
  void onAuthUserChanged(String? newUserId) {
    if (_disposed) return;
    final normalizedUserId = _normalize(newUserId);
    if (_lastKnownUserId == normalizedUserId) return;

    _authGeneration += 1;
    _lastKnownUserId = normalizedUserId;
    _resetSessionState();
    notifyListeners();
  }

  void _resetSessionState() {
    _myLeaveLoadGeneration += 1;
    _myRequestsLoadGeneration += 1;
    _myBalancesLoadGeneration += 1;
    _officialDateLoadGeneration += 1;
    _adminReviewGeneration += 1;
    _headReviewGeneration += 1;
    invalidateCachedLeaveData(notify: false);
    _requests = [];
    _myRequests = [];
    _departmentHeadRequests = [];
    _adminReviewTotal = 0;
    _headReviewTotal = 0;
    _adminReviewNextOffset = 0;
    _headReviewNextOffset = 0;
    _adminReviewHasMore = false;
    _headReviewHasMore = false;
    _adminReviewLoadingMore = false;
    _headReviewLoadingMore = false;
    _adminReviewLoadMoreError = null;
    _headReviewLoadMoreError = null;
    _adminReviewLoading = false;
    _headReviewLoading = false;
    _adminReviewError = null;
    _headReviewError = null;
    _adminReviewInitialLoadComplete = false;
    _headReviewInitialLoadComplete = false;
    _adminReviewLoadAttempted = false;
    _headReviewLoadAttempted = false;
    _adminReviewQueryKey = null;
    _headReviewQueryKey = null;
    _balances = [];
    _selectedRequest = null;
    _loading = false;
    _submitting = false;
    _reviewing = false;
    _error = null;
    _myRequestsLoading = false;
    _myBalancesLoading = false;
    _myRequestsLoaded = false;
    _myBalancesLoaded = false;
    _myRequestsError = null;
    _myBalancesError = null;
    _myRequestsLoadingMore = false;
    _myRequestsLoadMoreError = null;
    _myRequestsTotal = 0;
    _myRequestsNextOffset = 0;
    _myRequestsHasMore = false;
    _officialDate = null;
    _officialDateLoading = false;
    _officialDateError = null;
    _filterStatus = null;
    _filterLeaveType = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _authGeneration += 1;
    super.dispose();
  }

  Future<List<LeaveRequest>> _getMyRequestsCached(
    String userId, {
    LeaveRequestStatus? status,
    bool forceRefresh = false,
    bool Function()? shouldAcceptResult,
  }) async {
    final authGeneration = _authGeneration;
    final key = _myRequestsKey(userId, status);
    final cached = forceRefresh
        ? null
        : _readListCache(_requestCache, key, _requestCacheTtl);
    if (cached != null) return cached;
    final fresh = await _repository.listMyRequests(userId, status: status);
    if (!_isCurrentAuthGeneration(authGeneration) ||
        (shouldAcceptResult != null && !shouldAcceptResult())) {
      return const <LeaveRequest>[];
    }
    _writeListCache(_requestCache, key, fresh);
    return List<LeaveRequest>.from(fresh);
  }

  Future<LeaveRequestPage> _getMyRequestPageCached(
    String userId, {
    required int limit,
    required int offset,
    bool forceRefresh = false,
    bool Function()? shouldAcceptResult,
  }) async {
    final authGeneration = _authGeneration;
    final key = _myRequestPageKey(userId, limit, offset);
    final cached = forceRefresh ? null : _myRequestPageCache[key];
    if (cached != null && cached.isFresh(_requestCacheTtl)) {
      return cached.value;
    }
    final fresh = await _repository.listMyRequestPage(
      userId,
      limit: limit,
      offset: offset,
    );
    if (!_isCurrentAuthGeneration(authGeneration) ||
        (shouldAcceptResult != null && !shouldAcceptResult())) {
      return const LeaveRequestPage(items: [], total: 0, limit: 0, offset: 0);
    }
    final cachedPage = LeaveRequestPage(
      items: List<LeaveRequest>.unmodifiable(fresh.items),
      total: fresh.total,
      limit: fresh.limit,
      offset: fresh.offset,
    );
    _myRequestPageCache[key] = _LeaveCacheEntry<LeaveRequestPage>(
      cachedPage,
      DateTime.now(),
    );
    return cachedPage;
  }

  Future<List<LeaveBalance>> _getBalancesForUserCached(
    String userId, {
    bool forceRefresh = false,
    bool Function()? shouldAcceptResult,
  }) async {
    final authGeneration = _authGeneration;
    final key = _normalize(userId);
    if (key == null) return const <LeaveBalance>[];
    final cached = forceRefresh
        ? null
        : _readListCache(_balanceCache, key, _balanceCacheTtl);
    if (cached != null) return cached;
    final fresh = await _repository.getBalancesForUser(key);
    if (!_isCurrentAuthGeneration(authGeneration) ||
        (shouldAcceptResult != null && !shouldAcceptResult())) {
      return const <LeaveBalance>[];
    }
    _writeListCache(_balanceCache, key, fresh);
    return List<LeaveBalance>.from(fresh);
  }

  /// Fetches leave balances for a user (e.g. for admin approval dialog).
  ///
  /// On network or server failure, returns an empty list so callers that
  /// treat balances as informational (e.g. the approval confirmation dialog)
  /// can still proceed. Use [fetchBalancesForUserStrict] in print flows where
  /// incorrect balance figures must not appear on a formal document.
  Future<List<LeaveBalance>> fetchBalancesForUser(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    try {
      final balances = await _getBalancesForUserCached(
        userId,
        forceRefresh: forceRefresh,
      );
      return _isCurrentAuthGeneration(authGeneration)
          ? balances
          : const <LeaveBalance>[];
    } catch (_) {
      return [];
    }
  }

  /// Fetches leave balances for a user for a formal print flow.
  ///
  /// Unlike [fetchBalancesForUser], this method rethrows any network or
  /// server error so callers can block certification printing rather than
  /// silently substituting zero/default balance figures on the printed form.
  Future<List<LeaveBalance>> fetchBalancesForUserStrict(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    // Intentionally no try/catch — errors propagate to the print caller.
    final balances = await _getBalancesForUserCached(
      userId,
      forceRefresh: forceRefresh,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) {
      return const <LeaveBalance>[];
    }
    return balances;
  }

  Future<List<LeaveBalance>> fetchFormCreditsForRequestStrict(
    String requestId,
  ) async {
    final authGeneration = _authGeneration;
    final balances = await _repository.getFormCreditsForRequest(requestId);
    if (!_isCurrentAuthGeneration(authGeneration)) {
      return const <LeaveBalance>[];
    }
    return balances;
  }

  Future<void> loadMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final requests = await _getMyRequestsCached(
        userId,
        status: status,
        forceRefresh: forceRefresh,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _myRequests = requests;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _myRequests = [];
      _error = e.toString();
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
    bool forceRefresh = false,
  }) => _loadReviewRequests(query: query, departmentHead: false);

  LeaveRequestQuery _reviewPageQuery(LeaveRequestQuery query, int offset) =>
      LeaveRequestQuery(
        userId: query.userId,
        department: query.department,
        status: query.status,
        leaveType: query.leaveType,
        leaveTypeName: query.leaveTypeName,
        startDateFrom: query.startDateFrom,
        startDateTo: query.startDateTo,
        createdFrom: query.createdFrom,
        createdTo: query.createdTo,
        limit: _reviewPageSize,
        offset: offset,
      );

  Future<void> _loadReviewRequests({
    required LeaveRequestQuery query,
    required bool departmentHead,
  }) async {
    final authGeneration = _authGeneration;
    final generation = departmentHead
        ? ++_headReviewGeneration
        : ++_adminReviewGeneration;
    bool isCurrent() =>
        _isCurrentAuthGeneration(authGeneration) &&
        generation ==
            (departmentHead ? _headReviewGeneration : _adminReviewGeneration);
    final key = _requestQueryKey(departmentHead ? 'head' : 'admin', query);
    final oldKey = departmentHead ? _headReviewQueryKey : _adminReviewQueryKey;
    final previousCount = oldKey == key
        ? (departmentHead ? _departmentHeadRequests.length : _requests.length)
        : 0;
    if (oldKey != key) {
      if (departmentHead) {
        _departmentHeadRequests = [];
        _headReviewTotal = 0;
        _headReviewHasMore = false;
        _headReviewInitialLoadComplete = false;
        _headReviewLoadAttempted = false;
      } else {
        _requests = [];
        _adminReviewTotal = 0;
        _adminReviewHasMore = false;
        _adminReviewInitialLoadComplete = false;
        _adminReviewLoadAttempted = false;
      }
    }
    if (departmentHead) {
      _headReviewLoadingMore = false;
      _headReviewLoading = true;
      _headReviewError = null;
    } else {
      _adminReviewLoadingMore = false;
      _adminReviewLoading = true;
      _adminReviewError = null;
    }
    _filterStatus = query.status;
    _filterLeaveType = query.leaveType;
    notifyListeners();
    try {
      final items = <LeaveRequest>[];
      var offset = 0;
      var total = 0;
      do {
        final page = await _repository.listReviewRequestsPage(
          query: _reviewPageQuery(query, offset),
          departmentHead: departmentHead,
        );
        if (!isCurrent()) return;
        items.addAll(page.items);
        total = page.total;
        offset = page.offset + page.items.length;
        if (page.items.isEmpty) break;
      } while (offset < previousCount && offset < total);
      if (departmentHead) {
        _departmentHeadRequests = items;
        _headReviewTotal = total;
        _headReviewNextOffset = offset;
        _headReviewHasMore = offset < total;
        _headReviewQueryKey = key;
        _headReviewLoadMoreError = null;
        _headReviewInitialLoadComplete = true;
      } else {
        _requests = items;
        _adminReviewTotal = total;
        _adminReviewNextOffset = offset;
        _adminReviewHasMore = offset < total;
        _adminReviewQueryKey = key;
        _adminReviewLoadMoreError = null;
        _adminReviewInitialLoadComplete = true;
      }
    } catch (e) {
      if (!isCurrent()) return;
      if (departmentHead) {
        _headReviewError = e.toString();
        _headReviewLoadAttempted = true;
      } else {
        _adminReviewError = e.toString();
        _adminReviewLoadAttempted = true;
      }
    } finally {
      if (isCurrent()) {
        if (departmentHead) {
          _headReviewLoading = false;
        } else {
          _adminReviewLoading = false;
        }
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreReviewRequests({
    required LeaveRequestQuery query,
    required bool departmentHead,
  }) async {
    final key = _requestQueryKey(departmentHead ? 'head' : 'admin', query);
    if (key != (departmentHead ? _headReviewQueryKey : _adminReviewQueryKey) ||
        !reviewHasMore(departmentHead: departmentHead) ||
        reviewLoadingMore(departmentHead: departmentHead)) {
      return;
    }
    final authGeneration = _authGeneration;
    final generation = departmentHead
        ? _headReviewGeneration
        : _adminReviewGeneration;
    final offset = departmentHead
        ? _headReviewNextOffset
        : _adminReviewNextOffset;
    bool isCurrent() =>
        _isCurrentAuthGeneration(authGeneration) &&
        generation ==
            (departmentHead ? _headReviewGeneration : _adminReviewGeneration);
    if (departmentHead) {
      _headReviewLoadingMore = true;
      _headReviewLoadMoreError = null;
    } else {
      _adminReviewLoadingMore = true;
      _adminReviewLoadMoreError = null;
    }
    notifyListeners();
    try {
      final page = await _repository.listReviewRequestsPage(
        query: _reviewPageQuery(query, offset),
        departmentHead: departmentHead,
      );
      if (!isCurrent()) return;
      final merged = <String, LeaveRequest>{
        for (final request
            in departmentHead ? _departmentHeadRequests : _requests)
          if (request.id != null) request.id!: request,
      };
      for (final request in page.items) {
        if (request.id != null) merged[request.id!] = request;
      }
      if (departmentHead) {
        _departmentHeadRequests = merged.values.toList();
        _headReviewTotal = page.total;
        _headReviewNextOffset = page.offset + page.items.length;
        _headReviewHasMore = page.hasMore;
      } else {
        _requests = merged.values.toList();
        _adminReviewTotal = page.total;
        _adminReviewNextOffset = page.offset + page.items.length;
        _adminReviewHasMore = page.hasMore;
      }
    } catch (e) {
      if (!isCurrent()) return;
      if (departmentHead) {
        _headReviewLoadMoreError = e.toString();
      } else {
        _adminReviewLoadMoreError = e.toString();
      }
    } finally {
      if (isCurrent()) {
        if (departmentHead) {
          _headReviewLoadingMore = false;
        } else {
          _adminReviewLoadingMore = false;
        }
        notifyListeners();
      }
    }
  }

  Future<void> loadPendingRequests({bool forceRefresh = false}) async {
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _filterStatus = LeaveRequestStatus.pending;
      const key = 'pending';
      final cached = forceRefresh
          ? null
          : _readListCache(_requestCache, key, _requestCacheTtl);
      if (cached != null) {
        _requests = cached;
      } else {
        final fresh = await _repository.listPendingRequests();
        if (!_isCurrentAuthGeneration(authGeneration)) return;
        _writeListCache(_requestCache, key, fresh);
        _requests = List<LeaveRequest>.from(fresh);
      }
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _requests = [];
      _error = e.toString();
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadBalances(String userId, {bool forceRefresh = false}) async {
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _getBalancesForUserCached(
        userId,
        forceRefresh: forceRefresh,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _balances = _filterDisplayBalances(raw);
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _balances = [];
      _error = e.toString();
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMyLeaveData(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    final loadGeneration = ++_myLeaveLoadGeneration;
    bool isCurrentLoad() =>
        _isCurrentAuthGeneration(authGeneration) &&
        loadGeneration == _myLeaveLoadGeneration;

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([
        loadMyLeaveRequests(userId, forceRefresh: forceRefresh),
        loadMyLeaveBalances(userId, forceRefresh: forceRefresh),
        loadOfficialDate(forceRefresh: forceRefresh),
      ]);
    } finally {
      if (isCurrentLoad()) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadOfficialDate({bool forceRefresh = false}) async {
    if (!forceRefresh && _officialDate != null) return;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_officialDateLoadGeneration;
    bool isCurrentLoad() =>
        _isCurrentAuthGeneration(authGeneration) &&
        loadGeneration == _officialDateLoadGeneration;

    _officialDateLoading = true;
    _officialDateError = null;
    notifyListeners();
    try {
      final date = await _repository.getOfficialDate();
      if (!isCurrentLoad()) return;
      _officialDate = DateTime(date.year, date.month, date.day);
    } catch (e) {
      if (!isCurrentLoad()) return;
      _officialDateError = _loadErrorMessage(
        e,
        'Unable to load the official HRMS date. Please try again.',
      );
    } finally {
      if (isCurrentLoad()) {
        _officialDateLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMyLeaveRequests(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    final loadGeneration = ++_myRequestsLoadGeneration;
    bool isCurrentLoad() =>
        _isCurrentAuthGeneration(authGeneration) &&
        loadGeneration == _myRequestsLoadGeneration;

    _myRequestsLoading = true;
    _myRequestsError = null;
    _myRequestsLoadMoreError = null;
    notifyListeners();
    try {
      final page = await _getMyRequestPageCached(
        userId,
        limit: _myRequestsPageSize,
        offset: 0,
        forceRefresh: forceRefresh,
        shouldAcceptResult: isCurrentLoad,
      );
      if (!isCurrentLoad()) return;
      _myRequests = List<LeaveRequest>.from(page.items);
      _myRequestsTotal = page.total;
      _myRequestsNextOffset = page.offset + page.items.length;
      _myRequestsHasMore = page.hasMore;
      _myRequestsLoaded = true;
    } catch (e) {
      if (!isCurrentLoad()) return;
      _myRequestsError = _loadErrorMessage(
        e,
        'Unable to load leave requests. Please try again.',
      );
    } finally {
      if (isCurrentLoad()) {
        _myRequestsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreMyLeaveRequests(String userId) async {
    if (_myRequestsLoadingMore || !_myRequestsHasMore) return;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_myRequestsLoadGeneration;
    bool isCurrentLoad() =>
        _isCurrentAuthGeneration(authGeneration) &&
        loadGeneration == _myRequestsLoadGeneration;

    _myRequestsLoadingMore = true;
    _myRequestsLoadMoreError = null;
    notifyListeners();
    try {
      final page = await _getMyRequestPageCached(
        userId,
        limit: _myRequestsPageSize,
        offset: _myRequestsNextOffset,
        shouldAcceptResult: isCurrentLoad,
      );
      if (!isCurrentLoad()) return;

      final merged = List<LeaveRequest>.from(_myRequests);
      final indexesById = <String, int>{
        for (var index = 0; index < merged.length; index++)
          if ((merged[index].id ?? '').isNotEmpty) merged[index].id!: index,
      };
      for (final request in page.items) {
        final id = request.id;
        final existingIndex = id == null ? null : indexesById[id];
        if (existingIndex == null) {
          merged.add(request);
          if (id != null && id.isNotEmpty) indexesById[id] = merged.length - 1;
        } else {
          merged[existingIndex] = request;
        }
      }
      _myRequests = merged;
      _myRequestsTotal = page.total;
      _myRequestsNextOffset = page.offset + page.items.length;
      _myRequestsHasMore = page.hasMore;
    } catch (e) {
      if (!isCurrentLoad()) return;
      _myRequestsLoadMoreError = _loadErrorMessage(
        e,
        'Unable to load more leave requests. Please try again.',
      );
    } finally {
      if (isCurrentLoad()) {
        _myRequestsLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMyLeaveBalances(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    final loadGeneration = ++_myBalancesLoadGeneration;
    bool isCurrentLoad() =>
        _isCurrentAuthGeneration(authGeneration) &&
        loadGeneration == _myBalancesLoadGeneration;

    _myBalancesLoading = true;
    _myBalancesError = null;
    notifyListeners();
    try {
      final balances = await _getBalancesForUserCached(
        userId,
        forceRefresh: forceRefresh,
        shouldAcceptResult: isCurrentLoad,
      );
      if (!isCurrentLoad()) return;
      _balances = _filterDisplayBalances(balances);
      _myBalancesLoaded = true;
    } catch (e) {
      if (!isCurrentLoad()) return;
      _myBalancesError = _loadErrorMessage(
        e,
        'Unable to load leave credits. Please try again.',
      );
    } finally {
      if (isCurrentLoad()) {
        _myBalancesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> loadRequestById(String requestId) async {
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final selected = await _repository.getRequestById(requestId);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = selected;
      return _selectedRequest;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Refetches a request by ID without setting loading state (e.g. for admin
  /// to get latest attachment). Updates _selectedRequest and upserts into list.
  Future<LeaveRequest?> refreshRequestById(String requestId) async {
    final authGeneration = _authGeneration;
    _error = null;
    try {
      final fresh = await _repository.getRequestById(requestId);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      if (fresh != null) {
        _selectedRequest = fresh;
        _upsertRequest(fresh);
        notifyListeners();
      }
      return fresh;
    } catch (e) {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _error = _loadErrorMessage(
          e,
          'Could not check the latest request. Please try again.',
        );
        notifyListeners();
      }
      return null;
    }
  }

  Future<LeaveRequest?> saveDraft(LeaveRequest request) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.saveDraft(request);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      invalidateCachedLeaveData();
      _selectedRequest = saved;
      _upsertRequest(saved, addToMyRequests: true);
      return saved;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> submitRequest(LeaveRequest request) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.submitRequest(request);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = saved;
      _upsertRequest(saved, addToMyRequests: true);
      _notifyMutation();
      return saved;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error =
          e is Exception &&
              e.toString().replaceFirst('Exception: ', '').isNotEmpty
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> submitRequestWithAttachment({
    required LeaveRequest request,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.submitRequestWithAttachment(
        request: request,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = saved;
      _upsertRequest(saved, addToMyRequests: true);
      _notifyMutation();
      return saved;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error =
          e is Exception &&
              e.toString().replaceFirst('Exception: ', '').isNotEmpty
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> updateRequest(LeaveRequest request) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.updateRequest(request);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = saved;
      _upsertRequest(saved, addToMyRequests: true);
      _notifyMutation();
      return saved;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> cancelRequest({
    required String requestId,
    required String userId,
    String? reason,
  }) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.cancelRequest(
        requestId: requestId,
        userId: userId,
        reason: reason,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = updated;
      _upsertRequest(updated, addToMyRequests: true);
      _notifyMutation();
      return updated;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> discardDraft({
    required String requestId,
    required String userId,
  }) async {
    final authGeneration = _authGeneration;
    _error = null;
    try {
      await _repository.discardDraft(requestId: requestId, userId: userId);
      if (!_isCurrentAuthGeneration(authGeneration)) return false;
      _myRequests.removeWhere((request) => request.id == requestId);
      if (_selectedRequest?.id == requestId) _selectedRequest = null;
      if (_myRequestsTotal > 0) _myRequestsTotal--;
      _notifyMutation();
      notifyListeners();
      return true;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return false;
      _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      notifyListeners();
      return false;
    }
  }

  Future<LeaveRequest?> approveRequest(LeaveApprovalInput input) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.approveRequest(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged, addToAdminRequests: true);
      _notifyMutation();
      return merged;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  /// #15: Revoke approval — reverses balance deduction + clears DTR entries.
  Future<LeaveRequest?> revokeApproval(LeaveReviewDecisionInput input) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.revokeApproval(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged, addToAdminRequests: true);
      _notifyMutation();
      return merged;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> returnRequest(LeaveReviewDecisionInput input) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.returnRequest(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged, addToAdminRequests: true);
      _notifyMutation();
      return merged;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> rejectRequest(LeaveReviewDecisionInput input) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.rejectRequest(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged, addToAdminRequests: true);
      _notifyMutation();
      return merged;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<ForcedLeaveDeductionResult?> applyForcedLeaveDeduction(
    ForcedLeaveDeductionInput input,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.applyForcedLeaveDeduction(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _notifyMutation();
      return result;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<MonthlyLeaveAccrualResult?> runMonthlyAccrual(
    MonthlyLeaveAccrualInput input,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.runMonthlyAccrual(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      if (!input.dryRun) _notifyMutation();
      return result;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<YearEndForcedLeaveComplianceResult?> getYearEndForcedLeaveCompliance(
    int year,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.getYearEndForcedLeaveCompliance(year);
      return _isCurrentAuthGeneration(authGeneration) ? result : null;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<YearEndForcedLeaveApplyResult?> applyYearEndForcedLeaveDeductions(
    YearEndForcedLeaveApplyInput input,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.applyYearEndForcedLeaveDeductions(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      if (!input.dryRun) _notifyMutation();
      return result;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  /// Admin/HR: apply an audited correction without overwriting derived buckets.
  Future<LeaveBalance?> applyBalanceAdjustment({
    required String userId,
    required LeaveType leaveType,
    required double adjustmentDays,
    required String remarks,
    DateTime? asOfDate,
  }) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.applyBalanceAdjustment(
        userId: userId,
        leaveType: leaveType,
        adjustmentDays: adjustmentDays,
        remarks: remarks,
        asOfDate: asOfDate,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _notifyMutation();
      return saved;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> attachFile({
    required String requestId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.attachFile(
        requestId: requestId,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      invalidateCachedLeaveData();
      _selectedRequest = updated;
      _upsertRequest(updated);
      return updated;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> removeAttachment(String requestId) async {
    final authGeneration = _authGeneration;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.removeAttachment(requestId);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      invalidateCachedLeaveData();
      _selectedRequest = updated;
      _upsertRequest(updated);
      return updated;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  Future<List<int>?> getAttachmentBytes(String requestId) async {
    final authGeneration = _authGeneration;
    try {
      final bytes = await _repository.getAttachmentBytes(requestId);
      return _isCurrentAuthGeneration(authGeneration) ? bytes : null;
    } catch (error) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      rethrow;
    }
  }

  void _upsertRequest(
    LeaveRequest request, {
    bool addToMyRequests = false,
    bool addToAdminRequests = false,
    bool addToDepartmentHeadRequests = false,
  }) {
    void updateList(List<LeaveRequest> list, bool insert) {
      final index = list.indexWhere((r) => r.id == request.id);
      if (index >= 0) {
        list[index] = request;
      } else if (insert) {
        list.insert(0, request);
      }
    }

    updateList(_myRequests, addToMyRequests);
    updateList(_requests, addToAdminRequests);
    updateList(_departmentHeadRequests, addToDepartmentHeadRequests);
  }

  // ---- Department Head workflow ----

  /// Cache for the department-head check result.
  Map<String, dynamic>? _deptHeadCheck;
  Map<String, dynamic>? get deptHeadCheck => _deptHeadCheck;
  bool get isDeptHead => _deptHeadCheck?['isDeptHead'] == true;
  bool get hasDeptHeadHistory => _deptHeadCheck?['hasHistory'] == true;
  bool get canReviewPendingLeave =>
      _deptHeadCheck?['canReviewPending'] == true || isDeptHead;
  bool get canViewReviewHistory =>
      _deptHeadCheck?['canViewReviewHistory'] == true || hasDeptHeadHistory;

  /// Check if the current user is a department head.
  Future<bool> checkIsDepartmentHead({bool forceRefresh = false}) async {
    final authGeneration = _authGeneration;
    final cached = _deptHeadCheckCache;
    if (!forceRefresh && cached != null && cached.isFresh(_referenceCacheTtl)) {
      final cachedValue = Map<String, dynamic>.from(cached.value);
      final changed = !mapEquals(_deptHeadCheck, cachedValue);
      _deptHeadCheck = cachedValue;
      if (changed) {
        await Future<void>.delayed(Duration.zero);
        if (!_isCurrentAuthGeneration(authGeneration)) return false;
        notifyListeners();
      }
      return isDeptHead;
    }
    try {
      final check = await _repository.checkIsDepartmentHead();
      if (!_isCurrentAuthGeneration(authGeneration)) return false;
      _deptHeadCheck = check;
      _deptHeadCheckCache = _LeaveCacheEntry<Map<String, dynamic>>(
        Map<String, dynamic>.unmodifiable(_deptHeadCheck!),
        DateTime.now(),
      );
      notifyListeners();
      return isDeptHead;
    } catch (_) {
      if (!_isCurrentAuthGeneration(authGeneration)) return false;
      _deptHeadCheck = null;
      notifyListeners();
      return false;
    }
  }

  /// Load leave requests pending department head approval plus handled history.
  Future<void> loadDepartmentHeadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
    bool forceRefresh = false,
  }) => _loadReviewRequests(query: query, departmentHead: true);

  Future<LeaveRequest?> departmentHeadApprove(
    LeaveReviewDecisionInput input,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.departmentHeadApprove(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = updated;
      _upsertRequest(updated, addToDepartmentHeadRequests: true);
      _notifyMutation();
      return updated;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> departmentHeadReject(
    LeaveReviewDecisionInput input,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.departmentHeadReject(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = updated;
      _upsertRequest(updated, addToDepartmentHeadRequests: true);
      _notifyMutation();
      return updated;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  Future<LeaveRequest?> departmentHeadReturn(
    LeaveReviewDecisionInput input,
  ) async {
    final authGeneration = _authGeneration;
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.departmentHeadReturn(input);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _selectedRequest = updated;
      _upsertRequest(updated, addToDepartmentHeadRequests: true);
      _notifyMutation();
      return updated;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      if (_isCurrentAuthGeneration(authGeneration)) {
        _reviewing = false;
        notifyListeners();
      }
    }
  }

  /// Balance movement audit (does not mutate provider list state).
  Future<LeaveLedgerResult> fetchLeaveLedger(
    LeaveLedgerQuery query, {
    bool forceRefresh = false,
  }) async {
    final authGeneration = _authGeneration;
    final key = _ledgerKey(query);
    final cached = _ledgerCache[key];
    if (!forceRefresh && cached != null && cached.isFresh(_ledgerCacheTtl)) {
      final value = cached.value;
      return LeaveLedgerResult(
        total: value.total,
        limit: value.limit,
        offset: value.offset,
        rows: List<LeaveBalanceLedgerEntry>.from(value.rows),
        summaryEarned: value.summaryEarned,
        summaryUsed: value.summaryUsed,
        summaryPending: value.summaryPending,
        summaryAdjusted: value.summaryAdjusted,
      );
    }
    final fresh = await _repository.getLeaveLedger(query);
    if (!_isCurrentAuthGeneration(authGeneration)) {
      return LeaveLedgerResult(
        total: 0,
        limit: query.limit,
        offset: query.offset,
        rows: const [],
        summaryEarned: 0,
        summaryUsed: 0,
        summaryPending: 0,
        summaryAdjusted: 0,
      );
    }
    _ledgerCache[key] = _LeaveCacheEntry<LeaveLedgerResult>(
      LeaveLedgerResult(
        total: fresh.total,
        limit: fresh.limit,
        offset: fresh.offset,
        rows: List<LeaveBalanceLedgerEntry>.unmodifiable(fresh.rows),
        summaryEarned: fresh.summaryEarned,
        summaryUsed: fresh.summaryUsed,
        summaryPending: fresh.summaryPending,
        summaryAdjusted: fresh.summaryAdjusted,
      ),
      DateTime.now(),
    );
    return fresh;
  }
}
