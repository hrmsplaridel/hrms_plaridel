import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_overlay.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_slip_form_initial_values.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_workflow_event.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_form_widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_request_card.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_request_list.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/open_locator_attachment_io.dart'
    if (dart.library.html) 'package:hrms_plaridel/features/dtr/locator/utils/open_locator_attachment_web.dart'
    as locator_attachment;
import 'package:hrms_plaridel/shared/widgets/hrms_date_picker.dart';
import 'package:hrms_plaridel/shared/widgets/request_filters_bar.dart';

const _locatorSlipFilterOptions = <RequestFilterOption<String>>[
  RequestFilterOption(label: 'All'),
  RequestFilterOption(value: 'pending', label: 'Pending'),
  RequestFilterOption(value: 'returned', label: 'Needs Correction'),
  RequestFilterOption(value: 'approved', label: 'Approved'),
  RequestFilterOption(value: 'revoked', label: 'Revoked'),
  RequestFilterOption(value: 'rejected', label: 'Rejected'),
  RequestFilterOption(value: 'cancelled', label: 'Cancelled'),
];

const _locatorApprovalFilterOptions = <RequestFilterOption<String>>[
  RequestFilterOption(label: 'All'),
  RequestFilterOption(value: 'pending', label: 'Pending'),
  RequestFilterOption(value: 'returned', label: 'Returned'),
  RequestFilterOption(value: 'forwarded', label: 'Forwarded to HR'),
  RequestFilterOption(value: 'approved', label: 'Approved by HR'),
  RequestFilterOption(value: 'revoked', label: 'Revoked'),
  RequestFilterOption(value: 'rejected', label: 'Rejected'),
  RequestFilterOption(value: 'cancelled', label: 'Cancelled'),
];

typedef _LocatorWorkflowStep = ({
  String title,
  String? actor,
  DateTime? date,
  String? remarks,
  bool completed,
});

class EmployeeLocatorSlipContent extends StatefulWidget {
  const EmployeeLocatorSlipContent({
    super.key,
    this.tutorialHeaderKey,
    this.tutorialRequestsKey,
  });

  final GlobalKey? tutorialHeaderKey;
  final GlobalKey? tutorialRequestsKey;

  @override
  State<EmployeeLocatorSlipContent> createState() =>
      EmployeeLocatorSlipContentState();
}

class EmployeeLocatorSlipContentState extends State<EmployeeLocatorSlipContent>
    with WidgetsBindingObserver {
  static const int _historyPageSize = 50;
  static const Duration _reconciliationInterval = Duration(minutes: 2);
  final List<_LocatorSlipDraft> _slips = [];
  final List<_LocatorSlipDraft> _deptHeadQueue = [];
  final ScrollController _myRequestsScrollController = ScrollController();
  final ScrollController _approvalItemsScrollController = ScrollController();
  List<LocatorRequestType> _locatorTypes = const [];
  bool _loadingLocatorTypes = false;
  bool _locatorTypesLoaded = false;
  String? _locatorTypesError;
  Future<bool>? _isDeptHeadFuture;
  LocatorReviewerAccess _reviewerAccess = const LocatorReviewerAccess.none();
  _LocatorSection _currentSection = _LocatorSection.requests;
  bool _appliedDeptHeadDefaultSection = false;
  bool _loadingMy = false;
  bool _loadingApprovals = false;
  bool _myHistoryLoaded = false;
  bool _approvalHistoryLoaded = false;
  bool _loadingMoreMy = false;
  bool _loadingMoreApprovals = false;
  String? _myRequestsError;
  String? _approvalsError;
  String? _myLoadMoreError;
  String? _approvalLoadMoreError;
  String? _selectedStatusFilter;
  String? _selectedApprovalStatusFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _searchQuery = '';
  DateTime? _approvalFromDate;
  DateTime? _approvalToDate;
  String _approvalSearchQuery = '';
  int _myPage = 1;
  int _myPageCount = 1;
  int _myTotal = 0;
  int _approvalPage = 1;
  int _approvalPageCount = 1;
  int _approvalTotal = 0;
  Timer? _myFilterDebounce;
  Timer? _approvalFilterDebounce;
  String? _selectedSlipId;
  String? _selectedApprovalSlipId;
  StreamSubscription<AppRealtimeEvent>? _locatorRealtimeSub;
  AppRealtimeProvider? _realtimeProvider;
  Timer? _reconciliationTimer;
  bool _wasRealtimeConnected = false;
  bool _reconciliationInProgress = false;
  String? _authenticatedUserId;
  String? _authenticatedUserRole;
  DateTime? _officialHrmsDate;
  bool _loadingOfficialDate = false;
  String? _officialDateError;
  int _authGeneration = 0;
  int _myRequestsLoadGeneration = 0;
  int _approvalsLoadGeneration = 0;
  int _officialDateLoadGeneration = 0;
  int _locatorTypesLoadGeneration = 0;

  bool get _locatorTypesReady =>
      _locatorTypesLoaded &&
      !_loadingLocatorTypes &&
      _locatorTypesError == null &&
      _locatorTypes.isNotEmpty;
  bool get _hasMyFilters =>
      _selectedStatusFilter != null ||
      _fromDate != null ||
      _toDate != null ||
      _searchQuery.trim().isNotEmpty;
  bool get _hasApprovalFilters =>
      _selectedApprovalStatusFilter != null ||
      _approvalFromDate != null ||
      _approvalToDate != null ||
      _approvalSearchQuery.trim().isNotEmpty;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  Future<void> openCreateForm({
    LocatorSlipFormInitialValues? initialValues,
  }) async {
    final auth = context.read<AuthProvider>();
    final displayName = auth.displayName.trim().isEmpty
        ? 'Employee'
        : auth.displayName.trim();
    await _openCreateForm(context, displayName, initialValues: initialValues);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reconciliationTimer = Timer.periodic(
      _reconciliationInterval,
      (_) => unawaited(_reconcileLocatorData()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = context.watch<AuthProvider>();
    _synchronizeAuthenticatedUser(authProvider);
    if (_authenticatedUserId != null &&
        !_locatorTypesLoaded &&
        !_loadingLocatorTypes &&
        _locatorTypesError == null) {
      unawaited(_loadLocatorTypes(forceRefresh: true));
    }
    if (_authenticatedUserId != null &&
        !_loadingMy &&
        !_myHistoryLoaded &&
        _myRequestsError == null) {
      unawaited(_loadMyRequests());
    }
    if (_authenticatedUserId != null &&
        _officialHrmsDate == null &&
        !_loadingOfficialDate &&
        _officialDateError == null) {
      unawaited(_loadOfficialDate());
    }
    final realtimeProvider = context.read<AppRealtimeProvider>();
    if (!identical(_realtimeProvider, realtimeProvider)) {
      _realtimeProvider?.removeListener(_handleRealtimeConnectionChanged);
      _realtimeProvider = realtimeProvider;
      _wasRealtimeConnected = realtimeProvider.connected;
      realtimeProvider.addListener(_handleRealtimeConnectionChanged);
    }
    _locatorRealtimeSub ??= realtimeProvider.events.listen((event) {
      if (event.name != 'locator_updated') return;
      final userId = _authenticatedUserId;
      if (event.affectsUser(userId) ||
          _currentSection == _LocatorSection.approvals) {
        unawaited(_reconcileLocatorData());
      }
    });
  }

  void _handleRealtimeConnectionChanged() {
    final connected = _realtimeProvider?.connected == true;
    final reconnected = connected && !_wasRealtimeConnected;
    _wasRealtimeConnected = connected;
    if (reconnected) {
      unawaited(_reconcileLocatorData());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileLocatorData());
    }
  }

  void _synchronizeAuthenticatedUser(AuthProvider authProvider) {
    final normalizedUserId = (authProvider.user?.id ?? '').trim();
    final userId = normalizedUserId.isEmpty ? null : normalizedUserId;
    final normalizedRole = (authProvider.user?.role ?? '').trim().toLowerCase();
    final role = normalizedRole.isEmpty ? null : normalizedRole;
    if (_authenticatedUserId == userId && _authenticatedUserRole == role) {
      return;
    }

    _authenticatedUserId = userId;
    _authenticatedUserRole = role;
    _authGeneration += 1;
    _myRequestsLoadGeneration += 1;
    _approvalsLoadGeneration += 1;
    _officialDateLoadGeneration += 1;
    _locatorTypesLoadGeneration += 1;
    _slips.clear();
    _deptHeadQueue.clear();
    _currentSection = _LocatorSection.requests;
    _appliedDeptHeadDefaultSection = false;
    _loadingMy = false;
    _loadingApprovals = false;
    _myHistoryLoaded = false;
    _approvalHistoryLoaded = false;
    _loadingMoreMy = false;
    _loadingMoreApprovals = false;
    _myLoadMoreError = null;
    _approvalLoadMoreError = null;
    _officialHrmsDate = null;
    _loadingOfficialDate = false;
    _officialDateError = null;
    _locatorTypes = const [];
    _loadingLocatorTypes = false;
    _locatorTypesLoaded = false;
    _locatorTypesError = null;
    _myRequestsError = null;
    _approvalsError = null;
    _selectedStatusFilter = null;
    _selectedApprovalStatusFilter = null;
    _fromDate = null;
    _toDate = null;
    _searchQuery = '';
    _approvalFromDate = null;
    _approvalToDate = null;
    _approvalSearchQuery = '';
    _myPage = 1;
    _myPageCount = 1;
    _myTotal = 0;
    _approvalPage = 1;
    _approvalPageCount = 1;
    _approvalTotal = 0;
    _myFilterDebounce?.cancel();
    _approvalFilterDebounce?.cancel();
    _selectedSlipId = null;
    _selectedApprovalSlipId = null;
    _reviewerAccess = const LocatorReviewerAccess.none();

    final generation = _authGeneration;
    _isDeptHeadFuture = userId == null
        ? Future<bool>.value(false)
        : _checkIsDepartmentHead(
            userId: userId,
            role: role,
            authGeneration: generation,
          );
  }

  bool _isCurrentAuthSession(String userId, int authGeneration) {
    return mounted &&
        _authenticatedUserId == userId &&
        _authGeneration == authGeneration;
  }

  Future<void> _loadOfficialDate({bool forceRefresh = false}) async {
    final userId = _authenticatedUserId;
    if (userId == null) return;
    if (_loadingOfficialDate && !forceRefresh) return;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_officialDateLoadGeneration;
    setState(() {
      _loadingOfficialDate = true;
      _officialDateError = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/context',
      );
      final officialDate = _parseDateOnly(response.data?['official_date']);
      if (officialDate == null) {
        throw const FormatException('Missing official HRMS date');
      }
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _officialDateLoadGeneration) {
        return;
      }
      setState(() => _officialHrmsDate = officialDate);
    } catch (error) {
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _officialDateLoadGeneration) {
        return;
      }
      setState(() {
        _officialDateError = _apiErrorMessage(
          error,
          fallback: 'Could not load the official HRMS date.',
        );
      });
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration) &&
          loadGeneration == _officialDateLoadGeneration) {
        setState(() => _loadingOfficialDate = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconciliationTimer?.cancel();
    _realtimeProvider?.removeListener(_handleRealtimeConnectionChanged);
    _locatorRealtimeSub?.cancel();
    _myFilterDebounce?.cancel();
    _approvalFilterDebounce?.cancel();
    _myRequestsScrollController.dispose();
    _approvalItemsScrollController.dispose();
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
        } else if (_selectedStatusFilter == 'revoked') {
          if (item.status != _LocatorSlipStatus.revoked) return false;
        } else if (_selectedStatusFilter == 'returned') {
          if (item.status != _LocatorSlipStatus.returnedForCorrection) {
            return false;
          }
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
      if (_approvalSearchQuery.trim().isNotEmpty) {
        final query = _approvalSearchQuery.trim().toLowerCase();
        final searchable =
            '${item.employeeName} ${item.requestType.label} ${item.office} ${item.remarks} ${item.status.label}'
                .toLowerCase();
        if (!searchable.contains(query)) return false;
      }
      final matchesStatus = switch (_selectedApprovalStatusFilter) {
        'pending' => item.status == _LocatorSlipStatus.pendingDepartmentHead,
        'forwarded' => item.status == _LocatorSlipStatus.pendingHr,
        'returned' => item.status == _LocatorSlipStatus.returnedForCorrection,
        'approved' => item.status == _LocatorSlipStatus.approved,
        'revoked' => item.status == _LocatorSlipStatus.revoked,
        'rejected' => item.status == _LocatorSlipStatus.rejected,
        'cancelled' => item.status == _LocatorSlipStatus.cancelled,
        _ => true,
      };
      if (!matchesStatus) return false;
      if (_approvalFromDate != null &&
          _dateOnly(item.date).isBefore(_dateOnly(_approvalFromDate!))) {
        return false;
      }
      if (_approvalToDate != null &&
          _dateOnly(item.date).isAfter(_dateOnly(_approvalToDate!))) {
        return false;
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
            KeyedSubtree(
              key: widget.tutorialHeaderKey,
              child: _LocatorHeader(
                employeeName: displayName,
                onCreatePressed: () => _openCreateForm(context, displayName),
                onRefresh: () => _reconcileLocatorData(showConfirmation: true),
                refreshing: _reconciliationInProgress,
                showCreateAction: width >= 1024,
                createEnabled:
                    _officialHrmsDate != null &&
                    !_loadingOfficialDate &&
                    _locatorTypesReady,
              ),
            ),
            if (_loadingLocatorTypes && !_locatorTypesLoaded) ...[
              const SizedBox(height: 12),
              const _ReferenceDataLoadingState(
                message: 'Loading locator request types...',
              ),
            ],
            if (_locatorTypesError != null) ...[
              const SizedBox(height: 12),
              _ErrorState(
                message: _locatorTypesError!,
                onRetry: () => _loadLocatorTypes(forceRefresh: true),
              ),
            ],
            if (_officialDateError != null) ...[
              const SizedBox(height: 12),
              _ErrorState(
                message:
                    'Official HRMS date is unavailable. Filing is temporarily disabled.',
                onRetry: () => _loadOfficialDate(forceRefresh: true),
              ),
            ],
            if (isDepartmentHead) ...[
              const SizedBox(height: 16),
              _LocatorSectionTabs(
                current: _currentSection,
                onChanged: (section) {
                  setState(() => _currentSection = section);
                  if (section == _LocatorSection.approvals &&
                      !_approvalHistoryLoaded &&
                      !_loadingApprovals &&
                      _approvalsError == null) {
                    _loadDepartmentHeadRequests();
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            if (_currentSection == _LocatorSection.requests)
              KeyedSubtree(
                key: widget.tutorialRequestsKey,
                child: _buildMyRequests(width: width, compact: compact),
              ),
            if (_currentSection == _LocatorSection.approvals)
              KeyedSubtree(
                key: widget.tutorialRequestsKey,
                child: _buildApprovalsView(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMyRequests({required double width, required bool compact}) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxListHeight = width < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : width < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final visibleSlips = _filteredSlips;
    final useScrollableList = visibleSlips.length > 3;

    return _SectionCard(
      title: 'My Locator Requests',
      subtitle:
          'Use filters to quickly find requests by status, date, type, office, or reason.',
      icon: Icons.receipt_long_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RequestFiltersBar<String>(
            options: _locatorSlipFilterOptions,
            selectedValue: _selectedStatusFilter,
            fromDate: _fromDate,
            toDate: _toDate,
            searchQuery: _searchQuery,
            visibleCount: visibleSlips.length,
            totalCount: _myTotal,
            onStatusChanged: _onMyStatusChanged,
            onSearchChanged: _onMySearchChanged,
            onPickFromDate: () => _pickFilterDate(isFrom: true),
            onPickToDate: () => _pickFilterDate(isFrom: false),
            onClearFilters: _clearFilters,
            formatDate: _formatDate,
          ),
          const SizedBox(height: 16),
          if (_myRequestsError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ErrorState(
                message: _myRequestsError!,
                onRetry: () => _loadMyRequests(forceRefresh: true),
              ),
            ),
          if (_loadingMy)
            const _CenteredLoading(message: 'Loading locator requests...')
          else if (_myHistoryLoaded &&
              _slips.isEmpty &&
              _myRequestsError == null)
            _EmptyState(
              message: _hasMyFilters
                  ? 'No locator requests match the current filters.'
                  : 'No locator requests yet. Click "File Request" to create one.',
            )
          else if (_slips.isNotEmpty) ...[
            _myRequestsTable(
              items: visibleSlips,
              maxHeight: maxListHeight,
              useScrollableList: useScrollableList,
            ),
            if (_myPage < _myPageCount ||
                _loadingMoreMy ||
                _myLoadMoreError != null) ...[
              const SizedBox(height: 14),
              _LoadMoreHistoryControl(
                loaded: _slips.length,
                total: _myTotal,
                loading: _loadingMoreMy,
                error: _myLoadMoreError,
                onPressed: () => _loadMyRequests(loadMore: true),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _openSlipDetails(_LocatorSlipDraft item) {
    setState(() => _selectedSlipId = _slipSelectionKey(item));
    _showSlipDetails(context, item);
  }

  void _openApprovalDetails(_LocatorSlipDraft item) {
    setState(() => _selectedApprovalSlipId = _slipSelectionKey(item));
    _showSlipDetails(
      context,
      item,
      reviewMode: _reviewerAccess.canReviewPending,
    );
  }

  String _slipSelectionKey(_LocatorSlipDraft item) {
    return item.id ??
        '${item.date.toIso8601String()}-${item.requestType.code}-${item.office}-${item.employeeName}-${item.remarks}';
  }

  bool _canCancelSlip(_LocatorSlipDraft? item) {
    final id = item?.id?.trim();
    if (item == null || id == null || id.isEmpty) return false;
    return item.status == _LocatorSlipStatus.pendingDepartmentHead ||
        item.status == _LocatorSlipStatus.pendingHr ||
        item.status == _LocatorSlipStatus.returnedForCorrection;
  }

  void _showSlipDetails(
    BuildContext context,
    _LocatorSlipDraft item, {
    bool reviewMode = false,
  }) {
    final (statusBg, statusBorder, statusText) = _statusColors(item.status);
    final statusSubtitle = item.updatedAt != null
        ? 'Updated ${_formatDateTime(item.updatedAt!)}'
        : item.createdAt != null
        ? 'Filed ${_formatDateTime(item.createdAt!)}'
        : 'Current workflow status';
    final canReview =
        reviewMode && item.status == _LocatorSlipStatus.pendingDepartmentHead;
    final officialDate = _officialHrmsDate;
    final requestIsPast =
        officialDate != null &&
        _dateOnly(item.date).isBefore(_dateOnly(officialDate));
    final returnBlockedByPastDate = canReview && requestIsPast;
    final canReturnForCorrection =
        canReview && officialDate != null && !returnBlockedByPastDate;
    final isReturnedForCorrection =
        !reviewMode && item.status == _LocatorSlipStatus.returnedForCorrection;
    final correctionBlockedByPastDate =
        isReturnedForCorrection && requestIsPast;
    final canCorrect =
        isReturnedForCorrection &&
        officialDate != null &&
        _locatorTypesReady &&
        !correctionBlockedByPastDate;
    final datePolicyUnavailable =
        (canReview || isReturnedForCorrection) && officialDate == null;
    final typeConfigurationUnavailable =
        isReturnedForCorrection && !_locatorTypesReady;
    final correctionRemarks = item.hrReviewedAt != null
        ? item.hrRemarks
        : item.departmentHeadRemarks;

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

    unawaited(
      openResponsiveRightSidePanel<void>(
        context: context,
        barrierLabel: reviewMode
            ? 'Close locator approval details'
            : 'Close locator request details',
        breakpoint: 900,
        minWidth: 620,
        initialWidthFraction: 0.5,
        builder: (dialogContext) => EmployeeLocatorMobileDetailsDialog(
          requestTypeLabel: item.requestType.label,
          dateLabel: _formatDate(item.date),
          requestTypeIcon: _locatorRequestTypeIcon(item.requestType),
          statusLabel: item.status.label,
          statusIcon: _locatorStatusIcon(item.status),
          statusBg: statusBg,
          statusBorder: statusBorder,
          statusText: statusText,
          onClose: () => Navigator.of(dialogContext).pop(),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmployeeLocatorMobileDetailSection(
                title: 'Slip Information',
                icon: Icons.receipt_long_rounded,
                children: [
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: _formatDate(item.date),
                  ),
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.category_rounded,
                    label: 'Type',
                    value: item.requestType.label,
                  ),
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.place_rounded,
                    label: item.requestType.locationLabel,
                    value: item.office.trim().isEmpty
                        ? 'Not specified'
                        : item.office.trim(),
                  ),
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.schedule_rounded,
                    label: 'Time Segments',
                    value: _approvalSegmentsText(item),
                  ),
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.attach_file_rounded,
                    label: 'Attachment',
                    value: (item.attachmentName ?? '').trim().isEmpty
                        ? 'None'
                        : item.attachmentName!.trim(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              EmployeeLocatorMobileStatusPanel(
                statusLabel: item.status.label,
                statusIcon: _locatorStatusIcon(item.status),
                statusSubtitle: statusSubtitle,
                statusBg: statusBg,
                statusBorder: statusBorder,
                statusText: statusText,
              ),
              const SizedBox(height: 12),
              EmployeeLocatorMobileReasonPanel(
                text: item.remarks.trim().isEmpty
                    ? 'No reason provided.'
                    : item.remarks.trim(),
              ),
              if (returnBlockedByPastDate) ...[
                const SizedBox(height: 12),
                const EmployeeLocatorMobileDetailSection(
                  title: 'Correction unavailable',
                  icon: Icons.event_busy_rounded,
                  children: [
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Past-dated request',
                      value:
                          'This request can no longer be returned to the employee. Approve or reject it, or ask HR to use Record Correction.',
                    ),
                  ],
                ),
              ],
              if (correctionBlockedByPastDate) ...[
                const SizedBox(height: 12),
                const EmployeeLocatorMobileDetailSection(
                  title: 'Correction unavailable',
                  icon: Icons.event_busy_rounded,
                  children: [
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Past-dated request',
                      value:
                          'This returned request can no longer be corrected or moved to another date. Cancel it or contact HR for Record Correction.',
                    ),
                  ],
                ),
              ],
              if (datePolicyUnavailable) ...[
                const SizedBox(height: 12),
                const EmployeeLocatorMobileDetailSection(
                  title: 'Return temporarily unavailable',
                  icon: Icons.sync_problem_rounded,
                  children: [
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Official date unavailable',
                      value:
                          'Reload the page before returning this request for correction.',
                    ),
                  ],
                ),
              ],
              if (typeConfigurationUnavailable) ...[
                const SizedBox(height: 12),
                const EmployeeLocatorMobileDetailSection(
                  title: 'Correction temporarily unavailable',
                  icon: Icons.sync_problem_rounded,
                  children: [
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Request types unavailable',
                      value:
                          'Reload the page and retry loading locator request types before correcting this request.',
                    ),
                  ],
                ),
              ],
              if (canCorrect) ...[
                const SizedBox(height: 12),
                EmployeeLocatorMobileDetailSection(
                  title: 'Correction Requested',
                  icon: Icons.assignment_return_rounded,
                  children: [
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.rate_review_outlined,
                      label: 'Reviewer remarks',
                      value: (correctionRemarks ?? '').trim().isEmpty
                          ? 'Please replace or restore the required attachment.'
                          : correctionRemarks!.trim(),
                    ),
                  ],
                ),
              ],
              if (item.status == _LocatorSlipStatus.revoked) ...[
                const SizedBox(height: 12),
                EmployeeLocatorMobileDetailSection(
                  title: 'Approval Revoked',
                  icon: Icons.undo_rounded,
                  children: [
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.person_outline_rounded,
                      label: 'Revoked by',
                      value: (item.revokedByName ?? '').trim().isEmpty
                          ? 'HR/Admin'
                          : item.revokedByName!.trim(),
                    ),
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.schedule_rounded,
                      label: 'Revoked at',
                      value: item.revokedAt == null
                          ? 'Not recorded'
                          : _formatDateTime(item.revokedAt!),
                    ),
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.rate_review_outlined,
                      label: 'Reason',
                      value: (item.revocationReason ?? '').trim().isEmpty
                          ? 'No reason recorded.'
                          : item.revocationReason!.trim(),
                    ),
                    if (item.monthEndReconciliationRequired)
                      const EmployeeLocatorMobileDetailTile(
                        icon: Icons.sync_problem_rounded,
                        label: 'DTR reconciliation',
                        value:
                            'HR must rerun month-end processing for this month.',
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: EmployeeLocatorMobileDetailActions(
            canCancel: !reviewMode && _canCancelSlip(item),
            canPrint: item.status == _LocatorSlipStatus.approved,
            canOpenAttachment:
                item.id?.trim().isNotEmpty == true &&
                item.attachmentName?.trim().isNotEmpty == true,
            canReject: canReview,
            canApprove: canReview,
            canReturn: canReturnForCorrection,
            canCorrect: canCorrect,
            onHistory: () {
              Navigator.of(dialogContext).pop();
              _showSlipHistory(context, item);
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
              _cancelSlip(item);
            },
            onPrint: printForm,
            onOpenAttachment: () => _openAttachment(item),
            onReject: () {
              Navigator.of(dialogContext).pop();
              _departmentHeadReject(item);
            },
            onApprove: () {
              Navigator.of(dialogContext).pop();
              _departmentHeadApprove(item);
            },
            onReturn: () {
              Navigator.of(dialogContext).pop();
              _departmentHeadReturn(item);
            },
            onCorrect: () {
              Navigator.of(dialogContext).pop();
              _correctAndResubmit(item);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showSlipHistory(
    BuildContext context,
    _LocatorSlipDraft item,
  ) async {
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    final history = <_LocatorWorkflowStep>[];

    final slipId = item.id?.trim();
    if (slipId == null || slipId.isEmpty) {
      _showLocatorSnack('Official workflow history is not available yet.');
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (loadingContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Loading official workflow history...',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(loadingContext),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final response = await ApiClient.instance.get<List<dynamic>>(
        '/api/locator-slips/$slipId/history',
      );
      final events = (response.data ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (json) =>
                LocatorWorkflowEvent.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
      if (events.isNotEmpty) {
        history
          ..clear()
          ..addAll(
            events.map(
              (event) => (
                title: event.title,
                actor: event.actorName,
                date: event.createdAt,
                remarks: event.remarks,
                completed: true,
              ),
            ),
          );
      }
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted || !_isCurrentAuthSession(userId, authGeneration)) {
        return;
      }
      final retry = await showDialog<bool>(
        context: context,
        builder: (errorContext) => AlertDialog(
          title: const Text('History unavailable'),
          content: Text(
            _apiErrorMessage(
              error,
              fallback: 'Could not load the official workflow history.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(errorContext).pop(false),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(errorContext).pop(true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
      if (retry == true &&
          context.mounted &&
          _isCurrentAuthSession(userId, authGeneration)) {
        await _showSlipHistory(context, item);
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted || !_isCurrentAuthSession(userId, authGeneration)) {
      return;
    }
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
                    children: history.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Text(
                                'No official workflow events were recorded for this request.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _mutedColor(dialogContext),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ]
                        : List.generate(history.length, (index) {
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
                                          child: Container(
                                            width: 4,
                                            color: accent,
                                          ),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            step.title,
                                            style: TextStyle(
                                              color: _headingColor(
                                                dialogContext,
                                              ),
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
                                          if ((step.remarks ?? '')
                                              .trim()
                                              .isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                step.remarks!.trim(),
                                                style: TextStyle(
                                                  color: _mutedColor(
                                                    dialogContext,
                                                  ),
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

    return _SectionCard(
      title: 'Locator Requests & History',
      subtitle:
          'Review pending locator, pass slip, and work-from-home requests.',
      icon: Icons.fact_check_rounded,
      child: _loadingApprovals
          ? const _CenteredLoading(message: 'Loading approval queue...')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RequestFiltersBar<String>(
                  options: _locatorApprovalFilterOptions,
                  selectedValue: _selectedApprovalStatusFilter,
                  fromDate: _approvalFromDate,
                  toDate: _approvalToDate,
                  searchQuery: _approvalSearchQuery,
                  visibleCount: visibleItems.length,
                  totalCount: _approvalTotal,
                  onStatusChanged: _onApprovalStatusChanged,
                  onSearchChanged: _onApprovalSearchChanged,
                  onPickFromDate: () =>
                      _pickFilterDate(isFrom: true, approval: true),
                  onPickToDate: () =>
                      _pickFilterDate(isFrom: false, approval: true),
                  onClearFilters: _clearApprovalFilters,
                  formatDate: _formatDate,
                ),
                const SizedBox(height: 16),
                if (_approvalsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ErrorState(
                      message: _approvalsError!,
                      onRetry: () =>
                          _loadDepartmentHeadRequests(forceRefresh: true),
                    ),
                  ),
                if (_approvalHistoryLoaded &&
                    _deptHeadQueue.isEmpty &&
                    _approvalsError == null)
                  _EmptyState(
                    message: _hasApprovalFilters
                        ? 'No locator requests match the current filters.'
                        : 'No locator requests or history yet.',
                  )
                else if (_approvalHistoryLoaded &&
                    _approvalsError == null &&
                    visibleItems.isEmpty)
                  const _EmptyState(
                    message: 'No locator requests match the current filter.',
                  )
                else if (_deptHeadQueue.isNotEmpty) ...[
                  _approvalItemsTable(
                    items: visibleItems,
                    maxHeight: maxListHeight,
                    useScrollableList: useScrollableList,
                  ),
                  if (_approvalPage < _approvalPageCount ||
                      _loadingMoreApprovals ||
                      _approvalLoadMoreError != null) ...[
                    const SizedBox(height: 14),
                    _LoadMoreHistoryControl(
                      loaded: _deptHeadQueue.length,
                      total: _approvalTotal,
                      loading: _loadingMoreApprovals,
                      error: _approvalLoadMoreError,
                      onPressed: () =>
                          _loadDepartmentHeadRequests(loadMore: true),
                    ),
                  ],
                ],
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
                  onTap: () => _openSlipDetails(items[index]),
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
            controller: _myRequestsScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _myRequestsScrollController,
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
    return EmployeeLocatorMobileRequestList(
      maxHeight: maxHeight,
      useScrollableList: useScrollableList,
      scrollController: _myRequestsScrollController,
      children: List.generate(items.length, (index) {
        final item = items[index];
        return EmployeeLocatorMobileRequestCard(
          title: item.requestType.label,
          dateLabel: _formatDate(item.date),
          office: item.office,
          remarks: item.remarks,
          isSelected: _slipSelectionKey(item) == _selectedSlipId,
          segmentsText: _approvalSegmentsText(item),
          typeLabel: item.requestType.shortLabel,
          statusPill: _myRequestStatusPill(item),
          onTap: () => _openSlipDetails(item),
        );
      }),
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
    if (MediaQuery.sizeOf(context).width < 600) {
      return _approvalItemsMobileList(
        items: items,
        maxHeight: maxHeight,
        useScrollableList: useScrollableList,
      );
    }

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
                  onTap: () => _openApprovalDetails(items[index]),
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
            controller: _approvalItemsScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _approvalItemsScrollController,
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

  Widget _approvalItemsMobileList({
    required List<_LocatorSlipDraft> items,
    required double maxHeight,
    required bool useScrollableList,
  }) {
    // Keep the approval cards in the page's primary scroll view on mobile.
    // A second, height-limited list makes the last cards sit behind the FAB.
    return EmployeeLocatorMobileRequestList(
      maxHeight: maxHeight,
      useScrollableList: false,
      gap: 8,
      children: [
        for (final item in items)
          EmployeeLocatorMobileRequestCard(
            title: item.employeeName,
            dateLabel: _formatDate(item.date),
            office: item.office,
            remarks: item.remarks,
            segmentsText: _approvalSegmentsText(item),
            typeLabel: item.requestType.shortLabel,
            statusPill: _approvalStatusPill(item),
            isSelected: _slipSelectionKey(item) == _selectedApprovalSlipId,
            onTap: () => _openApprovalDetails(item),
          ),
      ],
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

  Future<void> _openCreateForm(
    BuildContext context,
    String employeeName, {
    LocatorSlipFormInitialValues? initialValues,
  }) async {
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    final typesReady = await _refreshLocatorTypesForForm(
      context,
      userId: userId,
      authGeneration: authGeneration,
    );
    if (!typesReady || !context.mounted) {
      return;
    }
    final officialDate = _officialHrmsDate;
    if (officialDate == null) {
      if (!_loadingOfficialDate) {
        unawaited(_loadOfficialDate(forceRefresh: true));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for the official HRMS date, then try again.'),
        ),
      );
      return;
    }
    final form = _LocatorSlipFormDialog(
      employeeName: employeeName,
      requestTypes: _locatorTypes,
      officialDate: officialDate,
      initialValues: initialValues,
    );
    final created = await openResponsiveRightSidePanel<_LocatorSlipDraft>(
      context: context,
      barrierLabel: 'Close locator request form',
      minWidth: 520,
      initialWidthFraction: 0.38,
      builder: (_) =>
          EmployeeHrmsAssistantOverlay(initialBottom: 92, child: form),
    );
    if (created == null || !_isCurrentAuthSession(userId, authGeneration)) {
      return;
    }
    setState(() {
      _myRequestsError = null;
      _loadingMy = true;
    });
    try {
      final payload = {
        'slip_date': _toIsoDate(created.date),
        'am_in': created.amIn,
        'am_out': created.amOut,
        'pm_in': created.pmIn,
        'pm_out': created.pmOut,
        'request_type': created.requestType.code,
        'office': created.office,
        'reason': created.remarks,
      };
      final attachmentBytes = created.pendingAttachmentBytes;
      final attachmentName = created.pendingAttachmentName?.trim();
      final hasAttachment =
          attachmentBytes != null &&
          attachmentName != null &&
          attachmentName.isNotEmpty;
      final Response<Map<String, dynamic>> res;
      if (hasAttachment) {
        res = await ApiClient.instance.dio.post<Map<String, dynamic>>(
          '/api/locator-slips/submit-with-attachment',
          data: FormData.fromMap({
            ...payload.map((key, value) => MapEntry(key, value.toString())),
            'file': MultipartFile.fromBytes(
              attachmentBytes,
              filename: attachmentName,
            ),
          }),
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );
      } else {
        res = await ApiClient.instance.post<Map<String, dynamic>>(
          '/api/locator-slips/submit',
          data: payload,
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );
      }
      if ((res.statusCode ?? 500) >= 400) {
        if (!_isCurrentAuthSession(userId, authGeneration)) return;
        final message = _apiResponseMessage(
          res.data,
          fallback: 'Failed to submit request.',
        );
        setState(() => _loadingMy = false);
        await _showLocatorErrorDialog(message);
        return;
      }
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      final data = res.data;
      LocatorSlipDataCache.instance.invalidateRequests();
      _LocatorSlipDraft? inserted;
      if (data != null) {
        inserted = _LocatorSlipDraft.fromApi(data);
        setState(() => _slips.insert(0, inserted!));
      }
      final msg = inserted != null
          ? (inserted.status == _LocatorSlipStatus.pendingHr
                ? 'Request submitted. Awaiting HR approval.'
                : 'Request submitted. Awaiting department head approval.')
          : 'Request submitted successfully.';
      _showLocatorSnack(msg);
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      final message = _apiErrorMessage(
        e,
        fallback: 'Failed to submit request.',
      );
      setState(() => _loadingMy = false);
      await _showLocatorErrorDialog(message);
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration)) {
        setState(() => _loadingMy = false);
      }
    }
  }

  Future<void> _cancelSlip(_LocatorSlipDraft item) async {
    if (!_canCancelSlip(item)) return;
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
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
    if (ok != true || !_isCurrentAuthSession(userId, authGeneration)) return;

    setState(() {
      _myRequestsError = null;
      _loadingMy = true;
    });
    try {
      final res = await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/$id/cancel',
        data: const {},
      );
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      LocatorSlipDataCache.instance.invalidateRequests();
      final data = res.data;
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
      await _loadMyRequests(forceRefresh: true);
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      _showLocatorSnack('Request cancelled.');
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      setState(
        () => _myRequestsError = _apiErrorMessage(
          e,
          fallback: 'Failed to cancel request.',
        ),
      );
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration)) {
        setState(() => _loadingMy = false);
      }
    }
  }

  Future<bool> _checkIsDepartmentHead({
    required String userId,
    required String? role,
    required int authGeneration,
  }) async {
    try {
      final access = await LocatorSlipDataCache.instance
          .checkDepartmentHeadAccess(userId: userId, role: role);
      if (!_isCurrentAuthSession(userId, authGeneration)) return false;
      _reviewerAccess = access;
      if (access.canAccessReviewSection) {
        unawaited(_loadDepartmentHeadRequests());
      }
      return access.canAccessReviewSection;
    } catch (_) {
      return false;
    }
  }

  Future<void> _reconcileLocatorData({bool showConfirmation = false}) async {
    if (!mounted || _authenticatedUserId == null || _reconciliationInProgress) {
      return;
    }
    setState(() => _reconciliationInProgress = true);
    LocatorSlipDataCache.instance.invalidateRequests();
    try {
      final refreshes = <Future<void>>[
        _loadMyRequests(forceRefresh: true),
        if (_reviewerAccess.canAccessReviewSection)
          _loadDepartmentHeadRequests(forceRefresh: true),
      ];
      await Future.wait(refreshes);
      if (showConfirmation &&
          mounted &&
          _myRequestsError == null &&
          (!_reviewerAccess.canAccessReviewSection ||
              _approvalsError == null)) {
        _showLocatorSnack('Locator requests refreshed.');
      }
    } finally {
      if (mounted) {
        setState(() => _reconciliationInProgress = false);
      }
    }
  }

  Future<void> _loadLocatorTypes({bool forceRefresh = false}) async {
    final userId = _authenticatedUserId;
    if (userId == null) return;
    if (_loadingLocatorTypes && !forceRefresh) return;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_locatorTypesLoadGeneration;
    setState(() {
      _loadingLocatorTypes = true;
      _locatorTypesError = null;
    });
    try {
      final items = (await LocatorSlipDataCache.instance.listTypes(
        forceRefresh: forceRefresh,
      )).where((type) => type.isActive).toList();
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _locatorTypesLoadGeneration) {
        return;
      }
      setState(() {
        _locatorTypes = items;
        _locatorTypesLoaded = true;
        if (items.isEmpty) {
          _locatorTypesError =
              'No active locator request types are configured. Contact HR before filing.';
        }
      });
    } catch (error) {
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _locatorTypesLoadGeneration) {
        return;
      }
      setState(() {
        _locatorTypes = const [];
        _locatorTypesLoaded = false;
        _locatorTypesError = _apiErrorMessage(
          error,
          fallback: 'Could not load locator request types.',
        );
      });
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration) &&
          loadGeneration == _locatorTypesLoadGeneration) {
        setState(() => _loadingLocatorTypes = false);
      }
    }
  }

  Future<bool> _refreshLocatorTypesForForm(
    BuildContext context, {
    required String userId,
    required int authGeneration,
  }) async {
    if (_loadingLocatorTypes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for locator request types, then try again.'),
        ),
      );
      return false;
    }
    await _loadLocatorTypes(forceRefresh: true);
    if (!_isCurrentAuthSession(userId, authGeneration)) return false;
    if (_locatorTypesReady) return true;
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _locatorTypesError ?? 'Locator request types are unavailable.',
        ),
      ),
    );
    return false;
  }

  Map<String, String> _myHistoryQuery(int page) => {
    'page': '$page',
    'page_size': '$_historyPageSize',
    if (_selectedStatusFilter != null) 'status': _selectedStatusFilter!,
    if (_fromDate != null) 'from': _toIsoDate(_fromDate!),
    if (_toDate != null) 'to': _toIsoDate(_toDate!),
    if (_searchQuery.trim().isNotEmpty) 'search': _searchQuery.trim(),
  };

  Map<String, String> _approvalHistoryQuery(int page) => {
    'page': '$page',
    'page_size': '$_historyPageSize',
    if (_selectedApprovalStatusFilter != null)
      'status': _selectedApprovalStatusFilter!,
    if (_approvalFromDate != null) 'from': _toIsoDate(_approvalFromDate!),
    if (_approvalToDate != null) 'to': _toIsoDate(_approvalToDate!),
    if (_approvalSearchQuery.trim().isNotEmpty)
      'search': _approvalSearchQuery.trim(),
  };

  void _mergeLocatorPage(
    List<_LocatorSlipDraft> target,
    List<_LocatorSlipDraft> incoming, {
    required bool append,
  }) {
    if (!append) {
      target
        ..clear()
        ..addAll(incoming);
      return;
    }
    final existingIds = target
        .map((item) => item.id?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final item in incoming) {
      final id = item.id?.trim();
      if (id == null || id.isEmpty || existingIds.add(id)) {
        target.add(item);
      }
    }
  }

  void _onMyStatusChanged(String? value) {
    setState(() {
      _selectedStatusFilter = value;
      _selectedSlipId = null;
    });
    unawaited(_loadMyRequests(forceRefresh: true));
  }

  void _onMySearchChanged(String value) {
    final normalized = value.length > 100 ? value.substring(0, 100) : value;
    setState(() => _searchQuery = normalized);
    _myFilterDebounce?.cancel();
    _myFilterDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_loadMyRequests(forceRefresh: true));
    });
  }

  void _onApprovalStatusChanged(String? value) {
    setState(() {
      _selectedApprovalStatusFilter = value;
      _selectedApprovalSlipId = null;
    });
    unawaited(_loadDepartmentHeadRequests(forceRefresh: true));
  }

  void _onApprovalSearchChanged(String value) {
    final normalized = value.length > 100 ? value.substring(0, 100) : value;
    setState(() => _approvalSearchQuery = normalized);
    _approvalFilterDebounce?.cancel();
    _approvalFilterDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        unawaited(_loadDepartmentHeadRequests(forceRefresh: true));
      }
    });
  }

  Future<void> _loadMyRequests({
    bool forceRefresh = false,
    bool loadMore = false,
  }) async {
    final userId = _authenticatedUserId;
    if (userId == null) return;
    if (loadMore && (_loadingMoreMy || _loadingMy || _myPage >= _myPageCount)) {
      return;
    }
    final role = _authenticatedUserRole;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_myRequestsLoadGeneration;
    final requestedPage = loadMore ? _myPage + 1 : 1;
    setState(() {
      if (loadMore) {
        _loadingMoreMy = true;
        _myLoadMoreError = null;
      } else {
        _loadingMy = true;
        _loadingMoreMy = false;
        _myLoadMoreError = null;
        _myRequestsError = null;
      }
    });
    try {
      final page = await LocatorSlipDataCache.instance.listMyRequests(
        userId: userId,
        role: role,
        query: _myHistoryQuery(requestedPage),
        forceRefresh: forceRefresh,
      );
      final items = page.items
          .map((item) => _LocatorSlipDraft.fromApi(item))
          .toList();
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _myRequestsLoadGeneration) {
        return;
      }
      setState(() {
        _mergeLocatorPage(_slips, items, append: loadMore);
        _myPage = page.page;
        _myPageCount = page.pageCount;
        _myTotal = page.total;
        _myHistoryLoaded = true;
      });
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _myRequestsLoadGeneration) {
        return;
      }
      final message = _apiErrorMessage(
        e,
        fallback: loadMore
            ? 'Failed to load more locator requests.'
            : 'Failed to load locator requests.',
      );
      setState(() {
        if (loadMore) {
          _myLoadMoreError = message;
        } else {
          _myRequestsError = message;
        }
      });
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration) &&
          loadGeneration == _myRequestsLoadGeneration) {
        setState(() {
          if (loadMore) {
            _loadingMoreMy = false;
          } else {
            _loadingMy = false;
          }
        });
      }
    }
  }

  Future<void> _loadDepartmentHeadRequests({
    bool forceRefresh = false,
    bool loadMore = false,
  }) async {
    final userId = _authenticatedUserId;
    if (userId == null) return;
    if (loadMore &&
        (_loadingMoreApprovals ||
            _loadingApprovals ||
            _approvalPage >= _approvalPageCount)) {
      return;
    }
    final role = _authenticatedUserRole;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_approvalsLoadGeneration;
    final requestedPage = loadMore ? _approvalPage + 1 : 1;
    setState(() {
      if (loadMore) {
        _loadingMoreApprovals = true;
        _approvalLoadMoreError = null;
      } else {
        _loadingApprovals = true;
        _loadingMoreApprovals = false;
        _approvalLoadMoreError = null;
        _approvalsError = null;
      }
    });
    try {
      final page = await LocatorSlipDataCache.instance
          .listDepartmentHeadRequests(
            userId: userId,
            role: role,
            query: _approvalHistoryQuery(requestedPage),
            forceRefresh: forceRefresh,
          );
      final items = page.items
          .map((item) => _LocatorSlipDraft.fromApi(item))
          .toList();
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _approvalsLoadGeneration) {
        return;
      }
      setState(() {
        _mergeLocatorPage(_deptHeadQueue, items, append: loadMore);
        _approvalPage = page.page;
        _approvalPageCount = page.pageCount;
        _approvalTotal = page.total;
        _approvalHistoryLoaded = true;
      });
    } catch (error) {
      if (!_isCurrentAuthSession(userId, authGeneration) ||
          loadGeneration != _approvalsLoadGeneration) {
        return;
      }
      final message = _apiErrorMessage(
        error,
        fallback: loadMore
            ? 'Failed to load more approval history.'
            : 'Failed to load approval history.',
      );
      setState(() {
        if (loadMore) {
          _approvalLoadMoreError = message;
        } else {
          _approvalsError = message;
        }
      });
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration) &&
          loadGeneration == _approvalsLoadGeneration) {
        setState(() {
          if (loadMore) {
            _loadingMoreApprovals = false;
          } else {
            _loadingApprovals = false;
          }
        });
      }
    }
  }

  Future<void> _departmentHeadApprove(_LocatorSlipDraft item) async {
    if (item.id == null || item.id!.isEmpty) return;
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/department-head-approve',
        data: const {},
      );
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      LocatorSlipDataCache.instance.invalidateRequests();
      await _loadDepartmentHeadRequests(forceRefresh: true);
      await _loadMyRequests(forceRefresh: true);
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      _showLocatorSnack('Approved and sent to HR for final approval.');
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      setState(
        () =>
            _approvalsError = _apiErrorMessage(e, fallback: 'Approve failed.'),
      );
    }
  }

  Future<void> _departmentHeadReject(_LocatorSlipDraft item) async {
    if (item.id == null || item.id!.isEmpty) return;
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    final reason = await _promptRejectionReason('Department Head');
    if (reason == null || !_isCurrentAuthSession(userId, authGeneration)) {
      return;
    }
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/department-head-reject',
        data: {'reviewer_remarks': reason},
      );
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      LocatorSlipDataCache.instance.invalidateRequests();
      await _loadDepartmentHeadRequests(forceRefresh: true);
      await _loadMyRequests(forceRefresh: true);
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      _showLocatorSnack('Request rejected.');
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      setState(
        () => _approvalsError = _apiErrorMessage(e, fallback: 'Reject failed.'),
      );
    }
  }

  Future<String?> _promptRejectionReason(String reviewerLabel) async {
    final controller = TextEditingController();
    String? validationMessage;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reject locator request'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Rejection reason',
              hintText: 'Explain why this request cannot be approved.',
              helperText: 'The employee will see this reason.',
              errorText: validationMessage,
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(
                    () => validationMessage = 'Rejection reason is required.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              icon: const Icon(Icons.block_rounded, size: 18),
              label: Text('Reject as $reviewerLabel'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<String?> _promptCorrectionRemarks() async {
    final controller = TextEditingController();
    final remarks = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Return for correction'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Correction remarks',
            hintText: 'State what the employee needs to correct.',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            icon: const Icon(Icons.assignment_return_rounded, size: 18),
            label: const Text('Return'),
          ),
        ],
      ),
    );
    controller.dispose();
    return remarks;
  }

  Future<void> _departmentHeadReturn(_LocatorSlipDraft item) async {
    final id = item.id?.trim();
    if (id == null || id.isEmpty) return;
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    final remarks = await _promptCorrectionRemarks();
    if (remarks == null || !_isCurrentAuthSession(userId, authGeneration)) {
      return;
    }
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/$id/department-head-return',
        data: {'reviewer_remarks': remarks},
      );
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      LocatorSlipDataCache.instance.invalidateRequests();
      await _loadDepartmentHeadRequests(forceRefresh: true);
      await _loadMyRequests(forceRefresh: true);
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      _showLocatorSnack('Request returned to the employee for correction.');
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      await _showLocatorErrorDialog(
        _apiErrorMessage(e, fallback: 'Failed to return the request.'),
      );
    }
  }

  Future<void> _correctAndResubmit(_LocatorSlipDraft item) async {
    final id = item.id?.trim();
    if (id == null || id.isEmpty) return;
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    final typesReady = await _refreshLocatorTypesForForm(
      context,
      userId: userId,
      authGeneration: authGeneration,
    );
    if (!typesReady || !mounted) {
      return;
    }
    final officialDate = _officialHrmsDate;
    if (officialDate == null) {
      if (!_loadingOfficialDate) {
        unawaited(_loadOfficialDate(forceRefresh: true));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for the official HRMS date, then try again.'),
        ),
      );
      return;
    }
    final corrected = await openResponsiveRightSidePanel<_LocatorSlipDraft>(
      context: context,
      barrierLabel: 'Close locator request correction form',
      minWidth: 520,
      initialWidthFraction: 0.38,
      builder: (_) => EmployeeHrmsAssistantOverlay(
        initialBottom: 92,
        child: _LocatorSlipFormDialog(
          employeeName: item.employeeName,
          requestTypes: _locatorTypes,
          officialDate: officialDate,
          title: 'Correct Locator Request',
          submitLabel: 'Save & Resubmit',
          initialValues: LocatorSlipFormInitialValues(
            slipDate: item.date,
            requestTypeCode: item.requestType.code,
            office: item.office,
            reason: item.remarks,
            amIn: item.amIn,
            amOut: item.amOut,
            pmIn: item.pmIn,
            pmOut: item.pmOut,
            existingAttachmentName: item.attachmentName,
          ),
        ),
      ),
    );
    if (corrected == null || !_isCurrentAuthSession(userId, authGeneration)) {
      return;
    }

    setState(() {
      _myRequestsError = null;
      _loadingMy = true;
    });
    try {
      final attachmentBytes = corrected.pendingAttachmentBytes;
      final attachmentName = corrected.pendingAttachmentName?.trim();
      if (attachmentBytes != null &&
          attachmentName != null &&
          attachmentName.isNotEmpty) {
        await ApiClient.instance.dio.post<Map<String, dynamic>>(
          '/api/locator-slips/$id/attachment',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(
              attachmentBytes,
              filename: attachmentName,
            ),
          }),
        );
        if (!_isCurrentAuthSession(userId, authGeneration)) return;
      }

      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/$id/resubmit',
        data: {
          'slip_date': _toIsoDate(corrected.date),
          'request_type': corrected.requestType.code,
          'office': corrected.office,
          'reason': corrected.remarks,
          'am_in': corrected.amIn,
          'am_out': corrected.amOut,
          'pm_in': corrected.pmIn,
          'pm_out': corrected.pmOut,
        },
      );
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      LocatorSlipDataCache.instance.invalidateRequests();
      await _loadMyRequests(forceRefresh: true);
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      _showLocatorSnack('Corrected request resubmitted for approval.');
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      await _showLocatorErrorDialog(
        _apiErrorMessage(e, fallback: 'Failed to resubmit the request.'),
      );
    } finally {
      if (_isCurrentAuthSession(userId, authGeneration)) {
        setState(() => _loadingMy = false);
      }
    }
  }

  Future<void> _openAttachment(_LocatorSlipDraft item) async {
    final id = item.id?.trim();
    final filename = item.attachmentName?.trim();
    if (id == null || id.isEmpty || filename == null || filename.isEmpty) {
      return;
    }
    final userId = _authenticatedUserId;
    if (userId == null) return;
    final authGeneration = _authGeneration;
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('Opening attachment...')),
      );
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/api/locator-slips/$id/attachment',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Attachment could not be loaded.')),
        );
        return;
      }
      messenger.clearSnackBars();
      await locator_attachment.openLocatorAttachmentBytes(bytes, filename);
    } catch (e) {
      if (!_isCurrentAuthSession(userId, authGeneration)) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _apiErrorMessage(e, fallback: 'Could not open attachment.'),
          ),
        ),
      );
    }
  }

  Future<void> _pickFilterDate({
    required bool isFrom,
    bool approval = false,
  }) async {
    final currentFrom = approval ? _approvalFromDate : _fromDate;
    final currentTo = approval ? _approvalToDate : _toDate;
    final initial = isFrom
        ? (currentFrom ?? DateTime.now())
        : (currentTo ?? currentFrom ?? DateTime.now());
    final picked = await showHrmsDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isFrom ? 'Select from date' : 'Select to date',
    );
    if (picked == null) return;
    setState(() {
      if (approval) {
        if (isFrom) {
          _approvalFromDate = picked;
          if (_approvalToDate != null &&
              _approvalToDate!.isBefore(_approvalFromDate!)) {
            _approvalToDate = _approvalFromDate;
          }
        } else {
          _approvalToDate = picked;
          if (_approvalFromDate != null &&
              _approvalFromDate!.isAfter(_approvalToDate!)) {
            _approvalFromDate = _approvalToDate;
          }
        }
      } else {
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
      }
    });
    if (approval) {
      await _loadDepartmentHeadRequests(forceRefresh: true);
    } else {
      await _loadMyRequests(forceRefresh: true);
    }
  }

  void _clearFilters() {
    _myFilterDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _selectedStatusFilter = null;
      _fromDate = null;
      _toDate = null;
    });
    unawaited(_loadMyRequests(forceRefresh: true));
  }

  void _clearApprovalFilters() {
    _approvalFilterDebounce?.cancel();
    setState(() {
      _approvalSearchQuery = '';
      _selectedApprovalStatusFilter = null;
      _approvalFromDate = null;
      _approvalToDate = null;
      _selectedApprovalSlipId = null;
    });
    unawaited(_loadDepartmentHeadRequests(forceRefresh: true));
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

class _LocatorHeader extends StatelessWidget {
  const _LocatorHeader({
    required this.employeeName,
    required this.onCreatePressed,
    required this.onRefresh,
    required this.refreshing,
    required this.showCreateAction,
    required this.createEnabled,
  });

  final String employeeName;
  final VoidCallback onCreatePressed;
  final VoidCallback onRefresh;
  final bool refreshing;
  final bool showCreateAction;
  final bool createEnabled;

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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: refreshing
                    ? 'Refreshing locator requests'
                    : 'Refresh locator requests',
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              if (showCreateAction) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: createEnabled ? onCreatePressed : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('File Request'),
                ),
              ],
            ],
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
  const _LocatorSlipFormDialog({
    required this.employeeName,
    required this.requestTypes,
    required this.officialDate,
    this.initialValues,
    this.title = 'File Request',
    this.submitLabel = 'Submit',
  });

  final String employeeName;
  final List<LocatorRequestType> requestTypes;
  final DateTime officialDate;
  final LocatorSlipFormInitialValues? initialValues;
  final String title;
  final String submitLabel;

  @override
  State<_LocatorSlipFormDialog> createState() => _LocatorSlipFormDialogState();
}

class _LocatorSlipFormDialogState extends State<_LocatorSlipFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  LocatorRequestType _requestType = LocatorRequestType.locator;
  _WfhCoverage _wfhCoverage = _WfhCoverage.wholeDay;
  final _officeController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _amIn = false;
  bool _amOut = false;
  bool _pmIn = false;
  bool _pmOut = false;
  List<int>? _pendingAttachmentBytes;
  String? _pendingAttachmentName;
  bool _savedAmInBeforeWfh = false;
  bool _savedAmOutBeforeWfh = false;
  bool _savedPmInBeforeWfh = false;
  bool _savedPmOutBeforeWfh = false;
  bool _hasSavedSegmentsBeforeWfh = false;
  bool _showAttachmentError = false;

  bool get _isWfhRequest => _requestType.usesWfhCoverage;
  bool get _requiresAttachment => _requestType.requiresAttachment;
  String? get _existingAttachmentName {
    final value = widget.initialValues?.existingAttachmentName?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get _effectiveAttachmentName =>
      (_pendingAttachmentName ?? '').trim().isNotEmpty
      ? _pendingAttachmentName!.trim()
      : _existingAttachmentName;

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
      final enteringWfh = !_requestType.usesWfhCoverage && type.usesWfhCoverage;
      final leavingWfh = _requestType.usesWfhCoverage && !type.usesWfhCoverage;

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
      _showAttachmentError = false;
      if (!type.requiresAttachment) {
        _pendingAttachmentBytes = null;
        _pendingAttachmentName = null;
      }
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
  void initState() {
    super.initState();
    final today = DateTime(
      widget.officialDate.year,
      widget.officialDate.month,
      widget.officialDate.day,
    );
    _date = today;
    final initial = widget.initialValues;
    if (widget.requestTypes.isNotEmpty) {
      if (initial?.requestTypeCode != null &&
          initial!.requestTypeCode!.trim().isNotEmpty) {
        final code = initial.requestTypeCode!.trim().toLowerCase();
        _requestType = widget.requestTypes.firstWhere(
          (type) => type.code == code,
          orElse: () => widget.requestTypes.firstWhere(
            (type) => type.code == LocatorRequestType.fromCode(code).code,
            orElse: () => widget.requestTypes.first,
          ),
        );
      } else {
        _requestType = widget.requestTypes.first;
      }
    }
    if (initial?.slipDate != null) {
      final date = initial!.slipDate!;
      final requested = DateTime(date.year, date.month, date.day);
      _date = requested.isBefore(today) ? today : requested;
    }
    if (initial?.office != null && initial!.office!.trim().isNotEmpty) {
      _officeController.text = initial.office!.trim();
    }
    if (initial?.reason != null && initial!.reason!.trim().isNotEmpty) {
      _remarksController.text = initial.reason!.trim();
    }
    if (_requestType.usesWfhCoverage) {
      if (initial != null && initial.hasSlotSelection) {
        _amIn = initial.amIn ?? false;
        _amOut = initial.amOut ?? false;
        _pmIn = initial.pmIn ?? false;
        _pmOut = initial.pmOut ?? false;
        _wfhCoverage = _coverageFromSlots(_amIn, _amOut, _pmIn, _pmOut);
      } else {
        _applyWfhCoverage(_wfhCoverage);
      }
    } else if (initial != null && initial.hasSlotSelection) {
      _amIn = initial.amIn ?? false;
      _amOut = initial.amOut ?? false;
      _pmIn = initial.pmIn ?? false;
      _pmOut = initial.pmOut ?? false;
    }
  }

  _WfhCoverage _coverageFromSlots(
    bool amIn,
    bool amOut,
    bool pmIn,
    bool pmOut,
  ) {
    final amSelected = amIn && amOut;
    final pmSelected = pmIn && pmOut;
    if (amSelected && pmSelected) return _WfhCoverage.wholeDay;
    if (amSelected) return _WfhCoverage.amOnly;
    if (pmSelected) return _WfhCoverage.pmOnly;
    return _WfhCoverage.wholeDay;
  }

  @override
  void dispose() {
    _officeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildFullScreen(context);
  }

  Widget _buildFullScreen(BuildContext context) {
    const accent = Color(0xFFF57C00);
    return Scaffold(
      backgroundColor: AppTheme.dashPanelOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _formFields(context),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            border: Border(
              top: BorderSide(color: AppTheme.dashHairlineOf(context)),
            ),
          ),
          child: EmployeeLocatorMobileFormActions(
            accent: accent,
            onCancel: () => Navigator.of(context).pop(),
            onSubmit: _save,
            submitLabel: widget.submitLabel,
          ),
        ),
      ),
    );
  }

  Widget _formFields(BuildContext context) {
    return Column(
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
        EmployeeLocatorMobileLabeledField(
          label: 'Name',
          labelColor: AppTheme.dashTextSecondaryOf(context),
          child: TextFormField(
            initialValue: widget.employeeName,
            enabled: false,
            decoration: _inputDecoration().copyWith(
              hintText: widget.employeeName,
            ),
          ),
        ),
        const SizedBox(height: 12),
        EmployeeLocatorMobileLabeledField(
          label: _requestType.locationLabel,
          labelColor: AppTheme.dashTextSecondaryOf(context),
          child: TextFormField(
            controller: _officeController,
            decoration: _inputDecoration().copyWith(
              hintText: _requestType.locationHint,
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? '${_requestType.locationLabel} is required'
                : null,
          ),
        ),
        const SizedBox(height: 12),
        EmployeeLocatorMobileLabeledField(
          label: 'Remarks / Reasons',
          labelColor: AppTheme.dashTextSecondaryOf(context),
          child: TextFormField(
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
        ),
        if (_requiresAttachment) ...[
          const SizedBox(height: 14),
          _attachmentPicker(),
        ],
      ],
    );
  }

  Widget _datePicker() {
    final firstAllowedDate = DateTime(
      widget.officialDate.year,
      widget.officialDate.month,
      widget.officialDate.day,
    );
    return EmployeeLocatorMobileDateField(
      labelColor: AppTheme.dashTextSecondaryOf(context),
      dateLabel: _formatDate(_date),
      decoration: _inputDecoration(),
      onTap: () async {
        final picked = await showHrmsDatePicker(
          context: context,
          initialDate: _date,
          firstDate: firstAllowedDate,
          lastDate: DateTime(2100),
          helpText: 'Select request date',
        );
        if (picked != null) {
          setState(() => _date = picked);
        }
      },
    );
  }

  Widget _requestTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmployeeLocatorMobileLabeledField(
          label: 'Request Type',
          labelColor: AppTheme.dashTextSecondaryOf(context),
          child: DropdownButtonFormField<LocatorRequestType>(
            initialValue: _requestType,
            decoration: _inputDecoration(),
            isExpanded: true,
            items: widget.requestTypes
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
        ),
      ],
    );
  }

  Widget _wfhCoverageDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmployeeLocatorMobileLabeledField(
          label: 'WFH Coverage',
          labelColor: AppTheme.dashTextSecondaryOf(context),
          child: DropdownButtonFormField<_WfhCoverage>(
            initialValue: _wfhCoverage,
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
        ),
      ],
    );
  }

  Widget _attachmentPicker() {
    final attachmentName = _effectiveAttachmentName;
    final hasAttachment = attachmentName != null;
    final hasReplacement = (_pendingAttachmentName ?? '').trim().isNotEmpty;
    final showError = _showAttachmentError && !hasAttachment;
    final borderColor = showError
        ? Colors.redAccent
        : AppTheme.dashHairlineOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmployeeLocatorMobileFieldLabel(
          text: 'Attachment *',
          color: AppTheme.dashTextSecondaryOf(context),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: showError ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(
                Icons.attach_file_rounded,
                size: 20,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasAttachment ? attachmentName : 'PDF, JPG, or PNG required',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasAttachment
                        ? AppTheme.dashTextPrimaryOf(context)
                        : AppTheme.dashTextSecondaryOf(context),
                    fontWeight: hasAttachment
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _pickAttachment,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(hasAttachment ? 'Change' : 'Upload'),
              ),
              if (hasReplacement)
                IconButton(
                  tooltip: 'Keep current attachment',
                  onPressed: () {
                    setState(() {
                      _pendingAttachmentBytes = null;
                      _pendingAttachmentName = null;
                    });
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          const Text(
            'Upload an attachment to submit this request.',
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() {
      _pendingAttachmentBytes = bytes;
      _pendingAttachmentName = file.name;
      _showAttachmentError = false;
    });
  }

  Widget _segmentSelector() {
    const accent = Color(0xFFF57C00);
    final locked = _isWfhRequest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmployeeLocatorMobileFieldLabel(
          text: 'Applicable Time Segment(s)',
          color: AppTheme.dashTextSecondaryOf(context),
        ),
        const SizedBox(height: 8),
        EmployeeLocatorMobileSegmentSelector(
          accent: accent,
          locked: locked,
          amIn: _amIn,
          amOut: _amOut,
          pmIn: _pmIn,
          pmOut: _pmOut,
          onAmIn: () => setState(() => _amIn = !_amIn),
          onAmOut: () => setState(() => _amOut = !_amOut),
          onPmIn: () => setState(() => _pmIn = !_pmIn),
          onPmOut: () => setState(() => _pmOut = !_pmOut),
        ),
      ],
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
    final requestDate = DateTime(_date.year, _date.month, _date.day);
    final today = DateTime(
      widget.officialDate.year,
      widget.officialDate.month,
      widget.officialDate.day,
    );
    if (requestDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Employees cannot file a locator for a past date. Contact HR for a correction.',
          ),
        ),
      );
      return;
    }
    if (_requiresAttachment && _effectiveAttachmentName == null) {
      setState(() => _showAttachmentError = true);
      return;
    }

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
        pendingAttachmentBytes: _pendingAttachmentBytes,
        pendingAttachmentName: _pendingAttachmentName,
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
    this.revokedByName,
    this.revokedAt,
    this.revocationReason,
    this.monthEndReconciliationRequired = false,
    this.monthEndReconciledAt,
    this.createdAt,
    this.updatedAt,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    this.attachmentName,
    this.pendingAttachmentBytes,
    this.pendingAttachmentName,
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
  final String? revokedByName;
  final DateTime? revokedAt;
  final String? revocationReason;
  final bool monthEndReconciliationRequired;
  final DateTime? monthEndReconciledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;
  final String? attachmentName;
  final List<int>? pendingAttachmentBytes;
  final String? pendingAttachmentName;
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
    String? revokedByName,
    DateTime? revokedAt,
    String? revocationReason,
    bool? monthEndReconciliationRequired,
    DateTime? monthEndReconciledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? amIn,
    bool? amOut,
    bool? pmIn,
    bool? pmOut,
    String? attachmentName,
    List<int>? pendingAttachmentBytes,
    String? pendingAttachmentName,
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
      revokedByName: revokedByName ?? this.revokedByName,
      revokedAt: revokedAt ?? this.revokedAt,
      revocationReason: revocationReason ?? this.revocationReason,
      monthEndReconciliationRequired:
          monthEndReconciliationRequired ?? this.monthEndReconciliationRequired,
      monthEndReconciledAt: monthEndReconciledAt ?? this.monthEndReconciledAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      amIn: amIn ?? this.amIn,
      amOut: amOut ?? this.amOut,
      pmIn: pmIn ?? this.pmIn,
      pmOut: pmOut ?? this.pmOut,
      attachmentName: attachmentName ?? this.attachmentName,
      pendingAttachmentBytes:
          pendingAttachmentBytes ?? this.pendingAttachmentBytes,
      pendingAttachmentName:
          pendingAttachmentName ?? this.pendingAttachmentName,
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
      requestType: LocatorRequestType.fromJson({
        'code': json['request_type'],
        'label': json['request_type_label'],
        'short_label': json['request_type_short_label'],
        'location_label': json['request_type_location_label'],
        'location_hint': json['request_type_location_hint'],
        'dtr_slot_label': json['request_type_dtr_slot_label'],
        'dtr_print_label': json['request_type_dtr_print_label'],
        'requires_attachment': json['request_type_requires_attachment'],
        'coverage_mode': json['request_type_coverage_mode'],
      }),
      office: (json['office'] ?? '').toString(),
      remarks: (json['reason'] ?? '').toString(),
      attachmentName: json['attachment_name']?.toString(),
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
                  status == _LocatorSlipStatus.revoked ||
                  status == _LocatorSlipStatus.rejected)
              ? genericReviewer
              : null),
      hrReviewedAt: _parseDateTime(json['hr_reviewed_at']),
      hrRemarks: readName(['hr_remarks']),
      revokedByName: readName(['revoked_by_name']),
      revokedAt: _parseDateTime(json['revoked_at']),
      revocationReason: readName(['revocation_reason']),
      monthEndReconciliationRequired:
          json['month_end_reconciliation_required'] == true,
      monthEndReconciledAt: _parseDateTime(json['month_end_reconciled_at']),
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
  returnedForCorrection('Returned for Correction'),
  approved('Approved'),
  revoked('Revoked'),
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
      case 'returned_for_correction':
        return _LocatorSlipStatus.returnedForCorrection;
      case 'approved':
        return _LocatorSlipStatus.approved;
      case 'revoked':
        return _LocatorSlipStatus.revoked;
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
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
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
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            ],
          ),
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

class _LoadMoreHistoryControl extends StatelessWidget {
  const _LoadMoreHistoryControl({
    required this.loaded,
    required this.total,
    required this.loading,
    required this.error,
    required this.onPressed,
  });

  final int loaded;
  final int total;
  final bool loading;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Showing $loaded of $total requests',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded, size: 18),
          label: Text(loading ? 'Loading...' : 'Load More'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade900, fontSize: 12),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferenceDataLoadingState extends StatelessWidget {
  const _ReferenceDataLoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          message,
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    case 'returned_for_correction':
      return 'Returned for Correction';
    case 'approved':
      return 'Approved by HR';
    case 'revoked':
      return 'Approval Revoked';
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
    _LocatorSlipStatus.returnedForCorrection => (
      Colors.orange.shade50,
      Colors.orange.shade300,
      Colors.orange.shade900,
    ),
    _LocatorSlipStatus.approved => (
      Colors.green.shade50,
      Colors.green.shade300,
      Colors.green.shade900,
    ),
    _LocatorSlipStatus.revoked => (
      Colors.deepOrange.shade50,
      Colors.deepOrange.shade300,
      Colors.deepOrange.shade900,
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
    _LocatorSlipStatus.returnedForCorrection => Icons.assignment_return_rounded,
    _LocatorSlipStatus.approved => Icons.check_circle_rounded,
    _LocatorSlipStatus.revoked => Icons.undo_rounded,
    _LocatorSlipStatus.rejected => Icons.cancel_rounded,
    _LocatorSlipStatus.cancelled => Icons.flag_rounded,
  };
}

IconData _locatorRequestTypeIcon(LocatorRequestType type) {
  if (type.usesWfhCoverage) return Icons.home_work_rounded;
  if (type.code == LocatorRequestType.passSlip.code) return Icons.badge_rounded;
  return Icons.near_me_rounded;
}
