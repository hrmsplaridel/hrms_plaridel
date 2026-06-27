import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

/// Query options for listing leave requests.
class LeaveRequestQuery {
  const LeaveRequestQuery({
    this.userId,
    this.status,
    this.leaveType,
    this.leaveTypeName,
    this.startDateFrom,
    this.startDateTo,
    this.createdFrom,
    this.createdTo,
    this.limit,
  });

  final String? userId;
  final LeaveRequestStatus? status;
  final LeaveType? leaveType;
  final String? leaveTypeName;
  final DateTime? startDateFrom;
  final DateTime? startDateTo;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final int? limit;

  /// Convert to URL query-param map for the API layer.
  Map<String, dynamic> toQueryParams() => {
    if (status != null) 'status': status!.value,
    if (_effectiveLeaveTypeName != null) 'leave_type': _effectiveLeaveTypeName,
    if (userId != null && userId!.isNotEmpty) 'user_id': userId,
    if (limit != null) 'limit': limit,
    if (startDateFrom != null) 'start_date_from': _toDateStr(startDateFrom!),
    if (startDateTo != null) 'start_date_to': _toDateStr(startDateTo!),
    if (createdFrom != null) 'created_from': createdFrom!.toIso8601String(),
    if (createdTo != null) 'created_to': createdTo!.toIso8601String(),
  };

  static String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? get _effectiveLeaveTypeName {
    final raw = leaveTypeName?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return leaveType?.value;
  }
}

/// Approval payload used by HR/admin actions.
class LeaveApprovalInput {
  const LeaveApprovalInput({
    required this.requestId,
    required this.reviewerId,
    this.reviewerName,
    this.reviewerRole,
    this.reviewerTitle,
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
  final String? reviewerRole;
  final String? reviewerTitle;
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
    this.reviewerRole,
    this.reviewerTitle,
    this.hrRemarks,
    this.reason,
    this.reviewedAt,
  });

  final String requestId;
  final String reviewerId;
  final String? reviewerName;
  final String? reviewerRole;
  final String? reviewerTitle;
  final String? hrRemarks;
  final String? reason;
  final DateTime? reviewedAt;
}

/// Admin payload for year-end forced leave deduction.
class ForcedLeaveDeductionInput {
  const ForcedLeaveDeductionInput({
    required this.userId,
    required this.daysToDeduct,
    this.year,
    this.remarks,
    this.allowNegativeBalance = false,
  });

  final String userId;
  final double daysToDeduct;
  final int? year;
  final String? remarks;
  final bool allowNegativeBalance;
}

/// Result returned after a forced leave deduction is applied.
class ForcedLeaveDeductionResult {
  const ForcedLeaveDeductionResult({
    required this.userId,
    required this.leaveType,
    required this.deductedDays,
    required this.remainingDays,
    this.year,
    this.remarks,
    this.appliedAt,
  });

  final String userId;
  final LeaveType leaveType;
  final double deductedDays;
  final double remainingDays;
  final int? year;
  final String? remarks;
  final DateTime? appliedAt;
}

/// Admin payload for monthly VL/SL accrual.
class MonthlyLeaveAccrualInput {
  const MonthlyLeaveAccrualInput({
    required this.dryRun,
    this.targetMonth,
    this.maxCatchUpMonths = 1,
  });

  final bool dryRun;
  final String? targetMonth;
  final int maxCatchUpMonths;
}

/// One employee/leave-type row returned by the monthly accrual preview/apply API.
class MonthlyLeaveAccrualDetail {
  const MonthlyLeaveAccrualDetail({
    required this.userId,
    required this.employeeName,
    required this.leaveType,
    required this.action,
    this.reason,
    this.monthsCredited,
    this.daysAdded,
    this.lastAccrualDate,
    this.createdBalanceRow = false,
    this.hireProrated = false,
    this.daysWorked,
    this.daysInMonth,
  });

  final String userId;
  final String employeeName;
  final LeaveType leaveType;
  final String action;
  final String? reason;
  final int? monthsCredited;
  final double? daysAdded;
  final String? lastAccrualDate;
  final bool createdBalanceRow;
  final bool hireProrated;
  final int? daysWorked;
  final int? daysInMonth;

  bool get willChangeBalance => action == 'would_apply' || action == 'applied';

  factory MonthlyLeaveAccrualDetail.fromJson(Map<String, dynamic> json) {
    return MonthlyLeaveAccrualDetail(
      userId: json['user_id']?.toString() ?? '',
      employeeName: json['employee_name']?.toString() ?? 'Unnamed employee',
      leaveType: leaveTypeFromString(json['leave_type']?.toString()),
      action: json['action']?.toString() ?? '',
      reason: json['reason']?.toString(),
      monthsCredited: _parseInt(json['months_credited']),
      daysAdded: _parseDoubleValue(json['days_added']),
      lastAccrualDate: json['last_accrual_date']?.toString(),
      createdBalanceRow: json['created_balance_row'] == true,
      hireProrated: json['hire_prorated'] == true,
      daysWorked: _parseInt(json['days_worked']),
      daysInMonth: _parseInt(json['days_in_month']),
    );
  }
}

/// Result returned by POST /api/leave/admin/monthly-accrual.
class MonthlyLeaveAccrualResult {
  const MonthlyLeaveAccrualResult({
    required this.targetYearMonth,
    required this.rate,
    required this.leaveTypes,
    required this.maxCatchUpMonths,
    required this.dryRun,
    required this.rowsUpdated,
    required this.rowsSkipped,
    required this.missingBalanceRowsCreated,
    required this.missingBalanceRowsDetected,
    required this.details,
  });

  final String targetYearMonth;
  final double rate;
  final List<LeaveType> leaveTypes;
  final int maxCatchUpMonths;
  final bool dryRun;
  final int rowsUpdated;
  final int rowsSkipped;
  final int missingBalanceRowsCreated;
  final int missingBalanceRowsDetected;
  final List<MonthlyLeaveAccrualDetail> details;

  factory MonthlyLeaveAccrualResult.fromJson(Map<String, dynamic> json) {
    final rawLeaveTypes = json['leaveTypes'] ?? json['leave_types'];
    final rawDetails = json['details'];
    return MonthlyLeaveAccrualResult(
      targetYearMonth:
          json['targetYearMonth']?.toString() ??
          json['target_year_month']?.toString() ??
          '',
      rate: _parseDoubleValue(json['rate']) ?? 0,
      leaveTypes: rawLeaveTypes is List
          ? rawLeaveTypes
                .map((item) => leaveTypeFromString(item?.toString()))
                .toList()
          : const <LeaveType>[],
      maxCatchUpMonths:
          _parseInt(json['maxCatchUpMonths']) ??
          _parseInt(json['max_catch_up_months']) ??
          1,
      dryRun: json['dryRun'] == true || json['dry_run'] == true,
      rowsUpdated:
          _parseInt(json['rowsUpdated']) ??
          _parseInt(json['rows_updated']) ??
          0,
      rowsSkipped:
          _parseInt(json['rowsSkipped']) ??
          _parseInt(json['rows_skipped']) ??
          0,
      missingBalanceRowsCreated:
          _parseInt(json['missingBalanceRowsCreated']) ??
          _parseInt(json['missing_balance_rows_created']) ??
          0,
      missingBalanceRowsDetected:
          _parseInt(json['missingBalanceRowsDetected']) ??
          _parseInt(json['missing_balance_rows_detected']) ??
          0,
      details: rawDetails is List
          ? rawDetails
                .whereType<Map>()
                .map(
                  (item) => MonthlyLeaveAccrualDetail.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const <MonthlyLeaveAccrualDetail>[],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Year-end forced leave compliance models
// ─────────────────────────────────────────────────────────────────────────────

/// One employee row returned by the year-end forced leave compliance query.
class YearEndForcedLeaveEmployee {
  const YearEndForcedLeaveEmployee({
    required this.userId,
    required this.fullName,
    required this.employeeNumber,
    required this.departmentName,
    required this.forcedDaysUsed,
    required this.requiredDays,
    required this.suggestedDeduction,
    required this.vlAvailable,
    required this.alreadyDeducted,
    required this.canApply,
    required this.status,
    this.deductedDays,
    this.deductedAt,
    // apply result fields (populated after apply)
    this.daysToDeduct,
    this.applyStatus,
    this.applyError,
    this.appliedAt,
  });

  final String userId;
  final String fullName;
  final String? employeeNumber;
  final String? departmentName;
  final double forcedDaysUsed;
  final double requiredDays;
  final double suggestedDeduction;
  final double vlAvailable;
  final bool alreadyDeducted;
  final bool canApply;

  /// 'pending' | 'compliant' | 'deducted'
  final String status;

  final double? deductedDays;
  final DateTime? deductedAt;

  // Set when this row comes from an apply result:
  final double? daysToDeduct;
  final String? applyStatus; // 'applied' | 'would_apply' | 'already_deducted' | 'compliant' | 'insufficient_balance' | 'error'
  final String? applyError;
  final DateTime? appliedAt;

  factory YearEndForcedLeaveEmployee.fromJson(Map<String, dynamic> j) {
    return YearEndForcedLeaveEmployee(
      userId: j['user_id']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? '',
      employeeNumber: j['employee_number']?.toString(),
      departmentName: j['current_department_name']?.toString(),
      forcedDaysUsed: _pd(j['forced_leave_days_used']),
      requiredDays: _pd(j['required_days']) == 0 ? 5 : _pd(j['required_days']),
      suggestedDeduction: _pd(j['suggested_deduction']),
      vlAvailable: _pd(j['vl_available']),
      alreadyDeducted: j['already_deducted'] == true,
      canApply: j['can_apply'] == true,
      status: j['status']?.toString() ?? 'pending',
      deductedDays: _pd2(j['deducted_days']),
      deductedAt: _parseDate(j['deducted_at']),
      daysToDeduct: _pd2(j['days_to_deduct']),
      applyStatus: j['apply_status']?.toString(),
      applyError: j['error']?.toString(),
      appliedAt: _parseDate(j['applied_at']),
    );
  }

  static double _pd(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
  static double? _pd2(dynamic v) =>
      v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

/// Summary counts from the compliance query.
class YearEndForcedLeaveSummary {
  const YearEndForcedLeaveSummary({
    required this.total,
    required this.compliant,
    required this.pendingDeduction,
    required this.alreadyDeducted,
    // apply result extras:
    this.applied = 0,
    this.insufficientBalance = 0,
    this.errors = 0,
    this.totalEligible = 0,
    this.wouldApply = 0,
  });

  final int total;
  final int compliant;
  final int pendingDeduction;
  final int alreadyDeducted;
  final int applied;
  final int insufficientBalance;
  final int errors;
  final int totalEligible;
  final int wouldApply;

  factory YearEndForcedLeaveSummary.fromJson(Map<String, dynamic> j) {
    return YearEndForcedLeaveSummary(
      total: _pi(j['total']),
      compliant: _pi(j['compliant']),
      pendingDeduction: _pi(j['pending_deduction']),
      alreadyDeducted: _pi(j['already_deducted']),
      applied: _pi(j['applied']),
      insufficientBalance: _pi(j['insufficient_balance']),
      errors: _pi(j['errors']),
      totalEligible: _pi(j['total_eligible']),
      wouldApply: _pi(j['would_apply']),
    );
  }

  static int _pi(dynamic v) =>
      v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);
}

/// Full result from GET /api/leave/admin/year-end-forced-leave.
class YearEndForcedLeaveComplianceResult {
  const YearEndForcedLeaveComplianceResult({
    required this.year,
    required this.requiredDays,
    required this.employees,
    required this.summary,
  });

  final int year;
  final double requiredDays;
  final List<YearEndForcedLeaveEmployee> employees;
  final YearEndForcedLeaveSummary summary;

  factory YearEndForcedLeaveComplianceResult.fromJson(Map<String, dynamic> j) {
    final rawEmployees = j['employees'];
    return YearEndForcedLeaveComplianceResult(
      year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
      requiredDays: (j['required_days'] as num?)?.toDouble() ?? 5,
      summary: YearEndForcedLeaveSummary.fromJson(
        j['summary'] is Map ? Map<String, dynamic>.from(j['summary'] as Map) : {},
      ),
      employees: rawEmployees is List
          ? rawEmployees
              .whereType<Map>()
              .map((e) => YearEndForcedLeaveEmployee.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Result from POST /api/leave/admin/year-end-forced-leave/apply.
class YearEndForcedLeaveApplyResult {
  const YearEndForcedLeaveApplyResult({
    required this.dryRun,
    required this.year,
    required this.summary,
    required this.results,
  });

  final bool dryRun;
  final int year;
  final YearEndForcedLeaveSummary summary;
  final List<YearEndForcedLeaveEmployee> results;

  factory YearEndForcedLeaveApplyResult.fromJson(Map<String, dynamic> j) {
    final rawResults = j['results'];
    return YearEndForcedLeaveApplyResult(
      dryRun: j['dry_run'] == true,
      year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
      summary: YearEndForcedLeaveSummary.fromJson(
        j['summary'] is Map ? Map<String, dynamic>.from(j['summary'] as Map) : {},
      ),
      results: rawResults is List
          ? rawResults
              .whereType<Map>()
              .map((e) => YearEndForcedLeaveEmployee.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Input for the year-end forced leave bulk apply endpoint.
class YearEndForcedLeaveApplyInput {
  const YearEndForcedLeaveApplyInput({
    required this.year,
    required this.dryRun,
    this.employeeIds,
    this.remarks,
  });

  final int year;
  final bool dryRun;
  final List<String>? employeeIds;
  final String? remarks;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _parseDoubleValue(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
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

  /// Submit a leave request and supporting attachment in one request.
  Future<LeaveRequest> submitRequestWithAttachment({
    required LeaveRequest request,
    required List<int> fileBytes,
    required String fileName,
  });

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
  Future<LeaveBalance> upsertBalance(LeaveBalance balance, {String? remarks});

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

  // ---- Department Head workflow ----

  /// Check if the current authenticated user is a department head.
  Future<Map<String, dynamic>> checkIsDepartmentHead();

  /// List leave requests pending department head approval plus requests already
  /// handled by the current department head.
  Future<List<LeaveRequest>> listDepartmentHeadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  });

  /// Department head approves a request (moves to pending_hr).
  Future<LeaveRequest> departmentHeadApprove(LeaveReviewDecisionInput input);

  /// Department head rejects a request.
  Future<LeaveRequest> departmentHeadReject(LeaveReviewDecisionInput input);

  /// Department head returns a request to the employee.
  Future<LeaveRequest> departmentHeadReturn(LeaveReviewDecisionInput input);

  /// Admin/HR applies year-end forced leave as a vacation balance deduction.
  Future<ForcedLeaveDeductionResult> applyForcedLeaveDeduction(
    ForcedLeaveDeductionInput input,
  );

  /// Admin/HR previews or applies monthly VL/SL accrual.
  Future<MonthlyLeaveAccrualResult> runMonthlyAccrual(
    MonthlyLeaveAccrualInput input,
  );

  /// Fetch year-end forced leave compliance for all active employees.
  Future<YearEndForcedLeaveComplianceResult> getYearEndForcedLeaveCompliance(int year);

  /// Preview or apply year-end forced leave deductions in bulk.
  Future<YearEndForcedLeaveApplyResult> applyYearEndForcedLeaveDeductions(
    YearEndForcedLeaveApplyInput input,
  );

  /// Balance movement audit (GET /api/leave/ledger). Employees: omit [query.userId].
  Future<LeaveLedgerResult> getLeaveLedger(LeaveLedgerQuery query);
}
