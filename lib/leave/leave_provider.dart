import 'package:flutter/foundation.dart';

import 'leave_repository.dart';
import 'models/leave_balance.dart';
import 'models/leave_request.dart';
import 'models/leave_type.dart';

/// State management for the leave module.
///
/// The provider depends only on the [LeaveRepository] contract, so the UI can
/// stay unchanged if the backend later switches from Supabase to a custom API.
class LeaveProvider extends ChangeNotifier {
  LeaveProvider({required LeaveRepository repository})
    : _repository = repository;

  final LeaveRepository _repository;
  LeaveRepository get repository => _repository;

  List<LeaveRequest> _requests = [];
  List<LeaveBalance> _balances = [];
  LeaveRequest? _selectedRequest;

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
      _requests.where((r) => r.status == LeaveRequestStatus.pending).toList();

  List<LeaveRequest> get approvedRequests =>
      _requests.where((r) => r.status == LeaveRequestStatus.approved).toList();

  List<LeaveRequest> get upcomingApprovedRequests {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return approvedRequests
        .where(
          (r) => r.startDate != null && !r.startDate!.isBefore(startOfToday),
        )
        .toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
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
      return _balances.firstWhere((b) => b.leaveType == leaveType);
    } catch (_) {
      return null;
    }
  }

  /// Fetches leave balances for a user (e.g. for admin approval dialog).
  Future<List<LeaveBalance>> fetchBalancesForUser(String userId) async {
    try {
      return await _repository.getBalancesForUser(userId);
    } catch (_) {
      return [];
    }
  }

  Future<void> loadMyRequests(
    String userId, {
    LeaveRequestStatus? status,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _requests = await _repository.listMyRequests(userId, status: status);
    } catch (e) {
      _requests = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _filterStatus = query.status;
      _filterLeaveType = query.leaveType;
      _requests = await _repository.listRequests(query: query);
    } catch (e) {
      _requests = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadPendingRequests() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _filterStatus = LeaveRequestStatus.pending;
      _requests = await _repository.listPendingRequests();
    } catch (e) {
      _requests = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadBalances(String userId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _balances = await _repository.getBalancesForUser(userId);
    } catch (e) {
      _balances = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadMyLeaveData(String userId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final requestsFuture = _repository.listMyRequests(
        userId,
        status: _filterStatus,
      );
      final balancesFuture = _repository.getBalancesForUser(userId);
      final results = await Future.wait([requestsFuture, balancesFuture]);
      _requests = results[0] as List<LeaveRequest>;
      _balances = results[1] as List<LeaveBalance>;
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
      return merged;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _reviewing = false;
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
}
