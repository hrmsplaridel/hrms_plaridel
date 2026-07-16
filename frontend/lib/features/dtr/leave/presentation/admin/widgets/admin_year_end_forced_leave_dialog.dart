import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';

class AdminYearEndForcedLeaveDialog extends StatefulWidget {
  const AdminYearEndForcedLeaveDialog({super.key});

  @override
  State<AdminYearEndForcedLeaveDialog> createState() =>
      _AdminYearEndForcedLeaveDialogState();
}

class _AdminYearEndForcedLeaveDialogState
    extends State<AdminYearEndForcedLeaveDialog> {
  late final TextEditingController _yearController;
  final _remarksController = TextEditingController();

  YearEndForcedLeaveComplianceResult? _compliance;
  YearEndForcedLeaveApplyResult? _applyResult;

  bool _loadingCompliance = false;
  bool _previewing = false;
  bool _applying = false;
  String? _error;

  // Filters
  String _statusFilter = 'all';
  String? _departmentFilter;
  final _employeeSearchController = TextEditingController();
  String _employeeSearch = '';

  // Pagination
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _yearController = TextEditingController(text: now.year.toString());
    _yearController.addListener(_onYearChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCompliance();
    });
  }

  @override
  void dispose() {
    _yearController.removeListener(_onYearChanged);
    _yearController.dispose();
    _remarksController.dispose();
    _employeeSearchController.dispose();
    super.dispose();
  }

  void _onYearChanged() {
    if (_compliance != null || _applyResult != null || _error != null) {
      setState(() {
        _compliance = null;
        _applyResult = null;
        _error = null;
      });
    }
  }

  int? _parsedYear() => int.tryParse(_yearController.text.trim());

  /// Opens the custom single-employee deduction mini-dialog for [emp].
  /// On success, reloads compliance data.
  Future<void> _customDeductEmployee(YearEndForcedLeaveEmployee emp) async {
    final applied = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomDeductDialog(employee: emp),
    );
    if (applied == true && mounted) {
      _loadCompliance();
    }
  }

  Future<void> _loadCompliance() async {
    final year = _parsedYear();
    if (year == null) {
      setState(
        () => _error = 'Enter a valid year (e.g. ${DateTime.now().year})',
      );
      return;
    }
    setState(() {
      _loadingCompliance = true;
      _error = null;
      _compliance = null;
      _applyResult = null;
      _currentPage = 0;
    });
    final result = await context
        .read<LeaveProvider>()
        .getYearEndForcedLeaveCompliance(year);
    if (!mounted) return;
    setState(() {
      _loadingCompliance = false;
      if (result == null) {
        _error =
            context.read<LeaveProvider>().error ??
            'Failed to load compliance data.';
      } else {
        _compliance = result;
      }
    });
  }

  Future<void> _preview() async {
    final year = _parsedYear();
    if (year == null) return;
    setState(() {
      _previewing = true;
      _error = null;
      _applyResult = null;
    });
    final result = await context
        .read<LeaveProvider>()
        .applyYearEndForcedLeaveDeductions(
          YearEndForcedLeaveApplyInput(
            year: year,
            dryRun: true,
            remarks: _remarksController.text.trim().isEmpty
                ? null
                : _remarksController.text.trim(),
          ),
        );
    if (!mounted) return;
    setState(() {
      _previewing = false;
      if (result == null) {
        _error = context.read<LeaveProvider>().error ?? 'Preview failed.';
      } else {
        _applyResult = result;
      }
    });
  }

  Future<void> _applyAll() async {
    final year = _parsedYear();
    if (year == null) return;
    final confirmed = await _confirmDialog(year);
    if (confirmed != true || !mounted) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    final result = await context
        .read<LeaveProvider>()
        .applyYearEndForcedLeaveDeductions(
          YearEndForcedLeaveApplyInput(
            year: year,
            dryRun: false,
            remarks: _remarksController.text.trim().isEmpty
                ? null
                : _remarksController.text.trim(),
          ),
        );
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (result == null) {
        _error = context.read<LeaveProvider>().error ?? 'Apply failed.';
      } else {
        _applyResult = result;
        // Reload compliance to reflect new state
        _loadCompliance();
      }
    });
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<bool?> _confirmDialog(int year) {
    final pendingCount =
        _compliance?.summary.pendingDeduction ??
        (_applyResult?.summary.wouldApply ?? 0);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Year-End Deduction'),
        content: Text(
          'This will apply forced leave deductions for $pendingCount employee(s) for the year $year. '
          'Deductions will be charged against their Vacation Leave balance. '
          'This action cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Apply Deductions'),
          ),
        ],
      ),
    );
  }

  List<String> get _availableDepartments {
    final source = _compliance?.employees ?? const [];
    return source
        .map((e) => e.departmentName)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  bool _matchesStatusFilter(YearEndForcedLeaveEmployee e) {
    if (_statusFilter == 'all') return true;
    final s = e.applyStatus ?? e.status;
    return switch (_statusFilter) {
      'pending' => s == 'pending' || s == 'would_apply' || s == 'applied',
      'monitoring' => s == 'monitoring',
      'compliant' => s == 'compliant',
      'deducted' => s == 'deducted' || s == 'already_deducted',
      _ => true,
    };
  }

  List<YearEndForcedLeaveEmployee> get _filteredRows {
    final source = _compliance?.employees ?? const [];
    final q = _employeeSearch.toLowerCase();
    return source.where((e) {
      if (!_matchesStatusFilter(e)) return false;
      if (_departmentFilter != null && e.departmentName != _departmentFilter) {
        return false;
      }
      if (q.isNotEmpty &&
          !e.fullName.toLowerCase().contains(q) &&
          !(e.employeeNumber?.toLowerCase().contains(q) ?? false)) {
        return false;
      }
      return true;
    }).toList();
  }

  int get _pageCount =>
      (_filteredRows.length / _pageSize).ceil().clamp(1, 99999);

  List<YearEndForcedLeaveEmployee> get _displayRows {
    final filtered = _filteredRows;
    final start = _currentPage * _pageSize;
    if (start >= filtered.length) return [];
    final end = (start + _pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  void _setFilter({
    String? status,
    String? Function()? department,
    String? employeeSearch,
  }) {
    setState(() {
      if (status != null) _statusFilter = status;
      if (department != null) _departmentFilter = department();
      if (employeeSearch != null) _employeeSearch = employeeSearch;
      _currentPage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingCompliance || _previewing || _applying;
    final summary = _compliance?.summary;
    final actionable =
        (summary?.pendingDeduction ?? 0) + (summary?.partial ?? 0);
    final selectedYear = _parsedYear();
    final yearClosed =
        selectedYear != null && selectedYear < DateTime.now().year;
    final canPreview = !busy && _compliance != null && actionable > 0;
    final canApply = canPreview && yearClosed;

    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header (fixed) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.assignment_turned_in_rounded,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Year-End Forced Leave Deduction',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Review qualifying vacation leave, eligibility, and the actual capped '
                          'deduction. Current-year records are preview-only.',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),

            // ── Year + remarks (fixed) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fields = [
                    TextFormField(
                      controller: _yearController,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: adminLeaveInputDecoration(context, 'Year')
                          .copyWith(
                            prefixIcon: const Icon(
                              Icons.calendar_today_outlined,
                            ),
                            hintText: DateTime.now().year.toString(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh_rounded),
                              tooltip: 'Reload',
                              onPressed: busy ? null : _loadCompliance,
                            ),
                          ),
                    ),
                    TextFormField(
                      controller: _remarksController,
                      enabled: !busy,
                      decoration:
                          adminLeaveInputDecoration(
                            context,
                            'Remarks (optional)',
                          ).copyWith(
                            prefixIcon: const Icon(Icons.comment_outlined),
                            hintText:
                                'e.g. Year-end CSC forced leave compliance',
                          ),
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
                      SizedBox(width: 160, child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  );
                },
              ),
            ),

            // ── Body (fills remaining height) ──
            Expanded(child: _buildBody(context, busy)),

            // ── Footer (fixed) ──
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: canPreview ? _preview : null,
                    icon: _previewing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded, size: 18),
                    label: Text(
                      _previewing ? 'Previewing...' : 'Preview Deductions',
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canApply ? _applyAll : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: canApply ? Colors.orange.shade700 : null,
                    ),
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                    label: Text(
                      _applying
                          ? 'Applying...'
                          : yearClosed
                          ? 'Apply Eligible Deductions'
                          : 'Available after year close',
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

  Widget _buildBody(BuildContext context, bool busy) {
    if (_error != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: _StatusPanel(
            icon: Icons.error_outline_rounded,
            message: _error!,
            warning: true,
          ),
        ),
      );
    }
    if (_loadingCompliance) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      );
    }
    if (_compliance == null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: _StatusPanel(
            icon: Icons.search_rounded,
            message: 'Compliance data will appear here. Use ↺ to reload.',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        // Summary + filters (fixed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryRow(
                summary: _compliance!.summary,
                year: _compliance!.year,
                isApplyResult: false,
              ),
              const SizedBox(height: 12),
              _StatusFilterBar(
                selected: _statusFilter,
                pendingCount: _compliance!.summary.pendingDeduction,
                monitoringCount: _compliance!.summary.monitoring,
                compliantCount: _compliance!.summary.compliant,
                deductedCount: _compliance!.summary.alreadyDeducted,
                onChanged: (v) => _setFilter(status: v),
              ),
              const SizedBox(height: 10),
              _FilterBar(
                departments: _availableDepartments,
                selectedDepartment: _departmentFilter,
                employeeSearchController: _employeeSearchController,
                onDepartmentChanged: (v) => _setFilter(department: () => v),
                onEmployeeSearchChanged: (v) => _setFilter(employeeSearch: v),
                enabled: !busy,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),

        // Table (scrollable, fills remaining height)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _displayRows.isEmpty
                ? Align(
                    alignment: Alignment.topCenter,
                    child: _StatusPanel(
                      icon: Icons.check_circle_outline_rounded,
                      message: _filteredRows.isEmpty
                          ? (_statusFilter == 'all' &&
                                    _departmentFilter == null &&
                                    _employeeSearch.isEmpty
                                ? 'No active employees found.'
                                : 'No employees match the current filters.')
                          : 'No employees on this page.',
                    ),
                  )
                : _ComplianceTable(
                    rows: _displayRows,
                    onCustomDeduct:
                        busy ||
                            (_parsedYear() ?? DateTime.now().year) >=
                                DateTime.now().year
                        ? null
                        : _customDeductEmployee,
                  ),
          ),
        ),

        // Pagination (fixed)
        if (_filteredRows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: _PaginationBar(
              currentPage: _currentPage,
              pageCount: _pageCount,
              totalRows: _filteredRows.length,
              pageSize: _pageSize,
              onPageChanged: (p) => setState(() => _currentPage = p),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.summary,
    required this.year,
    required this.isApplyResult,
  });

  final YearEndForcedLeaveSummary summary;
  final int year;
  final bool isApplyResult;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(label: 'Year', value: year.toString()),
        _SummaryChip(label: 'Total employees', value: summary.total.toString()),
        if (summary.pendingDeduction > 0)
          _SummaryChip(
            label: 'Need deduction',
            value: summary.pendingDeduction.toString(),
            highlight: true,
            highlightColor: Colors.orange.shade700,
          ),
        if (summary.monitoring > 0)
          _SummaryChip(
            label: 'Monitoring',
            value: summary.monitoring.toString(),
            highlight: true,
            highlightColor: Colors.orange.shade700,
          ),
        _SummaryChip(
          label: 'Compliant',
          value: summary.compliant.toString(),
          highlight: summary.compliant > 0,
          highlightColor: Colors.green.shade700,
        ),
        _SummaryChip(
          label: 'Already deducted',
          value: summary.alreadyDeducted.toString(),
        ),
        if (summary.optionalReview > 0)
          _SummaryChip(
            label: 'Optional / review',
            value: summary.optionalReview.toString(),
            highlight: true,
            highlightColor: Colors.blueGrey.shade700,
          ),
        if (isApplyResult && summary.applied > 0)
          _SummaryChip(
            label: 'Applied',
            value: summary.applied.toString(),
            highlight: true,
            highlightColor: Colors.green.shade700,
          ),
        if (isApplyResult && summary.insufficientBalance > 0)
          _SummaryChip(
            label: 'Insufficient VL',
            value: summary.insufficientBalance.toString(),
            highlight: true,
            highlightColor: Colors.red.shade700,
          ),
        if (isApplyResult && summary.errors > 0)
          _SummaryChip(
            label: 'Errors',
            value: summary.errors.toString(),
            highlight: true,
            highlightColor: Colors.red.shade700,
          ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    this.highlight = false,
    this.highlightColor,
  });

  final String label;
  final String value;
  final bool highlight;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final color = highlight && highlightColor != null
        ? highlightColor!
        : AppTheme.primaryNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 13,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: highlight ? color : null,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: highlight ? color : null),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selected,
    required this.pendingCount,
    required this.monitoringCount,
    required this.compliantCount,
    required this.deductedCount,
    required this.onChanged,
  });

  final String selected;
  final int pendingCount;
  final int monitoringCount;
  final int compliantCount;
  final int deductedCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('all', 'All'),
      if (pendingCount > 0) ('pending', 'Need deduction ($pendingCount)'),
      if (monitoringCount > 0) ('monitoring', 'Monitoring ($monitoringCount)'),
      ('compliant', 'Compliant ($compliantCount)'),
      ('deducted', 'Already deducted ($deductedCount)'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final active = selected == tab.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(tab.$2, style: const TextStyle(fontSize: 12)),
              selected: active,
              onSelected: (_) => onChanged(tab.$1),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
              selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
              labelStyle: TextStyle(
                color: active
                    ? AppTheme.dashIsDark(context)
                          ? AppTheme.primaryNavyLight
                          : AppTheme.primaryNavy
                    : AppTheme.dashTextSecondaryOf(context),
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Department + Employee search filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.departments,
    required this.selectedDepartment,
    required this.employeeSearchController,
    required this.onDepartmentChanged,
    required this.onEmployeeSearchChanged,
    required this.enabled,
  });

  final List<String> departments;
  final String? selectedDepartment;
  final TextEditingController employeeSearchController;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String> onEmployeeSearchChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final deptField = DropdownButtonFormField<String>(
          initialValue: selectedDepartment,
          decoration: adminLeaveInputDecoration(context, 'Department').copyWith(
            prefixIcon: const Icon(Icons.business_outlined, size: 18),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('All departments')),
            ...departments.map(
              (d) => DropdownMenuItem(
                value: d,
                child: Text(d, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: enabled ? (v) => onDepartmentChanged(v) : null,
          isExpanded: true,
        );

        final empField = TextField(
          controller: employeeSearchController,
          enabled: enabled,
          onChanged: onEmployeeSearchChanged,
          decoration: adminLeaveInputDecoration(context, 'Search employee')
              .copyWith(
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixIcon: employeeSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: enabled
                            ? () {
                                employeeSearchController.clear();
                                onEmployeeSearchChanged('');
                              }
                            : null,
                      )
                    : null,
              ),
        );

        if (compact) {
          return Column(
            children: [deptField, const SizedBox(height: 8), empField],
          );
        }
        return Row(
          children: [
            Expanded(child: deptField),
            const SizedBox(width: 10),
            Expanded(child: empField),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pagination bar
// ─────────────────────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.pageCount,
    required this.totalRows,
    required this.pageSize,
    required this.onPageChanged,
  });

  final int currentPage;
  final int pageCount;
  final int totalRows;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final start = currentPage * pageSize + 1;
    final end = ((currentPage + 1) * pageSize).clamp(0, totalRows);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Showing $start–$end of $totalRows employee${totalRows == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: currentPage > 0
                  ? () => onPageChanged(currentPage - 1)
                  : null,
              tooltip: 'Previous page',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Page ${currentPage + 1} of $pageCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: currentPage < pageCount - 1
                  ? () => onPageChanged(currentPage + 1)
                  : null,
              tooltip: 'Next page',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ComplianceTable extends StatefulWidget {
  const _ComplianceTable({required this.rows, this.onCustomDeduct});

  final List<YearEndForcedLeaveEmployee> rows;
  final void Function(YearEndForcedLeaveEmployee)? onCustomDeduct;

  @override
  State<_ComplianceTable> createState() => _ComplianceTableState();
}

class _ComplianceTableState extends State<_ComplianceTable> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        children: [
          // Header (fixed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                _HeaderCell('Employee', flex: 3),
                _HeaderCell('Department', flex: 2),
                _HeaderCell('Qualifying VL', flex: 1, align: TextAlign.center),
                _HeaderCell('Eligibility', flex: 1, align: TextAlign.center),
                _HeaderCell('VL Balance', flex: 1, align: TextAlign.center),
                _HeaderCell('Deduct', flex: 1, align: TextAlign.center),
                _HeaderCell('Status', flex: 2, align: TextAlign.center),
                const SizedBox(width: 36),
              ],
            ),
          ),
          // Rows — fill remaining height; only this area scrolls.
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: ListView.separated(
                controller: _scrollController,
                itemCount: widget.rows.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                itemBuilder: (ctx, i) => _ComplianceRow(
                  employee: widget.rows[i],
                  onCustomDeduct: widget.onCustomDeduct != null
                      ? () => widget.onCustomDeduct!(widget.rows[i])
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(
    this.text, {
    required this.flex,
    this.align = TextAlign.start,
  });

  final String text;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.dashTextSecondaryOf(context),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ComplianceRow extends StatelessWidget {
  const _ComplianceRow({required this.employee, this.onCustomDeduct});

  final YearEndForcedLeaveEmployee employee;
  final VoidCallback? onCustomDeduct;

  String _fmtDays(double d) {
    final s = d.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  // Status shown in the row
  String get _effectiveStatus => employee.applyStatus ?? employee.status;

  (String label, Color color, Color bg) get _statusBadge {
    return switch (_effectiveStatus) {
      'compliant' => ('Compliant', Colors.green.shade700, Colors.green.shade50),
      'deducted' => ('Deducted', Colors.blue.shade700, Colors.blue.shade50),
      'already_deducted' => (
        'Already deducted',
        Colors.blue.shade700,
        Colors.blue.shade50,
      ),
      'applied' => ('Applied', Colors.green.shade700, Colors.green.shade50),
      'would_apply' => (
        'Will deduct',
        Colors.orange.shade800,
        Colors.orange.shade50,
      ),
      'would_partially_apply' => (
        'Partial',
        Colors.orange.shade800,
        Colors.orange.shade50,
      ),
      'partially_applied' => (
        'Partially applied',
        Colors.orange.shade800,
        Colors.orange.shade50,
      ),
      'partial' => ('Partial', Colors.orange.shade800, Colors.orange.shade50),
      'monitoring' => (
        'Monitoring',
        Colors.orange.shade800,
        Colors.orange.shade50,
      ),
      'optional_below_threshold' => (
        'Optional / review',
        Colors.blueGrey.shade700,
        Colors.blueGrey.shade50,
      ),
      'insufficient_balance' => (
        'Low VL balance',
        Colors.red.shade700,
        Colors.red.shade50,
      ),
      'error' => ('Error', Colors.red.shade700, Colors.red.shade50),
      _ => ('Pending', Colors.orange.shade800, Colors.orange.shade50),
    };
  }

  double get _deductionDays =>
      employee.daysToDeduct ?? employee.actualDeduction;

  @override
  Widget build(BuildContext context) {
    final (label, fgColor, bgColor) = _statusBadge;
    final dim =
        _effectiveStatus == 'compliant' ||
        _effectiveStatus == 'already_deducted';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Name + employee number
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.fullName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: dim
                        ? AppTheme.dashTextSecondaryOf(context)
                        : AppTheme.dashTextPrimaryOf(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (employee.employeeNumber != null)
                  Text(
                    employee.employeeNumber!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
              ],
            ),
          ),
          // Department
          Expanded(
            flex: 2,
            child: Text(
              employee.departmentName ?? '—',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Forced days used
          Expanded(
            flex: 1,
            child: Text(
              _fmtDays(employee.forcedDaysUsed),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: employee.forcedDaysUsed >= employee.requiredDays
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
              ),
            ),
          ),
          // Eligibility
          Expanded(
            flex: 1,
            child: Tooltip(
              message: employee.eligibilityReason,
              child: Text(
                employee.eligible ? 'Required' : 'Optional',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: employee.eligible
                      ? AppTheme.dashTextPrimaryOf(context)
                      : Colors.blueGrey.shade700,
                ),
              ),
            ),
          ),
          // VL available
          Expanded(
            flex: 1,
            child: Text(
              _fmtDays(employee.vlAvailable),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color:
                    employee.vlAvailable < _deductionDays && _deductionDays > 0
                    ? Colors.red.shade700
                    : AppTheme.dashTextPrimaryOf(context),
              ),
            ),
          ),
          // Suggested deduction
          Expanded(
            flex: 1,
            child: Text(
              _deductionDays > 0 ? '−${_fmtDays(_deductionDays)}' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _deductionDays > 0
                    ? Colors.red.shade700
                    : Colors.green.shade700,
              ),
            ),
          ),
          // Status badge
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // Custom deduct button — only shown for pending rows
          SizedBox(
            width: 36,
            child: employee.canApply && onCustomDeduct != null
                ? Tooltip(
                    message: 'Custom deduction',
                    child: IconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                      onPressed: onCustomDeduct,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom single-employee deduction mini-dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CustomDeductDialog extends StatefulWidget {
  const _CustomDeductDialog({required this.employee});
  final YearEndForcedLeaveEmployee employee;

  @override
  State<_CustomDeductDialog> createState() => _CustomDeductDialogState();
}

class _CustomDeductDialogState extends State<_CustomDeductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _daysController;
  final _remarksController = TextEditingController();
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final suggested = widget.employee.suggestedDeduction;
    final text = suggested > 0
        ? (suggested == suggested.roundToDouble()
              ? suggested.toInt().toString()
              : suggested.toStringAsFixed(2))
        : '';
    _daysController = TextEditingController(text: text);
  }

  @override
  void dispose() {
    _daysController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String? _validateDays(String? v) {
    final val = double.tryParse((v ?? '').trim());
    if (val == null || val <= 0) return 'Enter days > 0';
    if (val > 30) return 'Cannot exceed 30 days';
    return null;
  }

  Future<void> _apply() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final days = double.parse(_daysController.text.trim());
    final remarks = _remarksController.text.trim().isEmpty
        ? null
        : _remarksController.text.trim();
    setState(() {
      _applying = true;
      _error = null;
    });
    final result = await context
        .read<LeaveProvider>()
        .applyForcedLeaveDeduction(
          ForcedLeaveDeductionInput(
            userId: widget.employee.userId,
            daysToDeduct: days,
            remarks: remarks,
          ),
        );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _applying = false;
        _error = context.read<LeaveProvider>().error ?? 'Deduction failed.';
      });
    } else {
      Navigator.of(context).pop(true);
    }
  }

  String _fmtDays(double d) {
    final s = d.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          Icon(Icons.edit_outlined, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Custom Deduction — ${emp.fullName}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info row
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _InfoChip(
                        label: 'Forced days used',
                        value: _fmtDays(emp.forcedDaysUsed),
                      ),
                    ),
                    Expanded(
                      child: _InfoChip(
                        label: 'Required',
                        value: _fmtDays(emp.requiredDays),
                      ),
                    ),
                    Expanded(
                      child: _InfoChip(
                        label: 'VL balance',
                        value: _fmtDays(emp.vlAvailable),
                      ),
                    ),
                    Expanded(
                      child: _InfoChip(
                        label: 'Suggested',
                        value: '−${_fmtDays(emp.suggestedDeduction)}',
                        valueColor: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              TextFormField(
                controller: _daysController,
                enabled: !_applying,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: adminLeaveInputDecoration(context, 'Days to deduct')
                    .copyWith(
                      prefixIcon: const Icon(
                        Icons.remove_circle_outline_rounded,
                      ),
                      hintText: '0.00',
                    ),
                validator: _validateDays,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarksController,
                enabled: !_applying,
                decoration: adminLeaveInputDecoration(
                  context,
                  'Remarks (optional)',
                ).copyWith(prefixIcon: const Icon(Icons.comment_outlined)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _StatusPanel(
                  icon: Icons.error_outline_rounded,
                  message: _error!,
                  warning: true,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _applying ? null : _apply,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
          ),
          icon: _applying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_applying ? 'Applying...' : 'Apply Deduction'),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.dashTextSecondaryOf(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppTheme.dashTextPrimaryOf(context),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.message,
    this.warning = false,
  });

  final IconData icon;
  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? Colors.red.shade700
        : AppTheme.dashTextSecondaryOf(context);
    final bg = warning
        ? Colors.red.shade50
        : AppTheme.dashMutedSurfaceOf(context);
    final border = warning
        ? Colors.red.shade100
        : AppTheme.dashHairlineOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
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
}
