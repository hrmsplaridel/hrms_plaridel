import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../realtime/app_realtime_provider.dart';
import '../leave_provider.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'leave_balance_history_screen.dart';
import 'leave_request_form_screen.dart';
import '../utils/leave_form_signatories.dart';
import '../utils/leave_request_pdf.dart';
import '../utils/responsive_leave_form_host.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/history_timeline.dart';
import '../widgets/leave_card.dart';
import '../widgets/leave_status_chip.dart';
import '../widgets/my_leave_loading_skeleton.dart';
import '../../widgets/request_filters_bar.dart';
import '../../widgets/section_header_actions.dart';

const _leaveRequestFilterOptions = <RequestFilterOption<LeaveRequestStatus>>[
  RequestFilterOption(label: 'All'),
  RequestFilterOption(value: LeaveRequestStatus.pending, label: 'Pending'),
  RequestFilterOption(value: LeaveRequestStatus.approved, label: 'Approved'),
  RequestFilterOption(value: LeaveRequestStatus.rejected, label: 'Rejected'),
  RequestFilterOption(value: LeaveRequestStatus.cancelled, label: 'Cancelled'),
];

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
                balances: provider.balances,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Leave',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        if (provider.error != null) ...[
          _ErrorBanner(message: provider.error!, onDismiss: provider.clearError),
          const SizedBox(height: 16),
        ],
        if (showLeaveSkeleton)
          const MyLeaveLoadingSkeleton(compact: true)
        else ...[
          _MobileLeaveSummaryStrip(
            totalAvailable: totalAvailable,
            pendingCount: provider.pendingCount,
            totalPendingDays: totalPendingDays,
            nextApproved: nextApproved,
          ),
          const SizedBox(height: 22),
          _MobileBalancesPanel(
            balances: provider.balances,
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
          _RequestsPanel(
            requests: provider.requests,
            loading: provider.loading,
            onEdit: (request) => _editRequest(context, request),
            onCancel: (request) => _cancelRequest(context, request),
            onPrint: _printLeaveForm,
          ),
        ],
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
    final userId = context.read<AuthProvider>().user?.id;
    final result = await openResponsiveLeaveFormHost<String?>(
      context: context,
      builder: (_) =>
          _buildEditLeaveRequestForm(provider: provider, request: request),
    );
    if (!mounted || result == null) return;
    if (result != kLeaveFormResultDraftSaved &&
        result != kLeaveFormResultSubmitted) {
      return;
    }
    if (userId != null && userId.isNotEmpty) {
      await provider.loadMyLeaveData(userId);
    }
    if (!mounted) return;
    showLeaveFormSuccessSnackBar(this.context, result);
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
      onSubmitRequestWithAttachment: (updated, fileBytes, fileName) async {
        final saved = updated.id == null || updated.id!.isEmpty
            ? await provider.submitRequestWithAttachment(
                request: updated,
                fileBytes: fileBytes,
                fileName: fileName,
              )
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

      final balances = await provider.fetchBalancesForUser(
        target.userId,
        forceRefresh: true,
      );
      final formSignatories = await loadLeaveFormSignatories(request: target);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preparing print...')));

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

  Future<void> _cancelRequest(
    BuildContext context,
    LeaveRequest request,
  ) async {
    final provider = context.read<LeaveProvider>();
    final userId = context.read<AuthProvider>().user?.id;
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

    final updated = await provider.cancelRequest(
      requestId: requestId,
      userId: userId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(this.context).showSnackBar(
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

class _MobileLeaveSummaryStrip extends StatelessWidget {
  const _MobileLeaveSummaryStrip({
    required this.totalAvailable,
    required this.pendingCount,
    required this.totalPendingDays,
    required this.nextApproved,
  });

  final double totalAvailable;
  final int pendingCount;
  final double totalPendingDays;
  final LeaveRequest? nextApproved;

  @override
  Widget build(BuildContext context) {
    final nextLabel = nextApproved?.leaveTypeLabel ?? 'None';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _MobileSummaryCard(
            title: 'Available Credits',
            value: totalAvailable.toStringAsFixed(1),
            icon: Icons.account_balance_wallet_outlined,
            accent: AppTheme.primaryNavy,
          ),
          const SizedBox(width: 12),
          _MobileSummaryCard(
            title: 'Pending Requests',
            value: '$pendingCount',
            icon: Icons.pending_actions_outlined,
            accent: const Color(0xFF795548),
            footer: totalPendingDays > 0
                ? '${totalPendingDays.toStringAsFixed(1)} day(s)'
                : null,
          ),
          const SizedBox(width: 12),
          _MobileSummaryCard(
            title: 'Next Approved',
            value: nextLabel,
            icon: Icons.event_available_outlined,
            accent: const Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }
}

class _MobileSummaryCard extends StatelessWidget {
  const _MobileSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.footer,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: 138,
      height: 96,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.045),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: value.length > 6 ? 18 : 25,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 3),
            Text(
              footer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileBalancesPanel extends StatelessWidget {
  const _MobileBalancesPanel({
    required this.balances,
    required this.loading,
    required this.onBalanceHistory,
  });

  final List<LeaveBalance> balances;
  final bool loading;
  final VoidCallback onBalanceHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Leave Balances',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
            TextButton(
              onPressed: onBalanceHistory,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavyDark,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Balance History',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (loading && balances.isEmpty)
          const _CenteredState(message: 'Loading leave balances...')
        else if (balances.isEmpty)
          const _CenteredState(message: 'No leave balances available yet.')
        else
          Column(
            children: List.generate(balances.length, (index) {
              final balance = balances[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == balances.length - 1 ? 0 : 12,
                ),
                child: _MobileLeaveBalanceCard(balance: balance),
              );
            }),
          ),
      ],
    );
  }
}

class _MobileLeaveBalanceCard extends StatelessWidget {
  const _MobileLeaveBalanceCard({required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final accent = _leaveBalanceAccent(balance.leaveType);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.dashIsDark(context) ? 0.28 : 0.035,
            ),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  balance.leaveTypeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 18) / 4;
              return Row(
                children: [
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Earned',
                    value: balance.earnedDays.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 6),
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Used',
                    value: balance.usedDays.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 6),
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Pending',
                    value: balance.pendingDays.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 6),
                  _MobileBalanceStatTile(
                    width: tileWidth,
                    label: 'Available',
                    value: balance.availableDays.toStringAsFixed(1),
                    accent: accent,
                    emphasized: true,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MobileBalanceStatTile extends StatelessWidget {
  const _MobileBalanceStatTile({
    required this.width,
    required this.label,
    required this.value,
    this.accent,
    this.emphasized = false,
  });

  final double width;
  final String label;
  final String value;
  final Color? accent;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? AppTheme.dashTextPrimaryOf(context);
    return SizedBox(
      width: width,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: emphasized
              ? effectiveAccent.withValues(
                  alpha: AppTheme.dashIsDark(context) ? 0.18 : 0.10,
                )
              : AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: emphasized
                      ? effectiveAccent
                      : AppTheme.dashTextSecondaryOf(context),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: emphasized
                      ? effectiveAccent
                      : AppTheme.dashTextPrimaryOf(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
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
      title: 'Leave Balances',
      subtitle: 'Available and pending credits per leave type.',
      icon: Icons.account_balance_wallet_rounded,
      headerTrailing: OutlinedButton.icon(
        onPressed: onBalanceHistory,
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        label: const Text('Balance History'),
      ),
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

class _RequestsPanel extends StatefulWidget {
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
  State<_RequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends State<_RequestsPanel> {
  late final ScrollController _requestsScrollController;
  String? _selectedRequestKey;
  LeaveRequestStatus? _selectedStatus;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _requestsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _requestsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final maxListHeight = screenWidth < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : screenWidth < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final filteredRequests = _filteredRequests;
    final useScrollableList = filteredRequests.length > 3;
    LeaveRequest? selectedRequest;
    for (final item in filteredRequests) {
      if (_requestKey(item) == _selectedRequestKey) {
        selectedRequest = item;
        break;
      }
    }

    return _SectionCard(
      title: 'My Requests',
      subtitle: 'Recent leave applications and their current status.',
      icon: Icons.event_note_rounded,
      headerTrailing: isMobile
          ? null
          : SectionHeaderActions(
              children: [
                SectionHeaderActionButton.outlined(
                  context: context,
                  onPressed: selectedRequest == null
                      ? null
                      : () => _showDetails(context, selectedRequest!),
                  label: 'View Details',
                ),
                SectionHeaderActionButton.outlined(
                  context: context,
                  onPressed: selectedRequest == null
                      ? null
                      : () => _showHistory(context, selectedRequest!),
                  label: 'View History',
                ),
                if (selectedRequest != null &&
                    _canEmployeeCancel(selectedRequest))
                  SectionHeaderActionButton.outlined(
                    context: context,
                    onPressed: () => widget.onCancel(selectedRequest!),
                    label: 'Cancel',
                    icon: Icons.cancel_outlined,
                  ),
              ],
            ),
      child: _buildRequestsContent(
        filteredRequests: filteredRequests,
        useScrollableList: useScrollableList,
        maxListHeight: maxListHeight,
        openOnTap: isMobile,
      ),
    );
  }

  Widget _buildRequestFiltersBar(int visibleCount) {
    return RequestFiltersBar<LeaveRequestStatus>(
      options: _leaveRequestFilterOptions,
      selectedValue: _selectedStatus,
      fromDate: _fromDate,
      toDate: _toDate,
      searchQuery: _searchQuery,
      visibleCount: visibleCount,
      totalCount: widget.requests.length,
      onSearchChanged: _onSearchQueryChanged,
      onStatusChanged: (status) => setState(() => _selectedStatus = status),
      onPickFromDate: () => _pickFilterDate(isFrom: true),
      onPickToDate: () => _pickFilterDate(isFrom: false),
      onClearFilters: _clearFilters,
    );
  }

  void _onSearchQueryChanged(String value) {
    if (_searchQuery == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  Widget _buildRequestsContent({
    required List<LeaveRequest> filteredRequests,
    required bool useScrollableList,
    required double maxListHeight,
    required bool openOnTap,
  }) {
    final filters = _buildRequestFiltersBar(filteredRequests.length);

    Widget listOrEmpty;
    if (widget.loading && widget.requests.isEmpty) {
      listOrEmpty = const _CenteredState(message: 'Loading leave requests...');
    } else if (widget.requests.isEmpty) {
      listOrEmpty = const _CenteredState(
        message:
            'No leave requests yet. Start by filing your first leave request.',
      );
    } else if (filteredRequests.isEmpty) {
      listOrEmpty = const _CenteredState(
        message: 'No leave requests match the current filters.',
      );
    } else if (!useScrollableList) {
      listOrEmpty = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(filteredRequests.length, (index) {
          final request = filteredRequests[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == filteredRequests.length - 1 ? 0 : 12,
            ),
            child: _EmployeeRequestItem(
              request: request,
              isSelected:
                  !openOnTap && _requestKey(request) == _selectedRequestKey,
              onTap: () => openOnTap
                  ? _showDetails(context, request)
                  : _toggleSelection(request),
            ),
          );
        }),
      );
    } else {
      listOrEmpty = ListView(
        controller: _requestsScrollController,
        primary: false,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(filteredRequests.length, (index) {
          final request = filteredRequests[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == filteredRequests.length - 1 ? 0 : 12,
            ),
            child: _EmployeeRequestItem(
              request: request,
              isSelected:
                  !openOnTap && _requestKey(request) == _selectedRequestKey,
              onTap: () => openOnTap
                  ? _showDetails(context, request)
                  : _toggleSelection(request),
            ),
          );
        }),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [filters, const SizedBox(height: 12), listOrEmpty],
    );

    if (!useScrollableList || filteredRequests.isEmpty) {
      return body;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxListHeight),
      child: Scrollbar(
        controller: _requestsScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _requestsScrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          child: body,
        ),
      ),
    );
  }

  List<LeaveRequest> get _filteredRequests {
    return widget.requests.where((request) {
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final text =
            '${request.leaveTypeLabel} ${request.reason ?? ''} ${request.status.displayName} ${request.employeeName ?? ''}'
                .toLowerCase();
        if (!text.contains(q)) return false;
      }
      if (_selectedStatus != null) {
        final status = request.status;
        if (_selectedStatus == LeaveRequestStatus.pending) {
          if (!status.isPending) return false;
        } else if (_selectedStatus == LeaveRequestStatus.rejected) {
          if (!status.isRejected) return false;
        } else if (status != _selectedStatus) {
          return false;
        }
      }
      if (_fromDate != null && request.startDate != null) {
        final d = _dateOnly(request.startDate!);
        if (d.isBefore(_dateOnly(_fromDate!))) return false;
      }
      if (_toDate != null && request.endDate != null) {
        final d = _dateOnly(request.endDate!);
        if (d.isAfter(_dateOnly(_toDate!))) return false;
      }
      return true;
    }).toList();
  }

  void _toggleSelection(LeaveRequest request) {
    final key = _requestKey(request);
    setState(() {
      _selectedRequestKey = _selectedRequestKey == key ? null : key;
    });
  }

  String _requestKey(LeaveRequest request) {
    return request.id ??
        '${request.createdAt?.toIso8601String() ?? ''}-${request.startDate?.toIso8601String() ?? ''}-${request.endDate?.toIso8601String() ?? ''}-${request.leaveTypeLabel}';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _pickFilterDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? _fromDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
          _toDate = _fromDate;
        }
      } else {
        _toDate = picked;
        if (_fromDate != null && _fromDate!.isAfter(_toDate!)) {
          _fromDate = _toDate;
        }
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedStatus = null;
      _fromDate = null;
      _toDate = null;
    });
  }

  void _showDetails(BuildContext context, LeaveRequest request) {
    final canEdit =
        request.status == LeaveRequestStatus.draft ||
        request.status == LeaveRequestStatus.returned ||
        request.status == LeaveRequestStatus.rejectedByDepartmentHead ||
        request.status == LeaveRequestStatus.rejectedByHr;

    showDialog<void>(
      context: context,
      builder: (_) => _EmployeeLeaveDetailsDialog(
        request: request,
        canEdit: canEdit,
        canCancel: _canEmployeeCancel(request),
        canPrint: request.status == LeaveRequestStatus.approved,
        onEdit: () => widget.onEdit(request),
        onHistory: () => _showHistory(context, request),
        onCancel: () => widget.onCancel(request),
        onPrint: () => widget.onPrint(request),
      ),
    );
  }

  void _showHistory(BuildContext context, LeaveRequest request) {
    final reviewed = request.reviewedAt;
    final reviewer = (request.reviewerName ?? '').trim().isNotEmpty
        ? request.reviewerName!.trim()
        : 'Approver';

    final events = [
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

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppTheme.dashPanelOf(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Leave Request History',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(dialogContext),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                HistoryTimeline(events: events),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeRequestItem extends StatelessWidget {
  const _EmployeeRequestItem({
    required this.request,
    required this.isSelected,
    required this.onTap,
  });

  final LeaveRequest request;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LeaveCard(
      request: request,
      onTap: onTap,
      isSelected: isSelected,
      showActions: false,
      onViewDetails: () {},
      onViewHistory: () {},
      onCancel: null,
    );
  }
}

/// Employee “view details” dialog — compact width, status chip, scrollable body.
class _EmployeeLeaveDetailsDialog extends StatelessWidget {
  const _EmployeeLeaveDetailsDialog({
    required this.request,
    required this.canEdit,
    required this.canCancel,
    required this.canPrint,
    required this.onEdit,
    required this.onHistory,
    required this.onCancel,
    required this.onPrint,
  });

  final LeaveRequest request;
  final bool canEdit;
  final bool canCancel;
  final bool canPrint;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onCancel;
  final VoidCallback onPrint;

  String get _leaveTypeText {
    return request.leaveTypeLabel;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxW = (screen.width - 40).clamp(300.0, 420.0);
    final bodyMaxH = (screen.height * 0.52).clamp(220.0, 420.0);

    return Dialog(
      backgroundColor: AppTheme.dashPanelOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.event_available_rounded,
                      color: AppTheme.primaryNavy,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Leave details',
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LeaveStatusChip(status: request.status),
                      ],
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
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bodyMaxH),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LeaveDetailTile(
                      icon: Icons.category_outlined,
                      label: 'Leave type',
                      value: _leaveTypeText,
                    ),
                    if (request.leaveType == LeaveType.maternityLeave &&
                        request.maternityDeliveryType != null)
                      _LeaveDetailTile(
                        icon: Icons.medical_information_outlined,
                        label: 'Classification',
                        value: request.maternityDeliveryType!.displayName,
                      ),
                    if (request.leaveType == LeaveType.maternityLeave &&
                        request.expectedDeliveryDate != null)
                      _LeaveDetailTile(
                        icon: Icons.child_friendly_rounded,
                        label: 'Expected delivery date',
                        value: _formatDate(request.expectedDeliveryDate!),
                      ),
                    if (request.leaveType == LeaveType.paternityLeave &&
                        request.childDeliveryDate != null)
                      _LeaveDetailTile(
                        icon: Icons.child_care_rounded,
                        label: 'Child delivery date',
                        value: _formatDate(request.childDeliveryDate!),
                      ),
                    if (request.leaveType ==
                            LeaveType.rehabilitationPrivilege &&
                        request.accidentDate != null)
                      _LeaveDetailTile(
                        icon: Icons.healing_rounded,
                        label: 'Accident date',
                        value: _formatDate(request.accidentDate!),
                      ),
                    if (request.leaveType ==
                            LeaveType.specialEmergencyCalamityLeave &&
                        request.calamityDate != null)
                      _LeaveDetailTile(
                        icon: Icons.warning_amber_rounded,
                        label: 'Calamity occurrence date',
                        value: _formatDate(request.calamityDate!),
                      ),
                    _LeaveDetailTile(
                      icon: Icons.date_range_rounded,
                      label: 'Date range',
                      value: _formatLeaveRequestRange(request),
                    ),
                    _LeaveDetailTile(
                      icon: Icons.timelapse_rounded,
                      label: 'Working days',
                      value:
                          request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
                    ),
                    _LeaveDetailTile(
                      icon: Icons.send_rounded,
                      label: 'Submitted',
                      value: request.dateFiled != null
                          ? _formatDate(request.dateFiled!)
                          : '—',
                    ),
                    if ((request.officeDepartment ?? '').trim().isNotEmpty)
                      _LeaveDetailTile(
                        icon: Icons.apartment_rounded,
                        label: 'Office / department',
                        value: request.officeDepartment!.trim(),
                      ),
                    _LeaveDetailTile(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Commutation',
                      value: request.commutation.displayName,
                    ),
                    if ((request.reason ?? '').trim().isNotEmpty)
                      _LeaveDetailReasonCard(text: request.reason!.trim()),
                    if ((request.disapprovalReason ?? '').trim().isNotEmpty)
                      _LeaveDetailNotice(
                        icon: Icons.info_outline_rounded,
                        title: 'Decision note',
                        body: request.disapprovalReason!.trim(),
                        tone: _LeaveNoticeTone.warning,
                      ),
                    if ((request.hrRemarks ?? '').trim().isNotEmpty &&
                        request.status == LeaveRequestStatus.approved)
                      _LeaveDetailNotice(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'HR remarks',
                        body: request.hrRemarks!.trim(),
                        tone: _LeaveNoticeTone.neutral,
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onHistory();
                    },
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('History'),
                  ),
                  if (canEdit)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onEdit();
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                    ),
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onCancel();
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel'),
                    ),
                  if (canPrint)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onPrint();
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveDetailTile extends StatelessWidget {
  const _LeaveDetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: AppTheme.primaryNavy.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveDetailReasonCard extends StatelessWidget {
  const _LeaveDetailReasonCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notes_rounded,
                  size: 18,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Reason',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LeaveNoticeTone { neutral, warning }

class _LeaveDetailNotice extends StatelessWidget {
  const _LeaveDetailNotice({
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final _LeaveNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, border, iconC) = switch (tone) {
      _LeaveNoticeTone.warning => (
        Colors.red.shade50,
        Colors.red.shade100,
        Colors.red.shade800,
      ),
      _LeaveNoticeTone.neutral => (
        AppTheme.dashMutedSurfaceOf(context),
        AppTheme.dashHairlineOf(context),
        AppTheme.primaryNavy,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconC),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
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

Color _leaveBalanceAccent(LeaveType type) {
  return switch (type) {
    LeaveType.sickLeave => const Color(0xFFE53935),
    LeaveType.vacationLeave => AppTheme.primaryNavyLight,
    LeaveType.maternityLeave => const Color(0xFFD81B60),
    LeaveType.paternityLeave => const Color(0xFF5E35B1),
    LeaveType.specialPrivilegeLeave => const Color(0xFF00897B),
    LeaveType.soloParentLeave => const Color(0xFF3949AB),
    LeaveType.studyLeave => const Color(0xFF1E88E5),
    LeaveType.tenDayVawcLeave => const Color(0xFF8E24AA),
    LeaveType.rehabilitationPrivilege => const Color(0xFF43A047),
    LeaveType.specialLeaveBenefitsForWomen => const Color(0xFFC2185B),
    LeaveType.specialEmergencyCalamityLeave => const Color(0xFFF4511E),
    LeaveType.adoptionLeave => const Color(0xFF6D4C41),
    LeaveType.mandatoryForcedLeave => const Color(0xFFFB8C00),
    LeaveType.others => AppTheme.primaryNavy,
  };
}

bool _canEmployeeCancel(LeaveRequest request) {
  return switch (request.status) {
    LeaveRequestStatus.draft ||
    LeaveRequestStatus.pending ||
    LeaveRequestStatus.pendingDepartmentHead ||
    LeaveRequestStatus.pendingHr ||
    LeaveRequestStatus.returned => true,
    LeaveRequestStatus.approved ||
    LeaveRequestStatus.rejectedByDepartmentHead ||
    LeaveRequestStatus.rejectedByHr ||
    LeaveRequestStatus.rejected ||
    LeaveRequestStatus.cancelled => false,
  };
}

String _formatLeaveRequestRange(LeaveRequest request) {
  if (request.startDate == null || request.endDate == null) return '—';
  return '${_formatDate(request.startDate!)} – ${_formatDate(request.endDate!)}';
}
