import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';

/// Balance movement audit from GET /api/leave/ledger.
///
/// [isAdmin]: HR filters + dashboard layout. Employee: JWT-scoped Stitch-style summary + list.
class LeaveBalanceHistoryScreen extends StatefulWidget {
  const LeaveBalanceHistoryScreen({
    super.key,
    required this.isAdmin,
    this.initialFilterUserId,
  });

  final bool isAdmin;

  /// Pre-fills admin employee filter (e.g. queue filter).
  final String? initialFilterUserId;

  @override
  State<LeaveBalanceHistoryScreen> createState() =>
      _LeaveBalanceHistoryScreenState();
}

class _LeaveBalanceHistoryScreenState extends State<LeaveBalanceHistoryScreen> {
  bool _loading = true;
  String? _error;
  LeaveLedgerResult? _result;
  static const int _pageSize = 50;

  /// Admin: applied API filters (updated on **Apply Filter**).
  String? _appliedEmployeeId;
  String? _appliedLeaveType;

  /// Admin: dropdown draft state (Apply copies into [_appliedEmployeeId] / [_appliedLeaveType]).
  String? _draftEmployeeId;
  String? _draftLeaveType;

  /// Admin: `/api/employees?status=Active` for the employee dropdown.
  bool _employeesLoading = true;
  String? _employeesError;
  List<_EmployeeOption> _employees = const [];
  StreamSubscription<AppRealtimeEvent>? _leaveRealtimeSub;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFilterUserId?.trim();
    _draftEmployeeId = initial != null && initial.isNotEmpty ? initial : null;
    _appliedEmployeeId = _draftEmployeeId;
    _appliedLeaveType = null;
    _draftLeaveType = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isAdmin) {
        _loadEmployees();
      }
      _load(resetOffset: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentUserId = context.watch<AuthProvider>().user?.id;
    _leaveRealtimeSub ??= context.read<AppRealtimeProvider>().events.listen((
      event,
    ) {
      if (event.name != 'leave_updated') return;
      if (widget.isAdmin) {
        final filterUserId = _appliedEmployeeId;
        if (filterUserId != null &&
            filterUserId.isNotEmpty &&
            !event.affectsUser(filterUserId)) {
          return;
        }
      } else {
        if (!event.affectsUser(_currentUserId)) return;
      }
      context.read<LeaveProvider>().invalidateCachedLeaveData();
      unawaited(_refreshFromRealtime());
    });
  }

  @override
  void dispose() {
    _leaveRealtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshFromRealtime() async {
    if (!mounted || _loading) return;
    await _load(resetOffset: true, forceRefresh: true);
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _employeesLoading = true;
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
                (e) => _EmployeeOption(
                  id: e['id']?.toString() ?? '',
                  name: e['full_name']?.toString() ?? 'Unnamed',
                ),
              )
              .where((e) => e.id.isNotEmpty)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _employees = rows;
        _employeesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _employeesError = e.toString();
        _employeesLoading = false;
      });
    }
  }

  Future<void> _load({
    required bool resetOffset,
    bool forceRefresh = false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = LeaveLedgerQuery(
        userId: widget.isAdmin
            ? (_appliedEmployeeId != null && _appliedEmployeeId!.isNotEmpty
                  ? _appliedEmployeeId
                  : null)
            : null,
        leaveType: widget.isAdmin
            ? (_appliedLeaveType != null && _appliedLeaveType!.isNotEmpty
                  ? _appliedLeaveType
                  : null)
            : null,
        limit: _pageSize,
        offset: resetOffset ? 0 : (_result?.offset ?? 0),
      );
      final page = await context.read<LeaveProvider>().fetchLeaveLedger(
        q,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _result = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final prev = _result;
    if (prev == null || prev.rows.length >= prev.total) return;
    setState(() => _loading = true);
    try {
      final q = LeaveLedgerQuery(
        userId: widget.isAdmin
            ? (_appliedEmployeeId != null && _appliedEmployeeId!.isNotEmpty
                  ? _appliedEmployeeId
                  : null)
            : null,
        leaveType: widget.isAdmin
            ? (_appliedLeaveType != null && _appliedLeaveType!.isNotEmpty
                  ? _appliedLeaveType
                  : null)
            : null,
        limit: _pageSize,
        offset: prev.offset + prev.rows.length,
      );
      final next = await context.read<LeaveProvider>().fetchLeaveLedger(q);
      if (!mounted) return;
      setState(() {
        _result = LeaveLedgerResult(
          total: next.total,
          limit: next.limit,
          offset: prev.offset,
          rows: [...prev.rows, ...next.rows],
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _appliedEmployeeId = _draftEmployeeId;
      _appliedLeaveType = _draftLeaveType;
    });
    _load(resetOffset: true, forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdmin) {
      return _buildAdminScaffold(context);
    }
    return _buildEmployeeScaffold(context);
  }

  Widget _buildEmployeeScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        title: const Text('Balance History'),
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading
                ? null
                : () => _load(resetOffset: true, forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _errorBanner(),
          Expanded(
            child: _loading && _result == null
                ? const Center(child: CircularProgressIndicator())
                : _buildEmployeeContent(),
          ),
        ],
      ),
    );
  }

  /// Stitch-style: summary band + scrollable list (or empty state).
  Widget _buildEmployeeContent() {
    final r = _result;
    if (r == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'No data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    final stats = _ledgerSummaryStats(r.rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmployeeSummaryBand(stats: stats),
        Expanded(
          child: r.rows.isEmpty
              ? const _EmployeeEmptyState()
              : _buildEmployeeHistoryList(r),
        ),
      ],
    );
  }

  Widget _buildEmployeeHistoryList(LeaveLedgerResult r) {
    final showMore = r.rows.length < r.total;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: r.rows.length + (showMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == r.rows.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                onPressed: _loading ? null : _loadMore,
                child: Text(
                  _loading
                      ? 'Loading…'
                      : 'Load more (${r.rows.length} of ${r.total})',
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _EmployeeLedgerRow(entry: r.rows[i]),
        );
      },
    );
  }

  Widget _buildAdminScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        title: const Text('Leave Ledger'),
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading
                ? null
                : () => _load(resetOffset: true, forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _errorBanner(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: _buildAdminBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    final dark = AppTheme.dashIsDark(context);
    return Material(
      color: dark
          ? Colors.red.shade900.withValues(alpha: 0.35)
          : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: dark ? Colors.red.shade300 : Colors.red.shade800,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(
                  color: dark ? Colors.red.shade100 : Colors.red.shade900,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Manage employee leave balances and transaction history.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _AdminSummaryChips(
            stats: _ledgerSummaryStats(_result?.rows ?? const []),
          ),
          const SizedBox(height: 6),
          Text(
            'These figures sum days from the ledger rows loaded below (current filters; '
            'use "Load more" to include additional history). They are activity totals for '
            'those entries only—not the employee\'s current leave balances.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _AdminFilterCard(
            employeesLoading: _employeesLoading,
            employeesError: _employeesError,
            employees: _employees,
            draftEmployeeId: _draftEmployeeId,
            draftLeaveType: _draftLeaveType,
            onEmployeeChanged: (v) => setState(() => _draftEmployeeId = v),
            onLeaveTypeChanged: (v) => setState(() => _draftLeaveType = v),
            onApply: _applyFilters,
            applyEnabled: !_loading || _result != null,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading && _result == null
                ? const Center(child: CircularProgressIndicator())
                : _buildAdminLedgerList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminLedgerList() {
    final r = _result;
    if (r == null) {
      return Center(
        child: Text(
          _error ?? 'No data.',
          style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
        ),
      );
    }
    if (r.rows.isEmpty) {
      return const _AdminEmptyState();
    }

    final showMore = r.rows.length < r.total;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: r.rows.length + (showMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == r.rows.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: TextButton(
                onPressed: _loading ? null : _loadMore,
                child: Text(
                  _loading
                      ? 'Loading…'
                      : 'Load more (${r.rows.length} of ${r.total})',
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _AdminLedgerTile(entry: r.rows[i]),
        );
      },
    );
  }
}

// --- Employee Balance History (Stitch layout) ---

class _EmployeeSummaryBand extends StatelessWidget {
  const _EmployeeSummaryBand({required this.stats});

  final _LedgerSummaryStats stats;

  String _fmtDays(double v) {
    if ((v - v.round()).abs() < 1e-9) return '${v.round()} Days';
    return '${v.toStringAsFixed(1)} Days';
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: double.infinity,
      color: AppTheme.sectionAltOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 400;
          final chips = [
            _EmployeeSummaryChip(
              amountLabel: _fmtDays(stats.totalEarned),
              caption: 'Earned',
              icon: Icons.arrow_upward_rounded,
              circleColor: dark
                  ? Colors.green.shade900.withValues(alpha: 0.4)
                  : const Color(0xFFE8F5E9),
              iconColor: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
            ),
            _EmployeeSummaryChip(
              amountLabel: _fmtDays(stats.totalUsed),
              caption: 'Used',
              icon: Icons.arrow_downward_rounded,
              circleColor: dark
                  ? Colors.red.shade900.withValues(alpha: 0.4)
                  : const Color(0xFFFFEBEE),
              iconColor: dark ? Colors.red.shade300 : const Color(0xFFC62828),
            ),
            _EmployeeSummaryChip(
              amountLabel: _fmtDays(stats.totalPending),
              caption: 'Pending',
              icon: Icons.schedule_rounded,
              circleColor: dark
                  ? AppTheme.dashMutedSurfaceOf(context)
                  : const Color(0xFFECEFF1),
              iconColor: dark
                  ? Colors.blueGrey.shade300
                  : const Color(0xFF607D8B),
            ),
          ];
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  chips[i],
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: chips[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeSummaryChip extends StatelessWidget {
  const _EmployeeSummaryChip({
    required this.amountLabel,
    required this.caption,
    required this.icon,
    required this.circleColor,
    required this.iconColor,
  });

  final String amountLabel;
  final String caption;
  final IconData icon;
  final Color circleColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: AppTheme.dashSurfaceCard(context, radius: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  amountLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.15,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.dashTextSecondaryOf(context),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeEmptyState extends StatelessWidget {
  const _EmployeeEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: AppTheme.dashTextSecondaryOf(
                context,
              ).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'No leave activity yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your leave accruals and requests will appear here once available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
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

class _EmployeeLedgerRow extends StatelessWidget {
  const _EmployeeLedgerRow({required this.entry});

  final LeaveBalanceLedgerEntry entry;

  static const List<String> _months = [
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

  String _shortDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _leaveTypeLabel(String raw) {
    if (raw.isEmpty) return '';
    return leaveTypeFromString(raw).displayName;
  }

  String _signedDaysLabel(double d) {
    if (d == 0) return '0 Days';
    final sign = d > 0 ? '+' : '-';
    final a = d.abs();
    final n = a == a.truncateToDouble()
        ? a.toInt().toString()
        : a.toStringAsFixed(2);
    return '$sign$n Days';
  }

  ({Color bg, Color fg, IconData icon}) _circleStyle(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final a = entry.action.toLowerCase();
    final b = entry.affectedBucket.toLowerCase();
    final d = entry.daysChanged;

    if (a == 'monthly_accrual' || a == 'applied' || (d > 0 && b == 'earned')) {
      return (
        bg: dark
            ? Colors.green.shade900.withValues(alpha: 0.4)
            : const Color(0xFFE8F5E9),
        fg: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
        icon: Icons.arrow_upward_rounded,
      );
    }
    if (a == 'admin_adjustment' || a.contains('adjust')) {
      return (
        bg: dark
            ? AppTheme.dashMutedSurfaceOf(context)
            : const Color(0xFFECEFF1),
        fg: dark ? Colors.blueGrey.shade300 : const Color(0xFF546E7A),
        icon: Icons.tune_rounded,
      );
    }
    if (a.contains('approved') ||
        a.contains('deduction') ||
        (d < 0 && b == 'used')) {
      return (
        bg: dark
            ? Colors.red.shade900.withValues(alpha: 0.4)
            : const Color(0xFFFFEBEE),
        fg: dark ? Colors.red.shade300 : const Color(0xFFC62828),
        icon: Icons.arrow_downward_rounded,
      );
    }
    if (d < 0) {
      return (
        bg: dark
            ? Colors.red.shade900.withValues(alpha: 0.4)
            : const Color(0xFFFFEBEE),
        fg: dark ? Colors.red.shade300 : const Color(0xFFC62828),
        icon: Icons.arrow_downward_rounded,
      );
    }
    if (d > 0) {
      return (
        bg: dark
            ? Colors.green.shade900.withValues(alpha: 0.4)
            : const Color(0xFFE8F5E9),
        fg: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
        icon: Icons.arrow_upward_rounded,
      );
    }
    return (
      bg: dark ? AppTheme.dashMutedSurfaceOf(context) : const Color(0xFFECEFF1),
      fg: dark ? Colors.blueGrey.shade300 : const Color(0xFF607D8B),
      icon: Icons.schedule_rounded,
    );
  }

  String _actionTitle(String raw) {
    final a = raw.toLowerCase();
    switch (a) {
      case 'monthly_accrual':
        return 'Monthly Accrual';
      case 'leave_approved':
        return 'Leave Approved';
      case 'admin_adjustment':
        return 'Manual Adjustment';
      case 'leave_submitted':
        return 'Leave Submitted';
      case 'forced_leave_deduction':
        return 'Forced Leave Deduction';
      case 'leave_cancelled':
        return 'Leave Cancelled';
      case 'leave_rejected':
        return 'Leave Rejected';
      case 'leave_returned':
        return 'Leave Returned';
      case 'leave_revoked':
        return 'Leave Revoked';
      default:
        if (raw.isEmpty) return 'Activity';
        return raw
            .split('_')
            .map((w) {
              if (w.isEmpty) return w;
              if (w.length == 1) return w.toUpperCase();
              return '${w[0].toUpperCase()}${w.substring(1)}';
            })
            .join(' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final st = _circleStyle(context);
    final amountColor = entry.daysChanged >= 0
        ? (dark ? Colors.green.shade300 : const Color(0xFF2E7D32))
        : (dark ? Colors.red.shade300 : const Color(0xFFC62828));
    final lt = _leaveTypeLabel(entry.leaveType);
    final metaBrief =
        entry.metadataJson != null && entry.metadataJson!.isNotEmpty
        ? entry.metadataJson!.entries
              .take(2)
              .map((e) => '${e.key}: ${e.value}')
              .join(' · ')
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: st.bg),
            child: Icon(st.icon, color: st.fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _actionTitle(entry.action),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.dashTextPrimaryOf(context),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _shortDate(entry.createdAt),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                if (lt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lt,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ],
                if (entry.remarks != null &&
                    entry.remarks!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.remarks!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.dashTextPrimaryOf(context),
                      height: 1.35,
                    ),
                  ),
                ],
                if (entry.affectedBucket.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.affectedBucket,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(
                        context,
                      ).withValues(alpha: 0.9),
                    ),
                  ),
                ],
                if (metaBrief != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    metaBrief,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.dashTextSecondaryOf(context),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _signedDaysLabel(entry.daysChanged),
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Admin dashboard pieces ---

class _LedgerSummaryStats {
  const _LedgerSummaryStats({
    required this.totalEarned,
    required this.totalUsed,
    required this.totalPending,
  });

  final double totalEarned;
  final double totalUsed;
  final double totalPending;
}

_LedgerSummaryStats _ledgerSummaryStats(List<LeaveBalanceLedgerEntry> rows) {
  double earned = 0;
  double used = 0;
  double pending = 0;

  for (final e in rows) {
    final b = e.affectedBucket.toLowerCase();
    final a = e.action.toLowerCase();
    final d = e.daysChanged;

    if (d > 0 && (b == 'earned' || a == 'monthly_accrual')) {
      earned += d;
    }
    if (d < 0 && b == 'used') {
      used += -d;
    }
    if (b == 'pending') {
      pending += d.abs();
    }
  }

  return _LedgerSummaryStats(
    totalEarned: earned,
    totalUsed: used,
    totalPending: pending,
  );
}

class _AdminSummaryChips extends StatelessWidget {
  const _AdminSummaryChips({required this.stats});

  final _LedgerSummaryStats stats;

  String _fmt(double v) {
    if ((v - v.round()).abs() < 1e-9) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final children = [
          _SummaryChip(
            label: 'Total Earned',
            value: _fmt(stats.totalEarned),
            icon: Icons.add_rounded,
            iconBoxColor: dark
                ? Colors.green.shade900.withValues(alpha: 0.4)
                : const Color(0xFFE8F5E9),
            iconColor: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
            valueColor: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
          ),
          _SummaryChip(
            label: 'Total Used',
            value: _fmt(stats.totalUsed),
            icon: Icons.remove_rounded,
            iconBoxColor: dark
                ? Colors.red.shade900.withValues(alpha: 0.4)
                : const Color(0xFFFFEBEE),
            iconColor: dark ? Colors.red.shade300 : const Color(0xFFC62828),
            valueColor: AppTheme.dashTextPrimaryOf(context),
          ),
          _SummaryChip(
            label: 'Total Pending',
            value: _fmt(stats.totalPending),
            icon: Icons.schedule_rounded,
            iconBoxColor: dark
                ? Colors.amber.shade900.withValues(alpha: 0.35)
                : const Color(0xFFFFF8E1),
            iconColor: dark ? Colors.amber.shade300 : const Color(0xFFF9A825),
            valueColor: dark ? Colors.amber.shade200 : const Color(0xFFF57F17),
          ),
        ];
        if (narrow) {
          return Wrap(spacing: 10, runSpacing: 10, children: children);
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Reference layout: white card, gray border, colored icon square, `Label: value` in one line.
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBoxColor,
    required this.iconColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconBoxColor;
  final Color iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.dashSurfaceCard(context, radius: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBoxColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  height: 1.25,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
                children: [
                  TextSpan(text: '$label: '),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeOption {
  const _EmployeeOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _AdminFilterCard extends StatelessWidget {
  const _AdminFilterCard({
    required this.employeesLoading,
    required this.employeesError,
    required this.employees,
    required this.draftEmployeeId,
    required this.draftLeaveType,
    required this.onEmployeeChanged,
    required this.onLeaveTypeChanged,
    required this.onApply,
    required this.applyEnabled,
  });

  final bool employeesLoading;
  final String? employeesError;
  final List<_EmployeeOption> employees;
  final String? draftEmployeeId;
  final String? draftLeaveType;
  final ValueChanged<String?> onEmployeeChanged;
  final ValueChanged<String?> onLeaveTypeChanged;
  final VoidCallback? onApply;
  final bool applyEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final row = constraints.maxWidth >= 720;
          final employeeField = _employeeDropdown(context);
          final leaveField = _leaveTypeDropdown(context);
          final applyBtn = FilledButton(
            onPressed: applyEnabled ? onApply : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Apply Filter'),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              if (row)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 2, child: employeeField),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: leaveField),
                    const SizedBox(width: 12),
                    applyBtn,
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    employeeField,
                    const SizedBox(height: 12),
                    leaveField,
                    const SizedBox(height: 12),
                    applyBtn,
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _employeeDropdown(BuildContext context) {
    if (employeesLoading) {
      return InputDecorator(
        decoration: adminLeaveInputDecoration(
          context,
          'Employee',
        ).copyWith(isDense: true),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading employees…',
              style: AppTheme.dashFieldTextStyle(context),
            ),
          ],
        ),
      );
    }
    if (employeesError != null) {
      final dark = AppTheme.dashIsDark(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Employees: $employeesError',
            style: TextStyle(
              color: dark ? Colors.red.shade300 : Colors.red.shade800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            value: draftEmployeeId,
            decoration: adminLeaveInputDecoration(
              context,
              'Employee',
            ).copyWith(isDense: true),
            hint: Text(
              'Select employee…',
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
            ),
            items: const [],
            onChanged: null,
          ),
        ],
      );
    }

    return DropdownButtonFormField<String?>(
      value: _safeEmployeeValue(draftEmployeeId, employees),
      dropdownColor: AppTheme.dashPanelOf(context),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: adminLeaveInputDecoration(
        context,
        'Employee',
      ).copyWith(isDense: true),
      hint: Text(
        'Select employee…',
        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'All employees',
            style: AppTheme.dashFieldTextStyle(context),
          ),
        ),
        ...employees.map(
          (e) => DropdownMenuItem<String?>(
            value: e.id,
            child: Text(
              e.name,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dashFieldTextStyle(context),
            ),
          ),
        ),
      ],
      onChanged: onEmployeeChanged,
    );
  }

  /// Keeps [DropdownButtonFormField] from asserting when list does not contain value.
  String? _safeEmployeeValue(String? id, List<_EmployeeOption> list) {
    if (id == null || id.isEmpty) return null;
    final ok = list.any((e) => e.id == id);
    return ok ? id : null;
  }

  Widget _leaveTypeDropdown(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: draftLeaveType,
      dropdownColor: AppTheme.dashPanelOf(context),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: adminLeaveInputDecoration(
        context,
        'Leave type',
      ).copyWith(isDense: true),
      hint: Text(
        'Select leave type…',
        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'All leave types',
            style: AppTheme.dashFieldTextStyle(context),
          ),
        ),
        ...LeaveType.values.map(
          (t) => DropdownMenuItem<String?>(
            value: t.value,
            child: Text(
              t.displayName,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dashFieldTextStyle(context),
            ),
          ),
        ),
      ],
      onChanged: onLeaveTypeChanged,
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: AppTheme.dashTextSecondaryOf(
                context,
              ).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'No leave activity yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave accruals, approvals, and adjustments will appear here once available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminLedgerTile extends StatelessWidget {
  const _AdminLedgerTile({required this.entry});

  final LeaveBalanceLedgerEntry entry;

  String _leaveTypeLabel(String raw) {
    if (raw.isEmpty) return '—';
    return leaveTypeFromString(raw).displayName;
  }

  String _fmtDt(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$mm/$dd/${d.year} · $h:$min';
  }

  String _fmtSigned(double d) {
    if (d == 0) return '0';
    final sign = d > 0 ? '+' : '-';
    final a = d.abs();
    final t = a == a.truncateToDouble()
        ? a.toInt().toString()
        : a.toStringAsFixed(2);
    return '$sign$t';
  }

  ({Color bg, Color fg, IconData icon}) _styleForEntry(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final a = entry.action.toLowerCase();
    final d = entry.daysChanged;

    if (a == 'monthly_accrual' ||
        a == 'applied' ||
        (d > 0 && entry.affectedBucket.toLowerCase() == 'earned')) {
      return (
        bg: dark
            ? Colors.green.shade900.withValues(alpha: 0.4)
            : const Color(0xFFE8F5E9),
        fg: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
        icon: Icons.add_rounded,
      );
    }
    if (a == 'admin_adjustment' || a.contains('adjust')) {
      return (
        bg: dark
            ? AppTheme.primaryNavy.withValues(alpha: 0.35)
            : const Color(0xFFE3F2FD),
        fg: dark ? AppTheme.primaryNavyLight : const Color(0xFF1565C0),
        icon: Icons.edit_outlined,
      );
    }
    if (a.contains('approved') ||
        a.contains('deduction') ||
        (d < 0 && entry.affectedBucket.toLowerCase() == 'used')) {
      return (
        bg: dark
            ? Colors.red.shade900.withValues(alpha: 0.4)
            : const Color(0xFFFFEBEE),
        fg: dark ? Colors.red.shade300 : const Color(0xFFC62828),
        icon: Icons.remove_rounded,
      );
    }
    if (d < 0) {
      return (
        bg: dark
            ? Colors.red.shade900.withValues(alpha: 0.4)
            : const Color(0xFFFFEBEE),
        fg: dark ? Colors.red.shade300 : const Color(0xFFC62828),
        icon: Icons.remove_rounded,
      );
    }
    return (
      bg: AppTheme.primaryNavy.withValues(alpha: dark ? 0.35 : 0.1),
      fg: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
      icon: Icons.swap_horiz_rounded,
    );
  }

  String _actionTitle(String raw) {
    final a = raw.toLowerCase();
    switch (a) {
      case 'monthly_accrual':
        return 'Monthly Accrual';
      case 'leave_approved':
        return 'Leave Approved';
      case 'admin_adjustment':
        return 'Manual Adjustment';
      case 'leave_submitted':
        return 'Leave Submitted';
      case 'forced_leave_deduction':
        return 'Forced Leave Deduction';
      case 'leave_cancelled':
        return 'Leave Cancelled';
      case 'leave_rejected':
        return 'Leave Rejected';
      case 'leave_returned':
        return 'Leave Returned';
      case 'leave_revoked':
        return 'Leave Revoked';
      default:
        if (raw.isEmpty) return 'Ledger entry';
        return raw
            .split('_')
            .map((w) {
              if (w.isEmpty) return w;
              if (w.length == 1) return w.toUpperCase();
              return '${w[0].toUpperCase()}${w.substring(1)}';
            })
            .join(' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final st = _styleForEntry(context);
    final meta = entry.metadataJson;
    final metaBrief = meta != null && meta.isNotEmpty
        ? meta.entries.take(3).map((e) => '${e.key}: ${e.value}').join(' · ')
        : null;

    final amountColor = entry.daysChanged >= 0
        ? (dark ? Colors.green.shade300 : const Color(0xFF2E7D32))
        : (dark ? Colors.red.shade300 : const Color(0xFFC62828));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: st.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(st.icon, color: st.fg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _actionTitle(entry.action),
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _leaveTypeLabel(entry.leaveType),
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bucket: ${entry.affectedBucket}',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                  ),
                ),
                if (entry.relatedLeaveRequestId != null &&
                    entry.relatedLeaveRequestId!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Ref #${entry.relatedLeaveRequestId}',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (entry.employeeName != null &&
                    entry.employeeName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.employeeName!,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (entry.remarks != null &&
                    entry.remarks!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.remarks!,
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 13,
                    ),
                  ),
                ],
                if (metaBrief != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    metaBrief,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _fmtDt(entry.createdAt),
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(
                      context,
                    ).withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtSigned(entry.daysChanged),
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
