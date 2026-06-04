import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_layout.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_summary_strip.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/utils/employee_leave_actions.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/widgets/employee_leave_requests_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_balance_history_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/my_leave_loading_skeleton.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

class EmployeeLeaveMobilePage extends StatefulWidget {
  const EmployeeLeaveMobilePage({
    super.key,
    this.onFileLeavePressed,
    this.showFileLeaveAction = true,
  });

  final VoidCallback? onFileLeavePressed;
  final bool showFileLeaveAction;

  @override
  State<EmployeeLeaveMobilePage> createState() =>
      _EmployeeLeaveMobilePageState();
}

class _EmployeeLeaveMobilePageState extends State<EmployeeLeaveMobilePage>
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
      unawaited(_refreshMyLeaveData(forceRefresh: true));
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refreshMyLeaveData());
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

  EmployeeLeaveActions get _leaveActions {
    return EmployeeLeaveActions(context: context, isMounted: () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LeaveProvider>();
    final showLeaveSkeleton =
        provider.loading &&
        provider.balances.isEmpty &&
        provider.requests.isEmpty;
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

    return EmployeeLeaveMobileLayout(
      errorBanner: provider.error == null
          ? null
          : _MobileLeaveErrorBanner(
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
        onBalanceHistory: _openBalanceHistory,
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

  void _openBalanceHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LeaveBalanceHistoryScreen(isAdmin: false),
      ),
    );
  }
}

class _MobileLeaveErrorBanner extends StatelessWidget {
  const _MobileLeaveErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
