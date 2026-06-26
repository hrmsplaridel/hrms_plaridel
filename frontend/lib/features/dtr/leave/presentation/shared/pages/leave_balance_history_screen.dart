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
  static const int _pageSize = 25;
  int _currentPage = 0; // 0-indexed

  /// Admin: active filter state (changes trigger an immediate reload).
  String? _draftEmployeeId;
  String? _draftLeaveType;
  String? _draftDepartmentId;

  /// Admin: employee list for filter dropdown.
  bool _employeesLoading = true;
  String? _employeesError;
  List<_EmployeeOption> _allEmployees = const [];

  /// Admin: department list for filter dropdown.
  bool _departmentsLoading = true;
  List<_DepartmentOption> _departments = const [];

  StreamSubscription<AppRealtimeEvent>? _leaveRealtimeSub;
  String? _currentUserId;

  /// Employees visible in the dropdown — server-filtered when a dept is active.
  List<_EmployeeOption> get _filteredEmployees => _allEmployees;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFilterUserId?.trim();
    _draftEmployeeId = initial != null && initial.isNotEmpty ? initial : null;
    _draftLeaveType = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isAdmin) {
        _loadEmployees();
        _loadDepartments();
      }
      _load(resetPage: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentUserId = context.watch<AuthProvider>().user?.id;
    final leaveProvider = context.read<LeaveProvider>();
    _leaveRealtimeSub ??= context.read<AppRealtimeProvider>().events.listen((
      event,
    ) {
      if (event.name != 'leave_updated') return;
      if (widget.isAdmin) {
        final filterUserId = _draftEmployeeId;
        if (filterUserId != null &&
            filterUserId.isNotEmpty &&
            !event.affectsUser(filterUserId)) {
          return;
        }
      } else {
        if (!event.affectsUser(_currentUserId)) return;
      }
      leaveProvider.invalidateCachedLeaveData();
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
    await _load(resetPage: true, forceRefresh: true);
  }

  Future<void> _loadEmployees({String? departmentId}) async {
    setState(() {
      _employeesLoading = true;
      _employeesError = null;
    });
    try {
      final deptParam =
          departmentId != null && departmentId.isNotEmpty
              ? '&department_id=$departmentId'
              : '';
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees?status=Active$deptParam',
      );
      final rows =
          (res.data ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => _EmployeeOption(
                  id: e['id']?.toString() ?? '',
                  name: e['full_name']?.toString() ?? 'Unnamed',
                  departmentId: e['current_department_id']?.toString(),
                ),
              )
              .where((e) => e.id.isNotEmpty)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _allEmployees = rows;
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

  Future<void> _loadDepartments() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments?status=Active',
      );
      final rows =
          (res.data ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => _DepartmentOption(
                  id: e['id']?.toString() ?? '',
                  name: e['name']?.toString() ?? 'Unknown',
                ),
              )
              .where((e) => e.id.isNotEmpty)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _departments = rows;
        _departmentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _departmentsLoading = false);
    }
  }

  Future<void> _load({
    required bool resetPage,
    bool forceRefresh = false,
  }) async {
    if (resetPage) _currentPage = 0;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = LeaveLedgerQuery(
        userId: widget.isAdmin
            ? (_draftEmployeeId != null && _draftEmployeeId!.isNotEmpty
                  ? _draftEmployeeId
                  : null)
            : null,
        leaveType: widget.isAdmin
            ? (_draftLeaveType != null && _draftLeaveType!.isNotEmpty
                  ? _draftLeaveType
                  : null)
            : null,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
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


  int get _totalPages {
    final total = _result?.total ?? 0;
    if (total == 0) return 1;
    return ((total - 1) ~/ _pageSize) + 1;
  }

  void _goToPage(int page) {
    final clamped = page.clamp(0, _totalPages - 1);
    if (clamped == _currentPage) return;
    _currentPage = clamped;
    _load(resetPage: false, forceRefresh: true);
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
                : () => _load(resetPage: true, forceRefresh: true),
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
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: r.rows.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EmployeeLedgerRow(entry: r.rows[i]),
            ),
          ),
        ),
        if (_totalPages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _PaginationBar(
              currentPage: _currentPage,
              totalPages: _totalPages,
              total: r.total,
              pageSize: _pageSize,
              loading: _loading,
              onPage: _goToPage,
            ),
          ),
      ],
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
                : () => _load(resetPage: true, forceRefresh: true),
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
          _AdminSummaryChips(
            stats: _ledgerSummaryStats(_result?.rows ?? const []),
            total: _result?.total,
          ),
          const SizedBox(height: 12),
          _AdminFilterCard(
            employeesLoading: _employeesLoading,
            employeesError: _employeesError,
            employees: _filteredEmployees,
            departments: _departments,
            departmentsLoading: _departmentsLoading,
            draftEmployeeId: _draftEmployeeId,
            draftLeaveType: _draftLeaveType,
            draftDepartmentId: _draftDepartmentId,
            onDepartmentChanged: (v) {
              setState(() {
                _draftDepartmentId = v;
                // Always reset employee selection when department changes
                _draftEmployeeId = null;
              });
              // Reload employee list filtered by the new department (server-side)
              _loadEmployees(departmentId: v);
              _load(resetPage: true, forceRefresh: true);
            },
            onEmployeeChanged: (v) {
              setState(() => _draftEmployeeId = v);
              _load(resetPage: true, forceRefresh: true);
            },
            onLeaveTypeChanged: (v) {
              setState(() => _draftLeaveType = v);
              _load(resetPage: true, forceRefresh: true);
            },
          ),
          const SizedBox(height: 12),
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

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: r.rows.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _AdminLedgerTile(entry: r.rows[i]),
            ),
          ),
        ),
        if (_totalPages > 1) ...[
          const SizedBox(height: 8),
          _PaginationBar(
            currentPage: _currentPage,
            totalPages: _totalPages,
            total: r.total,
            pageSize: _pageSize,
            loading: _loading,
            onPage: _goToPage,
          ),
        ],
      ],
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

DateTime ledgerDisplayDateForHistory(LeaveBalanceLedgerEntry entry) {
  if (entry.action.toLowerCase() != 'monthly_accrual') {
    return entry.createdAt;
  }
  final metadata = entry.metadataJson;
  if (metadata == null || metadata.isEmpty) {
    return entry.createdAt;
  }
  return _parseLedgerDateOnly(metadata['last_accrual_date']) ??
      _parseLedgerYearMonth(
        metadata['target_year_month'] ?? metadata['targetYearMonth'],
      ) ??
      entry.createdAt;
}

DateTime? _parseLedgerDateOnly(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

DateTime? _parseLedgerYearMonth(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  if (year == null || month == null) return null;
  return DateTime(year, month, 1);
}

class _EmployeeLedgerRow extends StatelessWidget {
  const _EmployeeLedgerRow({required this.entry});

  final LeaveBalanceLedgerEntry entry;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _shortDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _leaveTypeLabel(String raw) {
    if (raw.isEmpty) return '';
    return leaveTypeFromString(raw).displayName;
  }

  String _signedDaysLabel(double d) {
    if (d == 0) return '0 days';
    final sign = d > 0 ? '+' : '-';
    final a = d.abs();
    final n = a == a.truncateToDouble()
        ? a.toInt().toString()
        : a.toStringAsFixed(2);
    return '$sign$n days';
  }

  DateTime _displayDate() => ledgerDisplayDateForHistory(entry);

  ({Color bg, Color fg, IconData icon}) _iconStyle(BuildContext context) {
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
        (d < 0 && b == 'used')) {
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
    if (d > 0) {
      return (
        bg: dark
            ? Colors.green.shade900.withValues(alpha: 0.4)
            : const Color(0xFFE8F5E9),
        fg: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
        icon: Icons.add_rounded,
      );
    }
    return (
      bg: dark ? AppTheme.dashMutedSurfaceOf(context) : const Color(0xFFECEFF1),
      fg: dark ? Colors.blueGrey.shade300 : const Color(0xFF607D8B),
      icon: Icons.swap_horiz_rounded,
    );
  }

  String _actionTitle(String raw) {
    final a = raw.toLowerCase();
    switch (a) {
      case 'monthly_accrual':   return 'Monthly Accrual';
      case 'leave_approved':    return 'Leave Approved';
      case 'admin_adjustment':  return 'Balance Adjustment';
      case 'leave_submitted':   return 'Leave Filed';
      case 'forced_leave_deduction': return 'Forced Leave Deduction';
      case 'leave_cancelled':   return 'Leave Cancelled';
      case 'leave_rejected':    return 'Leave Not Approved';
      case 'leave_returned':    return 'Leave Returned';
      case 'leave_revoked':     return 'Approval Revoked';
      default:
        if (raw.isEmpty) return 'Activity';
        return raw
            .split('_')
            .map((w) {
              if (w.isEmpty) return w;
              return '${w[0].toUpperCase()}${w.substring(1)}';
            })
            .join(' ');
    }
  }

  /// Human-readable one-liner description for each action type.
  String _subtitle() {
    final a = entry.action.toLowerCase();
    final meta = entry.metadataJson ?? {};

    if (a == 'monthly_accrual') {
      final ym = meta['target_year_month']?.toString() ??
          meta['targetYearMonth']?.toString();
      final months = meta['months_credited'];
      if (ym != null && ym.length == 7) {
        final parts = ym.split('-');
        final mIdx = int.tryParse(parts[1]) ?? 0;
        const mNames = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        final mName = mIdx >= 1 && mIdx <= 12 ? mNames[mIdx] : parts[1];
        final suffix = months != null && months != 1
            ? ' · $months months credited'
            : '';
        return 'Accrual for $mName ${parts[0]}$suffix';
      }
      return 'Monthly leave accrual';
    }

    if (a == 'leave_approved') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      if (bucket == 'used') {
        final r = entry.remarks?.trim();
        return r != null && r.isNotEmpty ? r : 'Days deducted from balance';
      }
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Leave request approved';
    }

    if (a == 'leave_submitted') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') {
        final r = entry.remarks?.trim();
        return r != null && r.isNotEmpty ? r : 'Days reserved as pending';
      }
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Leave request submitted';
    }

    if (a == 'admin_adjustment') {
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Balance manually adjusted by HR';
    }

    if (a == 'forced_leave_deduction') {
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Forced leave deducted by HR';
    }

    if (a == 'leave_cancelled') return 'Leave request cancelled';
    if (a == 'leave_rejected') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Leave request was not approved';
    }
    if (a == 'leave_returned') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Returned for correction';
    }
    if (a == 'leave_revoked') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      if (bucket == 'used') return 'Deducted days returned to balance';
      return 'Leave approval was revoked';
    }

    final r = entry.remarks?.trim();
    return r != null && r.isNotEmpty ? r : '';
  }

  /// True effective direction from the employee's perspective:
  /// - used_days increasing = days consumed (negative effective change)
  /// - pending_days changing = internal hold (neutral)
  double _effectiveDaysForColor() {
    final bucket = entry.affectedBucket.toLowerCase();
    final d = entry.daysChanged;
    if (bucket == 'used' && d > 0) return -d;
    if (bucket == 'pending') return 0;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final st = _iconStyle(context);
    final effective = _effectiveDaysForColor();
    final amountColor = effective > 0
        ? (dark ? Colors.green.shade300 : const Color(0xFF2E7D32))
        : effective < 0
            ? (dark ? Colors.red.shade300 : const Color(0xFFC62828))
            : (dark
                ? AppTheme.dashTextSecondaryOf(context)
                : AppTheme.dashTextSecondaryOf(context));
    final lt = _leaveTypeLabel(entry.leaveType);
    final subtitle = _subtitle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: AppTheme.dashSurfaceCard(context, radius: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: st.bg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(st.icon, color: st.fg, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _actionTitle(entry.action),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.dashTextPrimaryOf(context),
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _shortDate(_displayDate()),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.dashTextSecondaryOf(context)
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                if (lt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    lt,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context)
                          .withValues(alpha: 0.85),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _signedDaysLabel(_effectiveDaysForColor()),
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
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
  const _AdminSummaryChips({required this.stats, this.total});

  final _LedgerSummaryStats stats;
  final int? total;

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
            label: 'Earned',
            value: '${_fmt(stats.totalEarned)} days',
            icon: Icons.add_rounded,
            iconBoxColor: dark
                ? Colors.green.shade900.withValues(alpha: 0.4)
                : const Color(0xFFE8F5E9),
            iconColor: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
            valueColor: dark ? Colors.green.shade300 : const Color(0xFF2E7D32),
          ),
          _SummaryChip(
            label: 'Used',
            value: '${_fmt(stats.totalUsed)} days',
            icon: Icons.remove_rounded,
            iconBoxColor: dark
                ? Colors.red.shade900.withValues(alpha: 0.4)
                : const Color(0xFFFFEBEE),
            iconColor: dark ? Colors.red.shade300 : const Color(0xFFC62828),
            valueColor: AppTheme.dashTextPrimaryOf(context),
          ),
          _SummaryChip(
            label: 'Pending',
            value: '${_fmt(stats.totalPending)} days',
            icon: Icons.schedule_rounded,
            iconBoxColor: dark
                ? Colors.amber.shade900.withValues(alpha: 0.35)
                : const Color(0xFFFFF8E1),
            iconColor: dark ? Colors.amber.shade300 : const Color(0xFFF9A825),
            valueColor: dark ? Colors.amber.shade200 : const Color(0xFFF57F17),
          ),
          if (total != null)
            _SummaryChip(
              label: 'Records',
              value: total.toString(),
              icon: Icons.list_alt_rounded,
              iconBoxColor: dark
                  ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                  : const Color(0xFFE8EAF6),
              iconColor: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
              valueColor: AppTheme.dashTextPrimaryOf(context),
            ),
        ];
        if (narrow) {
          return Wrap(spacing: 8, runSpacing: 8, children: children);
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
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
  const _EmployeeOption({required this.id, required this.name, this.departmentId});

  final String id;
  final String name;
  final String? departmentId;
}

class _DepartmentOption {
  const _DepartmentOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _AdminFilterCard extends StatelessWidget {
  const _AdminFilterCard({
    required this.employeesLoading,
    required this.employeesError,
    required this.employees,
    required this.departments,
    required this.departmentsLoading,
    required this.draftEmployeeId,
    required this.draftLeaveType,
    required this.draftDepartmentId,
    required this.onEmployeeChanged,
    required this.onLeaveTypeChanged,
    required this.onDepartmentChanged,
  });

  final bool employeesLoading;
  final String? employeesError;
  final List<_EmployeeOption> employees;
  final List<_DepartmentOption> departments;
  final bool departmentsLoading;
  final String? draftEmployeeId;
  final String? draftLeaveType;
  final String? draftDepartmentId;
  final ValueChanged<String?> onEmployeeChanged;
  final ValueChanged<String?> onLeaveTypeChanged;
  final ValueChanged<String?> onDepartmentChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final deptField = _departmentDropdown(context);
          final employeeField = _employeeDropdown(context);
          final leaveField = _leaveTypeDropdown(context);

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: deptField),
                const SizedBox(width: 10),
                Expanded(child: employeeField),
                const SizedBox(width: 10),
                Expanded(child: leaveField),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              deptField,
              const SizedBox(height: 10),
              employeeField,
              const SizedBox(height: 10),
              leaveField,
            ],
          );
        },
      ),
    );
  }

  Widget _departmentDropdown(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: draftDepartmentId,
      dropdownColor: AppTheme.dashPanelOf(context),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: adminLeaveInputDecoration(
        context,
        'Department',
      ).copyWith(isDense: true),
      hint: Text(
        departmentsLoading ? 'Loading…' : 'All departments',
        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'All departments',
            style: AppTheme.dashFieldTextStyle(context),
          ),
        ),
        ...departments.map(
          (d) => DropdownMenuItem<String?>(
            value: d.id,
            child: Text(
              d.name,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dashFieldTextStyle(context),
            ),
          ),
        ),
      ],
      onChanged: onDepartmentChanged,
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
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading…',
              style: AppTheme.dashFieldTextStyle(context),
            ),
          ],
        ),
      );
    }
    if (employeesError != null) {
      return DropdownButtonFormField<String?>(
        initialValue: null,
        decoration: adminLeaveInputDecoration(
          context,
          'Employee',
        ).copyWith(isDense: true),
        hint: Text(
          'Error loading employees',
          style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
        ),
        items: const [],
        onChanged: null,
      );
    }

    // Key on draftDepartmentId so the widget fully recreates when dept changes,
    // which resets FormFieldState and picks up the new employee list.
    return DropdownButtonFormField<String?>(
      key: ValueKey('emp_${draftDepartmentId ?? 'all'}'),
      initialValue: _safeEmployeeValue(draftEmployeeId, employees),
      dropdownColor: AppTheme.dashPanelOf(context),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: adminLeaveInputDecoration(
        context,
        'Employee',
      ).copyWith(isDense: true),
      hint: Text(
        employees.isEmpty && !employeesLoading
            ? 'No employees found'
            : 'All employees',
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
      initialValue: draftLeaveType,
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

// ─── Pagination bar ──────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.total,
    required this.pageSize,
    required this.loading,
    required this.onPage,
  });

  final int currentPage;
  final int totalPages;
  final int total;
  final int pageSize;
  final bool loading;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final start = currentPage * pageSize + 1;
    final end = ((currentPage + 1) * pageSize).clamp(0, total);
    final labelColor = AppTheme.dashTextSecondaryOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.first_page_rounded, size: 20),
          tooltip: 'First page',
          onPressed: (loading || currentPage == 0) ? null : () => onPage(0),
          color: AppTheme.primaryNavy,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          tooltip: 'Previous',
          onPressed:
              (loading || currentPage == 0) ? null : () => onPage(currentPage - 1),
          color: AppTheme.primaryNavy,
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: dark
                ? AppTheme.primaryNavy.withValues(alpha: 0.25)
                : AppTheme.primaryNavy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$start–$end of $total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          tooltip: 'Next',
          onPressed: (loading || currentPage >= totalPages - 1)
              ? null
              : () => onPage(currentPage + 1),
          color: AppTheme.primaryNavy,
        ),
        IconButton(
          icon: const Icon(Icons.last_page_rounded, size: 20),
          tooltip: 'Last page',
          onPressed: (loading || currentPage >= totalPages - 1)
              ? null
              : () => onPage(totalPages - 1),
          color: AppTheme.primaryNavy,
        ),
        if (loading) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: labelColor,
            ),
          ),
        ],
      ],
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
    const mNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${mNames[d.month]} ${d.day}, ${d.year}';
  }

  DateTime _displayDate() => ledgerDisplayDateForHistory(entry);

  String _fmtSigned(double d) {
    if (d == 0) return '0 days';
    final sign = d > 0 ? '+' : '-';
    final a = d.abs();
    final t = a == a.truncateToDouble()
        ? a.toInt().toString()
        : a.toStringAsFixed(2);
    return '$sign$t days';
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
      case 'monthly_accrual':        return 'Monthly Accrual';
      case 'leave_approved':         return 'Leave Approved';
      case 'admin_adjustment':       return 'Balance Adjustment';
      case 'leave_submitted':        return 'Leave Filed';
      case 'forced_leave_deduction': return 'Forced Leave Deduction';
      case 'leave_cancelled':        return 'Leave Cancelled';
      case 'leave_rejected':         return 'Leave Not Approved';
      case 'leave_returned':         return 'Leave Returned';
      case 'leave_revoked':          return 'Approval Revoked';
      default:
        if (raw.isEmpty) return 'Ledger Entry';
        return raw
            .split('_')
            .map((w) {
              if (w.isEmpty) return w;
              return '${w[0].toUpperCase()}${w.substring(1)}';
            })
            .join(' ');
    }
  }

  /// Human-friendly one-line description for each action type.
  String _subtitle() {
    final a = entry.action.toLowerCase();
    final meta = entry.metadataJson ?? {};

    if (a == 'monthly_accrual') {
      final ym = meta['target_year_month']?.toString() ??
          meta['targetYearMonth']?.toString();
      final months = meta['months_credited'];
      if (ym != null && ym.length == 7) {
        final parts = ym.split('-');
        final year = parts[0];
        const mNames = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        final mIdx = int.tryParse(parts[1]) ?? 0;
        final mName = mIdx >= 1 && mIdx <= 12 ? mNames[mIdx] : parts[1];
        final suffix = months != null && months != 1
            ? ' · $months months back-credited'
            : '';
        return 'Accrual for $mName $year$suffix';
      }
      return 'Monthly leave accrual';
    }

    if (a == 'leave_approved') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      if (bucket == 'used') {
        final r = entry.remarks?.trim();
        return r != null && r.isNotEmpty ? r : 'Days deducted from balance';
      }
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Leave request approved';
    }
    if (a == 'leave_submitted') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') {
        final r = entry.remarks?.trim();
        return r != null && r.isNotEmpty ? r : 'Days reserved as pending';
      }
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Leave request submitted';
    }
    if (a == 'admin_adjustment') {
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Balance manually adjusted by HR';
    }
    if (a == 'forced_leave_deduction') {
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Forced leave deducted by HR';
    }
    if (a == 'leave_cancelled') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      return 'Leave request cancelled';
    }
    if (a == 'leave_rejected') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Leave request was not approved';
    }
    if (a == 'leave_returned') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      final r = entry.remarks?.trim();
      return r != null && r.isNotEmpty ? r : 'Returned for correction';
    }
    if (a == 'leave_revoked') {
      final bucket = entry.affectedBucket.toLowerCase();
      if (bucket == 'pending') return 'Pending hold released';
      if (bucket == 'used') return 'Deducted days returned to balance';
      return 'Leave approval was revoked';
    }

    final r = entry.remarks?.trim();
    if (r != null && r.isNotEmpty) return r;
    return _leaveTypeLabel(entry.leaveType);
  }

  /// Effective direction from the employee's perspective for color coding.
  double _effectiveDaysForColor() {
    final bucket = entry.affectedBucket.toLowerCase();
    final d = entry.daysChanged;
    if (bucket == 'used' && d > 0) return -d;
    if (bucket == 'pending') return 0;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final st = _styleForEntry(context);
    final effective = _effectiveDaysForColor();
    final amountColor = effective > 0
        ? (dark ? Colors.green.shade300 : const Color(0xFF2E7D32))
        : effective < 0
            ? (dark ? Colors.red.shade300 : const Color(0xFFC62828))
            : AppTheme.dashTextSecondaryOf(context);

    final subtitle = _subtitle();
    final employeeName = entry.employeeName?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: AppTheme.dashSurfaceCard(context, radius: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: st.bg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(st.icon, color: st.fg, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _actionTitle(entry.action),
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _fmtDt(_displayDate()),
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context)
                            .withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _leaveTypeLabel(entry.leaveType),
                    if (employeeName.isNotEmpty) employeeName,
                  ].join(' · '),
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context)
                          .withValues(alpha: 0.85),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmtSigned(_effectiveDaysForColor()),
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
