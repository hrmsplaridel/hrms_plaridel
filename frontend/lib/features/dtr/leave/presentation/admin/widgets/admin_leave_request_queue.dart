import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/request_filters_bar.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/admin_row.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_shared_widgets.dart';

class AdminLeaveFilterBar extends StatelessWidget {
  const AdminLeaveFilterBar({
    super.key,
    required this.isDepartmentHead,
    required this.status,
    required this.leaveType,
    required this.leaveTypeOptions,
    required this.department,
    required this.departments,
    required this.employee,
    required this.employees,
    required this.onStatusChanged,
    required this.onLeaveTypeChanged,
    required this.onDepartmentChanged,
    required this.onEmployeeChanged,
    required this.onReset,
    this.startDateFrom,
    this.startDateTo,
    this.onStartDateFromChanged,
    this.onStartDateToChanged,
  });

  final bool isDepartmentHead;
  final LeaveRequestStatus? status;
  final String? leaveType;
  final List<AdminLeaveLeaveTypeFilterOption> leaveTypeOptions;
  final String? department;
  final List<String> departments;
  final String? employee;
  final List<AdminLeaveEmployeeFilterOption> employees;
  final ValueChanged<LeaveRequestStatus?> onStatusChanged;
  final ValueChanged<String?> onLeaveTypeChanged;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onEmployeeChanged;
  final VoidCallback onReset;
  // #11: Date range filters.
  final DateTime? startDateFrom;
  final DateTime? startDateTo;
  final ValueChanged<DateTime?>? onStartDateFromChanged;
  final ValueChanged<DateTime?>? onStartDateToChanged;

  static const double _mobileBreakpoint = 600;

  List<LeaveRequestStatus?> get _statusOptions => isDepartmentHead
      ? const <LeaveRequestStatus?>[
          null,
          LeaveRequestStatus.pendingDepartmentHead,
          LeaveRequestStatus.pendingHr,
          LeaveRequestStatus.approved,
          LeaveRequestStatus.returned,
          LeaveRequestStatus.rejectedByDepartmentHead,
          LeaveRequestStatus.rejectedByHr,
          LeaveRequestStatus.cancelled,
        ]
      : const <LeaveRequestStatus?>[
          null,
          LeaveRequestStatus.pendingHr,
          LeaveRequestStatus.returned,
          LeaveRequestStatus.approved,
          LeaveRequestStatus.rejectedByHr,
          LeaveRequestStatus.cancelled,
        ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < _mobileBreakpoint;
    final statusOptions = _statusOptions;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: isMobile
          ? _buildMobileFilters(context, statusOptions)
          : _buildDesktopFilters(context, statusOptions),
    );
  }

  Widget _buildMobileFilters(
    BuildContext context,
    List<LeaveRequestStatus?> statusOptions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HorizontalFilterChips<LeaveRequestStatus?>(
          options: [
            for (final value in statusOptions)
              RequestFilterOption(
                value: value,
                label: _filterStatusLabel(value),
              ),
          ],
          selectedValue: status,
          onSelected: onStatusChanged,
        ),
        const SizedBox(height: 10),
        if (isDepartmentHead)
          Row(
            children: [
              Expanded(child: _leaveTypeDropdown(context, compact: true)),
              const SizedBox(width: 8),
              Expanded(child: _employeeDropdown(context, compact: true)),
            ],
          )
        else ...[
          _leaveTypeDropdown(context, compact: true),
          const SizedBox(height: 8),
          _departmentDropdown(context, compact: true),
          const SizedBox(height: 8),
          _employeeDropdown(context, compact: true),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CompactFilterDateButton(
                label: startDateFrom == null
                    ? 'From'
                    : RequestFiltersBar.defaultFormatDate(startDateFrom!),
                onPressed: () => _pickDate(context, isFrom: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CompactFilterDateButton(
                label: startDateTo == null
                    ? 'To'
                    : RequestFiltersBar.defaultFormatDate(startDateTo!),
                onPressed: () => _pickDate(context, isFrom: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
            label: const Text('Reset Filters'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.dashIsDark(context)
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopFilters(
    BuildContext context,
    List<LeaveRequestStatus?> statusOptions,
  ) {
    return LayoutBuilder(
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
                  decoration: adminLeaveInputDecoration(context, 'Status'),
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  items: [
                    ...statusOptions.map(
                      (value) => DropdownMenuItem<LeaveRequestStatus?>(
                        value: value,
                        child: Text(_filterStatusLabel(value)),
                      ),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              SizedBox(
                width: 180,
                child: _leaveTypeDropdown(context, compact: false),
              ),
              if (!isDepartmentHead)
                SizedBox(
                  width: 180,
                  child: _departmentDropdown(context, compact: false),
                ),
              SizedBox(
                width: 220,
                child: _employeeDropdown(context, compact: false),
              ),
              _AdminLeaveDateFilterChip(
                label: 'From',
                date: startDateFrom,
                onChanged: onStartDateFromChanged,
              ),
              _AdminLeaveDateFilterChip(
                label: 'To',
                date: startDateTo,
                onChanged: onStartDateToChanged,
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
    );
  }

  Widget _leaveTypeDropdown(BuildContext context, {required bool compact}) {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      isDense: compact,
      initialValue: _safeLeaveTypeValue(leaveType, leaveTypeOptions),
      dropdownColor: AppTheme.dashPanelOf(context),
      decoration: _queueFilterDecoration(
        context,
        'Leave Type',
        compact: compact,
      ),
      style: AppTheme.dashFieldTextStyle(
        context,
      ).copyWith(fontSize: compact ? 13 : 14),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All leave types'),
        ),
        ...leaveTypeOptions.map(
          (option) => DropdownMenuItem<String?>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onLeaveTypeChanged,
    );
  }

  Widget _departmentDropdown(BuildContext context, {required bool compact}) {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      isDense: compact,
      initialValue: department,
      dropdownColor: AppTheme.dashPanelOf(context),
      decoration: _queueFilterDecoration(
        context,
        'Department',
        compact: compact,
      ),
      style: AppTheme.dashFieldTextStyle(
        context,
      ).copyWith(fontSize: compact ? 13 : 14),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All departments'),
        ),
        ...departments.map(
          (value) => DropdownMenuItem<String?>(
            value: value,
            child: Text(value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onDepartmentChanged,
    );
  }

  Widget _employeeDropdown(BuildContext context, {required bool compact}) {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      isDense: compact,
      initialValue: employee,
      dropdownColor: AppTheme.dashPanelOf(context),
      decoration: _queueFilterDecoration(context, 'Employee', compact: compact),
      style: AppTheme.dashFieldTextStyle(
        context,
      ).copyWith(fontSize: compact ? 13 : 14),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All employees'),
        ),
        ...employees.map(
          (e) => DropdownMenuItem<String?>(
            value: e.id,
            child: Text(e.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (!isDepartmentHead && department == null)
          ? null
          : onEmployeeChanged,
      hint: (!isDepartmentHead && department == null)
          ? const Text('Select department first')
          : null,
    );
  }

  InputDecoration _queueFilterDecoration(
    BuildContext context,
    String label, {
    required bool compact,
  }) {
    return adminLeaveInputDecoration(context, label).copyWith(
      isDense: compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 12,
      ),
      labelStyle: TextStyle(
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final current = isFrom ? startDateFrom : startDateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: isFrom ? 'Select start date' : 'Select end date',
    );
    if (picked == null) return;
    if (isFrom) {
      onStartDateFromChanged?.call(picked);
    } else {
      onStartDateToChanged?.call(picked);
    }
  }

  String? _safeLeaveTypeValue(
    String? value,
    List<AdminLeaveLeaveTypeFilterOption> options,
  ) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    return options.any((option) => option.value == raw) ? raw : null;
  }

  String _filterStatusLabel(LeaveRequestStatus? value) {
    if (value == null) return 'All statuses';
    if (!isDepartmentHead) return value.displayName;
    return switch (value) {
      LeaveRequestStatus.pendingDepartmentHead => 'Pending',
      LeaveRequestStatus.pendingHr => 'Forwarded to HR',
      LeaveRequestStatus.approved => 'Approved by HR',
      LeaveRequestStatus.rejectedByDepartmentHead => 'Rejected',
      LeaveRequestStatus.rejectedByHr => 'Rejected by HR',
      LeaveRequestStatus.returned => 'Returned',
      LeaveRequestStatus.cancelled => 'Cancelled',
      _ => value.displayName,
    };
  }
}

class AdminLeaveEmployeeFilterOption {
  const AdminLeaveEmployeeFilterOption({required this.id, required this.name});

  final String id;
  final String name;
}

class AdminLeaveLeaveTypeFilterOption {
  const AdminLeaveLeaveTypeFilterOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

/// Small chip-style date picker for filter bar.
class _AdminLeaveDateFilterChip extends StatelessWidget {
  const _AdminLeaveDateFilterChip({
    required this.label,
    required this.date,
    required this.onChanged,
  });

  final String label;
  final DateTime? date;
  final ValueChanged<DateTime?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final text = hasDate
        ? '$label: ${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
        : label;
    return InputChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      avatar: Icon(
        hasDate ? Icons.event_available_rounded : Icons.calendar_today_rounded,
        size: 16,
      ),
      deleteIcon: hasDate ? const Icon(Icons.close_rounded, size: 14) : null,
      onDeleted: hasDate ? () => onChanged?.call(null) : null,
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          helpText: 'Select $label date',
        );
        if (picked != null) onChanged?.call(picked);
      },
    );
  }
}

class AdminLeaveRequestQueuePanel extends StatefulWidget {
  const AdminLeaveRequestQueuePanel({
    super.key,
    required this.requests,
    required this.isDepartmentHead,
    required this.loading,
    required this.selectedRequest,
    required this.filterBar,
    required this.onSelect,
  });

  final List<LeaveRequest> requests;
  final bool isDepartmentHead;
  final bool loading;
  final LeaveRequest? selectedRequest;
  final Widget filterBar;
  final ValueChanged<LeaveRequest> onSelect;

  @override
  State<AdminLeaveRequestQueuePanel> createState() =>
      _AdminLeaveRequestQueuePanelState();
}

class _AdminLeaveRequestQueuePanelState
    extends State<AdminLeaveRequestQueuePanel> {
  static const int _rowsPerPage = 10;

  final ScrollController _queueScrollController = ScrollController();
  int _page = 0;

  @override
  void didUpdateWidget(covariant AdminLeaveRequestQueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requests != widget.requests) {
      _page = 0;
    } else {
      _clampPage();
    }
  }

  @override
  void dispose() {
    _queueScrollController.dispose();
    super.dispose();
  }

  int get _pageCount {
    if (widget.requests.isEmpty) return 1;
    return (widget.requests.length / _rowsPerPage).ceil();
  }

  void _clampPage() {
    final maxPage = _pageCount - 1;
    if (_page > maxPage) _page = maxPage;
    if (_page < 0) _page = 0;
  }

  void _goToPage(int page) {
    final maxPage = _pageCount - 1;
    setState(() => _page = page.clamp(0, maxPage).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxQueueHeight = screenWidth < 600
        ? (screenHeight * 0.42).clamp(260.0, 420.0)
        : screenWidth < 1024
        ? (screenHeight * 0.52).clamp(320.0, 580.0)
        : (screenHeight * 0.6).clamp(380.0, 760.0);

    _clampPage();
    final pageStart = _page * _rowsPerPage;
    final pageEnd = (pageStart + _rowsPerPage).clamp(0, widget.requests.length);
    final pageRequests = widget.requests.sublist(pageStart, pageEnd);

    return AdminLeaveSectionCard(
      title: widget.isDepartmentHead ? 'Requests & History' : 'Request Queue',
      subtitle: widget.isDepartmentHead
          ? 'Review pending requests and revisit items you forwarded, returned, or rejected.'
          : 'Tap a row to open details (side panel on wide screens, full screen on small).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.filterBar,
          const SizedBox(height: 14),
          if (widget.loading && widget.requests.isEmpty)
            const AdminLeaveCenteredState(message: 'Loading leave requests...')
          else if (widget.requests.isEmpty)
            const AdminLeaveCenteredState(
              message: 'No leave requests matched the filters.',
            )
          else ...[
            Container(
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: maxQueueHeight),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.dashHairlineOf(context)),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final tableWidth = !maxW.isFinite || maxW <= 0
                      ? kAdminTableMinWidth
                      : (maxW < kAdminTableMinWidth
                            ? kAdminTableMinWidth
                            : maxW);
                  return Scrollbar(
                    controller: _queueScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _queueScrollController,
                      primary: false,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const AdminTableHeader(),
                              ...pageRequests.map(
                                (request) => AdminRow(
                                  request: request,
                                  statusLabel: adminLeaveStatusLabel(
                                    request.status,
                                    isDepartmentHead: widget.isDepartmentHead,
                                  ),
                                  highlighted:
                                      request.id == widget.selectedRequest?.id,
                                  onView: () => widget.onSelect(request),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _AdminLeavePaginationBar(
              page: _page,
              pageCount: _pageCount,
              pageStart: pageStart,
              pageEnd: pageEnd,
              total: widget.requests.length,
              onPrevious: _page > 0 ? () => _goToPage(_page - 1) : null,
              onNext: _page < _pageCount - 1
                  ? () => _goToPage(_page + 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminLeavePaginationBar extends StatelessWidget {
  const _AdminLeavePaginationBar({
    required this.page,
    required this.pageCount,
    required this.pageStart,
    required this.pageEnd,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final int pageStart;
  final int pageEnd;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final showingText = total == 0
        ? 'Showing 0 requests'
        : 'Showing ${pageStart + 1}-$pageEnd of $total requests';
    final pageText = 'Page ${page + 1} of $pageCount';
    final textStyle = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final info = Column(
          crossAxisAlignment: isNarrow
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(showingText, style: textStyle),
            const SizedBox(height: 2),
            Text(pageText, style: textStyle),
          ],
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              label: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('Next'),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [info, const SizedBox(height: 10), controls],
          );
        }

        return Row(
          children: [
            Expanded(child: info),
            controls,
          ],
        );
      },
    );
  }
}
