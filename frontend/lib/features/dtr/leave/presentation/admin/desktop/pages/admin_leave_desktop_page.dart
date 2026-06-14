import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/employee_leave_card_view_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_balance_history_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/pages/leave_type_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_monthly_accrual_dialog.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_request_queue.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_review_dialogs.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_shared_widgets.dart';

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
  String? _leaveTypeFilter;
  List<AdminLeaveLeaveTypeFilterOption> _configuredLeaveTypeOptions = const [];
  String? _departmentFilter;
  String? _employeeFilter;
  List<LeaveTypeDefinition> _leaveTypeDefinitions = const [];
  // #11: Date range filters.
  DateTime? _startDateFrom;
  DateTime? _startDateTo;
  Timer? _autoRefreshTimer;
  StreamSubscription<AppRealtimeEvent>? _leaveRealtimeSub;

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadLeaveTypeFilterOptions(),
    );
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
    final leaveProvider = context.read<LeaveProvider>();
    _leaveRealtimeSub ??= context.read<AppRealtimeProvider>().events.listen((
      event,
    ) {
      if (event.name != 'leave_updated') return;
      if (!mounted) return;
      leaveProvider.invalidateCachedLeaveData();
      unawaited(_safeAutoRefresh(forceRefresh: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _leaveRealtimeSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _safeAutoRefresh(forceRefresh: true);
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _safeAutoRefresh();
    });
  }

  Future<void> _loadLeaveTypeFilterOptions({bool forceRefresh = false}) async {
    try {
      final definitions = await LeaveTypeDefinitionCache.instance.listAll(
        includeInactive: true,
        forceRefresh: forceRefresh,
      );
      final options =
          definitions
              .where((item) => item.name.trim().isNotEmpty)
              .map(
                (item) => AdminLeaveLeaveTypeFilterOption(
                  value: item.name.trim(),
                  label: item.displayName.trim().isNotEmpty
                      ? item.displayName.trim()
                      : item.name.trim(),
                ),
              )
              .toList()
            ..sort((a, b) => a.label.compareTo(b.label));
      if (!mounted) return;
      setState(() {
        _leaveTypeDefinitions = definitions;
        _configuredLeaveTypeOptions = options;
      });
    } catch (_) {
      // Request rows still supply used leave types if rules cannot be loaded.
    }
  }

  List<AdminLeaveLeaveTypeFilterOption> _leaveTypeFilterOptions(
    List<LeaveRequest> requests,
  ) {
    final byValue = <String, AdminLeaveLeaveTypeFilterOption>{};
    for (final option in _configuredLeaveTypeOptions) {
      byValue[option.value] = option;
    }
    for (final request in requests) {
      final value = request.effectiveLeaveTypeName.trim();
      if (value.isEmpty) continue;
      byValue.putIfAbsent(
        value,
        () => AdminLeaveLeaveTypeFilterOption(
          value: value,
          label: request.leaveTypeLabel.trim().isNotEmpty
              ? request.leaveTypeLabel.trim()
              : value,
        ),
      );
    }
    final selected = _leaveTypeFilter?.trim();
    if (selected != null && selected.isNotEmpty) {
      byValue.putIfAbsent(
        selected,
        () => AdminLeaveLeaveTypeFilterOption(value: selected, label: selected),
      );
    }
    return byValue.values.toList()..sort((a, b) => a.label.compareTo(b.label));
  }

  LeaveTypeDefinition? _definitionForRequest(LeaveRequest request) {
    final name = request.effectiveLeaveTypeName;
    for (final item in _leaveTypeDefinitions) {
      if (item.name == name) return item;
    }
    return null;
  }

  String _creditPolicyForRequest(LeaveRequest request) {
    final raw = _definitionForRequest(request)?.balanceLedgerType.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return switch (request.leaveType) {
      LeaveType.vacationLeave => 'vacationLeave',
      LeaveType.sickLeave => 'sickLeave',
      LeaveType.mandatoryForcedLeave => 'vacationLeave',
      _ => 'none',
    };
  }

  String _creditBucketForRequest(LeaveRequest request) {
    final policy = _creditPolicyForRequest(request);
    return policy == 'ownBalance' ? request.effectiveLeaveTypeName : policy;
  }

  LeaveBalance? _balanceForBucket(List<LeaveBalance> balances, String bucket) {
    for (final balance in balances) {
      if (balance.effectiveLeaveTypeName == bucket) return balance;
    }
    return null;
  }

  String _formatAdminDays(double days) {
    return days % 1 == 0 ? days.toStringAsFixed(0) : days.toStringAsFixed(1);
  }

  double _workingDaysInYear(DateTime? start, DateTime? end, int year) {
    if (start == null || end == null) return 0;
    var d = DateTime(
      start.year < year ? year : start.year,
      start.year < year ? 1 : start.month,
      start.year < year ? 1 : start.day,
    );
    final last = DateTime(
      end.year > year ? year : end.year,
      end.year > year ? 12 : end.month,
      end.year > year ? 31 : end.day,
    );
    var count = 0;
    while (!d.isAfter(last)) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
        count += 1;
      }
      d = d.add(const Duration(days: 1));
    }
    return count.toDouble();
  }

  Future<String> _creditSummaryForRequest({
    required LeaveRequest request,
    required List<LeaveBalance> balances,
  }) async {
    final policy = _creditPolicyForRequest(request);
    if (request.effectiveLeaveTypeName ==
        LeaveType.specialPrivilegeLeave.value) {
      final year = request.startDate?.year ?? DateTime.now().year;
      final requests = await context
          .read<LeaveProvider>()
          .repository
          .listRequests(
            query: LeaveRequestQuery(
              userId: request.userId,
              leaveTypeName: LeaveType.specialPrivilegeLeave.value,
              limit: 500,
            ),
          );
      final currentId = request.id;
      final used = requests
          .where((item) {
            if (currentId != null &&
                currentId.isNotEmpty &&
                item.id == currentId) {
              return false;
            }
            if (!(item.status.isPending ||
                item.status == LeaveRequestStatus.approved)) {
              return false;
            }
            final start = item.startDate;
            final end = item.endDate;
            if (start == null || end == null) return false;
            return start.year <= year && end.year >= year;
          })
          .fold<double>(
            0,
            (total, item) =>
                total + _workingDaysInYear(item.startDate, item.endDate, year),
          );
      final remaining = (3 - used).clamp(0, 3).toDouble();
      return 'Special Privilege Leave: ${_formatAdminDays(remaining)} of 3 day(s) remaining for $year. No VL/SL deduction.';
    }
    if (policy == 'none') {
      return 'No leave credit deduction for this leave type.';
    }
    final bucket = _creditBucketForRequest(request);
    final balance = _balanceForBucket(balances, bucket);
    final bucketLabel = switch (bucket) {
      'vacationLeave' => 'Vacation Leave',
      'sickLeave' => 'Sick Leave',
      _ => request.leaveTypeLabel,
    };
    if (balance == null) {
      return '$bucketLabel credits: no balance row is available yet.';
    }
    return '$bucketLabel credits: ${balance.availableDays.toStringAsFixed(1)} available (${balance.remainingDays.toStringAsFixed(1)} remaining excl. pending).';
  }

  Future<void> _safeAutoRefresh({bool forceRefresh = false}) async {
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    if (provider.reviewing || provider.submitting) return;
    await _loadRequests(forceRefresh: forceRefresh);
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
    final leaveTypeOptions = _leaveTypeFilterOptions(requests);

    final filteredRequests = requests.where((r) {
      if (!widget.isDepartmentHead &&
          r.status == LeaveRequestStatus.pendingDepartmentHead) {
        return false;
      }
      final statusOk = _statusFilter == null || r.status == _statusFilter;
      if (!statusOk) return false;
      final leaveTypeOk =
          _leaveTypeFilter == null ||
          r.effectiveLeaveTypeName == _leaveTypeFilter;
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
              .where(
                (r) => widget.isDepartmentHead
                    ? r.status == LeaveRequestStatus.pendingDepartmentHead
                    : r.status.isPending,
              )
              .length,
          reviewing: provider.reviewing,
          onRefresh: () => _loadRequests(forceRefresh: true),
          onForcedLeaveDeduction: widget.isDepartmentHead
              ? null
              : _applyForcedLeaveDeduction,
          onMonthlyAccrual: widget.isDepartmentHead ? null : _runMonthlyAccrual,
          onManualBalanceAdjustment: widget.isDepartmentHead
              ? null
              : _manualBalanceAdjustment,
          onEmployeeLeaveCard: widget.isDepartmentHead
              ? null
              : _openEmployeeLeaveCard,
          onLeaveLedger: widget.isDepartmentHead ? null : _openLeaveLedger,
          onLeaveTypeRules: widget.isDepartmentHead
              ? null
              : _openLeaveTypeRules,
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 16),
          AdminLeaveErrorBanner(
            message: provider.error!,
            onDismiss: provider.clearError,
          ),
        ],
        const SizedBox(height: 24),
        AdminLeaveRequestQueuePanel(
          requests: filteredRequests,
          isDepartmentHead: widget.isDepartmentHead,
          loading: provider.loading,
          selectedRequest: selected,
          filterBar: AdminLeaveFilterBar(
            isDepartmentHead: widget.isDepartmentHead,
            status: _statusFilter,
            leaveType: _leaveTypeFilter,
            leaveTypeOptions: leaveTypeOptions,
            department: _departmentFilter,
            departments: departments,
            employee: _employeeFilter,
            employees: employees
                .map(
                  (e) => AdminLeaveEmployeeFilterOption(id: e.id, name: e.name),
                )
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
            onEmployeeChanged: (value) =>
                setState(() => _employeeFilter = value),
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
          onSelect: (request) {
            setState(() => _selectedRequest = request);
            _openRequestDetailsPanel(request);
          },
        ),
      ],
    );
  }

  Future<void> _loadRequests({bool forceRefresh = false}) async {
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    final query = LeaveRequestQuery(
      status: _statusFilter,
      leaveTypeName: _leaveTypeFilter,
      startDateFrom: _startDateFrom,
      startDateTo: _startDateTo,
      limit: 200,
    );
    if (widget.isDepartmentHead) {
      await provider.loadDepartmentHeadRequests(
        query: query,
        forceRefresh: forceRefresh,
      );
    } else {
      await provider.loadRequests(query: query, forceRefresh: forceRefresh);
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
        builder: (ctx) => AdminLeaveDetailsSideSheet(
          initial: request,
          isDepartmentHead: widget.isDepartmentHead,
          onApprove: widget.isDepartmentHead ? _deptHeadApprove : _approve,
          onReturn: widget.isDepartmentHead ? _deptHeadReturn : _returnRequest,
          onReject: widget.isDepartmentHead ? _deptHeadReject : _rejectRequest,
          onRevoke: widget.isDepartmentHead ? null : _revokeApproval,
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
      final formSignatories = await loadLeaveFormSignatories(request: target);

      final balances = await provider.fetchBalancesForUser(
        target.userId,
        forceRefresh: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Preparing print...')));
      }

      await LeaveRequestPdf.printLeaveRequest(
        request: target,
        balances: balances,
        certificationOfficerName: formSignatories.certificationOfficer?.name,
        certificationOfficerTitle: formSignatories.certificationOfficer?.title,
        recommendationOfficerName: formSignatories.recommendationOfficer?.name,
        recommendationOfficerTitle:
            formSignatories.recommendationOfficer?.title,
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
    final leaveProvider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    final userId = request.userId;
    if (userId.isEmpty) {
      _showMessage('Cannot determine employee for this request.');
      return;
    }
    final balances = await leaveProvider.fetchBalancesForUser(
      userId,
      forceRefresh: true,
    );
    final creditBucket = _creditBucketForRequest(request);
    final leaveBalance = _balanceForBucket(balances, creditBucket);
    String creditSummary;
    try {
      creditSummary = await _creditSummaryForRequest(
        request: request,
        balances: balances,
      );
    } catch (_) {
      creditSummary =
          'Credit policy could not be refreshed. Final approval will still be validated by the server.';
    }

    if (!mounted) return;
    final input = await showDialog<LeaveApprovalInput>(
      context: context,
      builder: (_) => AdminLeaveApproveDialog(
        request: request,
        leaveBalance: leaveBalance,
        creditSummary: creditSummary,
      ),
    );
    if (input == null || !mounted) return;

    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);
    if (!mounted) return;

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
      final result = await leaveProvider.approveRequest(finalInput);
      ok = result != null;
    }
    if (!mounted) return;
    _showMessage(
      ok
          ? 'Leave request approved.'
          : (leaveProvider.error ?? 'Approval could not be completed.'),
    );
    if (ok) {
      await _loadRequests();
    }
  }

  Future<void> _returnRequest(LeaveRequest request) async {
    final leaveProvider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    final input = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => AdminLeaveDecisionDialog(
        title: 'Return Request',
        subtitle:
            'Send this request back to the employee for correction or missing information.',
        confirmLabel: 'Return Request',
        requireReason: true,
        request: request,
      ),
    );
    if (input == null || !mounted) return;

    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);
    if (!mounted) return;

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
      final result = await leaveProvider.returnRequest(finalInput);
      ok = result != null;
    }
    if (!mounted) return;
    _showMessage(ok ? 'Leave request returned.' : 'Return action failed.');
    if (ok) {
      await _loadRequests();
    }
  }

  Future<void> _rejectRequest(LeaveRequest request) async {
    final leaveProvider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    final input = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => AdminLeaveDecisionDialog(
        title: 'Reject Request',
        subtitle:
            'Reject this request and provide a clear reason for the employee.',
        confirmLabel: 'Reject Request',
        requireReason: true,
        request: request,
      ),
    );
    if (input == null || !mounted) return;

    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);
    if (!mounted) return;

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
      final result = await leaveProvider.rejectRequest(finalInput);
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
    final revokeDisabledReason = adminLeaveRevokeDisabledReason(request);
    if (revokeDisabledReason != null) {
      _showMessage(revokeDisabledReason);
      return;
    }
    final leaveProvider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    final input = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => AdminLeaveDecisionDialog(
        title: 'Revoke Approval',
        subtitle:
            'This will reverse the approval: balance will be restored and DTR leave entries removed. The request returns to the employee for correction.',
        confirmLabel: 'Revoke Approval',
        requireReason: false,
        request: request,
      ),
    );
    if (input == null || !mounted) return;

    final reviewerId = auth.user?.id;
    final reviewerRole = auth.user?.role;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }
    final reviewerInfo = await _loadReviewerSignatureInfo(auth);
    if (!mounted) return;

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

    final result = await leaveProvider.revokeApproval(finalInput);
    final ok = result != null;
    if (!mounted) return;
    _showMessage(
      ok
          ? 'Approval revoked. Leave balance restored.'
          : (leaveProvider.error ?? 'Revoke failed.'),
    );
    if (ok) await _loadRequests();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyForcedLeaveDeduction() async {
    final leaveProvider = context.read<LeaveProvider>();
    final input = await showDialog<_ForcedLeaveDeductionInput>(
      context: context,
      builder: (_) => const _ForcedLeaveDeductionDialog(),
    );
    if (input == null || !mounted) return;

    final result = await leaveProvider.applyForcedLeaveDeduction(
      ForcedLeaveDeductionInput(
        userId: input.userId,
        daysToDeduct: input.daysToDeduct,
        year: input.year,
        remarks: input.remarks,
      ),
    );
    if (!mounted) return;
    final ok = result != null;
    _showMessage(
      ok
          ? 'Year-end forced leave deduction applied.'
          : (leaveProvider.error ?? 'Deduction action failed.'),
    );
    if (ok) await _loadRequests();
  }

  Future<void> _runMonthlyAccrual() async {
    final result = await showDialog<MonthlyLeaveAccrualResult>(
      context: context,
      builder: (_) => const AdminMonthlyAccrualDialog(),
    );
    if (!mounted || result == null) return;
    _showMessage(
      result.rowsUpdated > 0
          ? 'Monthly accrual applied for ${result.targetYearMonth}: ${result.rowsUpdated} balance rows updated.'
          : 'Monthly accrual completed. No balances changed.',
    );
    await _loadRequests();
  }

  Future<void> _manualBalanceAdjustment() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _ManualBalanceAdjustmentDialog(),
    );
    if (!mounted || saved != true) return;
    _showMessage('Leave balance saved.');
    await _loadRequests();
  }

  void _openLeaveLedger() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LeaveBalanceHistoryScreen(
          isAdmin: true,
          initialFilterUserId: _employeeFilter,
        ),
      ),
    );
  }

  Future<void> _openEmployeeLeaveCard() async {
    final selected = await showDialog<_EmployeeLeaveCardSelection>(
      context: context,
      builder: (_) => const _EmployeeLeaveCardPickerDialog(),
    );
    if (!mounted || selected == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeLeaveCardViewScreen(
          userId: selected.userId,
          employeeName: selected.name,
        ),
      ),
    );
  }

  // ---- Department Head actions ----

  Future<void> _deptHeadApprove(LeaveRequest request) async {
    final leaveProvider = context.read<LeaveProvider>();
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
    final result = await leaveProvider.departmentHeadApprove(input);
    final ok = result != null;
    if (!mounted) return;
    _showMessage(
      ok
          ? 'Forwarded to HR for final approval.'
          : (leaveProvider.error ?? 'Department head approval failed.'),
    );
    if (ok) await _loadRequests();
  }

  Future<void> _deptHeadReject(LeaveRequest request) async {
    final leaveProvider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    final dialogResult = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => AdminLeaveDecisionDialog(
        title: 'Reject Request',
        subtitle: 'Reject this request as department head.',
        confirmLabel: 'Reject',
        requireReason: true,
        request: request,
      ),
    );
    if (dialogResult == null || !mounted) return;

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
    final result = await leaveProvider.departmentHeadReject(input);
    final ok = result != null;
    if (!mounted) return;
    _showMessage(ok ? 'Request rejected.' : 'Reject action failed.');
    if (ok) await _loadRequests();
  }

  Future<void> _deptHeadReturn(LeaveRequest request) async {
    final leaveProvider = context.read<LeaveProvider>();
    final auth = context.read<AuthProvider>();
    final dialogResult = await showDialog<LeaveReviewDecisionInput>(
      context: context,
      builder: (_) => AdminLeaveDecisionDialog(
        title: 'Return Request',
        subtitle: 'Return this to the employee for corrections.',
        confirmLabel: 'Return',
        requireReason: true,
        request: request,
      ),
    );
    if (dialogResult == null || !mounted) return;

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
    final result = await leaveProvider.departmentHeadReturn(input);
    final ok = result != null;
    if (!mounted) return;
    _showMessage(ok ? 'Request returned.' : 'Return action failed.');
    if (ok) await _loadRequests();
  }

  Future<void> _openLeaveTypeRules() async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: const LeaveTypeManagementScreen(),
      ),
    );
    if (!mounted) return;
    await _loadLeaveTypeFilterOptions(forceRefresh: true);
  }
}

class _HeaderMenuAction {
  const _HeaderMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.separatedBefore = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function() onSelected;
  final bool separatedBefore;
}

class _AdminHeaderCard extends StatelessWidget {
  const _AdminHeaderCard({
    required this.totalRequests,
    required this.pendingCount,
    required this.reviewing,
    required this.onRefresh,
    this.onForcedLeaveDeduction,
    this.onMonthlyAccrual,
    this.onManualBalanceAdjustment,
    this.onEmployeeLeaveCard,
    this.onLeaveLedger,
    this.onLeaveTypeRules,
  });

  final int totalRequests;
  final int pendingCount;
  final bool reviewing;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onForcedLeaveDeduction;
  final Future<void> Function()? onMonthlyAccrual;
  final Future<void> Function()? onManualBalanceAdjustment;
  final Future<void> Function()? onEmployeeLeaveCard;
  final VoidCallback? onLeaveLedger;
  final Future<void> Function()? onLeaveTypeRules;

  @override
  Widget build(BuildContext context) {
    final menuActions = <_HeaderMenuAction>[
      if (onLeaveTypeRules != null)
        _HeaderMenuAction(
          label: 'Leave Type Rules',
          icon: Icons.rule_rounded,
          onSelected: onLeaveTypeRules!,
        ),
      if (onLeaveLedger != null)
        _HeaderMenuAction(
          label: 'Leave Ledger',
          icon: Icons.receipt_long_outlined,
          onSelected: onLeaveLedger!,
        ),
      if (onEmployeeLeaveCard != null)
        _HeaderMenuAction(
          label: "Employee's Leave Card",
          icon: Icons.badge_outlined,
          onSelected: onEmployeeLeaveCard!,
        ),
      if (onManualBalanceAdjustment != null)
        _HeaderMenuAction(
          label: 'Manual balance adjustment',
          icon: Icons.account_balance_wallet_outlined,
          onSelected: onManualBalanceAdjustment!,
        ),
      if (onMonthlyAccrual != null)
        _HeaderMenuAction(
          label: 'Run Monthly Accrual',
          icon: Icons.event_repeat_rounded,
          onSelected: onMonthlyAccrual!,
        ),
      if (onForcedLeaveDeduction != null)
        _HeaderMenuAction(
          label: 'Apply Year-End Forced Leave Deduction',
          icon: Icons.assignment_turned_in_rounded,
          onSelected: onForcedLeaveDeduction!,
          separatedBefore: true,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final titleStyle = TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: isMobile ? 20 : 24,
          fontWeight: FontWeight.w700,
        );
        final refreshButton = FilledButton.icon(
          onPressed: reviewing ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(reviewing ? 'Reviewing...' : 'Refresh'),
        );
        final menuButton = menuActions.isEmpty
            ? null
            : PopupMenuButton<_HeaderMenuAction>(
                tooltip: 'More actions',
                enabled: !reviewing,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) {
                  action.onSelected();
                },
                itemBuilder: (context) {
                  final entries = <PopupMenuEntry<_HeaderMenuAction>>[];
                  for (final action in menuActions) {
                    if (action.separatedBefore) {
                      entries.add(const PopupMenuDivider());
                    }
                    entries.add(
                      PopupMenuItem<_HeaderMenuAction>(
                        value: action,
                        child: Row(
                          children: [
                            Icon(action.icon, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(action.label)),
                          ],
                        ),
                      ),
                    );
                  }
                  return entries;
                },
              );

        if (isMobile) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.dashSurfaceCard(context, radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Text('Leave Approvals', style: titleStyle)),
                    const SizedBox(width: 10),
                    refreshButton,
                    if (menuButton != null) ...[
                      const SizedBox(width: 4),
                      menuButton,
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _CompactHeaderCount(value: totalRequests, label: 'loaded'),
                    _CompactHeaderCount(
                      value: pendingCount,
                      label: 'pending',
                      emphasize: true,
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: AppTheme.dashSurfaceCard(context, radius: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leave Approvals', style: titleStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Review employee leave applications, inspect their form details, and record approval decisions.',
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          AdminLeaveHeaderChip(
                            label: 'Total Loaded',
                            value: '$totalRequests',
                          ),
                          AdminLeaveHeaderChip(
                            label: 'Pending',
                            value: '$pendingCount',
                            emphasize: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  refreshButton,
                  if (menuButton != null) ...[
                    const SizedBox(width: 8),
                    menuButton,
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CompactHeaderCount extends StatelessWidget {
  const _CompactHeaderCount({
    required this.value,
    required this.label,
    this.emphasize = false,
  });

  final int value;
  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final color = emphasize
        ? (AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy)
        : AppTheme.dashTextSecondaryOf(context);
    return Text(
      '$value $label',
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800),
    );
  }
}

class _ForcedLeaveDeductionInput {
  const _ForcedLeaveDeductionInput({
    required this.userId,
    required this.daysToDeduct,
    required this.year,
    this.remarks,
  });

  final String userId;
  final double daysToDeduct;
  final int year;
  final String? remarks;
}

class _EmployeeLeaveCardSelection {
  const _EmployeeLeaveCardSelection({required this.userId, required this.name});

  final String userId;
  final String name;
}

class _EmployeeLeaveCardPickerDialog extends StatefulWidget {
  const _EmployeeLeaveCardPickerDialog();

  @override
  State<_EmployeeLeaveCardPickerDialog> createState() =>
      _EmployeeLeaveCardPickerDialogState();
}

class _EmployeeLeaveCardPickerDialogState
    extends State<_EmployeeLeaveCardPickerDialog> {
  bool _loadingEmployees = true;
  String? _employeesError;
  List<Map<String, String>> _allEmployees = const [];
  List<Map<String, String>> _employees = const [];
  List<String> _departments = const [];
  String? _selectedDepartment;
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loadingEmployees = true;
      _employeesError = null;
    });
    try {
      final departmentsRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final departmentNameById = <String, String>{};
      for (final raw in (departmentsRes.data ?? const [])) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final id = row['id']?.toString() ?? '';
        final name = row['name']?.toString().trim() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          departmentNameById[id] = name;
        }
      }

      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: const {'status': 'Active', 'limit': 1000, 'offset': 0},
      );
      final payload = res.data;
      final employeeRows = payload is Map
          ? (payload['employees'] as List<dynamic>? ?? const <dynamic>[])
          : (payload is List ? payload : const <dynamic>[]);
      final rows =
          employeeRows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => {
                  'id': e['id']?.toString() ?? '',
                  'name': e['full_name']?.toString() ?? 'Unnamed',
                  'department': _extractDepartment(
                    e,
                    departmentNameById: departmentNameById,
                  ),
                },
              )
              .where((e) => (e['id'] ?? '').isNotEmpty)
              .toList()
            ..sort((a, b) => (a['name']!).compareTo(b['name']!));
      final departmentsFromApi = departmentNameById.values.toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final departmentsFromEmployees =
          rows
              .map((e) => (e['department'] ?? '').trim())
              .where((d) => d.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final departments = departmentsFromApi.isNotEmpty
          ? departmentsFromApi
          : departmentsFromEmployees;
      setState(() {
        _allEmployees = rows;
        _departments = departments;
        _selectedDepartment = null;
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

  String _extractDepartment(
    Map<String, dynamic> row, {
    required Map<String, String> departmentNameById,
  }) {
    const candidates = [
      'current_department_name',
      'department',
      'department_name',
      'office_department',
      'division',
      'division_office',
      'office',
    ];
    for (final key in candidates) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    const idCandidates = ['current_department_id', 'department_id'];
    for (final key in idCandidates) {
      final id = row[key]?.toString().trim() ?? '';
      if (id.isNotEmpty && departmentNameById.containsKey(id)) {
        return departmentNameById[id]!;
      }
    }
    return '';
  }

  void _onDepartmentChanged(String? department) {
    final filtered = department == null || department.isEmpty
        ? _allEmployees
        : _allEmployees
              .where((e) => (e['department'] ?? '').trim() == department)
              .toList();
    setState(() {
      _selectedDepartment = department;
      _employees = filtered;
      _selectedUserId = filtered.isNotEmpty ? filtered.first['id'] : null;
    });
  }

  void _confirmSelection() {
    final selectedUserId = _selectedUserId;
    if (selectedUserId == null || selectedUserId.isEmpty) return;
    final selectedEmployee = _employees.firstWhere(
      (e) => e['id'] == selectedUserId,
      orElse: () => {'id': selectedUserId, 'name': 'Selected employee'},
    );
    Navigator.of(context).pop(
      _EmployeeLeaveCardSelection(
        userId: selectedUserId,
        name: selectedEmployee['name'] ?? 'Selected employee',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(
                alpha: AppTheme.dashIsDark(context) ? 0.28 : 0.12,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.badge_outlined,
              color: AppTheme.dashIsDark(context)
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text("Employee's Leave Card")),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose an employee to view the leave card.',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
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
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dashMutedSurfaceOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dashHairlineOf(context)),
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedDepartment,
                      isExpanded: true,
                      dropdownColor: AppTheme.dashPanelOf(context),
                      style: AppTheme.dashFieldTextStyle(context),
                      decoration: adminLeaveInputDecoration(
                        context,
                        'Department',
                      ).copyWith(isDense: true),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All Departments'),
                        ),
                        ..._departments.map(
                          (department) => DropdownMenuItem<String>(
                            value: department,
                            child: Text(department),
                          ),
                        ),
                      ],
                      onChanged: _onDepartmentChanged,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedUserId,
                      isExpanded: true,
                      dropdownColor: AppTheme.dashPanelOf(context),
                      style: AppTheme.dashFieldTextStyle(context),
                      decoration: adminLeaveInputDecoration(context, 'Employee')
                          .copyWith(
                            isDense: true,
                            helperText: _employees.isEmpty
                                ? 'No employees found for this department.'
                                : '${_employees.length} employee(s) found',
                          ),
                      items: _employees
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e['id'],
                              child: Text(e['name']!),
                            ),
                          )
                          .toList(),
                      onChanged: _employees.isEmpty
                          ? null
                          : (v) => setState(() => _selectedUserId = v),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed:
              _loadingEmployees ||
                  _employeesError != null ||
                  _selectedUserId == null ||
                  _employees.isEmpty
              ? null
              : _confirmSelection,
          icon: const Icon(Icons.visibility_rounded),
          label: const Text('View Leave Card'),
        ),
      ],
    );
  }
}

class _ForcedLeaveDeductionDialog extends StatefulWidget {
  const _ForcedLeaveDeductionDialog();

  @override
  State<_ForcedLeaveDeductionDialog> createState() =>
      _ForcedLeaveDeductionDialogState();
}

class _ForcedLeaveDeductionDialogState
    extends State<_ForcedLeaveDeductionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _daysController = TextEditingController();
  final _remarksController = TextEditingController();
  bool _loadingEmployees = true;
  String? _employeesError;
  List<Map<String, String>> _employees = const [];
  String? _selectedUserId;
  late final TextEditingController _yearController;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    _loadEmployees();
  }

  @override
  void dispose() {
    _daysController.dispose();
    _remarksController.dispose();
    _yearController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(
                alpha: AppTheme.dashIsDark(context) ? 0.28 : 0.1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.assignment_turned_in_rounded,
              color: AppTheme.dashIsDark(context)
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apply Year-End Forced Leave Deduction'),
                const SizedBox(height: 4),
                Text(
                  'Deduct unused forced leave from vacation leave credits.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
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
                    initialValue: _selectedUserId,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    decoration: adminLeaveInputDecoration(
                      context,
                      'Employee',
                    ).copyWith(prefixIcon: const Icon(Icons.person_outline)),
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      TextFormField(
                        controller: _daysController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            adminLeaveInputDecoration(
                              context,
                              'Days to Deduct',
                            ).copyWith(
                              prefixIcon: const Icon(
                                Icons.remove_circle_outline,
                              ),
                            ),
                        validator: (value) {
                          final parsed = parseAdminLeaveDouble(value ?? '');
                          if (parsed == null) return 'Enter deduction days';
                          if (parsed <= 0) return 'Days must be greater than 0';
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _yearController,
                        keyboardType: TextInputType.number,
                        decoration: adminLeaveInputDecoration(context, 'Year')
                            .copyWith(
                              prefixIcon: const Icon(
                                Icons.calendar_today_outlined,
                              ),
                            ),
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null) return 'Enter a valid year';
                          if (parsed < 2000 || parsed > 2100) {
                            return 'Year must be between 2000 and 2100';
                          }
                          return null;
                        },
                      ),
                    ];
                    if (constraints.maxWidth < 560) {
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 12),
                          fields[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        SizedBox(width: 190, child: fields[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarksController,
                  minLines: 2,
                  maxLines: null,
                  decoration:
                      adminLeaveInputDecoration(
                        context,
                        'Remarks (Optional)',
                      ).copyWith(
                        alignLabelWithHint: true,
                        prefixIcon: const Icon(Icons.notes_outlined),
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dashMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fallback action for unused forced leave. This deducts vacation leave credits directly '
                          'and records an audit trail; it does not create a leave request.',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
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
        FilledButton.icon(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final days = parseAdminLeaveDouble(_daysController.text);
            if (days == null || days <= 0) return;
            final year = int.tryParse(_yearController.text.trim());
            if (year == null) return;
            Navigator.of(context).pop(
              _ForcedLeaveDeductionInput(
                userId: _selectedUserId!,
                daysToDeduct: days,
                year: year,
                remarks: trimAdminLeaveOrNull(_remarksController.text),
              ),
            );
          },
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Apply Deduction'),
        ),
      ],
    );
  }
}

class _ManualBalanceAdjustmentDialog extends StatefulWidget {
  const _ManualBalanceAdjustmentDialog();

  @override
  State<_ManualBalanceAdjustmentDialog> createState() =>
      _ManualBalanceAdjustmentDialogState();
}

class _ManualBalanceAdjustmentDialogState
    extends State<_ManualBalanceAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _earnedController = TextEditingController();
  final _usedController = TextEditingController();
  final _pendingController = TextEditingController();
  final _adjustedController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _loadingEmployees = true;
  bool _loadingBalances = false;
  String? _employeesError;
  List<String> _departments = const [];
  List<Map<String, String>> _employees = const [];
  String? _selectedDepartment;
  String? _selectedUserId;
  DateTime _asOfDate = DateTime.now();

  LeaveType _selectedLeaveType = LeaveType.vacationLeave;
  List<LeaveBalance> _balances = const [];

  List<TextEditingController> get _balanceControllers => [
    _earnedController,
    _usedController,
    _pendingController,
    _adjustedController,
  ];

  @override
  void dispose() {
    for (final controller in _balanceControllers) {
      controller.removeListener(_refreshPreview);
    }
    _earnedController.dispose();
    _usedController.dispose();
    _pendingController.dispose();
    _adjustedController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    for (final controller in _balanceControllers) {
      controller.addListener(_refreshPreview);
    }
    _loadEmployees();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loadingEmployees = true;
      _employeesError = null;
    });
    try {
      final departmentsRes = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
        queryParameters: const {'status': 'Active'},
      );
      final departmentsFromApi =
          (departmentsRes.data ?? const [])
              .whereType<Map>()
              .map((e) => e['name']?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: const {'status': 'Active', 'limit': 1000, 'offset': 0},
      );
      final payload = res.data;
      final employeeRows = payload is Map
          ? (payload['employees'] as List<dynamic>? ?? const <dynamic>[])
          : (payload is List ? payload : const <dynamic>[]);
      final rows =
          employeeRows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => {
                  'id': e['id']?.toString() ?? '',
                  'name': e['full_name']?.toString() ?? 'Unnamed',
                  'department':
                      e['current_department_name']?.toString().trim() ?? '',
                },
              )
              .where((e) => (e['id'] ?? '').isNotEmpty)
              .toList()
            ..sort((a, b) => (a['name']!).compareTo(b['name']!));
      final departmentsFromEmployees =
          rows
              .map((e) => (e['department'] ?? '').trim())
              .where((department) => department.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final departments = departmentsFromApi.isNotEmpty
          ? departmentsFromApi
          : departmentsFromEmployees;
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _employees = rows;
        _selectedDepartment = null;
        _selectedUserId = null;
        _loadingEmployees = false;
      });
      _applyBalanceToFields();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _employeesError = e.toString();
        _loadingEmployees = false;
      });
    }
  }

  Future<void> _loadBalancesFor(String userId) async {
    setState(() {
      _loadingBalances = true;
      _balances = const [];
    });
    try {
      final list = await context.read<LeaveProvider>().fetchBalancesForUser(
        userId,
      );
      if (!mounted || _selectedUserId != userId) return;
      setState(() {
        _balances = list;
        _loadingBalances = false;
      });
      _applyBalanceToFields();
    } catch (_) {
      if (!mounted || _selectedUserId != userId) return;
      setState(() {
        _balances = const [];
        _loadingBalances = false;
      });
      _applyBalanceToFields();
    }
  }

  void _applyBalanceToFields() {
    final row = _selectedBalance;
    _earnedController.text = _formatDays(row?.earnedDays ?? 0);
    _usedController.text = _formatDays(row?.usedDays ?? 0);
    _pendingController.text = _formatDays(row?.pendingDays ?? 0);
    _adjustedController.text = _formatDays(row?.adjustedDays ?? 0);
    _asOfDate = row?.asOfDate ?? DateTime.now();
    _refreshPreview();
  }

  Future<void> _onEmployeeChanged(String? id) async {
    setState(() {
      _selectedUserId = id;
      _balances = const [];
    });
    if (id != null && id.isNotEmpty) {
      await _loadBalancesFor(id);
    }
  }

  void _onDepartmentChanged(String? department) {
    setState(() {
      _selectedDepartment = department;
      _selectedUserId = null;
      _balances = const [];
    });
    _applyBalanceToFields();
  }

  Future<void> _pickAsOfDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOfDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _asOfDate = picked);
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uid = _selectedUserId;
    if (uid == null || uid.isEmpty) return;

    final balance = LeaveBalance(
      userId: uid,
      leaveType: _selectedLeaveType,
      earnedDays: parseAdminLeaveDouble(_earnedController.text) ?? 0,
      usedDays: parseAdminLeaveDouble(_usedController.text) ?? 0,
      pendingDays: parseAdminLeaveDouble(_pendingController.text) ?? 0,
      adjustedDays: parseAdminLeaveDouble(_adjustedController.text) ?? 0,
      asOfDate: _asOfDate,
    );

    final saved = await context.read<LeaveProvider>().upsertBalance(
      balance,
      remarks: trimAdminLeaveOrNull(_remarksController.text),
    );
    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop(true);
    } else {
      final err = context.read<LeaveProvider>().error ?? 'Save failed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  LeaveBalance? get _selectedBalance {
    for (final balance in _balances) {
      if (balance.leaveType == _selectedLeaveType) return balance;
    }
    return null;
  }

  LeaveBalance get _draftBalance {
    return LeaveBalance(
      userId: _selectedUserId ?? '',
      leaveType: _selectedLeaveType,
      earnedDays: parseAdminLeaveDouble(_earnedController.text) ?? 0,
      usedDays: parseAdminLeaveDouble(_usedController.text) ?? 0,
      pendingDays: parseAdminLeaveDouble(_pendingController.text) ?? 0,
      adjustedDays: parseAdminLeaveDouble(_adjustedController.text) ?? 0,
      asOfDate: _asOfDate,
    );
  }

  String get _selectedEmployeeName {
    for (final employee in _employees) {
      if (employee['id'] == _selectedUserId) {
        return employee['name'] ?? 'Selected employee';
      }
    }
    return 'Select an employee';
  }

  List<Map<String, String>> get _filteredEmployees {
    final department = _selectedDepartment?.trim();
    if (department == null || department.isEmpty) return const [];
    return _employees
        .where((e) => (e['department'] ?? '').trim() == department)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.watch<LeaveProvider>().submitting;
    final hasDepartments = _departments.isNotEmpty;
    final hasEmployees = _filteredEmployees.isNotEmpty;
    final hasSelectedEmployee =
        _selectedUserId != null && _selectedUserId!.isNotEmpty;
    final canSave =
        !saving &&
        !_loadingEmployees &&
        !_loadingBalances &&
        _employeesError == null &&
        hasDepartments &&
        hasEmployees &&
        hasSelectedEmployee;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(
                alpha: AppTheme.dashIsDark(context) ? 0.28 : 0.1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: AppTheme.dashIsDark(context)
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Manual Balance Adjustment'),
                const SizedBox(height: 4),
                Text(
                  'Update leave credit buckets and record an audit note.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
                else if (!hasDepartments)
                  _statusPanel(
                    icon: Icons.apartment_outlined,
                    message:
                        'No active departments are available for adjustment.',
                  )
                else ...[
                  _sectionHeader(
                    icon: Icons.person_search_outlined,
                    title: 'Employee and Leave Type',
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'manual-balance-department-${_selectedDepartment ?? ''}',
                    ),
                    initialValue: _selectedDepartment,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    decoration: adminLeaveInputDecoration(context, 'Department')
                        .copyWith(
                          prefixIcon: const Icon(Icons.apartment_outlined),
                        ),
                    items: _departments
                        .map(
                          (department) => DropdownMenuItem<String>(
                            value: department,
                            child: Text(department),
                          ),
                        )
                        .toList(),
                    onChanged: saving ? null : _onDepartmentChanged,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Select a department' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'manual-balance-employee-${_selectedDepartment ?? ''}-${_selectedUserId ?? ''}',
                    ),
                    initialValue: _selectedUserId,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    decoration: adminLeaveInputDecoration(context, 'Employee')
                        .copyWith(
                          prefixIcon: const Icon(Icons.person_outline),
                          hintText: _selectedDepartment == null
                              ? 'Select department first'
                              : (hasEmployees
                                    ? 'Select employee'
                                    : 'No employees in this department'),
                        ),
                    items: _filteredEmployees
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e['id'],
                            child: Text(e['name']!),
                          ),
                        )
                        .toList(),
                    onChanged: saving || _selectedDepartment == null
                        ? null
                        : (v) {
                            if (v != null) unawaited(_onEmployeeChanged(v));
                          },
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Select an employee' : null,
                  ),
                  if (_selectedDepartment != null && !hasEmployees) ...[
                    const SizedBox(height: 12),
                    _statusPanel(
                      icon: Icons.person_off_outlined,
                      message: 'No active employees found for this department.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 560;
                      final leaveTypeField = DropdownButtonFormField<LeaveType>(
                        initialValue: _selectedLeaveType,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        decoration:
                            adminLeaveInputDecoration(
                              context,
                              'Leave type',
                            ).copyWith(
                              prefixIcon: const Icon(Icons.event_note_outlined),
                            ),
                        items: LeaveType.values
                            .map(
                              (t) => DropdownMenuItem<LeaveType>(
                                value: t,
                                child: Text(t.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: saving || _loadingBalances
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _selectedLeaveType = v);
                                _applyBalanceToFields();
                              },
                      );
                      final asOfField = _asOfDateField(
                        saving || !hasSelectedEmployee,
                      );
                      if (narrow) {
                        return Column(
                          children: [
                            leaveTypeField,
                            const SizedBox(height: 12),
                            asOfField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: leaveTypeField),
                          const SizedBox(width: 12),
                          SizedBox(width: 210, child: asOfField),
                        ],
                      );
                    },
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _loadingBalances
                        ? const Padding(
                            key: ValueKey('balance-loading'),
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(minHeight: 2),
                          )
                        : const SizedBox(
                            key: ValueKey('balance-idle'),
                            height: 12,
                          ),
                  ),
                  _balancePreviewPanel(
                    current: _selectedBalance,
                    draft: _draftBalance,
                  ),
                  const SizedBox(height: 18),
                  _sectionHeader(
                    icon: Icons.tune_outlined,
                    title: 'Balance Buckets',
                    trailing: IconButton(
                      onPressed: saving || _loadingBalances
                          ? null
                          : _applyBalanceToFields,
                      icon: const Icon(Icons.restore_rounded),
                      tooltip: 'Reset loaded values',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _balanceFieldGrid(
                    enabled:
                        !saving && !_loadingBalances && hasSelectedEmployee,
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader(
                    icon: Icons.history_edu_outlined,
                    title: 'Audit Note',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _remarksController,
                    enabled: !saving && hasSelectedEmployee,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        adminLeaveInputDecoration(
                          context,
                          'Reason / remarks',
                        ).copyWith(
                          alignLabelWithHint: true,
                          prefixIcon: const Icon(Icons.notes_outlined),
                          hintText:
                              'Example: Corrected imported opening balance',
                        ),
                  ),
                  const SizedBox(height: 12),
                  _statusPanel(
                    icon: _draftBalance.availableDays < 0
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    message: _draftBalance.availableDays < 0
                        ? 'Resulting available balance is negative. Save only if this reflects the intended HR correction.'
                        : 'Approvals continue to update used and pending days automatically after this adjustment.',
                    warning: _draftBalance.availableDays < 0,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: canSave ? _onSave : null,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(saving ? 'Saving...' : 'Update balance'),
        ),
      ],
    );
  }

  Widget _asOfDateField(bool saving) {
    return InkWell(
      onTap: saving ? null : _pickAsOfDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: adminLeaveInputDecoration(
          context,
          'As of date',
        ).copyWith(prefixIcon: const Icon(Icons.calendar_month_outlined)),
        child: Row(
          children: [
            Expanded(child: Text(formatAdminLeaveDate(_asOfDate))),
            Icon(
              Icons.expand_more_rounded,
              color: saving
                  ? AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.4)
                  : AppTheme.dashTextSecondaryOf(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceFieldGrid({required bool enabled}) {
    final fields = [
      _numberField(
        controller: _earnedController,
        label: 'Earned days',
        icon: Icons.add_circle_outline,
        helperText: 'Credits accrued or imported.',
        enabled: enabled,
        allowNegative: false,
      ),
      _numberField(
        controller: _usedController,
        label: 'Used days',
        icon: Icons.remove_circle_outline,
        helperText: 'Approved leave already consumed.',
        enabled: enabled,
        allowNegative: false,
      ),
      _numberField(
        controller: _pendingController,
        label: 'Pending days',
        icon: Icons.hourglass_empty_rounded,
        helperText: 'Filed requests awaiting final action.',
        enabled: enabled,
        allowNegative: false,
      ),
      _numberField(
        controller: _adjustedController,
        label: 'Adjusted days',
        icon: Icons.exposure_outlined,
        helperText: 'Use negative values to reduce credits.',
        enabled: enabled,
        allowNegative: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                fields[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 12),
                Expanded(child: fields[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: fields[2]),
                const SizedBox(width: 12),
                Expanded(child: fields[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String helperText,
    required bool enabled,
    required bool allowNegative,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      decoration: adminLeaveInputDecoration(
        context,
        label,
      ).copyWith(prefixIcon: Icon(icon), helperText: helperText),
      validator: (value) {
        final parsed = parseAdminLeaveDouble(value ?? '');
        if (parsed == null) return 'Enter $label';
        if (!allowNegative && parsed < 0) return 'Must be 0 or more';
        return null;
      },
    );
  }

  Widget _balancePreviewPanel({
    required LeaveBalance? current,
    required LeaveBalance draft,
  }) {
    final hasCurrent = current != null;
    final dark = AppTheme.dashIsDark(context);
    final availableColor = draft.availableDays < 0
        ? (dark ? Colors.red.shade300 : Colors.red.shade700)
        : (dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasCurrent ? 'Editing existing balance' : 'Creating balance',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: hasCurrent
                      ? AppTheme.primaryNavy.withValues(
                          alpha: dark ? 0.28 : 0.1,
                        )
                      : AppTheme.dashMutedSurfaceOf(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasCurrent ? 'Loaded' : 'New row',
                  style: TextStyle(
                    color: hasCurrent
                        ? (dark
                              ? AppTheme.primaryNavyLight
                              : AppTheme.primaryNavyDark)
                        : AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$_selectedEmployeeName - ${_selectedLeaveType.displayName}',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BalanceMetric(
                label: 'Current available',
                value: current == null
                    ? '--'
                    : _formatDays(current.availableDays),
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              _BalanceMetric(
                label: 'New remaining',
                value: _formatDays(draft.remainingDays),
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              _BalanceMetric(
                label: 'New available',
                value: _formatDays(draft.availableDays),
                color: availableColor,
                emphasize: true,
              ),
              _BalanceMetric(
                label: 'Pending reserve',
                value: _formatDays(draft.pendingDays),
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Available = earned - used + adjusted - pending',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    final dark = AppTheme.dashIsDark(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _statusPanel({
    required IconData icon,
    required String message,
    bool warning = false,
  }) {
    final dark = AppTheme.dashIsDark(context);
    final color = warning
        ? (dark ? Colors.red.shade300 : Colors.red.shade700)
        : AppTheme.dashTextSecondaryOf(context);
    final background = warning
        ? (dark
              ? Colors.red.shade900.withValues(alpha: 0.35)
              : Colors.red.shade50)
        : AppTheme.dashMutedSurfaceOf(context);
    final border = warning
        ? (dark ? Colors.red.shade700 : Colors.red.shade100)
        : AppTheme.dashHairlineOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDays(double value) {
    final normalized = value.abs() < 0.005 ? 0.0 : value;
    final fixed = normalized.toStringAsFixed(2);
    if (fixed.endsWith('.00')) return fixed.substring(0, fixed.length - 3);
    if (fixed.endsWith('0')) return fixed.substring(0, fixed.length - 1);
    return fixed;
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasize ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: emphasize ? 20 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
