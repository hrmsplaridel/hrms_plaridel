import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../leave_provider.dart';
import '../leave_repository.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import '../widgets/leave_request_card.dart';
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
    this.onApprove,
    this.onReturnRequest,
    this.onRejectRequest,
  });

  final LeaveApproveAction? onApprove;
  final LeaveDecisionAction? onReturnRequest;
  final LeaveDecisionAction? onRejectRequest;

  @override
  State<AdminLeaveScreen> createState() => _AdminLeaveScreenState();
}

class _AdminLeaveScreenState extends State<AdminLeaveScreen> {
  bool _initialized = false;
  LeaveRequest? _selectedRequest;
  LeaveRequestStatus? _statusFilter = LeaveRequestStatus.pending;
  LeaveType? _leaveTypeFilter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRequests());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LeaveProvider>();
    final width = MediaQuery.of(context).size.width;
    final compact = width < 1080;
    final requests = provider.requests;
    final selected =
        _selectedRequest ?? (requests.isNotEmpty ? requests.first : null);
    if (selected != _selectedRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedRequest = selected);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminHeaderCard(
          totalRequests: requests.length,
          pendingCount: requests
              .where((r) => r.status == LeaveRequestStatus.pending)
              .length,
          reviewing: provider.reviewing,
          onRefresh: _loadRequests,
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
          status: _statusFilter,
          leaveType: _leaveTypeFilter,
          onStatusChanged: (value) {
            setState(() => _statusFilter = value);
            _loadRequests();
          },
          onLeaveTypeChanged: (value) {
            setState(() => _leaveTypeFilter = value);
            _loadRequests();
          },
          onReset: () {
            setState(() {
              _statusFilter = LeaveRequestStatus.pending;
              _leaveTypeFilter = null;
            });
            _loadRequests();
          },
        ),
        const SizedBox(height: 20),
        compact
            ? Column(
                children: [
                  _RequestQueuePanel(
                    requests: requests,
                    loading: provider.loading,
                    selectedRequest: selected,
                    onSelect: (request) =>
                        setState(() => _selectedRequest = request),
                  ),
                  const SizedBox(height: 16),
                  _RequestDetailsPanel(
                    request: selected,
                    reviewing: provider.reviewing,
                    onApprove: selected == null
                        ? null
                        : () => _approve(selected),
                    onReturn: selected == null
                        ? null
                        : () => _returnRequest(selected),
                    onReject: selected == null
                        ? null
                        : () => _rejectRequest(selected),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: _RequestQueuePanel(
                      requests: requests,
                      loading: provider.loading,
                      selectedRequest: selected,
                      onSelect: (request) =>
                          setState(() => _selectedRequest = request),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 7,
                    child: _RequestDetailsPanel(
                      request: selected,
                      reviewing: provider.reviewing,
                      onApprove: selected == null
                          ? null
                          : () => _approve(selected),
                      onReturn: selected == null
                          ? null
                          : () => _returnRequest(selected),
                      onReject: selected == null
                          ? null
                          : () => _rejectRequest(selected),
                    ),
                  ),
                ],
              ),
      ],
    );
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    await provider.loadRequests(
      query: LeaveRequestQuery(
        status: _statusFilter,
        leaveType: _leaveTypeFilter,
        limit: 100,
      ),
    );
    if (!mounted) return;
    if (_selectedRequest == null && provider.requests.isNotEmpty) {
      setState(() => _selectedRequest = provider.requests.first);
    }
  }

  Future<void> _approve(LeaveRequest request) async {
    final input = await showDialog<LeaveApprovalInput>(
      context: context,
      builder: (_) => _ApproveDialog(request: request),
    );
    if (input == null) return;

    final auth = context.read<AuthProvider>();
    final reviewerId = auth.user?.id;
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }

    final finalInput = LeaveApprovalInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: auth.displayName,
      hrRemarks: input.hrRemarks,
      recommendationRemarks: input.recommendationRemarks,
      approvedDaysWithPay: input.approvedDaysWithPay,
      approvedDaysWithoutPay: input.approvedDaysWithoutPay,
      approvedOtherDetails: input.approvedOtherDetails,
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
    _showMessage(
      ok ? 'Leave request approved.' : 'Approval could not be completed.',
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
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }

    final finalInput = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: auth.displayName,
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
    if (reviewerId == null || reviewerId.isEmpty) {
      _showMessage('No logged-in reviewer found.');
      return;
    }

    final finalInput = LeaveReviewDecisionInput(
      requestId: request.id ?? '',
      reviewerId: reviewerId,
      reviewerName: auth.displayName,
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AdminHeaderCard extends StatelessWidget {
  const _AdminHeaderCard({
    required this.totalRequests,
    required this.pendingCount,
    required this.reviewing,
    required this.onRefresh,
  });

  final int totalRequests;
  final int pendingCount;
  final bool reviewing;
  final Future<void> Function() onRefresh;

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
          FilledButton.icon(
            onPressed: reviewing ? null : onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(reviewing ? 'Reviewing...' : 'Refresh'),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.leaveType,
    required this.onStatusChanged,
    required this.onLeaveTypeChanged,
    required this.onReset,
  });

  final LeaveRequestStatus? status;
  final LeaveType? leaveType;
  final ValueChanged<LeaveRequestStatus?> onStatusChanged;
  final ValueChanged<LeaveType?> onLeaveTypeChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
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
                const DropdownMenuItem<LeaveRequestStatus?>(
                  value: null,
                  child: Text('All statuses'),
                ),
                ...LeaveRequestStatus.values.map(
                  (value) => DropdownMenuItem<LeaveRequestStatus?>(
                    value: value,
                    child: Text(value.displayName),
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
}

class _RequestQueuePanel extends StatelessWidget {
  const _RequestQueuePanel({
    required this.requests,
    required this.loading,
    required this.selectedRequest,
    required this.onSelect,
  });

  final List<LeaveRequest> requests;
  final bool loading;
  final LeaveRequest? selectedRequest;
  final ValueChanged<LeaveRequest> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Request Queue',
      subtitle: 'Choose a leave request to inspect full details.',
      child: loading && requests.isEmpty
          ? const _CenteredState(message: 'Loading leave requests...')
          : requests.isEmpty
          ? const _CenteredState(
              message: 'No leave requests matched the filters.',
            )
          : Column(
              children: requests
                  .map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LeaveRequestCard(
                        request: request,
                        selected: request.id == selectedRequest?.id,
                        onTap: () => onSelect(request),
                        variant: LeaveRequestCardVariant.adminQueue,
                        showReason: false,
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _RequestDetailsPanel extends StatelessWidget {
  const _RequestDetailsPanel({
    required this.request,
    required this.reviewing,
    this.onApprove,
    this.onReturn,
    this.onReject,
  });

  final LeaveRequest? request;
  final bool reviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReturn;
  final VoidCallback? onReject;

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
              LeaveStatusChip(status: request!.status),
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
          _SubsectionTitle(title: 'Review Actions'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: reviewing ? null : onApprove,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: reviewing ? null : onReturn,
                icon: const Icon(Icons.reply_rounded),
                label: const Text('Return'),
              ),
              OutlinedButton.icon(
                onPressed: reviewing ? null : onReject,
                icon: const Icon(Icons.cancel_rounded),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                label: const Text('Reject'),
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
      (
        label: 'Attachment',
        value: request.attachmentName ?? 'No attachment linked yet',
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: rows
          .map(
            (item) => SizedBox(
              width: 260,
              child: _InfoTile(label: item.label, value: item.value),
            ),
          )
          .toList(),
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.request});

  final LeaveRequest request;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _withPayController;
  late final TextEditingController _withoutPayController;
  late final TextEditingController _otherDetailsController;
  late final TextEditingController _hrRemarksController;
  late final TextEditingController _recommendationController;

  @override
  void initState() {
    super.initState();
    _withPayController = TextEditingController(
      text: widget.request.workingDaysApplied?.toStringAsFixed(1) ?? '',
    );
    _withoutPayController = TextEditingController();
    _otherDetailsController = TextEditingController();
    _hrRemarksController = TextEditingController();
    _recommendationController = TextEditingController();
  }

  @override
  void dispose() {
    _withPayController.dispose();
    _withoutPayController.dispose();
    _otherDetailsController.dispose();
    _hrRemarksController.dispose();
    _recommendationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve Leave Request'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(
                  controller: _withPayController,
                  label: 'Approved Days With Pay',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _withoutPayController,
                  label: 'Approved Days Without Pay',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _otherDetailsController,
                  label: 'Other Approval Details',
                  maxLines: null,
                  minLines: 2,
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _recommendationController,
                  label: 'Recommendation Remarks',
                  maxLines: null,
                  minLines: 3,
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: _hrRemarksController,
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
              LeaveApprovalInput(
                requestId: widget.request.id ?? '',
                reviewerId: '',
                approvedDaysWithPay: _parseDouble(_withPayController.text),
                approvedDaysWithoutPay: _parseDouble(
                  _withoutPayController.text,
                ),
                approvedOtherDetails: _trimOrNull(_otherDetailsController.text),
                recommendationRemarks: _trimOrNull(
                  _recommendationController.text,
                ),
                hrRemarks: _trimOrNull(_hrRemarksController.text),
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
