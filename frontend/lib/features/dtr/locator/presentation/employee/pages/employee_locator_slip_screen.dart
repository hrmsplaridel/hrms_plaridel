import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';
import 'package:hrms_plaridel/shared/widgets/request_filters_bar.dart';
import 'package:hrms_plaridel/shared/widgets/section_header_actions.dart';

const _locatorSlipFilterOptions = <RequestFilterOption<String>>[
  RequestFilterOption(label: 'All'),
  RequestFilterOption(value: 'pending', label: 'Pending'),
  RequestFilterOption(value: 'approved', label: 'Approved'),
  RequestFilterOption(value: 'rejected', label: 'Rejected'),
  RequestFilterOption(value: 'cancelled', label: 'Cancelled'),
];

const _locatorApprovalFilterOptions = <RequestFilterOption<String>>[
  RequestFilterOption(label: 'All'),
  RequestFilterOption(value: 'pending', label: 'Pending'),
  RequestFilterOption(value: 'forwarded', label: 'Forwarded to HR'),
  RequestFilterOption(value: 'approved', label: 'Approved by HR'),
  RequestFilterOption(value: 'rejected', label: 'Rejected'),
  RequestFilterOption(value: 'cancelled', label: 'Cancelled'),
];

class EmployeeLocatorSlipScreen extends StatefulWidget {
  const EmployeeLocatorSlipScreen({super.key});

  @override
  State<EmployeeLocatorSlipScreen> createState() =>
      EmployeeLocatorSlipScreenState();
}

class EmployeeLocatorSlipScreenState extends State<EmployeeLocatorSlipScreen> {
  final List<_LocatorSlipDraft> _slips = [];
  final List<_LocatorSlipDraft> _deptHeadQueue = [];
  Future<bool>? _isDeptHeadFuture;
  _LocatorSection _currentSection = _LocatorSection.requests;
  bool _appliedDeptHeadDefaultSection = false;
  bool _loadingMy = false;
  bool _loadingApprovals = false;
  String? _error;
  String? _selectedStatusFilter;
  String? _selectedApprovalStatusFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _searchQuery = '';
  String? _selectedSlipId;
  String? _selectedApprovalSlipId;
  StreamSubscription<AppRealtimeEvent>? _locatorRealtimeSub;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  Future<void> openCreateForm() async {
    final auth = context.read<AuthProvider>();
    final displayName = auth.displayName.trim().isEmpty
        ? 'Employee'
        : auth.displayName.trim();
    await _openCreateForm(context, displayName);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDeptHeadFuture ??= _checkIsDepartmentHead();
    if (!_loadingMy && _slips.isEmpty) {
      _loadMyRequests();
    }
    final realtimeProvider = context.read<AppRealtimeProvider>();
    final authProvider = context.read<AuthProvider>();
    _locatorRealtimeSub ??= realtimeProvider.events.listen((event) {
      if (event.name != 'locator_updated') return;
      final userId = authProvider.user?.id;
      if (event.affectsUser(userId)) {
        unawaited(_loadMyRequests());
      }
      if (_currentSection == _LocatorSection.approvals) {
        unawaited(_loadDepartmentHeadRequests());
      }
    });
  }

  @override
  void dispose() {
    _locatorRealtimeSub?.cancel();
    super.dispose();
  }

  List<_LocatorSlipDraft> get _filteredSlips {
    return _slips.where((item) {
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final searchable =
            '${item.employeeName} ${item.requestType.label} ${item.office} ${item.remarks} ${item.status.label}'
                .toLowerCase();
        if (!searchable.contains(q)) return false;
      }
      if (_selectedStatusFilter != null) {
        if (_selectedStatusFilter == 'pending') {
          if (item.status != _LocatorSlipStatus.pendingDepartmentHead &&
              item.status != _LocatorSlipStatus.pendingHr) {
            return false;
          }
        } else if (_selectedStatusFilter == 'approved') {
          if (item.status != _LocatorSlipStatus.approved) return false;
        } else if (_selectedStatusFilter == 'rejected') {
          if (item.status != _LocatorSlipStatus.rejected) return false;
        } else if (_selectedStatusFilter == 'cancelled') {
          if (item.status != _LocatorSlipStatus.cancelled) return false;
        }
      }
      if (_fromDate != null &&
          _dateOnly(item.date).isBefore(_dateOnly(_fromDate!))) {
        return false;
      }
      if (_toDate != null &&
          _dateOnly(item.date).isAfter(_dateOnly(_toDate!))) {
        return false;
      }
      return true;
    }).toList();
  }

  List<_LocatorSlipDraft> get _filteredDeptHeadQueue {
    return _deptHeadQueue.where((item) {
      switch (_selectedApprovalStatusFilter) {
        case 'pending':
          return item.status == _LocatorSlipStatus.pendingDepartmentHead;
        case 'forwarded':
          return item.status == _LocatorSlipStatus.pendingHr;
        case 'approved':
          return item.status == _LocatorSlipStatus.approved;
        case 'rejected':
          return item.status == _LocatorSlipStatus.rejected;
        case 'cancelled':
          return item.status == _LocatorSlipStatus.cancelled;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName.trim().isEmpty
        ? 'Employee'
        : auth.displayName.trim();
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 860;

    return FutureBuilder<bool>(
      future: _isDeptHeadFuture,
      builder: (context, snapshot) {
        final isDepartmentHead = snapshot.data == true;
        if (isDepartmentHead && !_appliedDeptHeadDefaultSection) {
          _appliedDeptHeadDefaultSection = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _currentSection = _LocatorSection.approvals;
            });
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LocatorHeader(
              employeeName: displayName,
              onCreatePressed: () => _openCreateForm(context, displayName),
              showCreateAction: width >= 1024,
            ),
            if (isDepartmentHead) ...[
              const SizedBox(height: 16),
              _LocatorSectionTabs(
                current: _currentSection,
                onChanged: (section) {
                  setState(() => _currentSection = section);
                  if (section == _LocatorSection.approvals) {
                    _loadDepartmentHeadRequests();
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            if (_currentSection == _LocatorSection.requests)
              _buildMyRequests(width: width, compact: compact),
            if (_currentSection == _LocatorSection.approvals)
              _buildApprovalsView(),
          ],
        );
      },
    );
  }

  Widget _buildMyRequests({required double width, required bool compact}) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isMobile = width < 600;
    final maxListHeight = width < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : width < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final visibleSlips = _filteredSlips;
    _LocatorSlipDraft? selectedSlip;
    for (final item in visibleSlips) {
      if (_slipSelectionKey(item) == _selectedSlipId) {
        selectedSlip = item;
        break;
      }
    }
    final canCancelSelected = _canCancelSlip(selectedSlip);
    final useScrollableList = visibleSlips.length > 3;

    return _SectionCard(
      title: 'My Locator Requests',
      subtitle:
          'Use filters to quickly find requests by status, date, type, office, or reason.',
      icon: Icons.receipt_long_rounded,
      headerTrailing: isMobile
          ? null
          : SectionHeaderActions(
              children: [
                SectionHeaderActionButton.outlined(
                  context: context,
                  onPressed: selectedSlip == null
                      ? null
                      : () => _showSlipDetails(context, selectedSlip!),
                  label: 'View Details',
                ),
                SectionHeaderActionButton.outlined(
                  context: context,
                  onPressed: selectedSlip == null
                      ? null
                      : () => _showSlipHistory(context, selectedSlip!),
                  label: 'View History',
                ),
                SectionHeaderActionButton.outlined(
                  context: context,
                  onPressed: !canCancelSelected
                      ? null
                      : () => _cancelSlip(selectedSlip!),
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RequestFiltersBar<String>(
            options: _locatorSlipFilterOptions,
            selectedValue: _selectedStatusFilter,
            fromDate: _fromDate,
            toDate: _toDate,
            searchQuery: _searchQuery,
            visibleCount: _filteredSlips.length,
            totalCount: _slips.length,
            onStatusChanged: (status) =>
                setState(() => _selectedStatusFilter = status),
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            onPickFromDate: () => _pickFilterDate(isFrom: true),
            onPickToDate: () => _pickFilterDate(isFrom: false),
            onClearFilters: _clearFilters,
            formatDate: _formatDate,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ErrorState(message: _error!),
            ),
          _loadingMy
              ? const _CenteredLoading(message: 'Loading locator requests...')
              : _slips.isEmpty
              ? const _EmptyState(
                  message:
                      'No locator requests yet. Click "File Request" to create one.',
                )
              : _filteredSlips.isEmpty
              ? const _EmptyState(
                  message: 'No locator requests match the current filters.',
                )
              : _myRequestsTable(
                  items: visibleSlips,
                  maxHeight: maxListHeight,
                  useScrollableList: useScrollableList,
                ),
        ],
      ),
    );
  }

  void _toggleSlipSelection(_LocatorSlipDraft item) {
    final id = _slipSelectionKey(item);
    setState(() {
      _selectedSlipId = _selectedSlipId == id ? null : id;
    });
  }

  String _slipSelectionKey(_LocatorSlipDraft item) {
    return item.id ??
        '${item.date.toIso8601String()}-${item.requestType.code}-${item.office}-${item.employeeName}-${item.remarks}';
  }

  bool _canCancelSlip(_LocatorSlipDraft? item) {
    final id = item?.id?.trim();
    if (item == null || id == null || id.isEmpty) return false;
    return item.status == _LocatorSlipStatus.pendingDepartmentHead ||
        item.status == _LocatorSlipStatus.pendingHr;
  }

  void _showSlipDetails(BuildContext context, _LocatorSlipDraft item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _LocatorSlipDetailsDialog(
        item: item,
        canCancel: _canCancelSlip(item),
        onHistory: () => _showSlipHistory(context, item),
        onCancel: () => _cancelSlip(item),
      ),
    );
  }

  void _showSlipHistory(BuildContext context, _LocatorSlipDraft item) {
    final rawStatus = item.rawStatus;
    final history =
        <
          ({
            String title,
            String? actor,
            DateTime? date,
            String? remarks,
            bool completed,
          })
        >[
          (
            title: item.status == _LocatorSlipStatus.draft
                ? 'Draft'
                : 'Submitted',
            actor: item.employeeName,
            date: item.createdAt ?? item.date,
            remarks: null,
            completed: true,
          ),
          if (item.status == _LocatorSlipStatus.pendingDepartmentHead)
            (
              title: 'Pending Department Head',
              actor: item.departmentHeadName,
              date: null,
              remarks: null,
              completed: false,
            ),
          if (item.departmentHeadReviewedAt != null ||
              rawStatus == 'pending_hr' ||
              rawStatus == 'approved' ||
              rawStatus == 'rejected_by_hr' ||
              rawStatus == 'rejected_by_department_head')
            (
              title: rawStatus == 'rejected_by_department_head'
                  ? 'Rejected by Department Head'
                  : 'Reviewed by Department Head',
              actor: item.departmentHeadName,
              date: item.departmentHeadReviewedAt,
              remarks: item.departmentHeadRemarks,
              completed: true,
            ),
          if (item.status == _LocatorSlipStatus.pendingHr)
            (
              title: 'Pending HR Admin',
              actor: item.hrReviewerName,
              date: null,
              remarks: null,
              completed: false,
            ),
          if (rawStatus == 'approved')
            (
              title: 'Approved by HR',
              actor: item.hrReviewerName,
              date: item.hrReviewedAt,
              remarks: item.hrRemarks,
              completed: true,
            ),
          if (rawStatus == 'rejected_by_hr')
            (
              title: 'Rejected by HR',
              actor: item.hrReviewerName,
              date: item.hrReviewedAt,
              remarks: item.hrRemarks,
              completed: true,
            ),
          if (rawStatus == 'cancelled')
            (
              title: 'Cancelled',
              actor: null,
              date: item.updatedAt,
              remarks: null,
              completed: true,
            ),
        ];
    final accent = AppTheme.primaryNavy;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppTheme.dashPanelOf(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Locator Request History',
                        style: TextStyle(
                          color: _headingColor(dialogContext),
                          fontSize: 40 * 0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close,
                        color: _mutedColor(dialogContext),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.dashHairlineOf(dialogContext)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    children: List.generate(history.length, (index) {
                      final step = history[index];
                      final isFirst = index == 0;
                      final isLast = index == history.length - 1;
                      final actor = step.actor?.trim();
                      String subtitle = step.date == null
                          ? 'Awaiting action'
                          : _formatDateTime(step.date!);
                      if (actor != null && actor.isNotEmpty) {
                        subtitle = '$subtitle by $actor';
                      } else if (step.title.contains('Department Head') &&
                          step.title != 'Pending Department Head') {
                        subtitle = '$subtitle by Department Head';
                      } else if (step.title.contains('HR')) {
                        subtitle = '$subtitle by HR Admin';
                      }
                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 44,
                              height: 96,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 20,
                                    top: isFirst ? 14 : 0,
                                    bottom: isLast ? 82 : 0,
                                    child: Container(width: 4, color: accent),
                                  ),
                                  Positioned(
                                    left: 8,
                                    top: 0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        step.completed
                                            ? Icons.check_rounded
                                            : Icons.hourglass_top_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.title,
                                      style: TextStyle(
                                        color: _headingColor(dialogContext),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        color: _mutedColor(dialogContext),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if ((step.remarks ?? '').trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          step.remarks!.trim(),
                                          style: TextStyle(
                                            color: _mutedColor(dialogContext),
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Divider(height: 1, color: AppTheme.dashHairlineOf(dialogContext)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 16),
                child: Row(
                  children: [
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.15),
                        foregroundColor: accent,
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApprovalsView() {
    final visibleItems = _filteredDeptHeadQueue;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxListHeight = screenWidth < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : screenWidth < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final useScrollableList = visibleItems.length > 3;
    _LocatorSlipDraft? selectedApproval;
    for (final item in visibleItems) {
      if (_slipSelectionKey(item) == _selectedApprovalSlipId) {
        selectedApproval = item;
        break;
      }
    }
    final canReviewSelected =
        selectedApproval?.status == _LocatorSlipStatus.pendingDepartmentHead;

    return _SectionCard(
      title: 'Locator Requests & History',
      subtitle:
          'Review pending locator, pass slip, and work-from-home requests.',
      icon: Icons.fact_check_rounded,
      headerTrailing: SectionHeaderActions(
        children: [
          SectionHeaderActionButton.outlined(
            context: context,
            onPressed: selectedApproval == null
                ? null
                : () => _showSlipDetails(context, selectedApproval!),
            icon: Icons.visibility_rounded,
            label: 'View',
          ),
          SectionHeaderActionButton.outlined(
            context: context,
            onPressed: selectedApproval == null
                ? null
                : () => _showSlipHistory(context, selectedApproval!),
            icon: Icons.history_rounded,
            label: 'History',
          ),
          SectionHeaderActionButton.outlined(
            context: context,
            onPressed: !canReviewSelected
                ? null
                : () => _departmentHeadReject(selectedApproval!),
            icon: Icons.close_rounded,
            label: 'Reject',
          ),
          SectionHeaderActionButton.filled(
            context: context,
            onPressed: !canReviewSelected
                ? null
                : () => _departmentHeadApprove(selectedApproval!),
            icon: Icons.check_rounded,
            label: 'Approve',
          ),
        ],
      ),
      child: _loadingApprovals
          ? const _CenteredLoading(message: 'Loading approval queue...')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RequestFiltersBar<String>(
                  options: _locatorApprovalFilterOptions,
                  selectedValue: _selectedApprovalStatusFilter,
                  visibleCount: visibleItems.length,
                  totalCount: _deptHeadQueue.length,
                  showSearch: false,
                  showDateRange: false,
                  onStatusChanged: (value) {
                    setState(() {
                      _selectedApprovalStatusFilter = value;
                      _selectedApprovalSlipId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ErrorState(message: _error!),
                  ),
                if (_deptHeadQueue.isEmpty)
                  const _EmptyState(
                    message: 'No locator requests or history yet.',
                  )
                else if (visibleItems.isEmpty)
                  const _EmptyState(
                    message: 'No locator requests match the current filter.',
                  )
                else
                  _approvalItemsTable(
                    items: visibleItems,
                    maxHeight: maxListHeight,
                    useScrollableList: useScrollableList,
                  ),
              ],
            ),
    );
  }

  Widget _myRequestsTable({
    required List<_LocatorSlipDraft> items,
    required double maxHeight,
    required bool useScrollableList,
  }) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _myRequestsMobileList(
        items: items,
        maxHeight: maxHeight,
        useScrollableList: useScrollableList,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 900
            ? 900.0
            : constraints.maxWidth;
        final purposeWidth = tableWidth - 500;
        final content = SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _myRequestsTableHeader(context, purposeWidth),
              for (var index = 0; index < items.length; index++)
                _myRequestsTableRow(
                  context,
                  items[index],
                  purposeWidth: purposeWidth,
                  isLast: index == items.length - 1,
                  isSelected:
                      _slipSelectionKey(items[index]) == _selectedSlipId,
                  onTap: () => _toggleSlipSelection(items[index]),
                ),
            ],
          ),
        );

        final table = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            ),
          ),
        );

        if (!useScrollableList) return table;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              primary: false,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: table,
            ),
          ),
        );
      },
    );
  }

  Widget _myRequestsMobileList({
    required List<_LocatorSlipDraft> items,
    required double maxHeight,
    required bool useScrollableList,
  }) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(items.length, (index) {
        final item = items[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 12),
          child: _LocatorRequestMobileCard(
            item: item,
            isSelected: _slipSelectionKey(item) == _selectedSlipId,
            segmentsText: _approvalSegmentsText(item),
            statusPill: _myRequestStatusPill(item),
            onTap: () => _showSlipDetails(context, item),
          ),
        );
      }),
    );

    if (!useScrollableList) return list;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: list,
      ),
    );
  }

  Widget _myRequestsTableHeader(BuildContext context, double purposeWidth) {
    return Container(
      height: 44,
      color: AppTheme.dashMutedSurfaceOf(context),
      child: Row(
        children: [
          _approvalHeaderCell(context, 'Date', width: 120),
          _approvalHeaderCell(context, 'Type', width: 110),
          _approvalHeaderCell(
            context,
            'Location / Purpose',
            width: purposeWidth,
          ),
          _approvalHeaderCell(context, 'Time', width: 120),
          _approvalHeaderCell(context, 'Status', width: 150),
        ],
      ),
    );
  }

  Widget _myRequestsTableRow(
    BuildContext context,
    _LocatorSlipDraft item, {
    required double purposeWidth,
    required bool isLast,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final dark = _isDark(context);
    final borderColor = AppTheme.dashHairlineOf(context);
    final rowColor = isSelected
        ? (dark
              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
              : AppTheme.primaryNavy.withValues(alpha: 0.08))
        : Colors.transparent;
    final leftBorderColor = isSelected
        ? AppTheme.primaryNavy
        : Colors.transparent;

    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.04),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: leftBorderColor, width: 4),
              bottom: isLast ? BorderSide.none : BorderSide(color: borderColor),
            ),
          ),
          child: Row(
            children: [
              _approvalBodyCell(
                width: 116,
                child: _approvalCellText(
                  context,
                  _formatDate(item.date),
                  strong: true,
                ),
              ),
              _approvalBodyCell(
                width: 110,
                child: _approvalCellText(
                  context,
                  item.requestType.shortLabel,
                  strong: true,
                ),
              ),
              _approvalBodyCell(
                width: purposeWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _approvalCellText(context, item.office, strong: true),
                    if (item.remarks.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _approvalCellText(
                        context,
                        item.remarks,
                        color: _mutedColor(context),
                        fontSize: 12,
                      ),
                    ],
                  ],
                ),
              ),
              _approvalBodyCell(
                width: 120,
                child: _approvalCellText(context, _approvalSegmentsText(item)),
              ),
              _approvalBodyCell(width: 150, child: _myRequestStatusPill(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _approvalItemsTable({
    required List<_LocatorSlipDraft> items,
    required double maxHeight,
    required bool useScrollableList,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 920
            ? 920.0
            : constraints.maxWidth;
        final purposeWidth = tableWidth - 580;
        final content = SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _approvalTableHeader(context, purposeWidth),
              for (var index = 0; index < items.length; index++)
                _approvalTableRow(
                  context,
                  items[index],
                  purposeWidth: purposeWidth,
                  isLast: index == items.length - 1,
                  isSelected:
                      _slipSelectionKey(items[index]) ==
                      _selectedApprovalSlipId,
                  onTap: () => _toggleApprovalSelection(items[index]),
                ),
            ],
          ),
        );

        final table = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            ),
          ),
        );

        if (!useScrollableList) return table;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              primary: false,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: table,
            ),
          ),
        );
      },
    );
  }

  Widget _approvalTableHeader(BuildContext context, double purposeWidth) {
    return Container(
      height: 44,
      color: AppTheme.dashMutedSurfaceOf(context),
      child: Row(
        children: [
          _approvalHeaderCell(context, 'Employee', width: 190),
          _approvalHeaderCell(context, 'Date', width: 120),
          _approvalHeaderCell(
            context,
            'Purpose / Location',
            width: purposeWidth,
          ),
          _approvalHeaderCell(context, 'Time', width: 120),
          _approvalHeaderCell(context, 'Status', width: 150),
        ],
      ),
    );
  }

  Widget _approvalTableRow(
    BuildContext context,
    _LocatorSlipDraft item, {
    required double purposeWidth,
    required bool isLast,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final dark = _isDark(context);
    final borderColor = AppTheme.dashHairlineOf(context);
    final rowColor = isSelected
        ? (dark
              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
              : AppTheme.primaryNavy.withValues(alpha: 0.08))
        : Colors.transparent;
    final leftBorderColor = isSelected
        ? AppTheme.primaryNavy
        : Colors.transparent;

    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.04),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: leftBorderColor, width: 4),
              bottom: isLast ? BorderSide.none : BorderSide(color: borderColor),
            ),
          ),
          child: Row(
            children: [
              _approvalBodyCell(
                width: 186,
                child: _approvalCellText(
                  context,
                  item.employeeName,
                  strong: true,
                ),
              ),
              _approvalBodyCell(
                width: 120,
                child: _approvalCellText(context, _formatDate(item.date)),
              ),
              _approvalBodyCell(
                width: purposeWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _approvalCellText(
                      context,
                      '${item.requestType.shortLabel} · ${item.office}',
                      strong: true,
                    ),
                    if (item.remarks.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _approvalCellText(
                        context,
                        item.remarks,
                        color: _mutedColor(context),
                        fontSize: 12,
                      ),
                    ],
                  ],
                ),
              ),
              _approvalBodyCell(
                width: 120,
                child: _approvalCellText(context, _approvalSegmentsText(item)),
              ),
              _approvalBodyCell(width: 150, child: _approvalStatusPill(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _approvalHeaderCell(
    BuildContext context,
    String label, {
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _mutedColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _approvalBodyCell({required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _approvalCellText(
    BuildContext context,
    String text, {
    bool strong = false,
    Color? color,
    double fontSize = 13,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? _headingColor(context),
        fontSize: fontSize,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _approvalStatusPill(_LocatorSlipDraft item) {
    final (bg, border, textColor) = _statusColors(item.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        _departmentHeadStatusLabel(item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _myRequestStatusPill(_LocatorSlipDraft item) {
    final (bg, border, textColor) = _statusColors(item.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        item.status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _approvalSegmentsText(_LocatorSlipDraft item) {
    final segments = <String>[];
    if (item.amIn) segments.add('AM IN');
    if (item.amOut) segments.add('AM OUT');
    if (item.pmIn) segments.add('PM IN');
    if (item.pmOut) segments.add('PM OUT');
    return segments.isEmpty ? '-' : segments.join(', ');
  }

  void _toggleApprovalSelection(_LocatorSlipDraft item) {
    final id = _slipSelectionKey(item);
    setState(() {
      _selectedApprovalSlipId = _selectedApprovalSlipId == id ? null : id;
    });
  }

  Future<void> _openCreateForm(
    BuildContext context,
    String employeeName,
  ) async {
    final created = await showDialog<_LocatorSlipDraft>(
      context: context,
      builder: (_) => _LocatorSlipFormDialog(employeeName: employeeName),
    );
    if (!mounted || created == null) return;
    setState(() {
      _error = null;
      _loadingMy = true;
    });
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/locator-slips/submit',
        data: {
          'slip_date': _toIsoDate(created.date),
          'am_in': created.amIn,
          'am_out': created.amOut,
          'pm_in': created.pmIn,
          'pm_out': created.pmOut,
          'request_type': created.requestType.code,
          'office': created.office,
          'reason': created.remarks,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if ((res.statusCode ?? 500) >= 400) {
        if (!mounted) return;
        final message = _apiResponseMessage(
          res.data,
          fallback: 'Failed to submit request.',
        );
        setState(() => _loadingMy = false);
        await _showLocatorErrorDialog(message);
        return;
      }
      final data = res.data;
      _LocatorSlipDraft? inserted;
      if (data != null) {
        inserted = _LocatorSlipDraft.fromApi(data);
        setState(() => _slips.insert(0, inserted!));
      }
      if (!mounted) return;
      final msg = inserted != null
          ? (inserted.status == _LocatorSlipStatus.pendingHr
                ? 'Request submitted. Awaiting HR approval.'
                : 'Request submitted. Awaiting department head approval.')
          : 'Request submitted successfully.';
      _showLocatorSnack(msg);
    } catch (e) {
      if (!mounted) return;
      final message = _apiErrorMessage(
        e,
        fallback: 'Failed to submit request.',
      );
      setState(() => _loadingMy = false);
      await _showLocatorErrorDialog(message);
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<void> _cancelSlip(_LocatorSlipDraft item) async {
    if (!_canCancelSlip(item)) return;
    final id = item.id!.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel locator request?'),
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

    setState(() {
      _error = null;
      _loadingMy = true;
    });
    try {
      final res = await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/$id/cancel',
        data: const {},
      );
      final data = res.data;
      if (!mounted) return;
      setState(() {
        _selectedSlipId = null;
        if (data != null) {
          final updated = _LocatorSlipDraft.fromApi(data);
          final index = _slips.indexWhere((slip) => slip.id == updated.id);
          if (index >= 0) {
            _slips[index] = updated;
          }
        }
      });
      await _loadMyRequests();
      if (!mounted) return;
      _showLocatorSnack('Request cancelled.');
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _error = _apiErrorMessage(e, fallback: 'Failed to cancel request.'),
      );
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<bool> _checkIsDepartmentHead() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/department-head/check',
      );
      final isDeptHead = res.data?['isDeptHead'] == true;
      if (isDeptHead) {
        _loadDepartmentHeadRequests();
      }
      return isDeptHead;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadMyRequests() async {
    setState(() {
      _loadingMy = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/locator-slips/my',
      );
      final items = (res.data ?? const [])
          .whereType<Map>()
          .map((e) => _LocatorSlipDraft.fromApi(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        _slips
          ..clear()
          ..addAll(items);
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = _apiErrorMessage(
          e,
          fallback: 'Failed to load locator requests.',
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<void> _loadDepartmentHeadRequests() async {
    setState(() => _loadingApprovals = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/locator-slips/department-head',
      );
      final items = (res.data ?? const [])
          .whereType<Map>()
          .map((e) => _LocatorSlipDraft.fromApi(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        _deptHeadQueue
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deptHeadQueue.clear();
      });
    } finally {
      if (mounted) setState(() => _loadingApprovals = false);
    }
  }

  Future<void> _departmentHeadApprove(_LocatorSlipDraft item) async {
    if (item.id == null || item.id!.isEmpty) return;
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/department-head-approve',
        data: const {},
      );
      await _loadDepartmentHeadRequests();
      await _loadMyRequests();
      if (!mounted) return;
      _showLocatorSnack('Approved and sent to HR for final approval.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _apiErrorMessage(e, fallback: 'Approve failed.'));
    }
  }

  Future<void> _departmentHeadReject(_LocatorSlipDraft item) async {
    if (item.id == null || item.id!.isEmpty) return;
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/department-head-reject',
        data: const {},
      );
      await _loadDepartmentHeadRequests();
      await _loadMyRequests();
      if (!mounted) return;
      _showLocatorSnack('Request rejected.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _apiErrorMessage(e, fallback: 'Reject failed.'));
    }
  }

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
      _selectedStatusFilter = null;
      _fromDate = null;
      _toDate = null;
    });
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _toIsoDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _showLocatorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
    );
  }

  Future<void> _showLocatorErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request not allowed'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Locator slip details — mobile-first presentation for the employee request list.
class _LocatorSlipDetailsDialog extends StatelessWidget {
  const _LocatorSlipDetailsDialog({
    required this.item,
    required this.canCancel,
    required this.onHistory,
    required this.onCancel,
  });

  final _LocatorSlipDraft item;
  final bool canCancel;
  final VoidCallback onHistory;
  final VoidCallback onCancel;

  String _segmentsLine() {
    final parts = <String>[];
    if (item.amIn) parts.add('AM IN');
    if (item.amOut) parts.add('AM OUT');
    if (item.pmIn) parts.add('PM IN');
    if (item.pmOut) parts.add('PM OUT');
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dark = AppTheme.dashIsDark(context);
    final maxH = screen.height * 0.88;
    final maxW = (screen.width - 28).clamp(320.0, 640.0);
    final panelColor = AppTheme.dashPanelOf(context);
    final borderColor = AppTheme.dashHairlineOf(context);
    final (statusBg, statusBorder, statusText) = _statusColors(item.status);

    void printForm() {
      LocatorSlipPrint.printForm(
        context: context,
        id: item.id,
        employeeName: item.employeeName,
        dateText: _formatDate(item.date),
        requestTypeLabel: item.requestType.label,
        locationLabel: item.requestType.locationLabel,
        office: item.office,
        remarks: item.remarks,
        amIn: item.amIn,
        amOut: item.amOut,
        pmIn: item.pmIn,
        pmOut: item.pmOut,
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: panelColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LocatorDetailHeader(
                  item: item,
                  statusBg: statusBg,
                  statusBorder: statusBorder,
                  statusText: statusText,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LocatorDetailSection(
                          title: 'Slip Information',
                          icon: Icons.receipt_long_rounded,
                          children: [
                            _LocatorDetailTile(
                              icon: Icons.calendar_today_rounded,
                              label: 'Date',
                              value: _formatDate(item.date),
                            ),
                            _LocatorDetailTile(
                              icon: Icons.category_rounded,
                              label: 'Type',
                              value: item.requestType.label,
                            ),
                            _LocatorDetailTile(
                              icon: Icons.place_rounded,
                              label: item.requestType.locationLabel,
                              value: item.office.trim().isEmpty
                                  ? 'Not specified'
                                  : item.office.trim(),
                            ),
                            _LocatorDetailTile(
                              icon: Icons.schedule_rounded,
                              label: 'Time Segments',
                              value: _segmentsLine(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _LocatorStatusPanel(
                          status: item.status,
                          statusBg: statusBg,
                          statusBorder: statusBorder,
                          statusText: statusText,
                          createdAt: item.createdAt,
                          updatedAt: item.updatedAt,
                        ),
                        const SizedBox(height: 12),
                        _LocatorReasonPanel(
                          text: item.remarks.trim().isEmpty
                              ? 'No reason provided.'
                              : item.remarks.trim(),
                        ),
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark
                        ? AppTheme.dashMutedSurfaceOf(context)
                        : AppTheme.offWhite,
                    border: Border(top: BorderSide(color: borderColor)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: _LocatorDetailActions(
                      canCancel: canCancel,
                      canPrint: item.status == _LocatorSlipStatus.approved,
                      onClose: () => Navigator.of(context).pop(),
                      onHistory: () {
                        Navigator.of(context).pop();
                        onHistory();
                      },
                      onCancel: () {
                        Navigator.of(context).pop();
                        onCancel();
                      },
                      onPrint: printForm,
                    ),
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

class _LocatorDetailHeader extends StatelessWidget {
  const _LocatorDetailHeader({
    required this.item,
    required this.statusBg,
    required this.statusBorder,
    required this.statusText,
    required this.onClose,
  });

  final _LocatorSlipDraft item;
  final Color statusBg;
  final Color statusBorder;
  final Color statusText;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.primaryNavy.withValues(alpha: 0.18)
            : AppTheme.primaryNavy.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
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
                  'Request Details',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(
                    alpha: dark ? 0.24 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _locatorRequestTypeIcon(item.requestType),
                  color: AppTheme.primaryNavy,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.requestType.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(item.date),
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _LocatorDetailStatusPill(
                status: item.status,
                background: statusBg,
                border: statusBorder,
                foreground: statusText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocatorDetailSection extends StatelessWidget {
  const _LocatorDetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<_LocatorDetailTile> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryNavy),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 470;
              final tileWidth = wide
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final child in children)
                    SizedBox(width: tileWidth, child: child),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LocatorDetailTile extends StatelessWidget {
  const _LocatorDetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
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

class _LocatorStatusPanel extends StatelessWidget {
  const _LocatorStatusPanel({
    required this.status,
    required this.statusBg,
    required this.statusBorder,
    required this.statusText,
    this.createdAt,
    this.updatedAt,
  });

  final _LocatorSlipStatus status;
  final Color statusBg;
  final Color statusBorder;
  final Color statusText;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final subtitle = updatedAt != null
        ? 'Updated ${_formatDateTime(updatedAt!)}'
        : createdAt != null
        ? 'Filed ${_formatDateTime(createdAt!)}'
        : 'Current workflow status';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _locatorStatusIcon(status),
              color: statusText,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(
                    color: statusText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: statusText.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _LocatorReasonPanel extends StatelessWidget {
  const _LocatorReasonPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 19, color: AppTheme.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason / Purpose',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class _LocatorDetailStatusPill extends StatelessWidget {
  const _LocatorDetailStatusPill({
    required this.status,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final _LocatorSlipStatus status;
  final Color background;
  final Color border;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_locatorStatusIcon(status), size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocatorDetailActions extends StatelessWidget {
  const _LocatorDetailActions({
    required this.canCancel,
    required this.canPrint,
    required this.onClose,
    required this.onHistory,
    required this.onCancel,
    required this.onPrint,
  });

  final bool canCancel;
  final bool canPrint;
  final VoidCallback onClose;
  final VoidCallback onHistory;
  final VoidCallback onCancel;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onClose,
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onHistory,
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('History'),
                      ),
                    ),
                  ],
                ),
                if (canCancel) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancel Request'),
                    ),
                  ),
                ],
                if (canPrint) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onPrint,
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(onPressed: onClose, child: const Text('Close')),
              OutlinedButton.icon(
                onPressed: onHistory,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('History'),
              ),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Cancel'),
                ),
              if (canPrint)
                FilledButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LocatorRequestMobileCard extends StatelessWidget {
  const _LocatorRequestMobileCard({
    required this.item,
    required this.isSelected,
    required this.segmentsText,
    required this.statusPill,
    required this.onTap,
  });

  final _LocatorSlipDraft item;
  final bool isSelected;
  final String segmentsText;
  final Widget statusPill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final selectedColor = dark
        ? AppTheme.primaryNavy.withValues(alpha: 0.35)
        : AppTheme.primaryNavy.withValues(alpha: 0.08);
    final borderColor = isSelected
        ? AppTheme.primaryNavy.withValues(alpha: dark ? 0.75 : 0.4)
        : AppTheme.dashHairlineOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.requestType.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _formatDate(item.date),
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  statusPill,
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.office.trim().isEmpty ? 'Location not set' : item.office,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.remarks.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  item.remarks.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _LocatorMobileMetaChip(
                    icon: Icons.schedule_rounded,
                    label: segmentsText,
                  ),
                  _LocatorMobileMetaChip(
                    icon: Icons.category_outlined,
                    label: item.requestType.shortLabel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocatorMobileMetaChip extends StatelessWidget {
  const _LocatorMobileMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.dashTextSecondaryOf(context)),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocatorHeader extends StatelessWidget {
  const _LocatorHeader({
    required this.employeeName,
    required this.onCreatePressed,
    required this.showCreateAction,
  });

  final String employeeName;
  final VoidCallback onCreatePressed;
  final bool showCreateAction;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      child: Wrap(
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Locator Slips',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'File locator, pass slip, or work-from-home requests for DTR coverage, $employeeName.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (showCreateAction)
            FilledButton.icon(
              onPressed: onCreatePressed,
              icon: const Icon(Icons.add_rounded),
              label: const Text('File Request'),
            ),
        ],
      ),
    );
  }
}

enum _WfhCoverage {
  wholeDay('Whole day'),
  amOnly('AM only'),
  pmOnly('PM only');

  const _WfhCoverage(this.label);
  final String label;
}

class _LocatorSlipFormDialog extends StatefulWidget {
  const _LocatorSlipFormDialog({required this.employeeName});

  final String employeeName;

  @override
  State<_LocatorSlipFormDialog> createState() => _LocatorSlipFormDialogState();
}

class _LocatorSlipFormDialogState extends State<_LocatorSlipFormDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  LocatorRequestType _requestType = LocatorRequestType.locator;
  _WfhCoverage _wfhCoverage = _WfhCoverage.wholeDay;
  final _officeController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _amIn = false;
  bool _amOut = false;
  bool _pmIn = false;
  bool _pmOut = false;
  bool _savedAmInBeforeWfh = false;
  bool _savedAmOutBeforeWfh = false;
  bool _savedPmInBeforeWfh = false;
  bool _savedPmOutBeforeWfh = false;
  bool _hasSavedSegmentsBeforeWfh = false;

  bool get _isWfhRequest => _requestType == LocatorRequestType.workFromHome;

  void _applyWfhCoverage(_WfhCoverage coverage) {
    _amIn =
        coverage == _WfhCoverage.wholeDay || coverage == _WfhCoverage.amOnly;
    _amOut =
        coverage == _WfhCoverage.wholeDay || coverage == _WfhCoverage.amOnly;
    _pmIn =
        coverage == _WfhCoverage.wholeDay || coverage == _WfhCoverage.pmOnly;
    _pmOut =
        coverage == _WfhCoverage.wholeDay || coverage == _WfhCoverage.pmOnly;
  }

  void _setRequestType(LocatorRequestType type) {
    if (type == _requestType) return;
    setState(() {
      final enteringWfh =
          _requestType != LocatorRequestType.workFromHome &&
          type == LocatorRequestType.workFromHome;
      final leavingWfh =
          _requestType == LocatorRequestType.workFromHome &&
          type != LocatorRequestType.workFromHome;

      if (enteringWfh) {
        _savedAmInBeforeWfh = _amIn;
        _savedAmOutBeforeWfh = _amOut;
        _savedPmInBeforeWfh = _pmIn;
        _savedPmOutBeforeWfh = _pmOut;
        _hasSavedSegmentsBeforeWfh = true;
        _wfhCoverage = _WfhCoverage.wholeDay;
        _applyWfhCoverage(_wfhCoverage);
      } else if (leavingWfh && _hasSavedSegmentsBeforeWfh) {
        _amIn = _savedAmInBeforeWfh;
        _amOut = _savedAmOutBeforeWfh;
        _pmIn = _savedPmInBeforeWfh;
        _pmOut = _savedPmOutBeforeWfh;
      }

      _requestType = type;
    });
  }

  void _setWfhCoverage(_WfhCoverage coverage) {
    if (coverage == _wfhCoverage) return;
    setState(() {
      _wfhCoverage = coverage;
      _applyWfhCoverage(coverage);
    });
  }

  @override
  void dispose() {
    _officeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF57C00);
    return AlertDialog(
      backgroundColor: AppTheme.dashPanelOf(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Text(
        'File Request',
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _datePicker(),
                const SizedBox(height: 14),
                _requestTypeDropdown(),
                if (_isWfhRequest) ...[
                  const SizedBox(height: 14),
                  _wfhCoverageDropdown(),
                ],
                const SizedBox(height: 14),
                _segmentSelector(),
                const SizedBox(height: 14),
                _fieldLabel('Name'),
                TextFormField(
                  initialValue: widget.employeeName,
                  enabled: false,
                  decoration: _inputDecoration().copyWith(
                    hintText: widget.employeeName,
                  ),
                ),
                const SizedBox(height: 12),
                _fieldLabel(_requestType.locationLabel),
                TextFormField(
                  controller: _officeController,
                  decoration: _inputDecoration().copyWith(
                    hintText: _requestType.locationHint,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '${_requestType.locationLabel} is required'
                      : null,
                ),
                const SizedBox(height: 12),
                _fieldLabel('Remarks / Reasons'),
                TextFormField(
                  controller: _remarksController,
                  minLines: 4,
                  maxLines: 4,
                  decoration: _inputDecoration().copyWith(
                    hintText: 'Enter remarks...',
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Remarks/Reasons is required'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 40,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Cancel'),
            ),
            SizedBox(width: 12),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(72, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _datePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Date'),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _date = picked);
            }
          },
          child: InputDecorator(
            decoration: _inputDecoration().copyWith(
              suffixIcon: const Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: Color(0xFF7A7A7A),
              ),
            ),
            child: Text(_formatDate(_date)),
          ),
        ),
      ],
    );
  }

  Widget _requestTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Request Type'),
        DropdownButtonFormField<LocatorRequestType>(
          value: _requestType,
          decoration: _inputDecoration(),
          isExpanded: true,
          items: LocatorRequestType.values
              .map(
                (type) => DropdownMenuItem<LocatorRequestType>(
                  value: type,
                  child: Text(type.label),
                ),
              )
              .toList(),
          onChanged: (type) {
            if (type == null) return;
            _setRequestType(type);
          },
        ),
      ],
    );
  }

  Widget _wfhCoverageDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('WFH Coverage'),
        DropdownButtonFormField<_WfhCoverage>(
          value: _wfhCoverage,
          decoration: _inputDecoration(),
          isExpanded: true,
          items: _WfhCoverage.values
              .map(
                (coverage) => DropdownMenuItem<_WfhCoverage>(
                  value: coverage,
                  child: Text(coverage.label),
                ),
              )
              .toList(),
          onChanged: (coverage) {
            if (coverage == null) return;
            _setWfhCoverage(coverage);
          },
        ),
      ],
    );
  }

  Widget _segmentSelector() {
    const accent = Color(0xFFF57C00);
    const border = Color(0xFFBEBEBE);
    const divider = Color(0xFFC9C9C9);
    final locked = _isWfhRequest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Applicable Time Segment(s)'),
        const SizedBox(height: 8),
        Container(
          height: 42,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              _segmentCell(
                label: 'AM IN',
                selected: _amIn,
                onTap: locked ? null : () => setState(() => _amIn = !_amIn),
                accent: accent,
              ),
              _segmentDivider(divider),
              _segmentCell(
                label: 'AM OUT',
                selected: _amOut,
                onTap: locked ? null : () => setState(() => _amOut = !_amOut),
                accent: accent,
              ),
              _segmentDivider(divider),
              _segmentCell(
                label: 'PM IN',
                selected: _pmIn,
                onTap: locked ? null : () => setState(() => _pmIn = !_pmIn),
                accent: accent,
              ),
              _segmentDivider(divider),
              _segmentCell(
                label: 'PM OUT',
                selected: _pmOut,
                onTap: locked ? null : () => setState(() => _pmOut = !_pmOut),
                accent: accent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentDivider(Color color) => Container(width: 1, color: color);

  Widget _segmentCell({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    required Color accent,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? accent : Colors.white),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF2F2F2F),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return AppTheme.dashInputDecoration(
      context,
      radius: 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ).copyWith(
      isDense: true,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.dashInputBorderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFF57C00), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  void _save() {
    final hasTimeSegment = _amIn || _amOut || _pmIn || _pmOut;
    if (!hasTimeSegment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one AM/PM IN/OUT marker'),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      _LocatorSlipDraft(
        date: _date,
        employeeName: widget.employeeName,
        requestType: _requestType,
        office: _officeController.text.trim(),
        remarks: _remarksController.text.trim(),
        amIn: _amIn,
        amOut: _amOut,
        pmIn: _pmIn,
        pmOut: _pmOut,
        status: _LocatorSlipStatus.pendingDepartmentHead,
      ),
    );
  }
}

class _LocatorSlipDraft {
  const _LocatorSlipDraft({
    this.id,
    required this.date,
    required this.employeeName,
    this.requestType = LocatorRequestType.locator,
    required this.office,
    required this.remarks,
    this.rawStatus,
    this.departmentHeadName,
    this.departmentHeadReviewedAt,
    this.departmentHeadRemarks,
    this.hrReviewerName,
    this.hrReviewedAt,
    this.hrRemarks,
    this.createdAt,
    this.updatedAt,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    required this.status,
  });

  final String? id;
  final DateTime date;
  final String employeeName;
  final LocatorRequestType requestType;
  final String office;
  final String remarks;
  final String? rawStatus;
  final String? departmentHeadName;
  final DateTime? departmentHeadReviewedAt;
  final String? departmentHeadRemarks;
  final String? hrReviewerName;
  final DateTime? hrReviewedAt;
  final String? hrRemarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;
  final _LocatorSlipStatus status;

  _LocatorSlipDraft copyWith({
    String? id,
    DateTime? date,
    String? employeeName,
    LocatorRequestType? requestType,
    String? office,
    String? remarks,
    String? rawStatus,
    String? departmentHeadName,
    DateTime? departmentHeadReviewedAt,
    String? departmentHeadRemarks,
    String? hrReviewerName,
    DateTime? hrReviewedAt,
    String? hrRemarks,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? amIn,
    bool? amOut,
    bool? pmIn,
    bool? pmOut,
    _LocatorSlipStatus? status,
  }) {
    return _LocatorSlipDraft(
      id: id ?? this.id,
      date: date ?? this.date,
      employeeName: employeeName ?? this.employeeName,
      requestType: requestType ?? this.requestType,
      office: office ?? this.office,
      remarks: remarks ?? this.remarks,
      rawStatus: rawStatus ?? this.rawStatus,
      departmentHeadName: departmentHeadName ?? this.departmentHeadName,
      departmentHeadReviewedAt:
          departmentHeadReviewedAt ?? this.departmentHeadReviewedAt,
      departmentHeadRemarks:
          departmentHeadRemarks ?? this.departmentHeadRemarks,
      hrReviewerName: hrReviewerName ?? this.hrReviewerName,
      hrReviewedAt: hrReviewedAt ?? this.hrReviewedAt,
      hrRemarks: hrRemarks ?? this.hrRemarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      amIn: amIn ?? this.amIn,
      amOut: amOut ?? this.amOut,
      pmIn: pmIn ?? this.pmIn,
      pmOut: pmOut ?? this.pmOut,
      status: status ?? this.status,
    );
  }

  factory _LocatorSlipDraft.fromApi(Map<String, dynamic> json) {
    String? readName(List<String> keys) {
      for (final key in keys) {
        final value = (json[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }
      return null;
    }

    final rawStatus = (json['status'] ?? '').toString();
    final status = _LocatorSlipStatus.fromApi(rawStatus);
    final genericReviewer = readName(['reviewer_name', 'approver_name']);
    return _LocatorSlipDraft(
      id: (json['id'] ?? '').toString(),
      date: _parseDateOnly(json['slip_date']) ?? DateTime(1970, 1, 1),
      employeeName: (json['employee_name'] ?? 'Employee').toString(),
      requestType: LocatorRequestType.fromCode(json['request_type']),
      office: (json['office'] ?? '').toString(),
      remarks: (json['reason'] ?? '').toString(),
      rawStatus: rawStatus,
      departmentHeadName:
          readName([
            'dept_head_reviewer_name',
            'department_head_name',
            'dept_head_name',
            'reviewed_by_department_head_name',
            'department_head_reviewer_name',
          ]) ??
          (status == _LocatorSlipStatus.pendingHr ? genericReviewer : null),
      departmentHeadReviewedAt: _parseDateTime(json['dept_head_reviewed_at']),
      departmentHeadRemarks: readName(['dept_head_remarks']),
      hrReviewerName:
          readName([
            'hr_name',
            'hr_reviewer_name',
            'reviewed_by_hr_name',
            'approved_by_hr_name',
          ]) ??
          ((status == _LocatorSlipStatus.approved ||
                  status == _LocatorSlipStatus.rejected)
              ? genericReviewer
              : null),
      hrReviewedAt: _parseDateTime(json['hr_reviewed_at']),
      hrRemarks: readName(['hr_remarks']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      amIn: json['am_in'] == true,
      amOut: json['am_out'] == true,
      pmIn: json['pm_in'] == true,
      pmOut: json['pm_out'] == true,
      status: status,
    );
  }
}

enum _LocatorSlipStatus {
  draft('Draft'),
  pendingDepartmentHead('Pending Dept Head'),
  pendingHr('Pending HR Admin'),
  approved('Approved'),
  rejected('Rejected'),
  cancelled('Cancelled');

  const _LocatorSlipStatus(this.label);
  final String label;

  static _LocatorSlipStatus fromApi(String status) {
    switch (status.trim().toLowerCase()) {
      case 'draft':
        return _LocatorSlipStatus.draft;
      case 'pending_department_head':
        return _LocatorSlipStatus.pendingDepartmentHead;
      case 'pending_hr':
      case 'pending':
        return _LocatorSlipStatus.pendingHr;
      case 'approved':
        return _LocatorSlipStatus.approved;
      case 'cancelled':
        return _LocatorSlipStatus.cancelled;
      case 'rejected_by_department_head':
      case 'rejected_by_hr':
        return _LocatorSlipStatus.rejected;
      default:
        return _LocatorSlipStatus.draft;
    }
  }
}

enum _LocatorSection { requests, approvals }

class _LocatorSectionTabs extends StatelessWidget {
  const _LocatorSectionTabs({required this.current, required this.onChanged});

  final _LocatorSection current;
  final ValueChanged<_LocatorSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _tab(
          context,
          label: 'My Requests',
          icon: Icons.event_note_rounded,
          selected: current == _LocatorSection.requests,
          onTap: () => onChanged(_LocatorSection.requests),
        ),
        _tab(
          context,
          label: 'Approvals / History',
          icon: Icons.fact_check_rounded,
          selected: current == _LocatorSection.approvals,
          onTap: () => onChanged(_LocatorSection.approvals),
        ),
      ],
    );
  }

  Widget _tab(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final dark = AppTheme.dashIsDark(context);
    return Material(
      color: selected
          ? (dark
                ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                : AppTheme.primaryNavy.withValues(alpha: 0.12))
          : (dark
                ? AppTheme.dashMutedSurfaceOf(context)
                : AppTheme.lightGray.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? AppTheme.primaryNavy
                    : AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppTheme.primaryNavy
                      : AppTheme.dashTextPrimaryOf(context),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: child,
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

    return _InfoCard(
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
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  const _CenteredLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.red.shade900, fontSize: 12),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
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

String _formatDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '${_formatDate(value)} $hour:$minute $meridiem';
}

String _apiErrorMessage(Object error, {required String fallback}) {
  if (error is DioException) {
    final responseMessage = _apiResponseMessage(
      error.response?.data,
      fallback: '',
    );
    if (responseMessage.isNotEmpty) return responseMessage;
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return '$fallback $message';
  }
  final text = error.toString().trim();
  if (text.isEmpty) return fallback;
  return '$fallback $text';
}

String _apiResponseMessage(dynamic data, {required String fallback}) {
  if (data is Map) {
    final message = data['error'] ?? data['message'];
    final text = message?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  if (data is String && data.trim().isNotEmpty) return data.trim();
  return fallback;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
  return DateTime.tryParse(raw);
}

DateTime? _parseDateOnly(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

String _departmentHeadStatusLabel(_LocatorSlipDraft item) {
  switch (item.rawStatus) {
    case 'pending_department_head':
      return 'Pending';
    case 'pending_hr':
    case 'pending':
      return 'Forwarded to HR';
    case 'approved':
      return 'Approved by HR';
    case 'rejected_by_hr':
      return 'Rejected by HR';
    case 'rejected_by_department_head':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
  }
  return item.status.label;
}

(Color, Color, Color) _statusColors(_LocatorSlipStatus status) {
  return switch (status) {
    _LocatorSlipStatus.draft => (
      Colors.amber.shade50,
      Colors.amber.shade300,
      Colors.amber.shade900,
    ),
    _LocatorSlipStatus.pendingDepartmentHead || _LocatorSlipStatus.pendingHr =>
      (Colors.blue.shade50, Colors.blue.shade300, Colors.blue.shade900),
    _LocatorSlipStatus.approved => (
      Colors.green.shade50,
      Colors.green.shade300,
      Colors.green.shade900,
    ),
    _LocatorSlipStatus.rejected => (
      Colors.red.shade50,
      Colors.red.shade300,
      Colors.red.shade900,
    ),
    _LocatorSlipStatus.cancelled => (
      Colors.grey.shade100,
      Colors.grey.shade400,
      Colors.grey.shade800,
    ),
  };
}

IconData _locatorStatusIcon(_LocatorSlipStatus status) {
  return switch (status) {
    _LocatorSlipStatus.draft => Icons.edit_note_rounded,
    _LocatorSlipStatus.pendingDepartmentHead =>
      Icons.supervisor_account_rounded,
    _LocatorSlipStatus.pendingHr => Icons.hourglass_top_rounded,
    _LocatorSlipStatus.approved => Icons.check_circle_rounded,
    _LocatorSlipStatus.rejected => Icons.cancel_rounded,
    _LocatorSlipStatus.cancelled => Icons.flag_rounded,
  };
}

IconData _locatorRequestTypeIcon(LocatorRequestType type) {
  return switch (type) {
    LocatorRequestType.locator => Icons.near_me_rounded,
    LocatorRequestType.passSlip => Icons.badge_rounded,
    LocatorRequestType.workFromHome => Icons.home_work_rounded,
  };
}
