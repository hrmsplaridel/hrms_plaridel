import 'leave_repository.dart';
import 'models/leave_balance.dart';
import 'models/leave_request.dart';
import 'models/leave_type.dart';

/// Temporary in-memory repository for local UI integration.
///
/// This keeps the leave module functional while the real backend is still
/// undecided. Replace this later with a Supabase or API-backed implementation.
class MockLeaveRepository implements LeaveRepository {
  final List<LeaveRequest> _requests = [];
  final Map<String, List<LeaveBalance>> _balancesByUser = {};
  int _requestCounter = 0;

  @override
  Future<LeaveRequest> saveDraft(LeaveRequest request) async {
    final now = DateTime.now();
    final old = _getRequestByIdInternal(request.id);
    final saved = request.copyWith(
      id: request.id ?? _nextRequestId(),
      status: LeaveRequestStatus.draft,
      dateFiled: request.dateFiled ?? now,
      createdAt: request.createdAt ?? now,
      updatedAt: now,
    );
    _upsertRequest(saved);
    _reconcilePendingEffect(old: old, updated: saved);
    return saved;
  }

  @override
  Future<LeaveRequest> submitRequest(LeaveRequest request) async {
    final now = DateTime.now();
    final old = _getRequestByIdInternal(request.id);
    final saved = request.copyWith(
      id: request.id ?? _nextRequestId(),
      status: LeaveRequestStatus.pending,
      dateFiled: request.dateFiled ?? now,
      createdAt: request.createdAt ?? now,
      updatedAt: now,
    );
    _upsertRequest(saved);
    _ensureDefaultBalances(saved.userId);
    _reconcilePendingEffect(old: old, updated: saved);
    return saved;
  }

  @override
  Future<LeaveRequest> updateRequest(LeaveRequest request) async {
    final old = _getRequestByIdInternal(request.id);
    final saved = request.copyWith(updatedAt: DateTime.now());
    _upsertRequest(saved);
    _ensureDefaultBalances(saved.userId);
    _reconcilePendingEffect(old: old, updated: saved);
    return saved;
  }

  @override
  Future<LeaveRequest?> getRequestById(String requestId) async {
    return _getRequestByIdInternal(requestId);
  }

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  }) async {
    var results = _sortedRequests(
      _requests.where((r) {
        if (r.userId != userId) return false;
        if (status != null && r.status != status) return false;
        return true;
      }).toList(),
    );
    if (limit != null && limit > 0 && results.length > limit) {
      results = results.take(limit).toList();
    }
    return results;
  }

  @override
  Future<List<LeaveRequest>> listRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) async {
    var results = _requests.where((r) {
      if (query.userId != null && r.userId != query.userId) return false;
      if (query.status != null && r.status != query.status) return false;
      if (query.leaveType != null && r.leaveType != query.leaveType) {
        return false;
      }
      if (query.startDateFrom != null &&
          (r.startDate == null ||
              r.startDate!.isBefore(query.startDateFrom!))) {
        return false;
      }
      if (query.startDateTo != null &&
          (r.startDate == null || r.startDate!.isAfter(query.startDateTo!))) {
        return false;
      }
      if (query.createdFrom != null &&
          (r.createdAt == null || r.createdAt!.isBefore(query.createdFrom!))) {
        return false;
      }
      if (query.createdTo != null &&
          (r.createdAt == null || r.createdAt!.isAfter(query.createdTo!))) {
        return false;
      }
      return true;
    }).toList();

    results = _sortedRequests(results);
    if (query.limit != null &&
        query.limit! > 0 &&
        results.length > query.limit!) {
      results = results.take(query.limit!).toList();
    }
    return results;
  }

  @override
  Future<List<LeaveRequest>> listPendingRequests() async {
    return _sortedRequests(
      _requests.where((r) => r.status == LeaveRequestStatus.pending).toList(),
    );
  }

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async {
    _ensureDefaultBalances(userId);
    final list = _balancesByUser[userId] ?? const <LeaveBalance>[];
    return List<LeaveBalance>.from(list)..sort(
      (a, b) => a.leaveType.displayName.compareTo(b.leaveType.displayName),
    );
  }

  @override
  Future<LeaveBalance?> getBalanceForUserByType(
    String userId,
    LeaveType leaveType,
  ) async {
    _ensureDefaultBalances(userId);
    try {
      return (_balancesByUser[userId] ?? const <LeaveBalance>[]).firstWhere(
        (b) => b.leaveType == leaveType,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LeaveBalance> upsertBalance(LeaveBalance balance) async {
    _ensureDefaultBalances(balance.userId);
    final list = _balancesByUser.putIfAbsent(balance.userId, () => []);
    final index = list.indexWhere((b) => b.leaveType == balance.leaveType);
    final saved = balance.copyWith(
      id: balance.id ?? 'balance_${balance.userId}_${balance.leaveType.value}',
      updatedAt: DateTime.now(),
      createdAt: balance.createdAt ?? DateTime.now(),
    );
    if (index >= 0) {
      list[index] = saved;
    } else {
      list.add(saved);
    }
    return saved;
  }

  @override
  Future<LeaveRequest> approveRequest(LeaveApprovalInput input) async {
    final old = _requireRequest(input.requestId);
    final approved = old.copyWith(
      status: LeaveRequestStatus.approved,
      reviewerId: input.reviewerId,
      reviewerName: input.reviewerName,
      reviewerRole: input.reviewerRole,
      reviewerTitle: input.reviewerTitle,
      hrRemarks: input.hrRemarks,
      recommendationRemarks: input.recommendationRemarks,
      approvedDaysWithPay:
          input.approvedDaysWithPay ??
          old.approvedDaysWithPay ??
          old.workingDaysApplied,
      approvedDaysWithoutPay:
          input.approvedDaysWithoutPay ?? old.approvedDaysWithoutPay,
      approvedOtherDetails:
          input.approvedOtherDetails ?? old.approvedOtherDetails,
      reviewedAt: input.reviewedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _upsertRequest(approved);
    _ensureDefaultBalances(approved.userId);
    _reconcilePendingEffect(old: old, updated: approved);

    final daysWithPay = approved.approvedDaysWithPay ?? 0;
    if (daysWithPay > 0) {
      _adjustUsedDays(approved.userId, approved.leaveType, daysWithPay);
    }
    return approved;
  }

  /// #15: Revoke an approved leave (mock: restores used_days).
  @override
  Future<LeaveRequest> revokeApproval(LeaveReviewDecisionInput input) async {
    final old = _requireRequest(input.requestId);
    final revoked = old.copyWith(
      status: LeaveRequestStatus.returned,
      reviewerId: input.reviewerId,
      reviewerName: input.reviewerName,
      reviewerRole: input.reviewerRole,
      reviewerTitle: input.reviewerTitle,
      hrRemarks: input.hrRemarks ?? 'Approval revoked.',
      disapprovalReason: input.reason,
      reviewedAt: input.reviewedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _upsertRequest(revoked);
    // Restore used_days in mock balance.
    final daysWithPay = old.approvedDaysWithPay ?? old.workingDaysApplied ?? 0;
    if (daysWithPay > 0) {
      _adjustUsedDays(revoked.userId, revoked.leaveType, -daysWithPay);
    }
    return revoked;
  }

  @override
  Future<LeaveRequest> returnRequest(LeaveReviewDecisionInput input) async {
    final old = _requireRequest(input.requestId);
    final updated = old.copyWith(
      status: LeaveRequestStatus.returned,
      reviewerId: input.reviewerId,
      reviewerName: input.reviewerName,
      reviewerRole: input.reviewerRole,
      reviewerTitle: input.reviewerTitle,
      hrRemarks: input.hrRemarks,
      disapprovalReason: input.reason,
      reviewedAt: input.reviewedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _upsertRequest(updated);
    _reconcilePendingEffect(old: old, updated: updated);
    return updated;
  }

  @override
  Future<LeaveRequest> rejectRequest(LeaveReviewDecisionInput input) async {
    final old = _requireRequest(input.requestId);
    final updated = old.copyWith(
      status: LeaveRequestStatus.rejected,
      reviewerId: input.reviewerId,
      reviewerName: input.reviewerName,
      reviewerRole: input.reviewerRole,
      reviewerTitle: input.reviewerTitle,
      hrRemarks: input.hrRemarks,
      disapprovalReason: input.reason,
      reviewedAt: input.reviewedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _upsertRequest(updated);
    _reconcilePendingEffect(old: old, updated: updated);
    return updated;
  }

  @override
  Future<LeaveRequest> cancelRequest({
    required String requestId,
    required String userId,
    String? reason,
  }) async {
    final old = _requireRequest(requestId);
    if (old.userId != userId) {
      throw Exception('You can only cancel your own leave request.');
    }
    final updated = old.copyWith(
      status: LeaveRequestStatus.cancelled,
      disapprovalReason: reason,
      updatedAt: DateTime.now(),
    );
    _upsertRequest(updated);
    _reconcilePendingEffect(old: old, updated: updated);
    return updated;
  }

  @override
  Future<LeaveRequest> attachFile({
    required String requestId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final old = _requireRequest(requestId);
    final updated = old.copyWith(
      attachmentName: fileName,
      attachmentPath:
          'mock://${LeaveRequest.storageBucket}/$requestId/$fileName',
      updatedAt: DateTime.now(),
    );
    _upsertRequest(updated);
    return updated;
  }

  @override
  Future<LeaveRequest> removeAttachment(String requestId) async {
    final old = _requireRequest(requestId);
    final updated = old.copyWith(
      attachmentName: null,
      attachmentPath: null,
      updatedAt: DateTime.now(),
    );
    _upsertRequest(updated);
    return updated;
  }

  @override
  Future<List<int>?> getAttachmentBytes(String requestId) async => null;

  String _nextRequestId() {
    _requestCounter += 1;
    return 'leave_${DateTime.now().millisecondsSinceEpoch}_$_requestCounter';
  }

  LeaveRequest? _getRequestByIdInternal(String? requestId) {
    if (requestId == null || requestId.isEmpty) return null;
    try {
      return _requests.firstWhere((r) => r.id == requestId);
    } catch (_) {
      return null;
    }
  }

  LeaveRequest _requireRequest(String requestId) {
    final request = _getRequestByIdInternal(requestId);
    if (request == null) {
      throw Exception('Leave request not found.');
    }
    return request;
  }

  void _upsertRequest(LeaveRequest request) {
    final index = _requests.indexWhere((r) => r.id == request.id);
    if (index >= 0) {
      _requests[index] = request;
    } else {
      _requests.add(request);
    }
  }

  List<LeaveRequest> _sortedRequests(List<LeaveRequest> requests) {
    requests.sort((a, b) {
      final aTime = a.updatedAt ?? a.createdAt ?? a.dateFiled ?? DateTime(1970);
      final bTime = b.updatedAt ?? b.createdAt ?? b.dateFiled ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return requests;
  }

  void _ensureDefaultBalances(String userId) {
    _balancesByUser.putIfAbsent(userId, () {
      final now = DateTime.now();
      return LeaveType.values
          .map(
            (type) => LeaveBalance(
              id: 'balance_${userId}_${type.value}',
              userId: userId,
              leaveType: type,
              earnedDays: switch (type) {
                LeaveType.vacationLeave => 15,
                LeaveType.sickLeave => 15,
                LeaveType.specialPrivilegeLeave => 3,
                _ => 0,
              },
              usedDays: 0,
              pendingDays: 0,
              adjustedDays: 0,
              asOfDate: now,
              lastAccrualDate: now,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList();
    });
  }

  void _reconcilePendingEffect({
    required LeaveRequest? old,
    required LeaveRequest updated,
  }) {
    final oldPending = old?.status == LeaveRequestStatus.pending
        ? (old?.workingDaysApplied ?? 0)
        : 0.0;
    final newPending = updated.status == LeaveRequestStatus.pending
        ? (updated.workingDaysApplied ?? 0)
        : 0.0;

    final oldType = old?.leaveType;
    final newType = updated.leaveType;

    if (oldType != null && oldPending > 0) {
      _adjustPendingDays(updated.userId, oldType, -oldPending);
    }
    if (newPending > 0) {
      _adjustPendingDays(updated.userId, newType, newPending);
    }
  }

  void _adjustPendingDays(String userId, LeaveType leaveType, double delta) {
    if (delta == 0) return;
    _ensureDefaultBalances(userId);
    final list = _balancesByUser[userId]!;
    final index = list.indexWhere((b) => b.leaveType == leaveType);
    if (index < 0) return;
    final current = list[index];
    final next = current.pendingDays + delta;
    list[index] = current.copyWith(
      pendingDays: next < 0 ? 0 : next,
      updatedAt: DateTime.now(),
    );
  }

  void _adjustUsedDays(String userId, LeaveType leaveType, double delta) {
    if (delta == 0) return;
    _ensureDefaultBalances(userId);
    final list = _balancesByUser[userId]!;
    final index = list.indexWhere((b) => b.leaveType == leaveType);
    if (index < 0) return;
    final current = list[index];
    final next = current.usedDays + delta;
    list[index] = current.copyWith(
      usedDays: next < 0 ? 0 : next,
      updatedAt: DateTime.now(),
    );
  }
}
