import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../leave_provider.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/leave_request_card.dart';

/// Employee-facing leave screen.
///
/// Shows:
/// - current balances
/// - pending/upcoming requests
/// - recent leave request history
class EmployeeLeaveScreen extends StatefulWidget {
  const EmployeeLeaveScreen({
    super.key,
    this.onFileLeavePressed,
  });

  final VoidCallback? onFileLeavePressed;

  @override
  State<EmployeeLeaveScreen> createState() => _EmployeeLeaveScreenState();
}

class _EmployeeLeaveScreenState extends State<EmployeeLeaveScreen> {
  bool _initialized = false;

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
                    subtitle: '${totalPendingDays.toStringAsFixed(1)} day(s) awaiting review',
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
                      subtitle: '${totalPendingDays.toStringAsFixed(1)} day(s) awaiting review',
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
            ),
          ],
        ),
      ],
    );
  }

  String _approvedLeaveSubtitle(LeaveRequest? request) {
    if (request == null || request.startDate == null || request.endDate == null) {
      return 'No approved upcoming leave yet';
    }
    return '${_formatDate(request.startDate!)} to ${_formatDate(request.endDate!)}';
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
  const _BalancesPanel({
    required this.balances,
    required this.loading,
  });

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
  });

  final List<LeaveRequest> requests;
  final bool loading;

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
                  message: 'No leave requests yet. Start by filing your first leave request.',
                )
              : Column(
                  children: requests
                      .map(
                        (request) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LeaveRequestCard(request: request),
                        ),
                      )
                      .toList(),
                ),
    );
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
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

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
              style: TextStyle(
                color: Colors.red.shade900,
                fontSize: 13,
              ),
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
