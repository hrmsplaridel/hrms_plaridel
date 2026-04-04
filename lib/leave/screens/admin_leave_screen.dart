import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../utils/open_attachment_io.dart'
    if (dart.library.html) '../utils/open_attachment_web.dart'
    as open_attachment;
import '../../providers/auth_provider.dart';
import '../leave_provider.dart';
import '../leave_repository.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import '../utils/leave_request_pdf.dart';
import '../../utils/responsive_right_side_panel.dart';
import '../widgets/admin_row.dart';
import '../widgets/history_timeline.dart';
import '../widgets/leave_status_chip.dart';

typedef LeaveApproveAction = Future<bool> Function(LeaveApprovalInput input);
typedef LeaveDecisionAction =
    Future<bool> Function(LeaveReviewDecisionInput input);

/// HR/admin leave review screen.
///
/// Shows request queue, details, and review actions. Action callbacks are
/// optional so this screen can be used before the backend wiring is finalized.
class AdminLeaveScreen extends StatefulWidget {
  const AdminLeaveScreen({
    super.key,
    this.isDepartmentHead = false,
    this.onApprove,
    this.onReturnRequest,
    this.onRejectRequest,
  });

  final bool isDepartmentHead;
  final LeaveApproveAction? onApprove;
  final LeaveDecisionAction? onReturnRequest;
  final LeaveDecisionAction? onRejectRequest;

  @override
  State<AdminLeaveScreen> createState() => _AdminLeaveScreenState();
}

class _AdminLeaveScreenState extends State<AdminLeaveScreen>
    with WidgetsBindingObserver {
  bool _initialized = false;
  LeaveRequest? _selectedRequest;
  LeaveRequestStatus? _statusFilter;
  LeaveType? _leaveTypeFilter;
  String? _departmentFilter;
  String? _employeeFilter;
  // #11: Date range filters.
  DateTime? _startDateFrom;
  DateTime? _startDateTo;
  Timer? _autoRefreshTimer;

  Future<({String name, String? title})> _loadReviewerSignatureInfo(
    AuthProvider auth,
  ) async {
    final fallbackName = auth.displayName.trim().isNotEmpty
        ? auth.displayName.trim()
        : 'Authorized Officer';
    final fallbackTitle = _reviewerTitleFromRole(auth.user?.role);
    return _loadSignatureInfoByUserId(
      userId: auth.user?.id,
      fallbackName: fallbackName,
      fallbackTitle: fallbackTitle,
    );
  }

  Future<({String name, String? title})> _loadSignatureInfoByUserId({
    required String? userId,
    required String fallbackName,
    String? fallbackTitle,
  }) async {
    if (userId == null || userId.isEmpty) {
      return (name: fallbackName, title: fallbackTitle);
    }
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/assignments?employee_id=$userId&status=Active',
      );
      final data = res.data;
      if (data != null && data.isNotEmpty) {
        final first = data.first as Map<String, dynamic>;
        final assignmentName = (first['employee_name'] as String?)?.trim();
        final assignmentTitle = (first['position_name'] as String?)?.trim();
        return (
          name: (assignmentName != null && assignmentName.isNotEmpty)
              ? assignmentName
              : fallbackName,
          title: (assignmentTitle != null && assignmentTitle.isNotEmpty)
              ? assignmentTitle
              : fallbackTitle,
        );
      }
    } catch (_) {
      // Fallback to auth profile when assignment lookup is unavailable.
    }
    return (name: fallbackName, title: fallbackTitle);
  }

  String? _reviewerTitleFromRole(String? role) {
    final raw = role?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.toLowerCase();
    if (normalized == 'admin' ||
        normalized == 'hr' ||
        normalized == 'hr_admin') {
      return 'Authorized HR Officer';
    }
    if (normalized.contains('mayor')) return 'Municipal Mayor';
    if (normalized.contains('super')) return 'Approving Authority';
    final parts = raw.replaceAll('_', ' ').split(RegExp(r'\s+'));
    return parts
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRequests());
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _safeAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _safeAutoRefresh();
    });
  }

  Future<void> _safeAutoRefresh() async {
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    if (provider.reviewing || provider.submitting) return;
    await _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LeaveProvider>();
    final requests = provider.requests;
    final departmentMap = <String, String>{};
    for (final request in requests) {
      final raw = (request.officeDepartment ?? '').trim();
      if (raw.isEmpty) continue;
      final normalized = raw
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('\u00A0', ' ')
          .replaceAll('\u200B', '');
      departmentMap.putIfAbsent(normalized, () => raw);
    }
    final departments = departmentMap.values.toList()..sort();
    final employeeDirectory = <String, String>{};
    for (final r in requests) {
      final name = (r.employeeName ?? '').trim();
      if (name.isEmpty) continue;
      employeeDirectory[r.userId] = name;
    }
    final employees =
        employeeDirectory.entries.map((e) => (id: e.key, name: e.value)).where((
          e,
        ) {
          if (_departmentFilter == null) return true;
          final req = requests.where((r) => r.userId == e.id);
          return req.any(
            (r) => (r.officeDepartment ?? '').trim() == _departmentFilter,
          );
        }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final filteredRequests = requests.where((r) {
      if (!widget.isDepartmentHead &&
          r.status == LeaveRequestStatus.pendingDepartmentHead) {
        return false;
      }
      final statusOk = _statusFilter == null || r.status == _statusFilter;
      if (!statusOk) return false;
      final leaveTypeOk =
          _leaveTypeFilter == null || r.leaveType == _leaveTypeFilter;
      if (!leaveTypeOk) return false;
      final fromOk =
          _startDateFrom == null ||
          (r.startDate != null &&
              !r.startDate!.isBefore(
                DateTime(
                  _startDateFrom!.year,
                  _startDateFrom!.month,
                  _startDateFrom!.day,
                ),
              ));
      if (!fromOk) return false;
      final toOk =
          _startDateTo == null ||
          (r.startDate != null &&
              !r.startDate!.isAfter(
                DateTime(
                  _startDateTo!.year,
                  _startDateTo!.month,
                  _startDateTo!.day,
                  23,
                  59,
                  59,
                ),
              ));
      if (!toOk) return false;
      final deptOk =
          _departmentFilter == null ||
          (r.officeDepartment ?? '').trim() == _departmentFilter;
      if (!deptOk) return false;
      final employeeOk = _employeeFilter == null || r.userId == _employeeFilter;
      if (!employeeOk) return false;
      return true;
    }).toList();
    // Sync the selected request to the latest instance from `filteredRequests`
    // so actions like Reject immediately reflect in the details panel history.
    LeaveRequest? selected;
    final selectedId = _selectedRequest?.id;
    if (selectedId != null && selectedId.isNotEmpty) {
      final matches = filteredRequests.where((r) => r.id == selectedId);
      selected = matches.isNotEmpty ? matches.first : null;
    } else {
      selected = null;
    }

    final shouldSyncSelected =
        _selectedRequest?.id != selected?.id ||
        _selectedRequest?.status != selected?.status ||
        _selectedRequest?.updatedAt != selected?.updatedAt ||
        _selectedRequest?.reviewedAt != selected?.reviewedAt;
    if (shouldSyncSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedRequest = selected);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminHeaderCard(
          totalRequests: filteredRequests.length,
          pendingCount: filteredRequests
              .where((r) => r.status.isPending)
              .length,
          reviewing: provider.reviewing,
          onRefresh: _loadRequests,
          onAssignMandatoryLeave: widget.isDepartmentHead
              ? null
              : _assignMandatoryForcedLeave,
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(
            message: provider.error!,
            onDismiss: provider.clearError,
          ),
        ],
        const SizedBox(height: 24),
        _FilterBar(
          isDepartmentHead: widget.isDepartmentHead,
          status: _statusFilter,
          leaveType: _leaveTypeFilter,
          department: _departmentFilter,
          departments: departments,
          employee: _employeeFilter,
          employees: employees
              .map((e) => _EmployeeFilterOption(id: e.id, name: e.name))
              .toList(),
          startDateFrom: _startDateFrom,
          startDateTo: _startDateTo,
          onStatusChanged: (value) {
            setState(() => _statusFilter = value);
            _loadRequests();
          },
          onLeaveTypeChanged: (value) {
            setState(() => _leaveTypeFilter = value);
            _loadRequests();
          },
          onDepartmentChanged: (value) => setState(() {
            _departmentFilter = value;
            _employeeFilter = null;
          }),
          onEmployeeChanged: (value) => setState(() => _employeeFilter = value),
          onStartDateFromChanged: (value) {
            setState(() => _startDateFrom = value);
            _loadRequests();
          },
          onStartDateToChanged: (value) {
            setState(() => _startDateTo = value);
            _loadRequests();
          },
          onReset: () {
            setState(() {
              _statusFilter = null;
              _leaveTypeFilter = null;
              _departmentFilter = null;
              _employeeFilter = null;
              _startDateFrom = null;
              _startDateTo = null;
            });
            _loadRequests();
          },
        ),
        const SizedBox(height: 20),
        _RequestQueuePanel(
          requests: filteredRequests,
          isDepartmentHead: widget.isDepartmentHead,
          loading: provider.loading,
          selectedRequest: selected,
          onSelect: (request) {
            setState(() => _selectedRequest = request);
            _openRequestDetailsPanel(request);
          },
        ),
      ],
    );
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    if (widget.isDepartmentHead) {
      await provider.loadDepartmentHeadRequests();
    } else {
      await provider.loadRequests(
        query: LeaveRequestQuery(
          status: _statusFilter,
          leaveType: _leaveTypeFilter,
          startDateFrom: _startDateFrom,
          startDateTo: _startDateTo,
          limit: 200,
        ),
      );
    }
    if (!mounted) return;
  }

  /// Same UX as filing leave: wide = resizable right sheet; narrow = full-screen route.
  /// Opens immediately; refresh runs in background so tap is not blocked on the network.
  void _openRequestDetailsPanel(LeaveRequest request) {
    final id = request.id;
    if (id != null && id.isNotEmpty) {
      unawaited(context.read<LeaveProvider>().refreshRequestById(id));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openResponsiveRightSidePanel<void>(
        context: context,
        barrierLabel: 'Close request details',
        minWidth: 400,
        initialWidthFraction: 0.46,
        builder: (ctx) => _AdminLeaveDetailsSideSheet(
          initial: request,
          isDepartmentHead: widget.isDepartmentHead,
          onApprove: widget.isDepartmentHead ? _deptHeadApprove : _approve,
          onReturn: widget.isDepartmentHead ? _deptHeadReturn : _returnRequest,
          onReject: widget.isDepartmentHead ? _deptHeadReject : _rejectRequest,
          onRevoke: _revokeApproval,
          onPrint: _printLeaveForm,
        ),
      );
    });
  }

  Future<void> _printLeaveForm(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    if (!mounted) return;

    try {
      // Best-effort refresh so we print the latest snapshot (e.g. after HR changes).
      LeaveRequest target = request;
      final id = request.id;
      if (id != null && id.isNotEmpty) {
        final fresh = await provider.refreshRequestById(id);
        if (fresh != null) {
          target = fresh;
          if (_selectedRequest?.id == id) {
            setState(() => _selectedRequest = fresh);
          }
        }
      }

      final signerInfo = await _loadSignatureInfoByUserId(
        userId: target.reviewerId ?? auth.user?.id,
        fallbackName: (target.reviewerName?.trim().isNotEmpty == true)
            ? target.reviewerName!.trim()
            : (auth.displayName.trim().isNotEmpty
                  ? auth.displayName.trim()
                  : 'Authorized Officer'),
        fallbackTitle: (target.reviewerTitle?.trim().isNotEmpty == true)
            ? target.reviewerTitle!.trim()
            : _reviewerTitleFromRole(target.reviewerRole ?? auth.user?.role),
      );
      target = target.copyWith(
        reviewerName: signerInfo.name,
        reviewerTitle: signerInfo.title,
      );

      final balances = await provider.fetchBalancesForUser(target.userId);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Preparing print...')));
      }

      await LeaveRequestPdf.printLeaveRequest(
        request: target,
        balances: balances,
        name: 'Leave_Application_${target.id ?? target.userId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _approve(LeaveRequest request) async {
    final userId = request.userId;
    if (userId.isEmpty) {
      _showMessage('Cannot determine employee for this request.');
      return;
    }
    final balances = await context.read<LeaveProvider>().fetchBalancesForUser(
      userId,
    );
    LeaveBalance? leaveBalance;
    final ledgerType = request.leaveType.balanceLedgerType;
    try {
      leaveBalance = balances.firstWhere((b) => b.leaveType == ledgerType);
    } catch (_) {}

    if (!mounted) return;
    final input = await showDialog<LeaveApprovalInput>(
      context: context,
      builder: (_) =>
          _ApproveDialog(request: request, leaveBalance: leaveBalance),
    );
    if (input == null) return;

    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);

    final finalInput = LeaveApprovalInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: reviewerInfo.name,
      reviewerRole: reviewerRole,
      reviewerTitle: reviewerInfo.title,
      hrRemarks: input.hrRemarks,
      approvedDaysWithPay: input.approvedDaysWithPay,
      approvedDaysWithoutPay: input.approvedDaysWithoutPay,
      reviewedAt: DateTime.now(),
    );

    bool ok;
    if (widget.onApprove != null) {
      ok = await widget.onApprove!(finalInput);
    } else {
      final result = await context.read<LeaveProvider>().approveRequest(
        finalInput,
      );
      ok = result != null;
    }
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    _showMessage(
      ok
          ? 'Leave request approved.'
          : (provider.error ?? 'Approval could not be completed.'),
    );
    if (ok) {
      await _loadRequests();
    }
  }

  Future<void> _returnRequest(LeaveRequest request) async {
    final input = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => _DecisionDialog(
        title: 'Return Request',
        subtitle:
            'Send this request back to the employee for correction or missing information.',
        confirmLabel: 'Return Request',
        requireReason: true,
        request: request,
      ),
    );
    if (input == null) return;

    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);

    final finalInput = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: reviewerInfo.name,
      reviewerRole: reviewerRole,
      reviewerTitle: reviewerInfo.title,
      hrRemarks: input.hrRemarks,
      reason: input.reason,
      reviewedAt: DateTime.now(),
    );

    bool ok;
    if (widget.onReturnRequest != null) {
      ok = await widget.onReturnRequest!(finalInput);
    } else {
      final result = await context.read<LeaveProvider>().returnRequest(
        finalInput,
      );
      ok = result != null;
    }
    if (!mounted) return;
    _showMessage(ok ? 'Leave request returned.' : 'Return action failed.');
    if (ok) {
      await _loadRequests();
    }
  }

  Future<void> _rejectRequest(LeaveRequest request) async {
    final input = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => _DecisionDialog(
        title: 'Reject Request',
        subtitle:
            'Reject this request and provide a clear reason for the employee.',
        confirmLabel: 'Reject Request',
        requireReason: true,
        request: request,
      ),
    );
    if (input == null) return;

    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);

    final finalInput = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: reviewerInfo.name,
      reviewerRole: reviewerRole,
      reviewerTitle: reviewerInfo.title,
      hrRemarks: input.hrRemarks,
      reason: input.reason,
      reviewedAt: DateTime.now(),
    );

    bool ok;
    if (widget.onRejectRequest != null) {
      ok = await widget.onRejectRequest!(finalInput);
    } else {
      final result = await context.read<LeaveProvider>().rejectRequest(
        finalInput,
      );
      ok = result != null;
    }
    if (!mounted) return;
    _showMessage(ok ? 'Leave request rejected.' : 'Reject action failed.');
    if (ok) {
      await _loadRequests();
    }
  }

  // #15: Revoke approval.
  Future<void> _revokeApproval(LeaveRequest request) async {
    final input = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => _DecisionDialog(
        title: 'Revoke Approval',
        subtitle:
            'This will reverse the approval: balance will be restored and DTR leave entries removed. The request returns to the employee for correction.',
        confirmLabel: 'Revoke Approval',
        requireReason: false,
        request: request,
      ),
    );
    if (input == null) return;

    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);

    final finalInput = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: reviewerInfo.name,
      reviewerRole: reviewerRole,
      reviewerTitle: reviewerInfo.title,
      hrRemarks: input.hrRemarks,
      reason: input.reason,
      reviewedAt: DateTime.now(),
    );

    final result = await context.read<LeaveProvider>().revokeApproval(
      finalInput,
    );
    final ok = result != null;
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    _showMessage(
      ok
          ? 'Approval revoked. Leave balance restored.'
          : (provider.error ?? 'Revoke failed.'),
    );
    if (ok) await _loadRequests();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignMandatoryForcedLeave() async {
    final input = await showDialog<_AssignMandatoryForcedLeaveInput>(
      context: context,
      builder: (_) => const _AssignMandatoryForcedLeaveDialog(),
    );
    if (input == null) return;

    final result = await context
        .read<LeaveProvider>()
        .assignMandatoryForcedLeave(
          AdminMandatoryLeaveAssignmentInput(
            userId: input.userId,
            startDate: input.startDate,
            endDate: input.endDate,
            reason: input.reason,
          ),
        );
    if (!mounted) return;
    final ok = result != null;
    final provider = context.read<LeaveProvider>();
    _showMessage(
      ok
          ? 'Mandatory/Forced Leave assigned.'
          : (provider.error ?? 'Assign action failed.'),
    );
    if (ok) await _loadRequests();
  }

  // ---- Department Head actions ----

  Future<void> _deptHeadApprove(LeaveRequest request) async {
    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final input = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: auth.displayName,
      reviewerRole: auth.user?.role,
    );
    final result = await context.read<LeaveProvider>().departmentHeadApprove(
      input,
    );
    final ok = result != null;
    if (!mounted) return;
    _showMessage(
      ok
          ? 'Forwarded to HR for final approval.'
          : (context.read<LeaveProvider>().error ??
                'Department head approval failed.'),
    );
    if (ok) await _loadRequests();
  }

  Future<void> _deptHeadReject(LeaveRequest request) async {
    final dialogResult = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => _DecisionDialog(
        title: 'Reject Request',
        subtitle: 'Reject this request as department head.',
        confirmLabel: 'Reject',
        requireReason: true,
        request: request,
      ),
    );
    if (dialogResult == null) return;
    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final input = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: auth.displayName,
      reviewerRole: auth.user?.role,
      reason: dialogResult.reason,
      hrRemarks: dialogResult.hrRemarks,
    );
    final result = await context.read<LeaveProvider>().departmentHeadReject(
      input,
    );
    final ok = result != null;
    if (!mounted) return;
    _showMessage(ok ? 'Request rejected.' : 'Reject action failed.');
    if (ok) await _loadRequests();
  }

  Future<void> _deptHeadReturn(LeaveRequest request) async {
    final dialogResult = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => _DecisionDialog(
        title: 'Return Request',
        subtitle: 'Return this to the employee for corrections.',
        confirmLabel: 'Return',
        requireReason: true,
        request: request,
      ),
    );
    if (dialogResult == null) return;
    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final input = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: auth.displayName,
      reviewerRole: auth.user?.role,
      reason: dialogResult.reason,
      hrRemarks: dialogResult.hrRemarks,
    );
    final result = await context.read<LeaveProvider>().departmentHeadReturn(
      input,
    );
    final ok = result != null;
    if (!mounted) return;
    _showMessage(ok ? 'Request returned.' : 'Return action failed.');
    if (ok) await _loadRequests();
  }
}

class _AdminHeaderCard extends StatelessWidget {
  const _AdminHeaderCard({
    required this.totalRequests,
    required this.pendingCount,
    required this.reviewing,
    required this.onRefresh,
    this.onAssignMandatoryLeave,
  });

  final int totalRequests;
  final int pendingCount;
  final bool reviewing;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onAssignMandatoryLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 16,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave Approvals',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Review employee leave applications, inspect their form details, and record approval decisions.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeaderChip(label: 'Total Loaded', value: '$totalRequests'),
                    _HeaderChip(
                      label: 'Pending',
                      value: '$pendingCount',
                      emphasize: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onAssignMandatoryLeave != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onAssignMandatoryLeave,
                  icon: const Icon(Icons.assignment_turned_in_rounded),
                  label: const Text('Assign Mandatory/Forced'),
                ),
              FilledButton.icon(
                onPressed: reviewing ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(reviewing ? 'Reviewing...' : 'Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignMandatoryForcedLeaveInput {
  const _AssignMandatoryForcedLeaveInput({
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.reason,
  });

  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
}

class _AssignMandatoryForcedLeaveDialog extends StatefulWidget {
  const _AssignMandatoryForcedLeaveDialog();

  @override
  State<_AssignMandatoryForcedLeaveDialog> createState() =>
      _AssignMandatoryForcedLeaveDialogState();
}

class _AssignMandatoryForcedLeaveDialogState
    extends State<_AssignMandatoryForcedLeaveDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _loadingEmployees = true;
  String? _employeesError;
  List<Map<String, String>> _employees = const [];
  String? _selectedUserId;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loadingEmployees = true;
      _employeesError = null;
    });
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees?status=Active',
      );
      final rows =
          (res.data ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => {
                  'id': e['id']?.toString() ?? '',
                  'name': e['full_name']?.toString() ?? 'Unnamed',
                },
              )
              .where((e) => (e['id'] ?? '').isNotEmpty)
              .toList()
            ..sort((a, b) => (a['name']!).compareTo(b['name']!));
      setState(() {
        _employees = rows;
        _selectedUserId = rows.isNotEmpty ? rows.first['id'] : null;
        _loadingEmployees = false;
      });
    } catch (e) {
      setState(() {
        _employeesError = e.toString();
        _loadingEmployees = false;
      });
    }
  }

  int? _computeWeekdays() {
    final s = _startDate;
    final e = _endDate;
    if (s == null || e == null || e.isBefore(s)) return null;
    int count = 0;
    DateTime d = s;
    while (!d.isAfter(e)) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
        count++;
      }
      d = d.add(const Duration(days: 1));
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final weekdays = _computeWeekdays();
    return AlertDialog(
      title: const Text('Assign Mandatory/Forced Leave'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingEmployees)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_employeesError != null)
                  Text(
                    'Failed to load employees: $_employeesError',
                    style: TextStyle(color: Colors.red.shade700),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _selectedUserId,
                    decoration: _inputDecoration('Employee'),
                    items: _employees
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e['id'],
                            child: Text(e['name']!),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUserId = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Select an employee' : null,
                  ),
                const SizedBox(height: 12),
                _dateField(
                  label: 'Start Date',
                  value: _startDate,
                  onChanged: (v) => setState(() => _startDate = v),
                ),
                const SizedBox(height: 12),
                _dateField(
                  label: 'End Date',
                  value: _endDate,
                  onChanged: (v) => setState(() => _endDate = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  minLines: 2,
                  maxLines: null,
                  decoration: _inputDecoration('Reason / Notes (Optional)'),
                ),
                const SizedBox(height: 10),
                Text(
                  weekdays == null
                      ? 'Select a valid date range.'
                      : 'Computed weekdays: $weekdays (max 5 for Mandatory/Forced Leave)',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            if (_startDate == null || _endDate == null) return;
            final days = _computeWeekdays();
            if (days == null || days <= 0) return;
            if (days > 5) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Mandatory/Forced Leave allows a maximum of 5 working days.',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              _AssignMandatoryForcedLeaveInput(
                userId: _selectedUserId!,
                startDate: _startDate!,
                endDate: _endDate!,
                reason: _trimOrNull(_reasonController.text),
              ),
            );
          },
          child: const Text('Assign'),
        ),
      ],
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Text(
          value == null
              ? 'Select Date'
              : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.isDepartmentHead,
    required this.status,
    required this.leaveType,
    required this.department,
    required this.departments,
    required this.employee,
    required this.employees,
    required this.onStatusChanged,
    required this.onLeaveTypeChanged,
    required this.onDepartmentChanged,
    required this.onEmployeeChanged,
    required this.onReset,
    this.startDateFrom,
    this.startDateTo,
    this.onStartDateFromChanged,
    this.onStartDateToChanged,
  });

  final bool isDepartmentHead;
  final LeaveRequestStatus? status;
  final LeaveType? leaveType;
  final String? department;
  final List<String> departments;
  final String? employee;
  final List<_EmployeeFilterOption> employees;
  final ValueChanged<LeaveRequestStatus?> onStatusChanged;
  final ValueChanged<LeaveType?> onLeaveTypeChanged;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onEmployeeChanged;
  final VoidCallback onReset;
  // #11: Date range filters.
  final DateTime? startDateFrom;
  final DateTime? startDateTo;
  final ValueChanged<DateTime?>? onStartDateFromChanged;
  final ValueChanged<DateTime?>? onStartDateToChanged;

  @override
  Widget build(BuildContext context) {
    final statusOptions = isDepartmentHead
        ? const <LeaveRequestStatus?>[
            null,
            LeaveRequestStatus.pendingDepartmentHead,
            LeaveRequestStatus.returned,
            LeaveRequestStatus.rejectedByDepartmentHead,
          ]
        : const <LeaveRequestStatus?>[
            null,
            LeaveRequestStatus.pendingHr,
            LeaveRequestStatus.returned,
            LeaveRequestStatus.approved,
            LeaveRequestStatus.rejectedByHr,
            LeaveRequestStatus.cancelled,
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<LeaveRequestStatus?>(
                    isExpanded: true,
                    initialValue: status,
                    decoration: _inputDecoration('Status'),
                    items: [
                      ...statusOptions.map(
                        (value) => DropdownMenuItem<LeaveRequestStatus?>(
                          value: value,
                          child: Text(_statusLabel(value)),
                        ),
                      ),
                    ],
                    onChanged: onStatusChanged,
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<LeaveType?>(
                    isExpanded: true,
                    initialValue: leaveType,
                    decoration: _inputDecoration('Leave Type'),
                    items: [
                      const DropdownMenuItem<LeaveType?>(
                        value: null,
                        child: Text('All leave types'),
                      ),
                      ...LeaveType.values.map(
                        (value) => DropdownMenuItem<LeaveType?>(
                          value: value,
                          child: Text(value.displayName),
                        ),
                      ),
                    ],
                    onChanged: onLeaveTypeChanged,
                  ),
                ),
                if (!isDepartmentHead)
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: department,
                      decoration: _inputDecoration('Department'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All departments'),
                        ),
                        ...departments.map(
                          (value) => DropdownMenuItem<String?>(
                            value: value,
                            child: Text(value),
                          ),
                        ),
                      ],
                      onChanged: onDepartmentChanged,
                    ),
                  ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: employee,
                    decoration: _inputDecoration(
                      isDepartmentHead ? 'Employee' : 'Employee',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All employees'),
                      ),
                      ...employees.map(
                        (e) => DropdownMenuItem<String?>(
                          value: e.id,
                          child: Text(e.name),
                        ),
                      ),
                    ],
                    onChanged: (!isDepartmentHead && department == null)
                        ? null
                        : onEmployeeChanged,
                    hint: (!isDepartmentHead && department == null)
                        ? const Text('Select department first')
                        : null,
                  ),
                ),
                // #11: Date range pickers.
                _DateFilterChip(
                  label: 'From',
                  date: startDateFrom,
                  onChanged: onStartDateFromChanged,
                ),
                _DateFilterChip(
                  label: 'To',
                  date: startDateTo,
                  onChanged: onStartDateToChanged,
                ),
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Reset Filters'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(LeaveRequestStatus? value) {
    if (value == null) return 'All statuses';
    if (!isDepartmentHead) return value.displayName;
    return switch (value) {
      LeaveRequestStatus.pendingDepartmentHead => 'Pending',
      LeaveRequestStatus.rejectedByDepartmentHead => 'Rejected',
      LeaveRequestStatus.returned => 'Returned',
      _ => value.displayName,
    };
  }
}

class _EmployeeFilterOption {
  const _EmployeeFilterOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// Small chip-style date picker for filter bar.
class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({
    required this.label,
    required this.date,
    required this.onChanged,
  });

  final String label;
  final DateTime? date;
  final ValueChanged<DateTime?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final text = hasDate
        ? '$label: ${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
        : label;
    return InputChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      avatar: Icon(
        hasDate ? Icons.event_available_rounded : Icons.calendar_today_rounded,
        size: 16,
      ),
      deleteIcon: hasDate ? const Icon(Icons.close_rounded, size: 14) : null,
      onDeleted: hasDate ? () => onChanged?.call(null) : null,
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          helpText: 'Select $label date',
        );
        if (picked != null) onChanged?.call(picked);
      },
    );
  }
}

class _RequestQueuePanel extends StatelessWidget {
  const _RequestQueuePanel({
    required this.requests,
    required this.isDepartmentHead,
    required this.loading,
    required this.selectedRequest,
    required this.onSelect,
  });

  final List<LeaveRequest> requests;
  final bool isDepartmentHead;
  final bool loading;
  final LeaveRequest? selectedRequest;
  final ValueChanged<LeaveRequest> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Request Queue',
      subtitle:
          'Tap a row to open details (side panel on wide screens, full screen on small).',
      child: loading && requests.isEmpty
          ? const _CenteredState(message: 'Loading leave requests...')
          : requests.isEmpty
          ? const _CenteredState(
              message: 'No leave requests matched the filters.',
            )
          : Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black.withOpacity(0.08)),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final tableWidth = !maxW.isFinite || maxW <= 0
                      ? kAdminTableMinWidth
                      : (maxW < kAdminTableMinWidth
                            ? kAdminTableMinWidth
                            : maxW);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AdminTableHeader(),
                          ...requests.map(
                            (request) => AdminRow(
                              request: request,
                              statusLabel: _statusLabel(
                                request.status,
                                isDepartmentHead: isDepartmentHead,
                              ),
                              highlighted: request.id == selectedRequest?.id,
                              onView: () => onSelect(request),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Leave review details shown over the queue (matches [openResponsiveLeaveFormHost] behavior).
class _AdminLeaveDetailsSideSheet extends StatelessWidget {
  const _AdminLeaveDetailsSideSheet({
    required this.initial,
    required this.isDepartmentHead,
    required this.onApprove,
    required this.onReturn,
    required this.onReject,
    required this.onRevoke,
    required this.onPrint,
  });

  final LeaveRequest initial;
  final bool isDepartmentHead;
  final Future<void> Function(LeaveRequest) onApprove;
  final Future<void> Function(LeaveRequest) onReturn;
  final Future<void> Function(LeaveRequest) onReject;
  final Future<void> Function(LeaveRequest) onRevoke;
  final Future<void> Function(LeaveRequest) onPrint;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            color: AppTheme.offWhite,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Request details',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<LeaveProvider>(
              builder: (context, provider, _) {
                var req = initial;
                final id = initial.id;
                if (id != null && id.isNotEmpty) {
                  final hit = provider.requests
                      .where((r) => r.id == id)
                      .toList();
                  if (hit.isNotEmpty) req = hit.first;
                }
                final pending = req.status.isPending;
                final approved = req.status == LeaveRequestStatus.approved;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: _RequestDetailsPanel(
                    request: req,
                    isDepartmentHead: isDepartmentHead,
                    reviewing: provider.reviewing,
                    onApprove: pending ? () => onApprove(req) : null,
                    onReturn: pending ? () => onReturn(req) : null,
                    onReject: pending ? () => onReject(req) : null,
                    onRevoke: approved ? () => onRevoke(req) : null,
                    onPrint: () => onPrint(req),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestDetailsPanel extends StatelessWidget {
  const _RequestDetailsPanel({
    required this.request,
    required this.isDepartmentHead,
    required this.reviewing,
    this.onApprove,
    this.onReturn,
    this.onReject,
    this.onRevoke, // #15
    this.onPrint,
  });

  final LeaveRequest? request;
  final bool isDepartmentHead;
  final bool reviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReturn;
  final VoidCallback? onReject;
  final VoidCallback? onRevoke; // #15
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    if (request == null) {
      return const _SectionCard(
        title: 'Request Details',
        subtitle: 'Select a request from the queue to review it.',
        child: _CenteredState(message: 'No request selected.'),
      );
    }

    return _SectionCard(
      title: 'Request Details',
      subtitle: 'Review the employee application before taking action.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request!.employeeName ?? 'Unknown employee',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      request!.leaveType.displayName,
                      style: TextStyle(
                        color: AppTheme.primaryNavyDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              LeaveStatusChip(
                status: request!.status,
                label: _statusLabel(
                  request!.status,
                  isDepartmentHead: isDepartmentHead,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DetailPill(
                label: 'Date Filed',
                value: request!.dateFiled != null
                    ? _formatDate(request!.dateFiled!)
                    : '—',
              ),
              _DetailPill(
                label: 'Inclusive Dates',
                value: _formatRange(request!),
              ),
              _DetailPill(
                label: 'Working Days',
                value: request!.workingDaysApplied?.toStringAsFixed(1) ?? '—',
              ),
              _DetailPill(
                label: 'Commutation',
                value: request!.commutation.displayName,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailGrid(request: request!),
          const SizedBox(height: 20),
          if ((request!.reason ?? '').trim().isNotEmpty) ...[
            _SubsectionTitle(title: 'Reason / Details'),
            _BodyCard(content: request!.reason!.trim()),
            const SizedBox(height: 16),
          ],
          _SubsectionTitle(title: 'Approval History'),
          const SizedBox(height: 8),
          HistoryTimeline(events: _buildHistoryEvents(request!)),
          const SizedBox(height: 10),
          _SubsectionTitle(title: 'Review Actions'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (onApprove != null)
                FilledButton.icon(
                  onPressed: reviewing ? null : onApprove,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Approve'),
                ),
              if (onReturn != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onReturn,
                  icon: const Icon(Icons.reply_rounded),
                  label: const Text('Return'),
                ),
              if (onReject != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onReject,
                  icon: const Icon(Icons.cancel_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  label: const Text('Reject'),
                ),
              // #15: Revoke — shown only when status is approved.
              if (onRevoke != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onRevoke,
                  icon: const Icon(Icons.undo_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                  label: const Text('Revoke Approval'),
                ),
              if (onPrint != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onPrint,
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Print Form'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRange(LeaveRequest request) {
    if (request.startDate == null || request.endDate == null) return '—';
    return '${_formatDate(request.startDate!)} to ${_formatDate(request.endDate!)}';
  }

  List<LeaveHistoryEvent> _buildHistoryEvents(LeaveRequest request) {
    final reviewer = (request.reviewerName ?? '').trim().isNotEmpty
        ? request.reviewerName!.trim()
        : 'Approver';
    final submittedAt = request.dateFiled ?? request.createdAt;
    final reviewedAt = request.reviewedAt;
    final status = request.status;

    final deptHeadApprovedStage =
        status == LeaveRequestStatus.pendingHr ||
        status == LeaveRequestStatus.approved ||
        status == LeaveRequestStatus.rejected ||
        status == LeaveRequestStatus.rejectedByHr;

    final deptHeadRejected =
        status == LeaveRequestStatus.rejectedByDepartmentHead;
    final hrApproved = status == LeaveRequestStatus.approved;
    final hrRejected =
        status == LeaveRequestStatus.rejected ||
        status == LeaveRequestStatus.rejectedByHr;

    return [
      LeaveHistoryEvent(
        label: 'Submitted',
        dateTime: submittedAt,
        actor: request.employeeName ?? 'Employee',
        remarks: request.reason,
      ),
      if (deptHeadApprovedStage)
        LeaveHistoryEvent(
          label: 'Approved by Department Head',
          dateTime: reviewedAt,
          actor: reviewer,
          completed: true,
        ),
      if (deptHeadApprovedStage)
        LeaveHistoryEvent(
          label: 'Forwarded to HR',
          dateTime: reviewedAt,
          actor: reviewer,
          completed: true,
        ),
      if (deptHeadRejected)
        LeaveHistoryEvent(
          label: 'Rejected by Department Head',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks:
              (request.disapprovalReason ?? request.hrRemarks)
                      ?.trim()
                      .isNotEmpty ==
                  true
              ? (request.disapprovalReason ?? request.hrRemarks)
              : null,
          completed: true,
        ),
      if (status == LeaveRequestStatus.pendingHr)
        LeaveHistoryEvent(
          label: 'Approved by HR',
          dateTime: null,
          actor: reviewer,
          completed: false,
        ),
      if (hrApproved)
        LeaveHistoryEvent(
          label: 'Approved by HR',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks: request.hrRemarks,
          completed: true,
        ),
      if (hrRejected)
        LeaveHistoryEvent(
          label: 'Rejected by HR',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks:
              (request.disapprovalReason ?? request.hrRemarks)
                      ?.trim()
                      .isNotEmpty ==
                  true
              ? (request.disapprovalReason ?? request.hrRemarks)
              : null,
          completed: true,
        ),
    ];
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Office/Department', value: request.officeDepartment ?? '—'),
      (label: 'Position Title', value: request.positionTitle ?? '—'),
      (
        label: 'Salary',
        value: request.salary != null
            ? request.salary!.toStringAsFixed(2)
            : '—',
      ),
      (label: 'Custom Leave Type', value: request.customLeaveTypeText ?? '—'),
      (label: 'Location', value: request.locationOption?.displayName ?? '—'),
      (label: 'Location Details', value: request.locationDetails ?? '—'),
      (
        label: 'Sick Leave Nature',
        value: request.sickLeaveNature?.displayName ?? '—',
      ),
      (label: 'Sick Illness Details', value: request.sickIllnessDetails ?? '—'),
      (
        label: 'Women Illness Details',
        value: request.womenIllnessDetails ?? '—',
      ),
      (label: 'Study Purpose', value: request.studyPurpose?.displayName ?? '—'),
      (
        label: 'Study Purpose Details',
        value: request.studyPurposeDetails ?? '—',
      ),
      (label: 'Other Purpose', value: request.otherPurpose?.displayName ?? '—'),
      (
        label: 'Other Purpose Details',
        value: request.otherPurposeDetails ?? '—',
      ),
    ];

    final attachmentName = request.attachmentName?.trim();
    final hasAttachment = attachmentName != null && attachmentName.isNotEmpty;
    final requestId = request.id;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ...rows
            .where((r) => r.label != 'Attachment')
            .map(
              (item) => SizedBox(
                width: 260,
                child: _InfoTile(label: item.label, value: item.value),
              ),
            ),
        SizedBox(
          width: 260,
          child: _AttachmentTile(
            requestId: requestId,
            attachmentName: attachmentName,
            hasAttachment: hasAttachment,
          ),
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.requestId,
    required this.attachmentName,
    required this.hasAttachment,
  });

  final String? requestId;
  final String? attachmentName;
  final bool hasAttachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachment',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (!hasAttachment)
            Text(
              'No attachment linked yet',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    attachmentName!,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: requestId != null && requestId!.isNotEmpty
                      ? () => _openOrDownloadAttachment(context)
                      : null,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('View'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openOrDownloadAttachment(BuildContext context) async {
    if (requestId == null || requestId!.isEmpty) return;

    final provider = context.read<LeaveProvider>();
    final snackbar = ScaffoldMessenger.of(context);

    try {
      snackbar.showSnackBar(
        const SnackBar(content: Text('Downloading attachment...')),
      );
      final bytes = await provider.getAttachmentBytes(requestId!);
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        snackbar.showSnackBar(
          const SnackBar(content: Text('Attachment could not be loaded.')),
        );
        return;
      }

      snackbar.clearSnackBars();
      snackbar.showSnackBar(
        const SnackBar(content: Text('Opening attachment...')),
      );

      final name = attachmentName ?? 'attachment';
      await open_attachment.openAttachmentBytes(bytes, name);
      if (context.mounted) {
        snackbar.showSnackBar(
          const SnackBar(content: Text('Attachment opened.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        snackbar.showSnackBar(
          SnackBar(content: Text('Could not open attachment: $e')),
        );
      }
    }
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.request, this.leaveBalance});

  final LeaveRequest request;
  final LeaveBalance? leaveBalance;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _withPayController;
  late final TextEditingController _withoutPayController;
  late final TextEditingController _remarksController;

  double get _totalRequested => widget.request.workingDaysApplied ?? 0.0;

  @override
  void initState() {
    super.initState();
    _withPayController = TextEditingController(
      text: _totalRequested.toStringAsFixed(1),
    );
    _withoutPayController = TextEditingController(text: '0.0');
    _remarksController = TextEditingController();
  }

  @override
  void dispose() {
    _withPayController.dispose();
    _withoutPayController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String? _validateApprovedDays(String? value) {
    final withPay = _parseDouble(_withPayController.text) ?? 0;
    final withoutPay = _parseDouble(_withoutPayController.text) ?? 0;
    if (withPay < 0 || withoutPay < 0) {
      return 'Days cannot be negative.';
    }
    final sum = withPay + withoutPay;
    if (sum > _totalRequested) {
      return 'Approved with pay + without pay must not exceed total requested ($_totalRequested days).';
    }
    if (sum != _totalRequested) {
      return 'Approved days must equal total requested ($_totalRequested days).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final balanceLabel = widget.leaveBalance != null
        ? '${widget.leaveBalance!.leaveType.displayName}: ${widget.leaveBalance!.remainingDays.toStringAsFixed(1)} days remaining'
        : 'No balance record for this leave type';

    return AlertDialog(
      title: const Text('Approve Leave Request'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Requested: ${_totalRequested.toStringAsFixed(1)} days',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                _DialogField(
                  controller: _withPayController,
                  label: 'Approved Days With Pay',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (_) => _validateApprovedDays(null),
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _withoutPayController,
                  label: 'Approved Days Without Pay',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (_) => _validateApprovedDays(null),
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _remarksController,
                  label: 'Remarks',
                  maxLines: null,
                  minLines: 2,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.offWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Leave Balance:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        balanceLabel,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              LeaveApprovalInput(
                requestId: widget.request.id ?? '',
                reviewerId: '',
                approvedDaysWithPay: _parseDouble(_withPayController.text),
                approvedDaysWithoutPay: _parseDouble(
                  _withoutPayController.text,
                ),
                hrRemarks: _trimOrNull(_remarksController.text),
              ),
            );
          },
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.requireReason,
    required this.request,
  });

  final String title;
  final String subtitle;
  final String confirmLabel;
  final bool requireReason;
  final LeaveRequest request;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reasonController;
  late final TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _remarksController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _DialogField(
                  controller: _reasonController,
                  label: 'Reason',
                  maxLines: null,
                  minLines: 3,
                  validator: widget.requireReason
                      ? (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Reason is required.';
                          }
                          return null;
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _remarksController,
                  label: 'HR Remarks',
                  maxLines: null,
                  minLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              LeaveReviewDecisionInput(
                requestId: widget.request.id ?? '',
                reviewerId: '',
                reason: _trimOrNull(_reasonController.text),
                hrRemarks: _trimOrNull(_remarksController.text),
              ),
            );
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _inputDecoration(label),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasize
            ? AppTheme.primaryNavy.withOpacity(0.10)
            : AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: emphasize
                    ? AppTheme.primaryNavyDark
                    : AppTheme.textPrimary,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _SubsectionTitle extends StatelessWidget {
  const _SubsectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Text(
        content,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, color: Colors.red.shade700),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppTheme.offWhite,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
    ),
  );
}

double? _parseDouble(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

String? _trimOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _statusLabel(
  LeaveRequestStatus status, {
  required bool isDepartmentHead,
}) {
  if (!isDepartmentHead) return status.displayName;
  return switch (status) {
    LeaveRequestStatus.pendingDepartmentHead => 'Pending',
    LeaveRequestStatus.rejectedByDepartmentHead => 'Rejected',
    _ => status.displayName,
  };
}
