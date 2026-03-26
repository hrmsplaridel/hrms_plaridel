import 'models/leave_balance.dart';
import 'models/leave_request.dart';
import 'models/leave_type.dart';

/// Query options for listing leave requests.
class LeaveRequestQuery {
  const LeaveRequestQuery({
    this.userId,
    this.status,
    this.leaveType,
    this.startDateFrom,
    this.startDateTo,
    this.createdFrom,
    this.createdTo,
    this.limit,
  });

  final String? userId;
  final LeaveRequestStatus? status;
  final LeaveType? leaveType;
  final DateTime? startDateFrom;
  final DateTime? startDateTo;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final int? limit;

  /// Convert to URL query-param map for the API layer.
  Map<String, dynamic> toQueryParams() => {
    if (status != null) 'status': status!.value,
    if (leaveType != null) 'leave_type': leaveType!.value,
    if (userId != null && userId!.isNotEmpty) 'user_id': userId,
    if (limit != null) 'limit': limit,
    if (startDateFrom != null)
      'start_date_from': _toDateStr(startDateFrom!),
    if (startDateTo != null) 'start_date_to': _toDateStr(startDateTo!),
    if (createdFrom != null) 'created_from': createdFrom!.toIso8601String(),
    if (createdTo != null) 'created_to': createdTo!.toIso8601String(),
  };

  static String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Approval payload used by HR/admin actions.
class LeaveApprovalInput {
  const LeaveApprovalInput({
    required this.requestId,
    required this.reviewerId,
    this.reviewerName,
    this.hrRemarks,
    this.recommendationRemarks,
    this.approvedDaysWithPay,
    this.approvedDaysWithoutPay,
    this.approvedOtherDetails,
    this.reviewedAt,
  });

  final String requestId;
  final String reviewerId;
  final String? reviewerName;
  final String? hrRemarks;
  final String? recommendationRemarks;
  final double? approvedDaysWithPay;
  final double? approvedDaysWithoutPay;
  final String? approvedOtherDetails;
  final DateTime? reviewedAt;
}

/// Return/reject payload used by HR/admin actions.
class LeaveReviewDecisionInput {
  const LeaveReviewDecisionInput({
    required this.requestId,
    required this.reviewerId,
    this.reviewerName,
    this.hrRemarks,
    this.reason,
    this.reviewedAt,
  });

  final String requestId;
  final String reviewerId;
  final String? reviewerName;
  final String? hrRemarks;
  final String? reason;
  final DateTime? reviewedAt;
}

/// Backend-neutral contract for leave data access.
///
/// Implement this with:
/// - Supabase
/// - REST/GraphQL API backed by PostgreSQL
/// - local/mock storage for testing
abstract class LeaveRepository {
  const LeaveRepository();

  /// Create a new draft request or update an existing draft.
  Future<LeaveRequest> saveDraft(LeaveRequest request);

  /// Submit a leave request for HR/admin review.
  Future<LeaveRequest> submitRequest(LeaveRequest request);

  /// Update an editable request before final review.
  Future<LeaveRequest> updateRequest(LeaveRequest request);

  /// Get one request by id.
  Future<LeaveRequest?> getRequestById(String requestId);

  /// Employee-facing request list.
  Future<List<LeaveRequest>> listMyRequests(
    String userId, {
    LeaveRequestStatus? status,
    int? limit,
  });

  /// General request listing for admin tables/reports.
  Future<List<LeaveRequest>> listRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  });

  /// Pending requests awaiting review.
  Future<List<LeaveRequest>> listPendingRequests();

  /// Employee-facing balances for all supported leave types.
  Future<List<LeaveBalance>> getBalancesForUser(String userId);

  /// One specific leave type balance for validation or summaries.
  Future<LeaveBalance?> getBalanceForUserByType(
    String userId,
    LeaveType leaveType,
  );

  /// Create or update a balance record.
  Future<LeaveBalance> upsertBalance(LeaveBalance balance);

  /// Approve a request and apply any balance changes required by policy.
  Future<LeaveRequest> approveRequest(LeaveApprovalInput input);

  /// Revoke a previously approved leave request (Admin only).
  /// Restores the used_days balance and cleans up DTR on_leave rows.
  Future<LeaveRequest> revokeApproval(LeaveReviewDecisionInput input);

  /// Send a request back to the employee for correction.
  Future<LeaveRequest> returnRequest(LeaveReviewDecisionInput input);

  /// Reject a request.
  Future<LeaveRequest> rejectRequest(LeaveReviewDecisionInput input);

  /// Cancel a request from the employee side.
  Future<LeaveRequest> cancelRequest({
    required String requestId,
    required String userId,
    String? reason,
  });

  /// Optional hook for uploading a supporting attachment.
  ///
  /// Kept backend-neutral by accepting raw bytes and a filename.
  Future<LeaveRequest> attachFile({
    required String requestId,
    required List<int> fileBytes,
    required String fileName,
  });

  /// Optional hook for removing a supporting attachment.
  Future<LeaveRequest> removeAttachment(String requestId);

  /// Fetch attachment bytes for viewing/downloading. Returns null if none or not supported.
  Future<List<int>?> getAttachmentBytes(String requestId) => Future.value(null);
}
