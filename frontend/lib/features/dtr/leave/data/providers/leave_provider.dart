import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

/// All balances returned by the backend are now shown.
/// Annual-quota types (SPL, MFL, Paternity, etc.) are computed server-side.
List<LeaveBalance> _filterDisplayBalances(List<LeaveBalance> raw) {
  // Only exclude `others` and custom admin types with no meaningful quota.
  return raw.where((b) => b.effectiveLeaveTypeName != 'others').toList();
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
  List<LeaveBalance> _balances = [];
  LeaveRequest? _selectedRequest;
  static const Duration _requestCacheTtl = Duration(seconds: 30);
  static const Duration _balanceCacheTtl = Duration(seconds: 60);
  static const Duration _ledgerCacheTtl = Duration(seconds: 60);
  static const Duration _referenceCacheTtl = Duration(minutes: 5);
  final Map<String, _LeaveCacheEntry<List<LeaveRequest>>> _requestCache = {};
  final Map<String, _LeaveCacheEntry<List<LeaveBalance>>> _balanceCache = {};
  final Map<String, _LeaveCacheEntry<LeaveLedgerResult>> _ledgerCache = {};
  _LeaveCacheEntry<Map<String, dynamic>>? _deptHeadCheckCache;

  bool _loading = false;
  bool _submitting = false;
  bool _reviewing = false;
  String? _error;

  LeaveRequestStatus? _filterStatus;
  LeaveType? _filterLeaveType;

  List<LeaveRequest> get requests => List.unmodifiable(_requests);
  List<LeaveBalance> get balances => List.unmodifiable(_balances);
  LeaveRequest? get selectedRequest => _selectedRequest;

  bool get loading => _loading;
  bool get submitting => _submitting;
  bool get reviewing => _reviewing;
  String? get error => _error;

  LeaveRequestStatus? get filterStatus => _filterStatus;
  LeaveType? get filterLeaveType => _filterLeaveType;

  List<LeaveRequest> get pendingRequests =>
      _requests.where((r) => r.status.isPending).toList();

  List<LeaveRequest> get approvedRequests =>
      _requests.where((r) => r.status == LeaveRequestStatus.approved).toList();

  List<LeaveRequest> get upcomingApprovedRequests {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
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

  void clearSelection() {
    _selectedRequest = null;
    notifyListeners();
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
      query.status?.value ?? '',
      _normalize(query.leaveTypeName) ?? query.leaveType?.value ?? '',
      _dateOnlyKey(query.startDateFrom),
      _dateOnlyKey(query.startDateTo),
      _dateTimeKey(query.createdFrom),
      _dateTimeKey(query.createdTo),
      query.limit?.toString() ?? '',
    ].join('|');
  }

  static String _myRequestsKey(String userId, LeaveRequestStatus? status) {
    return ['my', _normalize(userId) ?? '', status?.value ?? ''].join('|');
  }

  static String _ledgerKey(LeaveLedgerQuery query) {
    return [
      _normalize(query.userId) ?? '',
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
    _balanceCache.clear();
    _ledgerCache.clear();
    _deptHeadCheckCache = null;
    _deptHeadCheck = null;
    if (notify) notifyListeners();
  }

  /// Called by the proxy provider whenever [AuthProvider] changes.
  /// Flushes all caches when the authenticated user switches so stale
  /// department-head status (and balances/requests) from a previous session
  /// can never bleed into the new user's view.
  String? _lastKnownUserId;
  void onAuthUserChanged(String? newUserId) {
    if (_lastKnownUserId != null && _lastKnownUserId != newUserId) {
      invalidateCachedLeaveData(notify: false);
    }
    _lastKnownUserId = newUserId;
  }

  Future<List<LeaveRequest>> _getMyRequestsCached(
    String userId, {
    LeaveRequestStatus? status,
    bool forceRefresh = false,
  }) async {
    final key = _myRequestsKey(userId, status);
    final cached = forceRefresh
        ? null
        : _readListCache(_requestCache, key, _requestCacheTtl);
    if (cached != null) return cached;
    final fresh = await _repository.listMyRequests(userId, status: status);
    _writeListCache(_requestCache, key, fresh);
    return List<LeaveRequest>.from(fresh);
  }

  Future<List<LeaveBalance>> _getBalancesForUserCached(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final key = _normalize(userId);
    if (key == null) return const <LeaveBalance>[];
    final cached = forceRefresh
        ? null
        : _readListCache(_balanceCache, key, _balanceCacheTtl);
    if (cached != null) return cached;
    final fresh = await _repository.getBalancesForUser(key);
    _writeListCache(_balanceCache, key, fresh);
    return List<LeaveBalance>.from(fresh);
  }

  /// Fetches leave balances for a user (e.g. for admin approval dialog).
  Future<List<LeaveBalance>> fetchBalancesForUser(
    String userId, {
    bool forceRefresh = false,
  }) async {
    try {
      return await _getBalancesForUserCached(
        userId,
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> loadMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    bool forceRefresh = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _requests = await _getMyRequestsCached(
        userId,
        status: status,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      _requests = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
    bool forceRefresh = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _filterStatus = query.status;
      _filterLeaveType = query.leaveType;
      final key = _requestQueryKey('admin', query);
      final cached = forceRefresh
          ? null
          : _readListCache(_requestCache, key, _requestCacheTtl);
      if (cached != null) {
        _requests = cached;
      } else {
        final fresh = await _repository.listRequests(query: query);
        _writeListCache(_requestCache, key, fresh);
        _requests = List<LeaveRequest>.from(fresh);
      }
    } catch (e) {
      // Keep the currently displayed queue if a background refresh fails.
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadPendingRequests({bool forceRefresh = false}) async {
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
        _writeListCache(_requestCache, key, fresh);
        _requests = List<LeaveRequest>.from(fresh);
      }
    } catch (e) {
      _requests = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadBalances(String userId, {bool forceRefresh = false}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _getBalancesForUserCached(
        userId,
        forceRefresh: forceRefresh,
      );
      _balances = _filterDisplayBalances(raw);
    } catch (e) {
      _balances = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadMyLeaveData(
    String userId, {
    bool forceRefresh = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final requestsFuture = _getMyRequestsCached(
        userId,
        status: _filterStatus,
        forceRefresh: forceRefresh,
      );
      final balancesFuture = _getBalancesForUserCached(
        userId,
        forceRefresh: forceRefresh,
      );
      final results = await Future.wait([requestsFuture, balancesFuture]);
      _requests = results[0] as List<LeaveRequest>;
      _balances = _filterDisplayBalances(results[1] as List<LeaveBalance>);
    } catch (e) {
      _requests = [];
      _balances = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<LeaveRequest?> loadRequestById(String requestId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _selectedRequest = await _repository.getRequestById(requestId);
      return _selectedRequest;
    } catch (e) {
      _selectedRequest = null;
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refetches a request by ID without setting loading state (e.g. for admin
  /// to get latest attachment). Updates _selectedRequest and upserts into list.
  Future<LeaveRequest?> refreshRequestById(String requestId) async {
    try {
      final fresh = await _repository.getRequestById(requestId);
      if (fresh != null) {
        _selectedRequest = fresh;
        _upsertRequest(fresh);
        notifyListeners();
      }
      return fresh;
    } catch (_) {
      return null;
    }
  }

  Future<LeaveRequest?> saveDraft(LeaveRequest request) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.saveDraft(request);
      invalidateCachedLeaveData();
      _selectedRequest = saved;
      _upsertRequest(saved);
      return saved;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> submitRequest(LeaveRequest request) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.submitRequest(request);
      _selectedRequest = saved;
      _upsertRequest(saved);
      _notifyMutation();
      return saved;
    } catch (e) {
      _error =
          e is Exception &&
              e.toString().replaceFirst('Exception: ', '').isNotEmpty
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> submitRequestWithAttachment({
    required LeaveRequest request,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.submitRequestWithAttachment(
        request: request,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      _selectedRequest = saved;
      _upsertRequest(saved);
      _notifyMutation();
      return saved;
    } catch (e) {
      _error =
          e is Exception &&
              e.toString().replaceFirst('Exception: ', '').isNotEmpty
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> updateRequest(LeaveRequest request) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.updateRequest(request);
      _selectedRequest = saved;
      _upsertRequest(saved);
      _notifyMutation();
      return saved;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> cancelRequest({
    required String requestId,
    required String userId,
    String? reason,
  }) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.cancelRequest(
        requestId: requestId,
        userId: userId,
        reason: reason,
      );
      _selectedRequest = updated;
      _upsertRequest(updated);
      _notifyMutation();
      return updated;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> approveRequest(LeaveApprovalInput input) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.approveRequest(input);
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged);
      _notifyMutation();
      return merged;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  /// #15: Revoke approval — reverses balance deduction + clears DTR entries.
  Future<LeaveRequest?> revokeApproval(LeaveReviewDecisionInput input) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.revokeApproval(input);
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged);
      _notifyMutation();
      return merged;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> returnRequest(LeaveReviewDecisionInput input) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.returnRequest(input);
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged);
      _notifyMutation();
      return merged;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> rejectRequest(LeaveReviewDecisionInput input) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.rejectRequest(input);
      final merged = updated.copyWith(
        reviewerName: updated.reviewerName ?? input.reviewerName,
        reviewerRole: updated.reviewerRole ?? input.reviewerRole,
        reviewerTitle: updated.reviewerTitle ?? input.reviewerTitle,
      );
      _selectedRequest = merged;
      _upsertRequest(merged);
      _notifyMutation();
      return merged;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<ForcedLeaveDeductionResult?> applyForcedLeaveDeduction(
    ForcedLeaveDeductionInput input,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.applyForcedLeaveDeduction(input);
      _notifyMutation();
      return result;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<MonthlyLeaveAccrualResult?> runMonthlyAccrual(
    MonthlyLeaveAccrualInput input,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.runMonthlyAccrual(input);
      if (!input.dryRun) _notifyMutation();
      return result;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<YearEndForcedLeaveComplianceResult?> getYearEndForcedLeaveCompliance(
    int year,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      return await _repository.getYearEndForcedLeaveCompliance(year);
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<YearEndForcedLeaveApplyResult?> applyYearEndForcedLeaveDeductions(
    YearEndForcedLeaveApplyInput input,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.applyYearEndForcedLeaveDeductions(input);
      if (!input.dryRun) _notifyMutation();
      return result;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  /// Admin/HR: create or overwrite one [LeaveBalance] row for an employee.
  Future<LeaveBalance?> upsertBalance(
    LeaveBalance balance, {
    String? remarks,
  }) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.upsertBalance(balance, remarks: remarks);
      _notifyMutation();
      return saved;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> attachFile({
    required String requestId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.attachFile(
        requestId: requestId,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      invalidateCachedLeaveData();
      _selectedRequest = updated;
      _upsertRequest(updated);
      return updated;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> removeAttachment(String requestId) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.removeAttachment(requestId);
      invalidateCachedLeaveData();
      _selectedRequest = updated;
      _upsertRequest(updated);
      return updated;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<List<int>?> getAttachmentBytes(String requestId) async {
    try {
      return await _repository.getAttachmentBytes(requestId);
    } catch (_) {
      return null;
    }
  }

  void _upsertRequest(LeaveRequest request) {
    final index = _requests.indexWhere((r) => r.id == request.id);
    if (index >= 0) {
      _requests[index] = request;
    } else {
      _requests = [request, ..._requests];
    }
  }

  // ---- Department Head workflow ----

  /// Cache for the department-head check result.
  Map<String, dynamic>? _deptHeadCheck;
  Map<String, dynamic>? get deptHeadCheck => _deptHeadCheck;
  bool get isDeptHead => _deptHeadCheck?['isDeptHead'] == true;

  /// Check if the current user is a department head.
  Future<bool> checkIsDepartmentHead({bool forceRefresh = false}) async {
    final cached = _deptHeadCheckCache;
    if (!forceRefresh && cached != null && cached.isFresh(_referenceCacheTtl)) {
      final cachedValue = Map<String, dynamic>.from(cached.value);
      final changed = !mapEquals(_deptHeadCheck, cachedValue);
      _deptHeadCheck = cachedValue;
      if (changed) {
        await Future<void>.delayed(Duration.zero);
        notifyListeners();
      }
      return isDeptHead;
    }
    try {
      _deptHeadCheck = await _repository.checkIsDepartmentHead();
      _deptHeadCheckCache = _LeaveCacheEntry<Map<String, dynamic>>(
        Map<String, dynamic>.unmodifiable(_deptHeadCheck!),
        DateTime.now(),
      );
      notifyListeners();
      return isDeptHead;
    } catch (_) {
      _deptHeadCheck = null;
      notifyListeners();
      return false;
    }
  }

  /// Load leave requests pending department head approval plus handled history.
  Future<void> loadDepartmentHeadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
    bool forceRefresh = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _filterStatus = query.status;
      _filterLeaveType = query.leaveType;
      final key = _requestQueryKey('department-head', query);
      final cached = forceRefresh
          ? null
          : _readListCache(_requestCache, key, _requestCacheTtl);
      if (cached != null) {
        _requests = cached;
      } else {
        final fresh = await _repository.listDepartmentHeadRequests(
          query: query,
        );
        _writeListCache(_requestCache, key, fresh);
        _requests = List<LeaveRequest>.from(fresh);
      }
    } catch (e) {
      // Keep the currently displayed queue if a background refresh fails.
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> departmentHeadApprove(
    LeaveReviewDecisionInput input,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.departmentHeadApprove(input);
      _selectedRequest = updated;
      _upsertRequest(updated);
      _notifyMutation();
      return updated;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> departmentHeadReject(
    LeaveReviewDecisionInput input,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.departmentHeadReject(input);
      _selectedRequest = updated;
      _upsertRequest(updated);
      _notifyMutation();
      return updated;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  Future<LeaveRequest?> departmentHeadReturn(
    LeaveReviewDecisionInput input,
  ) async {
    _reviewing = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _repository.departmentHeadReturn(input);
      _selectedRequest = updated;
      _upsertRequest(updated);
      _notifyMutation();
      return updated;
    } catch (e) {
      _error = e is Exception && e.toString().startsWith('Exception: ')
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return null;
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  /// Balance movement audit (does not mutate provider list state).
  Future<LeaveLedgerResult> fetchLeaveLedger(
    LeaveLedgerQuery query, {
    bool forceRefresh = false,
  }) async {
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
      );
    }
    final fresh = await _repository.getLeaveLedger(query);
    _ledgerCache[key] = _LeaveCacheEntry<LeaveLedgerResult>(
      LeaveLedgerResult(
        total: fresh.total,
        limit: fresh.limit,
        offset: fresh.offset,
        rows: List<LeaveBalanceLedgerEntry>.unmodifiable(fresh.rows),
        summaryEarned: fresh.summaryEarned,
        summaryUsed: fresh.summaryUsed,
        summaryPending: fresh.summaryPending,
      ),
      DateTime.now(),
    );
    return fresh;
  }
}
