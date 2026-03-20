import 'package:dio/dio.dart';

import '../api/client.dart';
import 'leave_repository.dart';
import 'models/leave_balance.dart';
import 'models/leave_request.dart';
import 'models/leave_type.dart';

class ApiLeaveRepository implements LeaveRepository {
  const ApiLeaveRepository();

  static Map<String, dynamic> _asMap(dynamic v) =>
      Map<String, dynamic>.from(v as Map);

  /// Extract backend error message from DioException for user-facing feedback.
  static String _messageFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    return e.message ?? 'Request failed';
  }

  static Map<String, dynamic> _toApiPayload(LeaveRequest request) {
    final json = request.toJson();
    // Backend expects leave_type as text name, and start/end dates in date-only string.
    json['leave_type'] = request.leaveType.value;
    return json;
  }

  @override
  Future<LeaveRequest> saveDraft(LeaveRequest request) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/leave/draft',
        data: _toApiPayload(request),
      );
      final data = res.data;
      if (data == null) throw Exception('No data returned');
      return LeaveRequest.fromJson(data);
    } on DioException catch (e) {
      throw Exception(_messageFromDio(e));
    }
  }

  @override
  Future<LeaveRequest> submitRequest(LeaveRequest request) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/leave/submit',
        data: _toApiPayload(request),
      );
      final data = res.data;
      if (data == null) throw Exception('No data returned');
      return LeaveRequest.fromJson(data);
    } on DioException catch (e) {
      throw Exception(_messageFromDio(e));
    }
  }

  @override
  Future<LeaveRequest> updateRequest(LeaveRequest request) async {
    final id = request.id;
    if (id == null || id.isEmpty) {
      throw Exception('Missing request id');
    }
    try {
      final res = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/leave/$id',
        data: _toApiPayload(request),
      );
      final data = res.data;
      if (data == null) throw Exception('No data returned');
      return LeaveRequest.fromJson(data);
    } on DioException catch (e) {
      throw Exception(_messageFromDio(e));
    }
  }

  @override
  Future<LeaveRequest?> getRequestById(String requestId) async {
    if (requestId.isEmpty) return null;
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/$requestId',
      );
      final data = res.data;
      if (data == null) return null;
      return LeaveRequest.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
  }) async {
    // userId is inferred from JWT on backend; we keep signature for compatibility.
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/leave/my',
      queryParameters: {
        if (status != null) 'status': status.value,
      },
    );
    final data = res.data ?? const [];
    return data.map((e) => LeaveRequest.fromJson(_asMap(e))).toList();
  }

  @override
  Future<List<LeaveRequest>> listRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) async {
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/leave',
      queryParameters: {
        if (query.status != null) 'status': query.status!.value,
        if (query.leaveType != null) 'leave_type': query.leaveType!.value,
        if (query.userId != null && query.userId!.isNotEmpty)
          'user_id': query.userId,
        if (query.limit != null) 'limit': query.limit,
      },
    );
    final data = res.data ?? const [];
    return data.map((e) => LeaveRequest.fromJson(_asMap(e))).toList();
  }

  @override
  Future<List<LeaveRequest>> listPendingRequests() async {
    final res = await ApiClient.instance.get<List<dynamic>>('/api/leave/pending');
    final data = res.data ?? const [];
    return data.map((e) => LeaveRequest.fromJson(_asMap(e))).toList();
  }

  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async {
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/leave/balances/$userId',
    );
    final data = res.data ?? const [];
    return data.map((e) => LeaveBalance.fromJson(_asMap(e))).toList();
  }

  @override
  Future<LeaveBalance?> getBalanceForUserByType(
    String userId,
    LeaveType leaveType,
  ) async {
    final balances = await getBalancesForUser(userId);
    try {
      return balances.firstWhere((b) => b.leaveType == leaveType);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LeaveBalance> upsertBalance(LeaveBalance balance) async {
    throw Exception('Balance upsert not implemented yet.');
  }

  @override
  Future<LeaveRequest> approveRequest(LeaveApprovalInput input) async {
    final res = await ApiClient.instance.patch<Map<String, dynamic>>(
      '/api/leave/${input.requestId}/approve',
      data: {
        'reviewer_remarks': input.hrRemarks,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('No data returned');
    return LeaveRequest.fromJson(data);
  }

  @override
  Future<LeaveRequest> returnRequest(LeaveReviewDecisionInput input) async {
    final res = await ApiClient.instance.patch<Map<String, dynamic>>(
      '/api/leave/${input.requestId}/return',
      data: {
        'reviewer_remarks': input.reason ?? input.hrRemarks,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('No data returned');
    return LeaveRequest.fromJson(data);
  }

  @override
  Future<LeaveRequest> rejectRequest(LeaveReviewDecisionInput input) async {
    final res = await ApiClient.instance.patch<Map<String, dynamic>>(
      '/api/leave/${input.requestId}/reject',
      data: {
        'reviewer_remarks': input.reason ?? input.hrRemarks,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('No data returned');
    return LeaveRequest.fromJson(data);
  }

  @override
  Future<LeaveRequest> cancelRequest({
    required String requestId,
    required String userId,
    String? reason,
  }) async {
    // userId is inferred from JWT on backend; keep signature for compatibility.
    final res = await ApiClient.instance.patch<Map<String, dynamic>>(
      '/api/leave/$requestId/cancel',
      data: {
        if (reason != null) 'reason': reason,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('No data returned');
    return LeaveRequest.fromJson(data);
  }

  @override
  Future<LeaveRequest> attachFile({
    required String requestId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    throw Exception('Leave attachments not implemented yet.');
  }

  @override
  Future<LeaveRequest> removeAttachment(String requestId) async {
    throw Exception('Leave attachments not implemented yet.');
  }
}

