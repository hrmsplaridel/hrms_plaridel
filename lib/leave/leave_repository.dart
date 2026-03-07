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
}
