import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_layout.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_summary_strip.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/utils/employee_leave_actions.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_balance_history_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/my_leave_loading_skeleton.dart';

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
    this.showFileLeaveAction = true,
  });

  final VoidCallback? onFileLeavePressed;
  final bool showFileLeaveAction;

  @override
  State<EmployeeLeaveScreen> createState() => _EmployeeLeaveScreenState();
}

class _EmployeeLeaveScreenState extends State<EmployeeLeaveScreen>
    with WidgetsBindingObserver {
  bool _initialized = false;
  Timer? _autoRefreshTimer;
  StreamSubscription<AppRealtimeEvent>? _leaveRealtimeSub;
  String? _currentUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentUserId = context.read<AuthProvider>().user?.id;
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = _currentUserId;
      if (userId == null || userId.isEmpty) return;
      context.read<LeaveProvider>().loadMyLeaveData(userId);
    });
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
    final leaveProvider = context.read<LeaveProvider>();
    _leaveRealtimeSub ??= context.read<AppRealtimeProvider>().events.listen((
      event,
    ) {
      if (event.name != 'leave_updated') return;
      if (!event.affectsUser(_currentUserId)) return;
      if (!mounted) return;
      leaveProvider.invalidateCachedLeaveData();
      unawaited(_refreshMyLeaveData(forceRefresh: true));
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
      _refreshMyLeaveData(forceRefresh: true);
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshMyLeaveData();
    });
  }

  Future<void> _refreshMyLeaveData({bool forceRefresh = false}) async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) return;
    await context.read<LeaveProvider>().loadMyLeaveData(
      userId,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _retryRequests() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    await context.read<LeaveProvider>().loadMyLeaveRequests(
      userId,
      forceRefresh: true,
    );
  }

  Future<void> _loadMoreRequests() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    await context.read<LeaveProvider>().loadMoreMyLeaveRequests(userId);
  }

  Future<void> _retryBalances() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    await context.read<LeaveProvider>().loadMyLeaveBalances(
      userId,
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LeaveProvider>();
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName.isNotEmpty
        ? auth.displayName
        : 'Employee';
    final width = MediaQuery.of(context).size.width;
    final mobile = width < 600;
    final compact = width < 820;
    final showLeaveSkeleton =
        provider.myRequestsLoading &&
        provider.myBalancesLoading &&
        !provider.myRequestsLoaded &&
        !provider.myBalancesLoaded;

    // Only count accrual-based leaves (Sick + Vacation) for the credits summary.
    const creditTypes = {'vacationLeave', 'sickLeave'};
    final totalAvailable = provider.myBalancesLoaded
        ? provider.balances
              .where((b) => creditTypes.contains(b.effectiveLeaveTypeName))
              .fold<double>(0, (sum, item) => sum + item.availableDays)
        : null;
    final totalPendingDays = provider.myRequestsLoaded
        ? provider.pendingRequests.fold<double>(
            0,
            (sum, item) => sum + (item.workingDaysApplied ?? 0),
          )
        : null;
    final nextApproved = provider.upcomingApprovedRequests.isNotEmpty
        ? provider.upcomingApprovedRequests.first
        : null;

    if (mobile) {
      return _buildMobileLayout(
        provider: provider,
        showLeaveSkeleton: showLeaveSkeleton,
        totalAvailable: totalAvailable,
        totalPendingDays: totalPendingDays,
        nextApproved: nextApproved,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LeavePageHeader(
          displayName: displayName,
          pendingCount: provider.pendingCount,
          onFileLeavePressed: widget.showFileLeaveAction
              ? widget.onFileLeavePressed
              : null,
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(
            message: provider.error!,
            onDismiss: provider.clearError,
          ),
        ],
        const SizedBox(height: 24),
        if (showLeaveSkeleton)
          MyLeaveLoadingSkeleton(compact: compact)
        else ...[
          compact
              ? Column(
                  children: [
                    _SummaryCard(
                      title: 'Available Credits',
                      value: totalAvailable?.toStringAsFixed(1) ?? '--',
                      subtitle: 'Across tracked leave balances',
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                    const SizedBox(height: 16),
                    _SummaryCard(
                      title: 'Pending Requests',
                      value: provider.myRequestsLoaded
                          ? '${provider.pendingCount}'
                          : '--',
                      subtitle: provider.myRequestsLoaded
                          ? '${totalPendingDays!.toStringAsFixed(1)} day(s) awaiting review'
                          : 'Request information unavailable',
                      icon: Icons.pending_actions_rounded,
                    ),
                    const SizedBox(height: 16),
                    _SummaryCard(
                      title: 'Next Approved Leave',
                      value:
                          provider.myRequestsLoaded &&
                              provider.officialDate != null
                          ? nextApproved?.leaveTypeLabel ?? 'None'
                          : 'Unavailable',
                      subtitle:
                          provider.myRequestsLoaded &&
                              provider.officialDate != null
                          ? _approvedLeaveSubtitle(nextApproved)
                          : 'Official date unavailable',
                      icon: Icons.event_available_rounded,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'Available Credits',
                        value: totalAvailable?.toStringAsFixed(1) ?? '--',
                        subtitle: 'Across tracked leave balances',
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Pending Requests',
                        value: provider.myRequestsLoaded
                            ? '${provider.pendingCount}'
                            : '--',
                        subtitle: provider.myRequestsLoaded
                            ? '${totalPendingDays!.toStringAsFixed(1)} day(s) awaiting review'
                            : 'Request information unavailable',
                        icon: Icons.pending_actions_rounded,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Next Approved Leave',
                        value:
                            provider.myRequestsLoaded &&
                                provider.officialDate != null
                            ? nextApproved?.leaveTypeLabel ?? 'None'
                            : 'Unavailable',
                        subtitle:
                            provider.myRequestsLoaded &&
                                provider.officialDate != null
                            ? _approvedLeaveSubtitle(nextApproved)
                            : 'Official date unavailable',
                        icon: Icons.event_available_rounded,
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 24),
          Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final credits = _BalancesPanel(
                    balances: provider.balances
                        .where(
                          (b) =>
                              b.effectiveLeaveTypeName == 'vacationLeave' ||
                              b.effectiveLeaveTypeName == 'sickLeave',
                        )
                        .toList(),
                    loading: provider.myBalancesLoading,
                    error: provider.myBalancesError,
                    onRetry: _retryBalances,
                    onBalanceHistory: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const LeaveBalanceHistoryScreen(isAdmin: false),
                        ),
                      );
                    },
                  );
                  final entitlements = _LeaveDaysPanel(
                    balances: provider.balances,
                    loading: provider.myBalancesLoading,
                  );
                  if (constraints.maxWidth < 1100) {
                    return Column(
                      children: [
                        credits,
                        const SizedBox(height: 16),
                        entitlements,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: credits),
                      const SizedBox(width: 32),
                      Expanded(child: entitlements),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              EmployeeLeaveRequestsPanel(
                requests: provider.myRequests,
                loading: provider.myRequestsLoading,
                error: provider.myRequestsError,
                onRetry: _retryRequests,
                totalRequests: provider.myRequestsTotal,
                hasMore: provider.myRequestsHasMore,
                loadingMore: provider.myRequestsLoadingMore,
                loadMoreError: provider.myRequestsLoadMoreError,
                onLoadMore: _loadMoreRequests,
                onEdit: _leaveActions.editRequest,
                onCancel: _leaveActions.cancelRequest,
                onDiscard: _leaveActions.discardDraft,
                onPreview: _leaveActions.previewLeaveForm,
                onPrint: _leaveActions.printLeaveForm,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMobileLayout({
    required LeaveProvider provider,
    required bool showLeaveSkeleton,
    required double? totalAvailable,
    required double? totalPendingDays,
    required LeaveRequest? nextApproved,
  }) {
    return EmployeeLeaveMobileLayout(
      errorBanner: provider.error == null
          ? null
          : _ErrorBanner(
              message: provider.error!,
              onDismiss: provider.clearError,
            ),
      showLoading: showLeaveSkeleton,
      loadingSkeleton: const MyLeaveLoadingSkeleton(compact: true),
      summaryStrip: EmployeeLeaveMobileSummaryStrip(
        totalAvailable: totalAvailable,
        pendingCount: provider.myRequestsLoaded ? provider.pendingCount : null,
        totalPendingDays: totalPendingDays,
        nextApproved: nextApproved,
        nextApprovedAvailable:
            provider.myRequestsLoaded && provider.officialDate != null,
      ),
      balancesPanel: EmployeeLeaveMobileBalancesPanel(
        balances: provider.balances,
        loading: provider.myBalancesLoading,
        error: provider.myBalancesError,
        onRetry: _retryBalances,
        onBalanceHistory: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const LeaveBalanceHistoryScreen(isAdmin: false),
            ),
          );
        },
      ),
      requestsPanel: EmployeeLeaveRequestsPanel(
        requests: provider.myRequests,
        loading: provider.myRequestsLoading,
        error: provider.myRequestsError,
        onRetry: _retryRequests,
        totalRequests: provider.myRequestsTotal,
        hasMore: provider.myRequestsHasMore,
        loadingMore: provider.myRequestsLoadingMore,
        loadMoreError: provider.myRequestsLoadMoreError,
        onLoadMore: _loadMoreRequests,
        onEdit: _leaveActions.editRequest,
        onCancel: _leaveActions.cancelRequest,
        onDiscard: _leaveActions.discardDraft,
        onPreview: _leaveActions.previewLeaveForm,
        onPrint: _leaveActions.printLeaveForm,
      ),
    );
  }

  EmployeeLeaveActions get _leaveActions {
    return EmployeeLeaveActions(context: context, isMounted: () => mounted);
  }

  String _approvedLeaveSubtitle(LeaveRequest? request) {
    if (request == null ||
        request.startDate == null ||
        request.endDate == null) {
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
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
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
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Track your leave balances, review request status, and file a new leave request, $displayName.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
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
          if (onFileLeavePressed != null)
            FilledButton.icon(
              onPressed: onFileLeavePressed,
              icon: const Icon(Icons.add_rounded),
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
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryNavy, size: 22),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
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
    required this.error,
    required this.onRetry,
    required this.onBalanceHistory,
  });

  final List<LeaveBalance> balances;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onBalanceHistory;

  @override
  Widget build(BuildContext context) {
    return _BalanceSection(
      title: 'Leave Credits',
      headerTrailing: OutlinedButton.icon(
        onPressed: onBalanceHistory,
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        label: const Text('Credit History'),
      ),
      child: error != null && balances.isEmpty
          ? _SectionLoadError(message: error!, onRetry: onRetry)
          : loading && balances.isEmpty
          ? const _CenteredState(message: 'Loading leave credits...')
          : balances.isEmpty
          ? const _CenteredState(message: 'No leave credits available yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  _SectionLoadError(message: error!, onRetry: onRetry),
                  const SizedBox(height: 12),
                ],
                ...balances.map(
                  (balance) => _CompactBalanceRow(balance: balance),
                ),
              ],
            ),
    );
  }
}

class _LeaveDaysPanel extends StatelessWidget {
  const _LeaveDaysPanel({required this.balances, required this.loading});

  final List<LeaveBalance> balances;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final entitlementBalances = balances
        .where((balance) => balance.isAnnualEntitlement)
        .toList();
    if (!loading && entitlementBalances.isEmpty) {
      return const SizedBox.shrink();
    }
    return _BalanceSection(
      title: 'Annual Leave Entitlements',
      child: loading && entitlementBalances.isEmpty
          ? const _CenteredState(message: 'Loading leave days...')
          : Column(
              children: entitlementBalances
                  .map(
                    (balance) =>
                        _CompactBalanceRow(balance: balance, annual: true),
                  )
                  .toList(),
            ),
    );
  }
}

class _CompactBalanceRow extends StatelessWidget {
  const _CompactBalanceRow({required this.balance, this.annual = false});

  final LeaveBalance balance;
  final bool annual;

  String _days(double value) => value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance.leaveTypeLabel,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (annual && balance.entitlementYear != null)
                  Text(
                    '${balance.entitlementYear}',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          _BalanceAmount(
            label: annual ? 'Entitled' : 'Earned',
            value: _days(balance.earnedDays),
          ),
          _BalanceAmount(label: 'Used', value: _days(balance.usedDays)),
          _BalanceAmount(label: 'Pending', value: _days(balance.pendingDays)),
          _BalanceAmount(
            label: 'Available',
            value: _days(balance.availableDays),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _BalanceAmount extends StatelessWidget {
  const _BalanceAmount({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: emphasized
                  ? AppTheme.primaryNavy
                  : AppTheme.dashTextPrimaryOf(context),
              fontSize: 13,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceSection extends StatelessWidget {
  const _BalanceSection({
    required this.title,
    required this.child,
    this.headerTrailing,
  });

  final String title;
  final Widget child;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(width: 12),
                headerTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
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
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 14,
        ),
      ),
    );
  }
}

class _SectionLoadError extends StatelessWidget {
  const _SectionLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: AppTheme.dashTextPrimaryOf(context)),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
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
