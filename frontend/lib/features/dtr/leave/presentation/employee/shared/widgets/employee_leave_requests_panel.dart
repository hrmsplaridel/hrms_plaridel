import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/widgets/employee_leave_desktop_requests_content.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_requests_content.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/history_timeline.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';
import 'package:hrms_plaridel/shared/widgets/request_filters_bar.dart';

const _leaveRequestFilterOptions = <RequestFilterOption<LeaveRequestStatus>>[
  RequestFilterOption(label: 'All'),
  RequestFilterOption(value: LeaveRequestStatus.pending, label: 'Pending'),
  RequestFilterOption(value: LeaveRequestStatus.approved, label: 'Approved'),
  RequestFilterOption(value: LeaveRequestStatus.rejected, label: 'Rejected'),
  RequestFilterOption(value: LeaveRequestStatus.cancelled, label: 'Cancelled'),
];

class EmployeeLeaveRequestsPanel extends StatefulWidget {
  const EmployeeLeaveRequestsPanel({
    super.key,
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
  State<EmployeeLeaveRequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends State<EmployeeLeaveRequestsPanel> {
  late final ScrollController _requestsScrollController;
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

    return _EmployeeRequestsSectionCard(
      title: 'My Requests',
      subtitle: 'Recent leave applications and their current status.',
      icon: Icons.event_note_rounded,
      child: _buildRequestsContent(
        filteredRequests: filteredRequests,
        useScrollableList: useScrollableList,
        maxListHeight: maxListHeight,
        isMobile: isMobile,
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
    required bool isMobile,
  }) {
    final filters = _buildRequestFiltersBar(filteredRequests.length);
    if (!isMobile) {
      return EmployeeLeaveDesktopRequestsContent(
        filters: filters,
        requests: filteredRequests,
        allRequests: widget.requests,
        loading: widget.loading,
        maxListHeight: maxListHeight,
        scrollController: _requestsScrollController,
        onOpenRequest: (request) => _showDetails(context, request),
      );
    }
    return EmployeeLeaveMobileRequestsContent(
      filters: filters,
      requests: filteredRequests,
      allRequests: widget.requests,
      loading: widget.loading,
      useScrollableList: useScrollableList,
      maxListHeight: maxListHeight,
      scrollController: _requestsScrollController,
      onOpenRequest: (request) => _showDetails(context, request),
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
                    if (request.leaveType == LeaveType.adoptionLeave &&
                        request.adoptionParentRole != null)
                      _LeaveDetailTile(
                        icon: Icons.family_restroom_rounded,
                        label: 'Adoption eligibility',
                        value: request.adoptionParentRole!.displayName,
                      ),
                    if (request.leaveType == LeaveType.adoptionLeave &&
                        request.adoptionPlacementDate != null)
                      _LeaveDetailTile(
                        icon: Icons.event_available_rounded,
                        label: 'PAPA / adoption placement date',
                        value: _formatDate(request.adoptionPlacementDate!),
                      ),
                    if (request.leaveType == LeaveType.tenDayVawcLeave &&
                        request.vawcSupportDocumentType != null)
                      _LeaveDetailTile(
                        icon: Icons.verified_user_outlined,
                        label: 'VAWC supporting document',
                        value: request.vawcSupportDocumentType!.displayName,
                      ),
                    if (request.leaveType == LeaveType.tenDayVawcLeave &&
                        (request.vawcCaseDetails ?? '').trim().isNotEmpty)
                      _LeaveDetailTile(
                        icon: Icons.description_outlined,
                        label: 'VAWC case details',
                        value: request.vawcCaseDetails!.trim(),
                      ),
                    if (request.leaveType == LeaveType.soloParentLeave &&
                        (request.soloParentIdNumber ?? '').trim().isNotEmpty)
                      _LeaveDetailTile(
                        icon: Icons.badge_outlined,
                        label: 'Solo Parent ID number',
                        value: request.soloParentIdNumber!.trim(),
                      ),
                    if (request.leaveType == LeaveType.soloParentLeave &&
                        request.soloParentIdExpiryDate != null)
                      _LeaveDetailTile(
                        icon: Icons.event_busy_outlined,
                        label: 'Solo Parent ID expiry',
                        value: _formatDate(request.soloParentIdExpiryDate!),
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

class _EmployeeRequestsSectionCard extends StatelessWidget {
  const _EmployeeRequestsSectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

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
            ],
          ),
          const SizedBox(height: 20),
          child,
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

bool _canEmployeeCancel(LeaveRequest request) {
  return switch (request.status) {
    LeaveRequestStatus.draft ||
    LeaveRequestStatus.pending ||
    LeaveRequestStatus.pendingDepartmentHead ||
    LeaveRequestStatus.pendingHr => true,
    LeaveRequestStatus.approved ||
    LeaveRequestStatus.rejected ||
    LeaveRequestStatus.rejectedByDepartmentHead ||
    LeaveRequestStatus.rejectedByHr ||
    LeaveRequestStatus.returned ||
    LeaveRequestStatus.cancelled => false,
  };
}

String _formatLeaveRequestRange(LeaveRequest request) {
  if (request.startDate == null || request.endDate == null) return '—';
  return '${_formatDate(request.startDate!)} – ${_formatDate(request.endDate!)}';
}
