import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';

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
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';
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
        provider.loading &&
        provider.balances.isEmpty &&
        provider.requests.isEmpty;

    // Only count accrual-based leaves (Sick + Vacation) for the credits summary.
    const creditTypes = {'vacationLeave', 'sickLeave'};
    final totalAvailable = provider.balances
        .where((b) => creditTypes.contains(b.effectiveLeaveTypeName))
        .fold<double>(0, (sum, item) => sum + item.availableDays);
    final totalPendingDays = provider.pendingRequests.fold<double>(
      0,
      (sum, item) => sum + (item.workingDaysApplied ?? 0),
    );
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
                      value: nextApproved?.leaveTypeLabel ?? 'None',
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
                        value: nextApproved?.leaveTypeLabel ?? 'None',
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
                balances: provider.balances
                    .where(
                      (b) =>
                          b.effectiveLeaveTypeName == 'vacationLeave' ||
                          b.effectiveLeaveTypeName == 'sickLeave',
                    )
                    .toList(),
                loading: provider.loading,
                onBalanceHistory: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const LeaveBalanceHistoryScreen(isAdmin: false),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _LeaveDaysPanel(
                balances: provider.balances,
                loading: provider.loading,
              ),
              const SizedBox(height: 16),
              EmployeeLeaveRequestsPanel(
                requests: provider.requests,
                loading: provider.loading,
                onEdit: _leaveActions.editRequest,
                onCancel: _leaveActions.cancelRequest,
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
    required double totalAvailable,
    required double totalPendingDays,
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
        pendingCount: provider.pendingCount,
        totalPendingDays: totalPendingDays,
        nextApproved: nextApproved,
      ),
      balancesPanel: EmployeeLeaveMobileBalancesPanel(
        balances: provider.balances,
        loading: provider.loading,
        onBalanceHistory: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const LeaveBalanceHistoryScreen(isAdmin: false),
            ),
          );
        },
      ),
      requestsPanel: EmployeeLeaveRequestsPanel(
        requests: provider.requests,
        loading: provider.loading,
        onEdit: _leaveActions.editRequest,
        onCancel: _leaveActions.cancelRequest,
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
    required this.onBalanceHistory,
  });

  final List<LeaveBalance> balances;
  final bool loading;
  final VoidCallback onBalanceHistory;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Leave Credits',
      subtitle: 'Earned and available credits for Sick and Vacation Leave.',
      icon: Icons.account_balance_wallet_rounded,
      headerTrailing: OutlinedButton.icon(
        onPressed: onBalanceHistory,
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        label: const Text('Credit History'),
      ),
      child: loading && balances.isEmpty
          ? const _CenteredState(message: 'Loading leave credits...')
          : balances.isEmpty
          ? const _CenteredState(message: 'No leave credits available yet.')
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

class _LeaveDaysPanel extends StatelessWidget {
  const _LeaveDaysPanel({required this.balances, required this.loading});

  final List<LeaveBalance> balances;
  final bool loading;

  static const _annualEntitlementTypes = {
    'specialPrivilegeLeave',
    'mandatoryForcedLeave',
    'soloParentLeave',
    'specialEmergencyCalamityLeave',
  };

  @override
  Widget build(BuildContext context) {
    final entitlementBalances = balances
        .where(
          (b) => _annualEntitlementTypes.contains(b.effectiveLeaveTypeName),
        )
        .toList();
    if (!loading && entitlementBalances.isEmpty) {
      return const SizedBox.shrink();
    }
    return _SectionCard(
      title: 'Annual Leave Entitlements',
      subtitle: 'Quota-based leave only. Eligibility and approval rules apply.',
      icon: Icons.calendar_today_rounded,
      child: loading && entitlementBalances.isEmpty
          ? const _CenteredState(message: 'Loading leave days...')
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
                  children: entitlementBalances
                      .map(
                        (balance) => SizedBox(
                          width: cardWidth,
                          child: LeaveDaysCard(balance: balance),
                        ),
                      )
                      .toList(),
                );
              },
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
    this.headerTrailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? headerTrailing;

  static const double _mobileBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < _mobileBreakpoint;
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
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
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile && headerTrailing != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: headerTrailing!,
                  ),
                ),
              ],
            ],
          ),
          if (isMobile && headerTrailing != null) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: headerTrailing!),
          ],
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
