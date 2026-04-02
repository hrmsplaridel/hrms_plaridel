import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../leave_provider.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'leave_request_form_screen.dart';
import '../utils/leave_request_pdf.dart';
import '../utils/responsive_leave_form_host.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/history_timeline.dart';
import '../widgets/leave_card.dart';

/// Employee-facing leave screen.
///
/// Shows:
/// - current balances
/// - pending/upcoming requests
/// - recent leave request history
class EmployeeLeaveScreen extends StatefulWidget {
  const EmployeeLeaveScreen({super.key, this.onFileLeavePressed});

  final VoidCallback? onFileLeavePressed;

  @override
  State<EmployeeLeaveScreen> createState() => _EmployeeLeaveScreenState();
}

class _EmployeeLeaveScreenState extends State<EmployeeLeaveScreen>
    with WidgetsBindingObserver {
  bool _initialized = false;
  Timer? _autoRefreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthProvider>().user?.id;
      if (userId == null || userId.isEmpty) return;
      context.read<LeaveProvider>().loadMyLeaveData(userId);
    });
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
      _refreshMyLeaveData();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshMyLeaveData();
    });
  }

  Future<void> _refreshMyLeaveData() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) return;
    await context.read<LeaveProvider>().loadMyLeaveData(userId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LeaveProvider>();
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName.isNotEmpty
        ? auth.displayName
        : 'Employee';
    final width = MediaQuery.of(context).size.width;
    final compact = width < 820;

    final totalAvailable = provider.balances.fold<double>(
      0,
      (sum, item) => sum + item.availableDays,
    );
    final totalPendingDays = provider.pendingRequests.fold<double>(
      0,
      (sum, item) => sum + (item.workingDaysApplied ?? 0),
    );
    final nextApproved = provider.upcomingApprovedRequests.isNotEmpty
        ? provider.upcomingApprovedRequests.first
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LeavePageHeader(
          displayName: displayName,
          pendingCount: provider.pendingCount,
          onFileLeavePressed: widget.onFileLeavePressed,
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(
            message: provider.error!,
            onDismiss: provider.clearError,
          ),
        ],
        const SizedBox(height: 24),
        compact
            ? Column(
                children: [
                  _SummaryCard(
                    title: 'Available Credits',
                    value: totalAvailable.toStringAsFixed(1),
                    subtitle: 'Across tracked leave balances',
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(
                    title: 'Pending Requests',
                    value: '${provider.pendingCount}',
                    subtitle:
                        '${totalPendingDays.toStringAsFixed(1)} day(s) awaiting review',
                    icon: Icons.pending_actions_rounded,
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(
                    title: 'Next Approved Leave',
                    value: nextApproved?.leaveType.displayName ?? 'None',
                    subtitle: _approvedLeaveSubtitle(nextApproved),
                    icon: Icons.event_available_rounded,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Available Credits',
                      value: totalAvailable.toStringAsFixed(1),
                      subtitle: 'Across tracked leave balances',
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Pending Requests',
                      value: '${provider.pendingCount}',
                      subtitle:
                          '${totalPendingDays.toStringAsFixed(1)} day(s) awaiting review',
                      icon: Icons.pending_actions_rounded,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Next Approved Leave',
                      value: nextApproved?.leaveType.displayName ?? 'None',
                      subtitle: _approvedLeaveSubtitle(nextApproved),
                      icon: Icons.event_available_rounded,
                    ),
                  ),
                ],
              ),
        const SizedBox(height: 24),
        Column(
          children: [
            _BalancesPanel(
              balances: provider.balances,
              loading: provider.loading,
            ),
            const SizedBox(height: 16),
            _RequestsPanel(
              requests: provider.requests,
              loading: provider.loading,
              onEdit: (request) => _editRequest(context, request),
              onCancel: (request) => _cancelRequest(context, request),
              onPrint: _printLeaveForm,
            ),
          ],
        ),
      ],
    );
  }

  String _approvedLeaveSubtitle(LeaveRequest? request) {
    if (request == null ||
        request.startDate == null ||
        request.endDate == null) {
      return 'No approved upcoming leave yet';
    }
    return '${_formatDate(request.startDate!)} to ${_formatDate(request.endDate!)}';
  }

  Future<void> _editRequest(BuildContext context, LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    final result = await openResponsiveLeaveFormHost<bool>(
      context: context,
      builder: (_) =>
          _buildEditLeaveRequestForm(provider: provider, request: request),
    );
    if (!mounted || result != true) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId != null && userId.isNotEmpty) {
      await context.read<LeaveProvider>().loadMyLeaveData(userId);
    }
  }

  Widget _buildEditLeaveRequestForm({
    required LeaveProvider provider,
    required LeaveRequest request,
  }) {
    return LeaveRequestFormScreen(
      initialRequest: request,
      onSaveDraft: (updated) async {
        final saved = updated.id == null || updated.id!.isEmpty
            ? await provider.saveDraft(updated)
            : await provider.updateRequest(
                updated.copyWith(
                  // Backend does NOT allow returned -> draft.
                  // Keep status as returned when editing a returned request.
                  status: request.status == LeaveRequestStatus.returned
                      ? LeaveRequestStatus.returned
                      : LeaveRequestStatus.draft,
                ),
              );
        return saved != null;
      },
      onSubmitRequest: (updated) async {
        // For draft/returned edits, resubmission updates the same request to pending.
        final saved = updated.id == null || updated.id!.isEmpty
            ? await provider.submitRequest(updated)
            : await provider.updateRequest(
                updated.copyWith(status: LeaveRequestStatus.pending),
              );
        return saved != null;
      },
    );
  }

  /// Opens the system print / save-PDF dialog with the official leave form PDF.
  Future<void> _printLeaveForm(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    if (!mounted) return;
    try {
      LeaveRequest target = request;
      final id = request.id;
      if (id != null && id.isNotEmpty) {
        final fresh = await provider.refreshRequestById(id);
        if (fresh != null) target = fresh;
      }

      final balances = await provider.fetchBalancesForUser(target.userId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preparing print...')));

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

  Future<void> _cancelRequest(
    BuildContext context,
    LeaveRequest request,
  ) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id;
    if (userId == null || userId.isEmpty) return;
    final requestId = request.id;
    if (requestId == null || requestId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: const Text(
          'This will cancel the request. You can file a new request anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final updated = await context.read<LeaveProvider>().cancelRequest(
      requestId: requestId,
      userId: userId,
    );
    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated != null
              ? 'Leave request cancelled.'
              : (provider.error ?? 'Cancel failed.'),
        ),
      ),
    );
    await provider.loadMyLeaveData(userId);
  }
}

class _LeavePageHeader extends StatelessWidget {
  const _LeavePageHeader({
    required this.displayName,
    required this.pendingCount,
    this.onFileLeavePressed,
  });

  final String displayName;
  final int pendingCount;
  final VoidCallback? onFileLeavePressed;

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
        runSpacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Leave',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Track your leave balances, review request status, and file a new leave request, $displayName.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  pendingCount == 0
                      ? 'No pending requests at the moment.'
                      : '$pendingCount leave request(s) currently awaiting review.',
                  style: TextStyle(
                    color: AppTheme.primaryNavyDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onFileLeavePressed,
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('File Leave Request'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          Icon(icon, color: AppTheme.primaryNavy, size: 22),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
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
        ],
      ),
    );
  }
}

class _BalancesPanel extends StatelessWidget {
  const _BalancesPanel({required this.balances, required this.loading});

  final List<LeaveBalance> balances;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Leave Balances',
      subtitle: 'Available and pending credits per leave type.',
      icon: Icons.account_balance_wallet_rounded,
      child: loading && balances.isEmpty
          ? const _CenteredState(message: 'Loading leave balances...')
          : balances.isEmpty
          ? const _CenteredState(message: 'No leave balances available yet.')
          : LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 600
                    ? 1
                    : (constraints.maxWidth < 960 ? 2 : 3);
                final cardWidth =
                    (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                    crossAxisCount;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: balances
                      .map(
                        (balance) => SizedBox(
                          width: cardWidth,
                          child: LeaveBalanceCard(balance: balance),
                        ),
                      )
                      .toList(),
                );
              },
            ),
    );
  }
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel({
    required this.requests,
    required this.loading,
    required this.onEdit,
    required this.onCancel,
    required this.onPrint,
  });

  final List<LeaveRequest> requests;
  final bool loading;
  final ValueChanged<LeaveRequest> onEdit;
  final ValueChanged<LeaveRequest> onCancel;
  final ValueChanged<LeaveRequest> onPrint;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'My Requests',
      subtitle: 'Recent leave applications and their current status.',
      icon: Icons.event_note_rounded,
      child: loading && requests.isEmpty
          ? const _CenteredState(message: 'Loading leave requests...')
          : requests.isEmpty
          ? const _CenteredState(
              message:
                  'No leave requests yet. Start by filing your first leave request.',
            )
          : Column(
              children: requests
                  .map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EmployeeRequestItem(
                        request: request,
                        onEdit: () => onEdit(request),
                        onCancel: () => onCancel(request),
                        onPrint: () => onPrint(request),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _EmployeeRequestItem extends StatelessWidget {
  const _EmployeeRequestItem({
    required this.request,
    required this.onEdit,
    required this.onCancel,
    required this.onPrint,
  });

  final LeaveRequest request;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onPrint;

  bool get _canEdit =>
      request.status == LeaveRequestStatus.draft ||
      request.status == LeaveRequestStatus.returned ||
      request.status == LeaveRequestStatus.rejectedByDepartmentHead ||
      request.status == LeaveRequestStatus.rejectedByHr;

  bool get _canCancel =>
      request.status == LeaveRequestStatus.draft ||
      request.status.isPending ||
      request.status == LeaveRequestStatus.returned;

  @override
  Widget build(BuildContext context) {
    return LeaveCard(
      request: request,
      onViewDetails: () => _showDetails(context),
      onViewHistory: () => _showHistory(context),
      onCancel: _canCancel ? onCancel : null,
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave Details'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('Leave Type', request.leaveType.displayName),
              _detailLine('Date Range', _formatRange(request)),
              _detailLine(
                'Number of Days',
                request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
              ),
              _detailLine('Status', request.status.displayName),
              _detailLine(
                'Submitted Date',
                request.dateFiled != null
                    ? _formatDate(request.dateFiled!)
                    : '—',
              ),
              if ((request.reason ?? '').trim().isNotEmpty)
                _detailLine('Reason', request.reason!.trim()),
            ],
          ),
        ),
        actions: [
          if (_canEdit)
            OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
          OutlinedButton(onPressed: onPrint, child: const Text('Print Form')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHistory(BuildContext context) {
    final events = _buildHistoryEvents(request);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave Request History'),
        content: SizedBox(width: 560, child: HistoryTimeline(events: events)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<LeaveHistoryEvent> _buildHistoryEvents(LeaveRequest request) {
    final reviewed = request.reviewedAt;
    final reviewer = (request.reviewerName ?? '').trim().isNotEmpty
        ? request.reviewerName!.trim()
        : 'Approver';
    return [
      LeaveHistoryEvent(
        label: 'Submitted',
        dateTime: request.dateFiled ?? request.createdAt,
        actor: request.employeeName ?? 'Employee',
        remarks: request.reason,
      ),
      LeaveHistoryEvent(
        label: 'Approved by Department Head',
        dateTime:
            request.status == LeaveRequestStatus.pendingHr ||
                request.status == LeaveRequestStatus.approved
            ? reviewed
            : null,
        actor: reviewer,
        completed:
            request.status == LeaveRequestStatus.pendingHr ||
            request.status == LeaveRequestStatus.approved,
      ),
      LeaveHistoryEvent(
        label: 'Forwarded to HR',
        dateTime:
            request.status == LeaveRequestStatus.pendingHr ||
                request.status == LeaveRequestStatus.approved
            ? reviewed
            : null,
        actor: reviewer,
        completed:
            request.status == LeaveRequestStatus.pendingHr ||
            request.status == LeaveRequestStatus.approved,
      ),
      LeaveHistoryEvent(
        label: 'Approved by HR',
        dateTime: request.status == LeaveRequestStatus.approved
            ? reviewed
            : null,
        actor: reviewer,
        remarks: request.hrRemarks,
        completed: request.status == LeaveRequestStatus.approved,
      ),
    ];
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

  String _formatRange(LeaveRequest request) {
    if (request.startDate == null || request.endDate == null) return '—';
    return '${_formatDate(request.startDate!)} – ${_formatDate(request.endDate!)}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.primaryNavy, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
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
