import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart'
    show DashboardProfilePanel;
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';
import 'package:hrms_plaridel/shared/widgets/admin_welcome_status_card.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/shared/utils/time_greeting.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';
import 'package:provider/provider.dart';

const _kCourseOptions = <String>[
  'Bachelor of Science in Information Technology',
  'Bachelor of Science in Computer Science',
  'Bachelor of Science in Civil Engineering',
  'Bachelor of Science in Accountancy',
  'Bachelor of Science in Business Administration',
  'Bachelor of Science in Public Administration',
  'Bachelor of Science in Nursing',
  'Bachelor of Elementary Education',
  'Bachelor of Secondary Education',
  'Bachelor of Science in Psychology',
  'Bachelor of Science in Criminology',
  'Bachelor of Science in Hospitality Management',
  'Bachelor of Science in Agriculture',
  'Bachelor of Arts in Communication',
  'Bachelor of Laws',
];

class MayorDashboardPage extends StatefulWidget {
  const MayorDashboardPage({super.key});

  @override
  State<MayorDashboardPage> createState() => _MayorDashboardPageState();
}

enum _MayorMenu { dashboard, requests, history, profile }

class _MayorDashboardPageState extends State<MayorDashboardPage> {
  _MayorMenu _selectedMenu = _MayorMenu.dashboard;
  bool _sidebarCollapsed = false;
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  final _repo = MayorEndorsementRepo.instance;

  late Future<MayorDashboardData> _dashboardFuture = _repo.fetchDashboard();
  String _search = '';
  String _office = '';
  String _status = '';
  String _priority = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  int _page = 1;
  int _historyPage = 1;
  final int _pageSize = 20;
  bool _loadingList = false;
  bool _loadingHistory = false;
  bool _submittingIntake = false;

  /// Bumps [DashboardContentNavigator] homeRefreshKey so list/loading updates paint.
  int _contentEpoch = 0;
  MayorEndorsementListResponse _requests = MayorEndorsementListResponse.empty();
  MayorEndorsementListResponse _history = MayorEndorsementListResponse.empty();

  void _bumpContent() {
    _contentEpoch++;
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _loadHistory();
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardFuture = _repo.fetchDashboard();
      _bumpContent();
    });
    await _dashboardFuture;
    if (mounted) setState(_bumpContent);
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loadingList = true;
      _bumpContent();
    });
    try {
      final result = await _repo.listRequests(
        search: _search,
        office: _office,
        status: _status,
        priority: _priority,
        fromDate: _fromDate,
        toDate: _toDate,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _requests = result;
        _bumpContent();
      });
    } catch (e) {
      if (!mounted) return;
      _showError(
        'Failed to load endorsement requests: ${userFacingApiError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingList = false;
          _bumpContent();
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _bumpContent();
    });
    try {
      // History is independent of Requests filters (pending/mayor_approved would
      // otherwise wipe endorsed/rejected results).
      final result = await _repo.listHistory(
        page: _historyPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _history = result;
        _bumpContent();
      });
    } catch (e) {
      if (!mounted) return;
      _showError(
        'Failed to load endorsement history: ${userFacingApiError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _bumpContent();
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      _refreshDashboard(),
      _loadRequests(),
      _loadHistory(),
    ]);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRequest(MayorEndorsementRequest item) async {
    final details = await _repo.getRequestDetails(item.id);
    if (!mounted) return;

    final result = await showDialog<_ReviewActionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MayorReviewDialog(
        details: details,
        onScheduleMeeting: () => _scheduleMayorMeeting(item),
        onMarkNoShow: () => _markMayorMeetingNoShow(item),
        onMarkMetMayor: () => _markMetMayor(item),
      ),
    );

    if (!mounted || result == null) return;

    if (result.action == _ReviewAction.approve) {
      if (item.status == 'pending' && !item.hasMetMayor) {
        _showError(
          'Step 2 first: the applicant must meet the Mayor. '
          'If they cannot, schedule a meeting.',
        );
        return;
      }
      final ok = await _confirm(
        title: 'Approve by Municipal Mayor',
        message:
            'Approve this endorsement as Municipal Mayor? Mayor\'s Office can then approve the endorsement form.',
      );
      if (!ok) return;
      try {
        await _repo.approveRequest(
          item.id,
          destinationOfficeId: result.destinationOfficeId,
          destinationOfficeName: result.destinationOfficeName,
          remarks: result.remarks,
        );
        _showSuccess(
          'Approved by Municipal Mayor. Awaiting Mayor\'s Office form approval.',
        );
        await _refreshAll();
      } catch (e) {
        _showError('Failed to approve request: ${userFacingApiError(e)}');
      }
      return;
    }

    if (result.action == _ReviewAction.approveForm) {
      await _approveOfficeForm(
        item,
        destinationOfficeId: result.destinationOfficeId,
        destinationOfficeName: result.destinationOfficeName,
        remarks: result.remarks,
      );
      return;
    }

    if (result.action == _ReviewAction.reject) {
      if (item.status == 'pending' && !item.hasMetMayor) {
        _showError(
          'Step 2 first: the applicant must meet the Mayor. '
          'If they cannot, schedule a meeting.',
        );
        return;
      }
      final ok = await _confirm(
        title: 'Reject Endorsement',
        message: 'Reject this endorsement request?',
      );
      if (!ok) return;
      try {
        await _repo.rejectRequest(item.id, result.reason ?? '');
        _showSuccess('Endorsement rejected.');
        await _refreshAll();
      } catch (e) {
        _showError('Failed to reject request: ${userFacingApiError(e)}');
      }
    }
  }

  Future<void> _approveFromCard(MayorEndorsementRequest item) async {
    if (item.status == 'mayor_approved') {
      await _approveOfficeForm(item);
      return;
    }
    if (item.status != 'pending') return;
    if (!item.hasMetMayor) {
      _showError(
        'Step 2 first: the applicant must meet the Mayor. '
        'If they cannot, schedule a meeting.',
      );
      return;
    }

    final picked = await showDialog<_ApproveOfficeChoice>(
      context: context,
      builder: (_) => _ApproveEndorsementDialog(
        applicantName: item.applicantName,
        initialOfficeName: item.endorseToOffice == 'Unassigned'
            ? ''
            : item.endorseToOffice,
        initialOfficeId: item.destinationOfficeId,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await _repo.approveRequest(
        item.id,
        destinationOfficeId: picked.officeId,
        destinationOfficeName: picked.officeName,
        remarks: item.mayorRemarks,
      );
      _showSuccess(
        'Approved by Municipal Mayor. Awaiting Mayor\'s Office form approval.',
      );
      await _refreshAll();
    } catch (e) {
      _showError('Failed to approve request: ${userFacingApiError(e)}');
    }
  }

  Future<void> _rejectFromCard(MayorEndorsementRequest item) async {
    if (item.status != 'pending' && item.status != 'mayor_approved') return;
    if (item.status == 'pending' && !item.hasMetMayor) {
      _showError(
        'Step 2 first: the applicant must meet the Mayor. '
        'If they cannot, schedule a meeting.',
      );
      return;
    }
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject endorsement?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use this if the endorsement for ${item.applicantName} is not valid. '
                'Enter the reason below.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                minLines: 3,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Rejection reason',
                  hintText: 'Why is this endorsement not valid?',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(reasonCtrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null) return;
    if (reason.isEmpty) {
      _showError('A rejection reason is required.');
      return;
    }
    try {
      await _repo.rejectRequest(item.id, reason);
      _showSuccess('Endorsement rejected.');
      await _refreshAll();
    } catch (e) {
      _showError('Failed to reject request: ${userFacingApiError(e)}');
    }
  }

  Future<void> _openIntakeForm() async {
    final result = await showDialog<MayorEndorsementIntakeSubmission>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _MayorEndorsementIntakeDialog(),
    );
    if (!mounted || result == null) return;

    setState(() {
      _submittingIntake = true;
      _bumpContent();
    });
    try {
      await _repo.submitEndorsementRequest(
        priority: result.priority,
        intakeForm: result.intakeForm.toJson(),
        staffNotes: result.staffNotes,
        requestedOfficeId: result.requestedOfficeId,
        requestedOfficeName: result.requestedOfficeName,
      );
      _showSuccess(
        'Intake form submitted and queued for Mayor / Mayor\'s Office staff review.',
      );
      await _refreshAll();
    } catch (e) {
      _showError(
        'Failed to submit endorsement intake form: ${userFacingApiError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingIntake = false;
          _bumpContent();
        });
      }
    }
  }

  Future<bool> _scheduleMayorMeeting(MayorEndorsementRequest item) async {
    final now = DateTime.now();
    final initial =
        item.appointmentAt?.toLocal() ?? now.add(const Duration(days: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Meeting with the Mayor',
    );
    if (day == null || !mounted) return false;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Meeting time',
    );
    if (time == null || !mounted) return false;
    final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    try {
      await _repo.scheduleMayorMeeting(item.id, appointmentAt: dt);
      _showSuccess(
        item.appointmentStatus == 'no_show'
            ? 'Meeting rescheduled. Applicant can see the Mayor on the new date.'
            : 'Meeting with the Mayor scheduled.',
      );
      await _refreshAll();
      return true;
    } catch (e) {
      _showError('Failed to save schedule: ${userFacingApiError(e)}');
      return false;
    }
  }

  Future<bool> _markMetMayor(MayorEndorsementRequest item) async {
    final ok = await _confirm(
      title: 'Applicant met the Mayor?',
      message:
          'Confirm that ${item.applicantName} already talked to / saw the Mayor. '
          'After this you can approve (and set the office) or reject.',
    );
    if (!ok) return false;
    try {
      await _repo.markMetMayor(item.id);
      _showSuccess('Meeting recorded. You can now approve or reject.');
      await _refreshAll();
      return true;
    } catch (e) {
      _showError('Failed to record meeting: ${userFacingApiError(e)}');
      return false;
    }
  }

  Future<bool> _markMayorMeetingNoShow(MayorEndorsementRequest item) async {
    final ok = await _confirm(
      title: 'Applicant did not appear?',
      message:
          'Mark ${item.applicantName} as no-show. You can reschedule another meeting with the Mayor after this.',
    );
    if (!ok) return false;
    try {
      await _repo.markMayorMeetingNoShow(item.id);
      _showSuccess('Marked as did not appear. Reschedule when ready.');
      await _refreshAll();
      return true;
    } catch (e) {
      _showError('Failed to mark no-show: ${userFacingApiError(e)}');
      return false;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return res == true;
  }

  /// Mayor's Office personnel: approve endorsement form after municipal mayor approval.
  Future<void> _approveOfficeForm(
    MayorEndorsementRequest item, {
    String? destinationOfficeId,
    String? destinationOfficeName,
    String? remarks,
  }) async {
    if (item.status != 'mayor_approved') {
      _showError(
        'Endorsement form can only be approved after the Municipal Mayor has approved the request.',
      );
      return;
    }

    final resolvedDestination =
        [
              destinationOfficeName,
              item.destinationOfficeName,
              item.requestedOfficeName,
              item.endorseToOffice,
            ]
            .map((e) => (e ?? '').trim())
            .firstWhere(
              (e) => e.isNotEmpty && e != 'Unassigned',
              orElse: () => '',
            );
    if (resolvedDestination.isEmpty) {
      final picked = await showDialog<_ApproveOfficeChoice>(
        context: context,
        builder: (_) => _ApproveEndorsementDialog(
          applicantName: item.applicantName,
          initialOfficeName: '',
          initialOfficeId: item.destinationOfficeId,
        ),
      );
      if (picked == null || !mounted) return;
      await _approveOfficeForm(
        item,
        destinationOfficeId: picked.officeId,
        destinationOfficeName: picked.officeName,
        remarks: remarks,
      );
      return;
    }

    final ok = await _confirm(
      title: 'Approve Endorsement Form (Mayor\'s Office)',
      message:
          'Confirm that Mayor\'s Office personnel approve this endorsement form for ${item.applicantName}? '
          'This finalizes the endorsement and generates the letter.',
    );
    if (!ok) return;
    try {
      await _repo.approveEndorsementForm(
        item.id,
        destinationOfficeId: destinationOfficeId ?? item.destinationOfficeId,
        destinationOfficeName: resolvedDestination,
        remarks: remarks ?? item.mayorRemarks,
      );
      _showSuccess('Endorsement form approved by Mayor\'s Office.');
      await _refreshAll();
    } catch (e) {
      _showError(userFacingApiError(e));
    }
  }

  Widget _settingsPanel() => DashboardProfilePanel(onBack: _closeProfile);

  void _onMenuSelected(_MayorMenu menu) {
    if (menu == _MayorMenu.profile) {
      _openProfile();
      return;
    }
    final settingsOnTop = DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    );
    if (_selectedMenu == menu && !settingsOnTop) return;
    if (_selectedMenu != menu) {
      setState(() => _selectedMenu = menu);
    }
    DashboardContentNavigator.showHome(_contentNavKey);
    if (menu == _MayorMenu.history) {
      _loadHistory();
    } else if (menu == _MayorMenu.requests) {
      _loadRequests();
    } else if (menu == _MayorMenu.dashboard) {
      _refreshDashboard();
    }
  }

  void _openProfile() {
    if (DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    )) {
      setState(() => _selectedMenu = _MayorMenu.profile);
      return;
    }
    setState(() => _selectedMenu = _MayorMenu.profile);
    DashboardContentNavigator.openSettings(_contentNavKey);
  }

  void _closeProfile() {
    final nav = _contentNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
    if (!mounted) return;
    if (_selectedMenu == _MayorMenu.profile) {
      setState(() => _selectedMenu = _MayorMenu.dashboard);
      DashboardContentNavigator.showHome(_contentNavKey);
    }
  }

  Widget _buildContent() {
    switch (_selectedMenu) {
      case _MayorMenu.dashboard:
        return _MayorDashboardTab(
          dashboardFuture: _dashboardFuture,
          onRefresh: _refreshDashboard,
          onOpenRequest: _openRequest,
        );
      case _MayorMenu.requests:
        return _MayorRequestsTab(
          loading: _loadingList,
          submittingIntake: _submittingIntake,
          requests: _requests,
          search: _search,
          office: _office,
          status: _status,
          priority: _priority,
          fromDate: _fromDate,
          toDate: _toDate,
          onSearchChanged: (v) => _search = v,
          onOfficeChanged: (v) => _office = v,
          onStatusChanged: (v) => _status = v,
          onPriorityChanged: (v) => _priority = v,
          onFromDateChanged: (v) => _fromDate = v,
          onToDateChanged: (v) => _toDate = v,
          onApplyFilters: () async {
            _page = 1;
            await _loadRequests();
          },
          page: _requests.page,
          totalPages: _requests.totalPages,
          onPreviousPage: () async {
            if (_page <= 1) return;
            _page -= 1;
            await _loadRequests();
          },
          onNextPage: () async {
            if (_page >= _requests.totalPages) return;
            _page += 1;
            await _loadRequests();
          },
          onOpenIntakeForm: _openIntakeForm,
          onOpenRequest: _openRequest,
          onApproveOfficeForm: _approveOfficeForm,
          onApproveRequest: _approveFromCard,
          onRejectRequest: _rejectFromCard,
          onScheduleMeeting: _scheduleMayorMeeting,
          onMarkNoShow: _markMayorMeetingNoShow,
          onMarkMetMayor: _markMetMayor,
        );
      case _MayorMenu.history:
        return _MayorHistoryTab(
          history: _history,
          loading: _loadingHistory,
          onOpenRequest: _openRequest,
          onRefresh: _loadHistory,
          onPreviousPage: () async {
            if (_historyPage <= 1) return;
            _historyPage -= 1;
            await _loadHistory();
          },
          onNextPage: () async {
            if (_historyPage >= _history.totalPages) return;
            _historyPage += 1;
            await _loadHistory();
          },
        );
      case _MayorMenu.profile:
        return _settingsPanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final contentPadding = width > 900 ? 28.0 : (width > 600 ? 22.0 : 18.0);
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty ? a.displayName : 'Mayor',
    );
    final email = context.select<AuthProvider, String>(
      (a) => a.email.isNotEmpty ? a.email : 'Mayor',
    );
    final avatarPath = context.select<AuthProvider, String?>(
      (a) => a.avatarPath,
    );

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _MayorSidebar(
                  selectedMenu: _selectedMenu,
                  avatarPath: avatarPath,
                  email: email,
                  displayName: displayName,
                  showBrand: true,
                  onTap: (menu) {
                    _onMenuSelected(menu);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ),
      body: SafeArea(
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MayorSidebar(
                    railMode: true,
                    collapsed: _sidebarCollapsed,
                    showBrand: false,
                    selectedMenu: _selectedMenu,
                    avatarPath: avatarPath,
                    email: email,
                    displayName: displayName,
                    onTap: _onMenuSelected,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        DashboardAppHeaderBar(
                          showBrand: false,
                          showSidebarToggle: true,
                          sidebarCollapsed: _sidebarCollapsed,
                          onSidebarToggle: () => setState(
                            () => _sidebarCollapsed = !_sidebarCollapsed,
                          ),
                          compactActions: width < 600,
                          trailing: DashboardAccountMenuButton(
                            avatarPath: avatarPath,
                            compact: width < 600,
                            tooltip: displayName,
                            onProfile: _openProfile,
                          ),
                        ),
                        Expanded(
                          child: ColoredBox(
                            color: AppTheme.dashCanvasOf(context),
                            child: DashboardContentNavigator(
                              navigatorKey: _contentNavKey,
                              homeCacheKey: _selectedMenu,
                              homeRefreshKey: Object.hash(
                                _selectedMenu,
                                displayName,
                                contentPadding,
                                _contentEpoch,
                              ),
                              homeBuilder: _buildContent,
                              settingsPanel: _settingsPanel(),
                              homeScrollPadding: EdgeInsets.all(contentPadding),
                              settingsScrollPadding: const EdgeInsets.fromLTRB(
                                12,
                                8,
                                12,
                                28,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Builder(
                    builder: (innerContext) => DashboardAppHeaderBar(
                      showMenuButton: true,
                      onMenuPressed: () =>
                          Scaffold.of(innerContext).openDrawer(),
                      compactActions: width < 600,
                      trailing: DashboardAccountMenuButton(
                        avatarPath: avatarPath,
                        compact: width < 600,
                        tooltip: displayName,
                        onProfile: _openProfile,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: AppTheme.dashCanvasOf(context),
                      child: DashboardContentNavigator(
                        navigatorKey: _contentNavKey,
                        homeCacheKey: _selectedMenu,
                        homeRefreshKey: Object.hash(
                          _selectedMenu,
                          displayName,
                          contentPadding,
                          _contentEpoch,
                        ),
                        homeBuilder: _buildContent,
                        settingsPanel: _settingsPanel(),
                        homeScrollPadding: EdgeInsets.all(contentPadding),
                        settingsScrollPadding: const EdgeInsets.fromLTRB(
                          12,
                          8,
                          12,
                          28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MayorSidebar extends StatelessWidget {
  const _MayorSidebar({
    required this.selectedMenu,
    required this.avatarPath,
    required this.email,
    required this.displayName,
    required this.onTap,
    this.showBrand = true,
    this.railMode = false,
    this.collapsed = false,
  });

  final _MayorMenu selectedMenu;
  final String? avatarPath;
  final String email;
  final String displayName;
  final ValueChanged<_MayorMenu> onTap;
  final bool showBrand;
  final bool railMode;
  final bool collapsed;

  Widget _buildNavList(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: railMode ? 12 : (showBrand ? 4 : 12)),
        DashboardSidebarNavTile(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          selected: selectedMenu == _MayorMenu.dashboard,
          onTap: () => onTap(_MayorMenu.dashboard),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.dashHairlineOf(context),
          ),
        ),
        const DashboardSidebarSectionLabel('ENDORSEMENTS'),
        DashboardSidebarNavTile(
          icon: Icons.assignment_outlined,
          label: 'Requests',
          selected: selectedMenu == _MayorMenu.requests,
          onTap: () => onTap(_MayorMenu.requests),
        ),
        DashboardSidebarNavTile(
          icon: Icons.history_outlined,
          label: 'History',
          selected: selectedMenu == _MayorMenu.history,
          onTap: () => onTap(_MayorMenu.history),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final year = DateTime.now().year;
    final t = SidebarCollapseScope.maybeOf(context) ?? 0.0;
    final fadeExpanded = (1 - t).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: fadeExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: DashboardSidebarProfileCard(
            displayName: displayName,
            subtitle: email,
            avatarPath: avatarPath,
          ),
        ),
        Opacity(
          opacity: fadeExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Text(
              '© $year HRMS · Mayor Module',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final canvas = AppTheme.dashCanvasOf(context);
    final panel = AppTheme.dashPanelOf(context);

    final content = Column(
      children: [
        if (railMode) SidebarRailHeader(collapsed: collapsed),
        if (!railMode && showBrand) const PortalSidebarBrand(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildNavList(context),
          ),
        ),
        _buildFooter(context),
      ],
    );

    if (railMode) {
      return AnimatedSidebarWidth(
        collapsed: collapsed,
        child: DashboardSidebarRailFrame(
          hairline: hairline,
          canvas: canvas,
          child: content,
        ),
      );
    }

    return Container(
      width: kDashboardSidebarExpandedWidth,
      color: panel,
      child: content,
    );
  }
}

class _MayorDashboardTab extends StatelessWidget {
  const _MayorDashboardTab({
    required this.dashboardFuture,
    required this.onRefresh,
    required this.onOpenRequest,
  });

  final Future<MayorDashboardData> dashboardFuture;
  final Future<void> Function() onRefresh;
  final ValueChanged<MayorEndorsementRequest> onOpenRequest;

  @override
  Widget build(BuildContext context) {
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty ? a.displayName : 'Mayor',
    );
    return FutureBuilder<MayorDashboardData>(
      future: dashboardFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || snap.data == null) {
          return Column(
            children: [
              const SizedBox(height: 60),
              const Center(child: Text('Failed to load dashboard metrics.')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          );
        }
        final data = snap.data!;

        final cards = [
          _StatCard(
            title: 'Pending Endorsements',
            value: data.pendingCount.toString(),
            color: Colors.orange.shade700,
            icon: Icons.pending_actions_rounded,
          ),
          _StatCard(
            title: 'Awaiting Office Form',
            value: data.mayorApprovedCount.toString(),
            color: Colors.blue.shade700,
            icon: Icons.assignment_turned_in_outlined,
          ),
          _StatCard(
            title: 'Approved Endorsements',
            value: data.endorsedCount.toString(),
            color: Colors.green.shade700,
            icon: Icons.check_circle_rounded,
          ),
          _StatCard(
            title: 'Rejected Endorsements',
            value: data.rejectedCount.toString(),
            color: Colors.red.shade700,
            icon: Icons.cancel_rounded,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MayorWelcomeBanner(displayName: displayName),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map((c) => SizedBox(width: 310, child: c))
                  .toList(),
            ),
            const SizedBox(height: 16),
            _MayorSectionCard(
              title: 'Endorsement Statistics by Destination Office',
              child: data.officeStatistics.isEmpty
                  ? const _MayorEmptyState(
                      icon: Icons.account_balance_outlined,
                      title: 'No office statistics yet',
                      subtitle:
                          'Office distribution will appear once requests are reviewed.',
                    )
                  : Column(
                      children: data.officeStatistics
                          .map(
                            (s) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.account_balance_rounded,
                              ),
                              title: Text(s.officeName),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${s.total}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 16),
            _MayorSectionCard(
              title: 'Recent Endorsement Requests',
              child: data.recentRequests.isEmpty
                  ? const _MayorEmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No recent requests',
                      subtitle:
                          'New submissions from staff will appear in this list.',
                    )
                  : Column(
                      children: data.recentRequests
                          .map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onOpenRequest(r),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.dashHairlineOf(context),
                                    ),
                                    color: AppTheme.dashPanelOf(context),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.person_outline_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.applicantName,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                if ((r.submittedByName ?? '')
                                                    .trim()
                                                    .isNotEmpty)
                                                  'From ${r.submittedByName!.trim()}',
                                                'Office: ${r.endorseToOffice}',
                                                r.decisionLabel,
                                              ].join(' · '),
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color:
                                                    AppTheme.dashTextSecondaryOf(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          _MayorStatusPill(status: r.status),
                                          const SizedBox(height: 6),
                                          Text(
                                            _fmtDateTime(r.submittedAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MayorRequestsTab extends StatelessWidget {
  const _MayorRequestsTab({
    required this.loading,
    required this.submittingIntake,
    required this.requests,
    required this.search,
    required this.office,
    required this.status,
    required this.priority,
    required this.fromDate,
    required this.toDate,
    required this.onSearchChanged,
    required this.onOfficeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onApplyFilters,
    required this.page,
    required this.totalPages,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onOpenIntakeForm,
    required this.onOpenRequest,
    required this.onApproveOfficeForm,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onScheduleMeeting,
    required this.onMarkNoShow,
    required this.onMarkMetMayor,
  });

  final bool loading;
  final bool submittingIntake;
  final MayorEndorsementListResponse requests;
  final String search;
  final String office;
  final String status;
  final String priority;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOfficeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final Future<void> Function() onApplyFilters;
  final int page;
  final int totalPages;
  final Future<void> Function() onPreviousPage;
  final Future<void> Function() onNextPage;
  final Future<void> Function() onOpenIntakeForm;
  final ValueChanged<MayorEndorsementRequest> onOpenRequest;
  final Future<void> Function(MayorEndorsementRequest item) onApproveOfficeForm;
  final Future<void> Function(MayorEndorsementRequest item) onApproveRequest;
  final Future<void> Function(MayorEndorsementRequest item) onRejectRequest;
  final Future<bool> Function(MayorEndorsementRequest item) onScheduleMeeting;
  final Future<bool> Function(MayorEndorsementRequest item) onMarkNoShow;
  final Future<bool> Function(MayorEndorsementRequest item) onMarkMetMayor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _MayorTabHero(
          icon: Icons.assignment_outlined,
          title: 'All Endorsement Requests',
          subtitle:
              '1) Fill the Endorsement Intake Form. '
              '2) The applicant must talk to / see the Mayor — if they cannot, schedule a meeting '
              '(reschedule if they did not appear). '
              '3) After the meeting, approve and assign an office, or reject.',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: submittingIntake ? null : onOpenIntakeForm,
            icon: submittingIntake
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.note_add_rounded),
            label: Text(
              submittingIntake
                  ? 'Submitting...'
                  : 'New Endorsement Intake Form',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _FilterPanel(
          search: search,
          office: office,
          status: status,
          priority: priority,
          fromDate: fromDate,
          toDate: toDate,
          onSearchChanged: onSearchChanged,
          onOfficeChanged: onOfficeChanged,
          onStatusChanged: onStatusChanged,
          onPriorityChanged: onPriorityChanged,
          onFromDateChanged: onFromDateChanged,
          onToDateChanged: onToDateChanged,
          onApply: onApplyFilters,
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (requests.items.isEmpty)
          const _MayorEmptyState(
            icon: Icons.assignment_late_outlined,
            title: 'No endorsement requests found',
            subtitle: 'Try changing filters or wait for staff submissions.',
          )
        else
          _MayorSectionCard(
            title: 'Request Queue',
            child: Column(
              children: [
                for (var i = 0; i < requests.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _MayorRequestCard(
                    item: requests.items[i],
                    onOpen: () => onOpenRequest(requests.items[i]),
                    onApproveOfficeForm: () =>
                        onApproveOfficeForm(requests.items[i]),
                    onApproveRequest: () => onApproveRequest(requests.items[i]),
                    onRejectRequest: () => onRejectRequest(requests.items[i]),
                    onScheduleMeeting: () =>
                        onScheduleMeeting(requests.items[i]),
                    onMarkNoShow: () => onMarkNoShow(requests.items[i]),
                    onMarkMetMayor: () => onMarkMetMayor(requests.items[i]),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Page $page of $totalPages'),
            const SizedBox(width: 8),
            IconButton(
              onPressed: page > 1 ? onPreviousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: page < totalPages ? onNextPage : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _MayorRequestCard extends StatelessWidget {
  const _MayorRequestCard({
    required this.item,
    required this.onOpen,
    required this.onApproveOfficeForm,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onScheduleMeeting,
    required this.onMarkNoShow,
    required this.onMarkMetMayor,
  });

  final MayorEndorsementRequest item;
  final VoidCallback onOpen;
  final VoidCallback onApproveOfficeForm;
  final VoidCallback onApproveRequest;
  final VoidCallback onRejectRequest;
  final VoidCallback onScheduleMeeting;
  final VoidCallback onMarkNoShow;
  final VoidCallback onMarkMetMayor;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final awaitingMeeting = item.status == 'pending' && !item.hasMetMayor;
    final canDecide =
        (item.status == 'pending' && item.hasMetMayor) ||
        item.status == 'mayor_approved';
    final canOfficeApprove = item.status == 'mayor_approved';
    final canMayorApprove = item.status == 'pending' && item.hasMetMayor;
    final requester = (item.submittedByName ?? '').trim();
    final meeting = item.appointmentAt;
    final noShow = item.appointmentStatus == 'no_show';
    final isScheduled = item.appointmentStatus == 'scheduled';

    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
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
                          item.applicantName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          requester.isEmpty
                              ? 'Requested by: —'
                              : 'Requested by: $requester',
                          style: TextStyle(fontSize: 13, color: secondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.flowStepLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MayorStatusPill(status: item.status),
                  const SizedBox(width: 8),
                  _MayorPriorityPill(priority: item.priority),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _MayorMetaChip(
                    icon: Icons.account_balance_outlined,
                    label: 'Office to enter',
                    value: item.endorseToOffice,
                  ),
                  _MayorMetaChip(
                    icon: Icons.gavel_rounded,
                    label: 'Endorsement',
                    value: item.decisionLabel,
                  ),
                  _MayorMetaChip(
                    icon: noShow
                        ? Icons.event_busy_rounded
                        : Icons.event_available_rounded,
                    label: 'Meeting with Mayor',
                    value: meeting == null
                        ? item.meetingLabel
                        : '${item.meetingLabel} · ${_fmtDateTime(meeting)}',
                  ),
                  if (item.noShowCount > 0)
                    _MayorMetaChip(
                      icon: Icons.warning_amber_rounded,
                      label: 'No-shows',
                      value: '${item.noShowCount}',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (awaitingMeeting) ...[
                    FilledButton.icon(
                      onPressed: onMarkMetMayor,
                      icon: const Icon(Icons.handshake_outlined, size: 18),
                      label: const Text('Met the Mayor'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onScheduleMeeting,
                      icon: Icon(
                        noShow
                            ? Icons.event_repeat_rounded
                            : meeting == null
                            ? Icons.event_rounded
                            : Icons.edit_calendar_rounded,
                        size: 18,
                      ),
                      label: Text(
                        noShow
                            ? 'Reschedule'
                            : meeting == null
                            ? 'Schedule meeting'
                            : 'Change schedule',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                        side: const BorderSide(color: AppTheme.primaryNavy),
                      ),
                    ),
                    if (isScheduled)
                      TextButton.icon(
                        onPressed: onMarkNoShow,
                        icon: const Icon(Icons.event_busy_rounded, size: 18),
                        label: const Text('Did not appear'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryNavy,
                        ),
                      ),
                  ],
                  if (canMayorApprove)
                    FilledButton.icon(
                      onPressed: onApproveRequest,
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (canOfficeApprove)
                    FilledButton.icon(
                      onPressed: onApproveOfficeForm,
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Approve Form'),
                    ),
                  if (canDecide)
                    OutlinedButton.icon(
                      onPressed: onRejectRequest,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                        side: const BorderSide(color: Color(0xFFC62828)),
                      ),
                    ),
                  TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                    child: const Text('View details'),
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

class _MayorMetaChip extends StatelessWidget {
  const _MayorMetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryNavy),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dashTextPrimaryOf(context),
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

class _MayorHistoryTab extends StatelessWidget {
  const _MayorHistoryTab({
    required this.history,
    required this.loading,
    required this.onOpenRequest,
    required this.onRefresh,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final MayorEndorsementListResponse history;
  final bool loading;
  final ValueChanged<MayorEndorsementRequest> onOpenRequest;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPreviousPage;
  final Future<void> Function() onNextPage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _MayorTabHero(
          icon: Icons.history_outlined,
          title: 'Endorsement History',
          subtitle: 'Review all approved and rejected endorsements.',
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: loading ? null : onRefresh,
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(loading ? 'Loading...' : 'Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (loading && history.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (history.items.isEmpty)
          const _MayorEmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'No endorsement history yet',
            subtitle:
                'Fully endorsed and rejected requests will appear here after Mayor\'s Office completes review.',
          )
        else
          _MayorSectionCard(
            title: 'Processed Endorsements',
            child: Column(
              children: [
                _MayorTableHeader(
                  columns: const [
                    'Applicant',
                    'Office',
                    'Status',
                    'Processed Date',
                  ],
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < history.items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (_) {
                      final item = history.items[i];
                      final processed =
                          item.rejectedAt ??
                          item.officeFormApprovedAt ??
                          item.approvedAt ??
                          item.submittedAt;
                      return InkWell(
                        onTap: () => onOpenRequest(item),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.applicantName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.applicationId,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.officeName.isEmpty
                                      ? 'Unassigned'
                                      : item.officeName,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _MayorStatusPill(status: item.status),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    _fmtDateTime(processed),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Page ${history.page} of ${history.totalPages}'),
            const SizedBox(width: 8),
            IconButton(
              onPressed: history.page > 1 && !loading ? onPreviousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: history.page < history.totalPages && !loading
                  ? onNextPage
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.search,
    required this.office,
    required this.status,
    required this.priority,
    required this.fromDate,
    required this.toDate,
    required this.onSearchChanged,
    required this.onOfficeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onApply,
  });

  final String search;
  final String office;
  final String status;
  final String priority;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOfficeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final Future<void> Function() onApply;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.search,
  );
  late final TextEditingController _officeController = TextEditingController(
    text: widget.office,
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search applicant / application ID',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _officeController,
                decoration: const InputDecoration(
                  labelText: 'Office',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: widget.status.isEmpty ? '' : widget.status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(
                    value: 'mayor_approved',
                    child: Text(
                      'Awaiting Office Form',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(value: 'endorsed', child: Text('Endorsed')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (v) => widget.onStatusChanged(v ?? ''),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: widget.priority.isEmpty ? '' : widget.priority,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                ],
                onChanged: (v) => widget.onPriorityChanged(v ?? ''),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range_rounded),
              label: Text(
                widget.fromDate == null
                    ? 'From date'
                    : _fmtDateOnly(widget.fromDate!),
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: widget.fromDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                widget.onFromDateChanged(picked);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available_rounded),
              label: Text(
                widget.toDate == null
                    ? 'To date'
                    : _fmtDateOnly(widget.toDate!),
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: widget.toDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                widget.onToDateChanged(picked);
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.search_rounded),
              label: const Text('Apply'),
              onPressed: () async {
                widget.onSearchChanged(_searchController.text.trim());
                widget.onOfficeChanged(_officeController.text.trim());
                await widget.onApply();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MayorEndorsementIntakeDialog extends StatefulWidget {
  const _MayorEndorsementIntakeDialog();

  @override
  State<_MayorEndorsementIntakeDialog> createState() =>
      _MayorEndorsementIntakeDialogState();
}

class _MayorEndorsementIntakeDialogState
    extends State<_MayorEndorsementIntakeDialog> {
  String _priority = 'normal';
  final _officeCtrl = TextEditingController();
  String? _requestedOfficeId;
  List<_MayorOfficeOption> _offices = const [];
  bool _loadingOffices = false;
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController();
  final _currentWorkAddressCtrl = TextEditingController();
  final _prcCscCtrl = TextEditingController();
  final _rankCodeCtrl = TextEditingController();
  final _staffNotesCtrl = TextEditingController();

  final _homeStreetCtrl = TextEditingController();
  final _schoolStreetCtrl = TextEditingController();
  final GlobalKey<StructuredAddressFormState> _homeAddressKey =
      GlobalKey<StructuredAddressFormState>();
  final GlobalKey<StructuredAddressFormState> _schoolAddressKey =
      GlobalKey<StructuredAddressFormState>();

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    border: const OutlineInputBorder(),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  MayorIntakeFormData _buildIntakeFromInputs() {
    return MayorIntakeFormData(
      lastName: _lastNameCtrl.text,
      firstName: _firstNameCtrl.text,
      middleNameOrInitial: _middleCtrl.text,
      address: _homeAddressKey.currentState?.composeEncoded() ?? '',
      course: _courseCtrl.text,
      schoolAddress: _schoolAddressKey.currentState?.composeEncoded() ?? '',
      positionApplyingFor: _positionCtrl.text,
      currentWorkDesignation: _designationCtrl.text,
      agencyCompany: _agencyCtrl.text,
      noOfService: _serviceCtrl.text,
      currentWorkAddress: _currentWorkAddressCtrl.text,
      prcCscNo: _prcCscCtrl.text,
      rankAndCode: _rankCodeCtrl.text,
    );
  }

  Future<void> _previewSubmission() async {
    final intake = _buildIntakeFromInputs();
    final missing = intake.firstMissingLabel();
    if (missing != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please fill in: $missing')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Review Before Submit'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewRow('Last Name', intake.lastName),
                _previewRow('First Name', intake.firstName),
                _previewRow(
                  'Middle Name / Initial',
                  intake.middleNameOrInitial,
                ),
                _previewRow('Address', intake.address),
                _previewRow('Course', intake.course),
                _previewRow('School Address', intake.schoolAddress),
                _previewRow(
                  'Position Applying For',
                  intake.positionApplyingFor,
                ),
                _previewRow(
                  'Current Work / Designation',
                  intake.currentWorkDesignation,
                ),
                _previewRow('Agency / Company', intake.agencyCompany),
                _previewRow('No. of Service', intake.noOfService),
                _previewRow('Add. sa Current Work', intake.currentWorkAddress),
                _previewRow('PRC No. / CSC No.', intake.prcCscNo),
                _previewRow('Rank and Code', intake.rankAndCode),
                _previewRow('Office to endorse', _officeCtrl.text.trim()),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.trim().isEmpty ? '-' : value.trim()),
          ],
        ),
      ),
    );
  }

  Future<void> _loadOffices() async {
    setState(() => _loadingOffices = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/offices',
        queryParameters: const {'status': 'Active'},
      );
      final parsed = (res.data ?? const [])
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return _MayorOfficeOption(
              id: (m['id'] ?? '').toString(),
              name: (m['name'] ?? '').toString().trim(),
            );
          })
          .where((o) => o.id.isNotEmpty && o.name.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _offices = parsed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _offices = const []);
    } finally {
      if (mounted) setState(() => _loadingOffices = false);
    }
  }

  void _applyRequestedOffice(_MayorOfficeOption? office, {String? typed}) {
    if (office != null) {
      _requestedOfficeId = office.id;
      _officeCtrl.text = office.name;
      return;
    }
    final name = (typed ?? _officeCtrl.text).trim();
    _officeCtrl.text = name;
    String? matchedId;
    for (final o in _offices) {
      if (o.name.toLowerCase() == name.toLowerCase()) {
        matchedId = o.id;
        break;
      }
    }
    _requestedOfficeId = matchedId;
  }

  @override
  void initState() {
    super.initState();
    _loadOffices();
  }

  @override
  void dispose() {
    _officeCtrl.dispose();
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleCtrl.dispose();
    _courseCtrl.dispose();
    _positionCtrl.dispose();
    _designationCtrl.dispose();
    _agencyCtrl.dispose();
    _serviceCtrl.dispose();
    _currentWorkAddressCtrl.dispose();
    _prcCscCtrl.dispose();
    _rankCodeCtrl.dispose();
    _staffNotesCtrl.dispose();
    _homeStreetCtrl.dispose();
    _schoolStreetCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final intake = _buildIntakeFromInputs();
    final missing = intake.firstMissingLabel();
    if (missing != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please fill in: $missing')));
      return;
    }

    if (_officeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter the office the applicant will be endorsed to.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      MayorEndorsementIntakeSubmission(
        priority: _priority,
        intakeForm: intake,
        staffNotes: _staffNotesCtrl.text.trim().isEmpty
            ? null
            : _staffNotesCtrl.text.trim(),
        requestedOfficeId: _requestedOfficeId,
        requestedOfficeName: _officeCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      title: const Text('Endorsement Intake Form'),
      content: SizedBox(
        width: 920,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Fill out all applicant fields before submitting endorsement to Mayor.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Submission Details',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _priority,
                        decoration: _dec('Priority'),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                          DropdownMenuItem(
                            value: 'urgent',
                            child: Text('Urgent'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _priority = v ?? 'normal'),
                      ),
                      const SizedBox(height: 12),
                      Autocomplete<_MayorOfficeOption>(
                        displayStringForOption: (o) => o.name,
                        optionsBuilder: (textEditingValue) {
                          final q = textEditingValue.text.trim().toLowerCase();
                          if (q.isEmpty) return _offices;
                          return _offices.where(
                            (o) => o.name.toLowerCase().contains(q),
                          );
                        },
                        onSelected: (office) {
                          setState(() => _applyRequestedOffice(office));
                        },
                        fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                          if (textCtrl.text != _officeCtrl.text) {
                            textCtrl.value = TextEditingValue(
                              text: _officeCtrl.text,
                              selection: TextSelection.collapsed(
                                offset: _officeCtrl.text.length,
                              ),
                            );
                          }
                          return TextField(
                            controller: textCtrl,
                            focusNode: focusNode,
                            onChanged: (v) {
                              setState(
                                () => _applyRequestedOffice(null, typed: v),
                              );
                            },
                            decoration: _dec(
                              _loadingOffices
                                  ? 'Loading offices…'
                                  : 'Office to endorse (papasukan ng applicant)',
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Applicant Information',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _lastNameCtrl,
                          decoration: _dec('Last Name'),
                        ),
                        TextField(
                          controller: _firstNameCtrl,
                          decoration: _dec('First Name'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _middleCtrl,
                        decoration: _dec('Middle Name / Middle Initial'),
                      ),
                      const SizedBox(height: 10),
                      _buildCourseField(),
                      const SizedBox(height: 14),
                      StructuredAddressForm(
                        key: _homeAddressKey,
                        streetController: _homeStreetCtrl,
                        initialRawAddress: null,
                        inputDecoration: _dec,
                        sectionLabel: 'Address',
                      ),
                      const SizedBox(height: 14),
                      StructuredAddressForm(
                        key: _schoolAddressKey,
                        streetController: _schoolStreetCtrl,
                        initialRawAddress: null,
                        inputDecoration: _dec,
                        sectionLabel: 'School Address',
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _positionCtrl,
                          decoration: _dec('Position Applying for'),
                        ),
                        TextField(
                          controller: _designationCtrl,
                          decoration: _dec('Current Work / Designation'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _agencyCtrl,
                          decoration: _dec('Agency / Company'),
                        ),
                        TextField(
                          controller: _serviceCtrl,
                          decoration: _dec('No. of Service'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _currentWorkAddressCtrl,
                          decoration: _dec('Add. sa Current Work'),
                        ),
                        TextField(
                          controller: _prcCscCtrl,
                          decoration: _dec('Prc No. / CSC No.'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _rankCodeCtrl,
                        decoration: _dec('Rank and Code'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _staffNotesCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: _dec(
                  'Recommendations / Notes for Mayor (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _previewSubmission,
          icon: const Icon(Icons.preview_rounded),
          label: const Text('Preview Details'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Submit for Review'),
        ),
      ],
    );
  }

  Widget _gridTwo(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(children: [a, const SizedBox(height: 10), b]);
        }
        return Row(
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _buildCourseField() {
    return Autocomplete<String>(
      optionsBuilder: (text) {
        final q = text.text.trim().toLowerCase();
        if (q.isEmpty) return _kCourseOptions;
        return _kCourseOptions.where((c) => c.toLowerCase().contains(q));
      },
      onSelected: (value) => _courseCtrl.text = value,
      fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
        if (textCtrl.text != _courseCtrl.text) {
          textCtrl.text = _courseCtrl.text;
        }
        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          onChanged: (v) => _courseCtrl.text = v,
          decoration: _dec('Course (searchable and typeable)'),
        );
      },
    );
  }
}

class _MayorReviewDialog extends StatefulWidget {
  const _MayorReviewDialog({
    required this.details,
    required this.onScheduleMeeting,
    required this.onMarkNoShow,
    required this.onMarkMetMayor,
  });

  final MayorEndorsementDetails details;
  final Future<bool> Function() onScheduleMeeting;
  final Future<bool> Function() onMarkNoShow;
  final Future<bool> Function() onMarkMetMayor;

  @override
  State<_MayorReviewDialog> createState() => _MayorReviewDialogState();
}

class _MayorReviewDialogState extends State<_MayorReviewDialog> {
  final _destinationCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _loadingOffices = false;
  List<_MayorOfficeOption> _offices = const [];
  String? _selectedDestinationOfficeId;

  bool get _canEditDecisionFields {
    final req = widget.details.request;
    return (req.status == 'pending' && req.hasMetMayor) ||
        req.status == 'mayor_approved';
  }

  bool get _awaitingMeeting {
    final req = widget.details.request;
    return req.status == 'pending' && !req.hasMetMayor;
  }

  @override
  void initState() {
    super.initState();
    final req = widget.details.request;
    final fallbackOffice = req.endorseToOffice;
    _destinationCtrl.text = (req.destinationOfficeName ?? '').trim().isNotEmpty
        ? req.destinationOfficeName!.trim()
        : (req.requestedOfficeName ?? '').trim().isNotEmpty
        ? req.requestedOfficeName!.trim()
        : (fallbackOffice == 'Unassigned' ? '' : fallbackOffice);
    _remarksCtrl.text = req.mayorRemarks ?? '';
    _reasonCtrl.text = req.rejectionReason ?? '';
    _selectedDestinationOfficeId = req.destinationOfficeId;
    _loadOffices();
  }

  Future<void> _loadOffices() async {
    setState(() => _loadingOffices = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/offices',
        queryParameters: const {'status': 'Active'},
      );
      final parsed = (res.data ?? const [])
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return _MayorOfficeOption(
              id: (m['id'] ?? '').toString(),
              name: (m['name'] ?? '').toString().trim(),
            );
          })
          .where((o) => o.id.isNotEmpty && o.name.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _offices = parsed;
        if ((_selectedDestinationOfficeId ?? '').isEmpty) {
          final typed = _destinationCtrl.text.trim().toLowerCase();
          for (final o in parsed) {
            if (o.name.toLowerCase() == typed) {
              _selectedDestinationOfficeId = o.id;
              break;
            }
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _offices = const []);
    } finally {
      if (mounted) setState(() => _loadingOffices = false);
    }
  }

  void _applyDestinationOffice(_MayorOfficeOption? office, {String? typed}) {
    if (office != null) {
      _selectedDestinationOfficeId = office.id;
      _destinationCtrl.text = office.name;
      return;
    }
    final name = (typed ?? _destinationCtrl.text).trim();
    _destinationCtrl.text = name;
    String? matchedId;
    for (final o in _offices) {
      if (o.name.toLowerCase() == name.toLowerCase()) {
        matchedId = o.id;
        break;
      }
    }
    _selectedDestinationOfficeId = matchedId;
  }

  String? _validateDecisionFields({required bool requireDestination}) {
    if (!_canEditDecisionFields) return null;
    if (requireDestination && _destinationCtrl.text.trim().isEmpty) {
      final fallback = widget.details.request.endorseToOffice;
      if (fallback.isNotEmpty && fallback != 'Unassigned') {
        _destinationCtrl.text = fallback;
        return null;
      }
      return 'Please enter the Destination Office before continuing.';
    }
    return null;
  }

  void _showFieldError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _remarksCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.details.request;
    final applicant = widget.details.applicant;
    final canMayorApprove = req.status == 'pending' && req.hasMetMayor;
    final canOfficeApproveForm = req.status == 'mayor_approved';
    final canReject = canMayorApprove || canOfficeApproveForm;
    final statusColor = _statusColor(req.status);
    final priorityColor = _priorityColor(req.priority);
    final screenH = MediaQuery.sizeOf(context).height;
    final dialogH = (screenH * 0.88).clamp(560.0, 760.0);

    InputDecoration fieldDec({
      required String label,
      String? helper,
      String? hint,
      IconData? icon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 20, color: AppTheme.primaryNavy),
        prefixIconColor: AppTheme.primaryNavy,
        filled: true,
        fillColor: _canEditDecisionFields
            ? Colors.white
            : const Color(0xFFFAFBFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _canEditDecisionFields
                ? const Color(0xFFCBD5E1)
                : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFECEFF3)),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Colors.transparent,
      child: Material(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        shadowColor: Colors.black26,
        child: SizedBox(
          width: 1000,
          height: dialogH,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryNavyDark, AppTheme.primaryNavy],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.gavel_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mayor Endorsement Review',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${applicant.fullName.isNotEmpty ? applicant.fullName : req.applicantName}'
                            '  ·  ${req.applicationId}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _chip(
                      req.statusLabel,
                      bg: statusColor.withValues(alpha: 0.22),
                      fg: Colors.white,
                      border: statusColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    _chip(
                      'Priority: ${_cap(req.priority)}',
                      bg: priorityColor.withValues(alpha: 0.22),
                      fg: Colors.white,
                      border: priorityColor.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
              _ReviewWorkflowStrip(request: req),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: _MayorReviewSummaryBar(
                  request: req,
                  onMarkMetMayor: _awaitingMeeting
                      ? () async {
                          final ok = await widget.onMarkMetMayor();
                          if (ok && context.mounted)
                            Navigator.of(context).pop();
                        }
                      : null,
                  onScheduleMeeting: _awaitingMeeting
                      ? () async {
                          final ok = await widget.onScheduleMeeting();
                          if (ok && context.mounted)
                            Navigator.of(context).pop();
                        }
                      : null,
                  onMarkNoShow: _awaitingMeeting
                      ? () async {
                          final ok = await widget.onMarkNoShow();
                          if (ok && context.mounted)
                            Navigator.of(context).pop();
                        }
                      : null,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  children: [
                    _sectionCard(
                      title: 'I. Personal Information',
                      icon: Icons.badge_outlined,
                      child: _detailGrid([
                        _kv('Last Name', req.intakeForm.lastName),
                        _kv('First Name', req.intakeForm.firstName),
                        _kv(
                          'Middle Name / Initial',
                          req.intakeForm.middleNameOrInitial,
                        ),
                        _kv(
                          'Home Address',
                          _formatAddressForDisplay(req.intakeForm.address),
                          wide: true,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'II. Education & Position Sought',
                      icon: Icons.school_outlined,
                      child: _detailGrid([
                        _kv('Course', req.intakeForm.course, wide: true),
                        _kv(
                          'School Address',
                          _formatAddressForDisplay(
                            req.intakeForm.schoolAddress,
                          ),
                          wide: true,
                        ),
                        _kv(
                          'Position Applying For',
                          req.intakeForm.positionApplyingFor,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'III. Employment & Credentials',
                      icon: Icons.work_outline_rounded,
                      child: _detailGrid([
                        _kv(
                          'Current Work / Designation',
                          req.intakeForm.currentWorkDesignation,
                        ),
                        _kv('Agency / Company', req.intakeForm.agencyCompany),
                        _kv('No. of Service', req.intakeForm.noOfService),
                        _kv(
                          'Current Work Address',
                          req.intakeForm.currentWorkAddress,
                          wide: true,
                        ),
                        _kv('PRC No. / CSC No.', req.intakeForm.prcCscNo),
                        _kv('Rank and Code', req.intakeForm.rankAndCode),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'IV. Official Review & Decision',
                      icon: Icons.rate_review_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Staff recommendations',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  req.staffNotes?.trim().isEmpty ?? true
                                      ? 'No staff recommendations or notes were provided with this submission.'
                                      : req.staffNotes!,
                                  style: TextStyle(
                                    height: 1.45,
                                    color:
                                        (req.staffNotes?.trim().isEmpty ?? true)
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF1E293B),
                                    fontStyle:
                                        (req.staffNotes?.trim().isEmpty ?? true)
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_awaitingMeeting) ...[
                            Text(
                              'Step 2: the applicant must talk to / see the Mayor first. '
                              'If they already met, tap Met the Mayor. If not, schedule a meeting. '
                              'Approve or reject is available only after the meeting.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (canMayorApprove) ...[
                            Text(
                              'Step 3: they already met the Mayor. Enter Destination Office and remarks, then approve or reject.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (canOfficeApproveForm) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFA5D6A7),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.verified_outlined,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Municipal Mayor has approved this request. '
                                      'Fill in Destination Office and endorsement remarks/instructions, '
                                      'then approve the form to finalize and generate the letter.',
                                      style: TextStyle(height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Autocomplete<_MayorOfficeOption>(
                            initialValue: TextEditingValue(
                              text: _destinationCtrl.text,
                            ),
                            displayStringForOption: (o) => o.name,
                            optionsBuilder: (textEditingValue) {
                              final q = textEditingValue.text
                                  .trim()
                                  .toLowerCase();
                              if (q.isEmpty) return _offices;
                              return _offices.where(
                                (o) => o.name.toLowerCase().contains(q),
                              );
                            },
                            onSelected: (office) {
                              setState(() => _applyDestinationOffice(office));
                            },
                            fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                              if (textCtrl.text != _destinationCtrl.text) {
                                textCtrl.value = TextEditingValue(
                                  text: _destinationCtrl.text,
                                  selection: TextSelection.collapsed(
                                    offset: _destinationCtrl.text.length,
                                  ),
                                );
                              }
                              return TextField(
                                controller: textCtrl,
                                focusNode: focusNode,
                                enabled: _canEditDecisionFields,
                                textInputAction: TextInputAction.next,
                                onChanged: (v) {
                                  setState(
                                    () =>
                                        _applyDestinationOffice(null, typed: v),
                                  );
                                },
                                decoration: fieldDec(
                                  label: 'Destination Office',
                                  hint: _loadingOffices
                                      ? 'Loading offices…'
                                      : 'Type or select the receiving office',
                                  helper: _canEditDecisionFields
                                      ? (canOfficeApproveForm
                                            ? 'Required before Mayor\'s Office form approval'
                                            : 'Office where the endorsed applicant will be assigned')
                                      : null,
                                  icon: Icons.account_balance_outlined,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _remarksCtrl,
                            enabled: _canEditDecisionFields,
                            minLines: 3,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: fieldDec(
                              label: canOfficeApproveForm
                                  ? 'Endorsement Remarks / Instructions'
                                  : 'Endorsement Remarks / Instructions',
                              hint:
                                  'Type remarks or instructions for the destination office',
                              helper: canOfficeApproveForm
                                  ? 'Optional notes included in the endorsement letter'
                                  : (canMayorApprove
                                        ? 'Optional guidance for the destination office'
                                        : null),
                              icon: Icons.notes_rounded,
                            ),
                          ),
                          if (canReject) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _reasonCtrl,
                              enabled: true,
                              minLines: 2,
                              maxLines: 4,
                              decoration: fieldDec(
                                label: 'Rejection Reason',
                                hint:
                                    'Explain why this endorsement is rejected',
                                helper:
                                    'Required only when rejecting this endorsement',
                                icon: Icons.report_gmailerrorred_outlined,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.white,
                elevation: 8,
                shadowColor: Colors.black26,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_awaitingMeeting ||
                          canMayorApprove ||
                          canOfficeApproveForm)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _awaitingMeeting
                                ? 'Step 2: record Met the Mayor, or schedule if they have not appeared yet.'
                                : canMayorApprove
                                ? 'Step 3: enter Destination Office, then approve or reject.'
                                : 'Scroll to Section IV, confirm Destination Office and remarks, then approve the form.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Colors.blueGrey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryNavy,
                            ),
                            child: const Text('Close'),
                          ),
                          if (canReject)
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(
                                _ReviewActionResult(
                                  action: _ReviewAction.reject,
                                  reason: _reasonCtrl.text.trim(),
                                ),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC62828),
                                side: const BorderSide(
                                  color: Color(0xFFC62828),
                                ),
                              ),
                              label: const Text('Reject'),
                            ),
                          if (canMayorApprove)
                            FilledButton.icon(
                              onPressed: () {
                                final err = _validateDecisionFields(
                                  requireDestination: true,
                                );
                                if (err != null) {
                                  _showFieldError(err);
                                  return;
                                }
                                Navigator.of(context).pop(
                                  _ReviewActionResult(
                                    action: _ReviewAction.approve,
                                    destinationOfficeId:
                                        _selectedDestinationOfficeId,
                                    destinationOfficeName: _destinationCtrl.text
                                        .trim(),
                                    remarks: _remarksCtrl.text.trim(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.how_to_reg_rounded),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryNavy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              label: const Text('Approve (Municipal Mayor)'),
                            ),
                          if (canOfficeApproveForm)
                            FilledButton.icon(
                              onPressed: () {
                                final err = _validateDecisionFields(
                                  requireDestination: true,
                                );
                                if (err != null) {
                                  _showFieldError(err);
                                  return;
                                }
                                Navigator.of(context).pop(
                                  _ReviewActionResult(
                                    action: _ReviewAction.approveForm,
                                    destinationOfficeId:
                                        _selectedDestinationOfficeId,
                                    destinationOfficeName: _destinationCtrl.text
                                        .trim(),
                                    remarks: _remarksCtrl.text.trim(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.verified_rounded),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              label: const Text(
                                'Approve Form (Mayor\'s Office)',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: AppTheme.primaryNavy),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppTheme.dashTextPrimaryOf(context),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String text, {
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'endorsed':
        return const Color(0xFF2E7D32);
      case 'mayor_approved':
        return AppTheme.primaryNavy;
      case 'rejected':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFFEF6C00);
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.trim().toLowerCase()) {
      case 'urgent':
        return const Color(0xFFC62828);
      case 'high':
        return const Color(0xFFF57C00);
      case 'low':
        return AppTheme.textSecondary;
      default:
        return const Color(0xFF455A64);
    }
  }

  String _cap(String value) {
    final v = value.trim();
    if (v.isEmpty) return '-';
    return '${v[0].toUpperCase()}${v.substring(1).toLowerCase()}';
  }

  String _formatAddressForDisplay(String raw) {
    final p = parseStoredAddress(raw);
    if (!p.isStructured) {
      final v = raw.trim();
      return v.isEmpty ? '—' : v;
    }
    final parts = <String>[
      p.street,
      p.barangay,
      p.city,
      p.province,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }
}

class _MayorReviewSummaryBar extends StatelessWidget {
  const _MayorReviewSummaryBar({
    required this.request,
    this.onScheduleMeeting,
    this.onMarkNoShow,
    this.onMarkMetMayor,
  });

  final MayorEndorsementRequest request;
  final Future<void> Function()? onScheduleMeeting;
  final Future<void> Function()? onMarkNoShow;
  final Future<void> Function()? onMarkMetMayor;

  @override
  Widget build(BuildContext context) {
    final requester = (request.submittedByName ?? '').trim();
    final meeting = request.appointmentAt;
    final noShow = request.appointmentStatus == 'no_show';
    final isScheduled = request.appointmentStatus == 'scheduled';
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final showMeetingActions =
        onMarkMetMayor != null || onScheduleMeeting != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MayorMetaChip(
                icon: Icons.person_pin_rounded,
                label: 'Who requested',
                value: requester.isEmpty ? '—' : requester,
              ),
              _MayorMetaChip(
                icon: Icons.account_balance_outlined,
                label: 'Office applicant will enter',
                value: request.endorseToOffice,
              ),
              _MayorMetaChip(
                icon: Icons.gavel_rounded,
                label: 'Endorse?',
                value: request.decisionLabel,
              ),
              _MayorMetaChip(
                icon: noShow
                    ? Icons.event_busy_rounded
                    : Icons.event_available_rounded,
                label: 'Meeting with Mayor',
                value: meeting == null
                    ? request.meetingLabel
                    : '${request.meetingLabel} · ${_fmtDateTime(meeting)}',
              ),
            ],
          ),
          if (showMeetingActions) ...[
            const SizedBox(height: 12),
            Text(
              request.hasMetMayor
                  ? 'They already met the Mayor. You can now approve (and set the office) or reject.'
                  : noShow
                  ? 'They did not appear. Reschedule, or tap Met the Mayor if they already talked to the Mayor.'
                  : 'If they already talked to / saw the Mayor, tap Met the Mayor. '
                        'If not, schedule a meeting. If they miss it, mark Did not appear and reschedule.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: secondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onMarkMetMayor != null)
                  FilledButton.icon(
                    onPressed: onMarkMetMayor,
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                    label: const Text('Met the Mayor'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (onScheduleMeeting != null)
                  OutlinedButton.icon(
                    onPressed: onScheduleMeeting,
                    icon: Icon(
                      noShow
                          ? Icons.event_repeat_rounded
                          : meeting == null
                          ? Icons.event_rounded
                          : Icons.edit_calendar_rounded,
                      size: 18,
                    ),
                    label: Text(
                      noShow
                          ? 'Reschedule meeting'
                          : meeting == null
                          ? 'Schedule meeting'
                          : 'Change schedule',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                      side: const BorderSide(color: AppTheme.primaryNavy),
                    ),
                  ),
                if (isScheduled && onMarkNoShow != null)
                  TextButton.icon(
                    onPressed: onMarkNoShow,
                    icon: const Icon(Icons.event_busy_rounded, size: 18),
                    label: const Text('Did not appear'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewWorkflowStrip extends StatelessWidget {
  const _ReviewWorkflowStrip({required this.request});

  final MayorEndorsementRequest request;

  @override
  Widget build(BuildContext context) {
    final status = request.status.toLowerCase();
    final met =
        request.hasMetMayor ||
        status == 'mayor_approved' ||
        status == 'endorsed';
    final decided = status == 'endorsed';
    final officeForm = status == 'mayor_approved';
    final meetDone = met;
    final meetActive = !met && status != 'rejected';
    final decisionDone = decided;
    final decisionActive = met && !decided && status != 'rejected';
    final decisionLabel = officeForm
        ? 'Office form'
        : decided
        ? 'Endorsed'
        : 'Approve / Reject';

    Widget node({
      required int index,
      required String label,
      required bool active,
      required bool done,
    }) {
      final color = done || active
          ? AppTheme.primaryNavy
          : const Color(0xFF94A3B8);
      return Expanded(
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppTheme.primaryNavy
                    : active
                    ? AppTheme.primaryNavy
                    : const Color(0xFFE2E8F0),
              ),
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active || done
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: Colors.white,
      child: status == 'rejected'
          ? Row(
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 18,
                  color: Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'This endorsement request was rejected.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                node(index: 0, label: 'Intake form', active: false, done: true),
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: AppTheme.primaryNavy,
                ),
                node(
                  index: 1,
                  label: 'Meet the Mayor',
                  active: meetActive,
                  done: meetDone,
                ),
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: meetDone
                      ? AppTheme.primaryNavy
                      : const Color(0xFFE2E8F0),
                ),
                node(
                  index: 2,
                  label: decisionLabel,
                  active: decisionActive,
                  done: decisionDone,
                ),
              ],
            ),
    );
  }
}

Widget _detailGrid(List<Widget> children) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cols = width >= 860 ? 3 : (width >= 560 ? 2 : 1);
      final gap = 12.0;
      final itemW = (width - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children.map((child) {
          if (child is _KvField && child.wide && cols > 1) {
            return SizedBox(
              width: cols == 3 ? itemW * 2 + gap : width,
              child: child,
            );
          }
          return SizedBox(width: itemW, child: child);
        }).toList(),
      );
    },
  );
}

Widget _kv(String label, String value, {bool wide = false}) {
  return _KvField(label: label, value: value, wide: wide);
}

class _KvField extends StatelessWidget {
  const _KvField({required this.label, required this.value, this.wide = false});

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty || value.trim().toLowerCase() == 'none'
        ? '—'
        : value.trim();
    final empty = display == '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFECEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            display,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              height: 1.35,
              color: empty
                  ? AppTheme.dashTextSecondaryOf(context)
                  : AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
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

class _MayorWelcomeBanner extends StatelessWidget {
  const _MayorWelcomeBanner({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final greeting = personalizedTimeGreeting(displayName);
    final firstName = greetingFirstName(displayName);
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'M';
    final isNarrow = MediaQuery.of(context).size.width < 1180;

    return Container(
      padding: EdgeInsets.all(isNarrow ? 18 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF8F3),
            Colors.white,
            const Color(0xFFF8FAFF),
          ],
        ),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _welcomeAvatar(initial: initial),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _welcomeText(
                        greeting: greeting,
                        primary: primary,
                        secondary: secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerRight,
                  child: AdminWelcomeStatusCard(),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _welcomeAvatar(initial: initial),
                const SizedBox(width: 14),
                Expanded(
                  child: _welcomeText(
                    greeting: greeting,
                    primary: primary,
                    secondary: secondary,
                  ),
                ),
                const SizedBox(width: 10),
                const AdminWelcomeStatusCard(),
              ],
            ),
    );
  }

  Widget _welcomeAvatar({required String initial}) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFB54D), Color(0xFFE85D04)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE85D04).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _welcomeText({
    required String greeting,
    required Color primary,
    required Color secondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE85D04).withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE85D04).withValues(alpha: 0.18),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_rounded,
                size: 13,
                color: Color(0xFFE85D04),
              ),
              SizedBox(width: 6),
              Text(
                'Mayor Portal',
                style: TextStyle(
                  color: Color(0xFFE85D04),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          greeting,
          style: TextStyle(
            color: primary,
            fontSize: 33,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.08,
          ),
        ),
      ],
    );
  }
}

class _MayorTabHero extends StatelessWidget {
  const _MayorTabHero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavy.withValues(alpha: 0.08),
            AppTheme.primaryNavyLight.withValues(alpha: 0.04),
            AppTheme.dashPanelOf(context),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
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

class _MayorSectionCard extends StatelessWidget {
  const _MayorSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _MayorTableHeader extends StatelessWidget {
  const _MayorTableHeader({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: columns
            .map(
              (c) => Expanded(
                child: Text(
                  c,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MayorStatusPill extends StatelessWidget {
  const _MayorStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final (label, fg, bg) = switch (lower) {
      'endorsed' => ('Endorsed', Colors.green.shade800, Colors.green.shade50),
      'mayor_approved' => (
        'Awaiting Office Form',
        Colors.blue.shade800,
        Colors.blue.shade50,
      ),
      'rejected' => ('Rejected', Colors.red.shade800, Colors.red.shade50),
      _ => ('Pending', Colors.orange.shade900, Colors.orange.shade50),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _MayorPriorityPill extends StatelessWidget {
  const _MayorPriorityPill({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final lower = priority.toLowerCase();
    final (fg, bg) = switch (lower) {
      'urgent' => (Colors.red.shade800, Colors.red.shade50),
      'high' => (Colors.deepOrange.shade800, Colors.deepOrange.shade50),
      'low' => (Colors.blueGrey.shade800, Colors.blueGrey.shade50),
      _ => (Colors.indigo.shade800, Colors.indigo.shade50),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        priority.isEmpty ? 'normal' : priority,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _MayorEmptyState extends StatelessWidget {
  const _MayorEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryNavy),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReviewAction { approve, approveForm, reject }

class _ReviewActionResult {
  const _ReviewActionResult({
    required this.action,
    this.destinationOfficeId,
    this.destinationOfficeName,
    this.remarks,
    this.reason,
  });

  final _ReviewAction action;
  final String? destinationOfficeId;
  final String? destinationOfficeName;
  final String? remarks;
  final String? reason;
}

class _ApproveOfficeChoice {
  const _ApproveOfficeChoice({required this.officeName, this.officeId});
  final String officeName;
  final String? officeId;
}

class _ApproveEndorsementDialog extends StatefulWidget {
  const _ApproveEndorsementDialog({
    required this.applicantName,
    required this.initialOfficeName,
    this.initialOfficeId,
  });

  final String applicantName;
  final String initialOfficeName;
  final String? initialOfficeId;

  @override
  State<_ApproveEndorsementDialog> createState() =>
      _ApproveEndorsementDialogState();
}

class _ApproveEndorsementDialogState extends State<_ApproveEndorsementDialog> {
  late final TextEditingController _officeCtrl;
  String? _officeId;
  List<_MayorOfficeOption> _offices = const [];

  @override
  void initState() {
    super.initState();
    _officeCtrl = TextEditingController(text: widget.initialOfficeName);
    _officeId = widget.initialOfficeId;
    _loadOffices();
  }

  Future<void> _loadOffices() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/offices',
        queryParameters: const {'status': 'Active'},
      );
      final parsed = (res.data ?? const [])
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return _MayorOfficeOption(
              id: (m['id'] ?? '').toString(),
              name: (m['name'] ?? '').toString().trim(),
            );
          })
          .where((o) => o.id.isNotEmpty && o.name.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _offices = parsed);
    } catch (_) {}
  }

  void _applyOffice(_MayorOfficeOption? office, {String? typed}) {
    if (office != null) {
      _officeId = office.id;
      _officeCtrl.text = office.name;
      return;
    }
    final name = (typed ?? _officeCtrl.text).trim();
    _officeCtrl.text = name;
    String? matchedId;
    for (final o in _offices) {
      if (o.name.toLowerCase() == name.toLowerCase()) {
        matchedId = o.id;
        break;
      }
    }
    _officeId = matchedId;
  }

  void _submit() {
    final name = _officeCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the destination office, then tap Approve.'),
        ),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_ApproveOfficeChoice(officeName: name, officeId: _officeId));
  }

  @override
  void dispose() {
    _officeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve endorsement?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Endorse ${widget.applicantName} as Municipal Mayor. '
              'Confirm the office this applicant will enter.',
            ),
            const SizedBox(height: 14),
            Autocomplete<_MayorOfficeOption>(
              initialValue: TextEditingValue(text: _officeCtrl.text),
              displayStringForOption: (o) => o.name,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return _offices;
                return _offices.where((o) => o.name.toLowerCase().contains(q));
              },
              onSelected: (office) => setState(() => _applyOffice(office)),
              fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                if (textCtrl.text != _officeCtrl.text) {
                  textCtrl.value = TextEditingValue(
                    text: _officeCtrl.text,
                    selection: TextSelection.collapsed(
                      offset: _officeCtrl.text.length,
                    ),
                  );
                }
                return TextField(
                  controller: textCtrl,
                  focusNode: focusNode,
                  onChanged: (v) =>
                      setState(() => _applyOffice(null, typed: v)),
                  decoration: const InputDecoration(
                    labelText: 'Destination office',
                    hintText: 'Type or select the office',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
          ),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _MayorOfficeOption {
  const _MayorOfficeOption({required this.id, required this.name});
  final String id;
  final String name;
}

String _fmtDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtDateTime(DateTime d) =>
    '${_fmtDateOnly(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class MayorEndorsementRepo {
  MayorEndorsementRepo._();
  static final MayorEndorsementRepo instance = MayorEndorsementRepo._();

  Future<MayorDashboardData> fetchDashboard() async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/dashboard',
    );
    return MayorDashboardData.fromJson(res.data ?? {});
  }

  Future<MayorEndorsementListResponse> listRequests({
    String? search,
    String? office,
    String? status,
    String? priority,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements',
      queryParameters: {
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((office ?? '').trim().isNotEmpty) 'office': office!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
        if ((priority ?? '').trim().isNotEmpty) 'priority': priority!.trim(),
        if (fromDate != null) 'from_date': _fmtDateOnly(fromDate),
        if (toDate != null) 'to_date': _fmtDateOnly(toDate),
        'page': page,
        'page_size': pageSize,
      },
    );
    return MayorEndorsementListResponse.fromJson(res.data ?? {});
  }

  Future<MayorEndorsementListResponse> listHistory({
    String? search,
    String? office,
    String? status,
    String? priority,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/history',
      queryParameters: {
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((office ?? '').trim().isNotEmpty) 'office': office!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
        if ((priority ?? '').trim().isNotEmpty) 'priority': priority!.trim(),
        if (fromDate != null) 'from_date': _fmtDateOnly(fromDate),
        if (toDate != null) 'to_date': _fmtDateOnly(toDate),
        'page': page,
        'page_size': pageSize,
      },
    );
    return MayorEndorsementListResponse.fromJson(res.data ?? {});
  }

  Future<MayorEndorsementDetails> getRequestDetails(String requestId) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/$requestId',
    );
    return MayorEndorsementDetails.fromJson(res.data ?? {});
  }

  Future<void> approveRequest(
    String requestId, {
    String? destinationOfficeId,
    String? destinationOfficeName,
    String? remarks,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/approve',
      data: {
        if ((destinationOfficeId ?? '').trim().isNotEmpty)
          'destinationOfficeId': destinationOfficeId!.trim(),
        if ((destinationOfficeName ?? '').trim().isNotEmpty)
          'destinationOfficeName': destinationOfficeName!.trim(),
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> approveEndorsementForm(
    String requestId, {
    String? destinationOfficeId,
    String? destinationOfficeName,
    String? remarks,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/approve-form',
      data: {
        if ((destinationOfficeId ?? '').trim().isNotEmpty)
          'destinationOfficeId': destinationOfficeId!.trim(),
        if ((destinationOfficeName ?? '').trim().isNotEmpty)
          'destinationOfficeName': destinationOfficeName!.trim(),
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> rejectRequest(String requestId, String reason) async {
    if (reason.trim().isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(
          path: '/api/mayor/endorsements/$requestId/reject',
        ),
        error: 'Rejection reason is required.',
      );
    }
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/reject',
      data: {'reason': reason.trim()},
    );
  }

  Future<void> submitEndorsementRequest({
    required String priority,
    required Map<String, dynamic> intakeForm,
    String? staffNotes,
    String? requestedOfficeId,
    String? requestedOfficeName,
  }) async {
    await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/mayor/endorsements/requests',
      data: {
        'priority': priority,
        'intakeForm': intakeForm,
        if ((staffNotes ?? '').trim().isNotEmpty)
          'staffNotes': staffNotes!.trim(),
        if ((requestedOfficeId ?? '').trim().isNotEmpty)
          'requestedOfficeId': requestedOfficeId!.trim(),
        if ((requestedOfficeName ?? '').trim().isNotEmpty)
          'requestedOfficeName': requestedOfficeName!.trim(),
      },
    );
  }

  Future<void> scheduleMayorMeeting(
    String requestId, {
    required DateTime appointmentAt,
    String? notes,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/schedule',
      data: {
        'appointmentAt': appointmentAt.toUtc().toIso8601String(),
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      },
    );
  }

  Future<void> markMayorMeetingNoShow(String requestId, {String? notes}) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/no-show',
      data: {if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim()},
    );
  }

  Future<void> markMetMayor(String requestId, {String? notes}) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/met',
      data: {if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim()},
    );
  }
}

class MayorDashboardData {
  const MayorDashboardData({
    required this.pendingCount,
    required this.mayorApprovedCount,
    required this.endorsedCount,
    required this.rejectedCount,
    required this.recentRequests,
    required this.officeStatistics,
  });

  final int pendingCount;
  final int mayorApprovedCount;
  final int endorsedCount;
  final int rejectedCount;
  final List<MayorEndorsementRequest> recentRequests;
  final List<MayorOfficeStat> officeStatistics;

  factory MayorDashboardData.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from((json['summary'] as Map?) ?? {});
    final recentRaw = (json['recent_requests'] as List?) ?? const [];
    final officeRaw = (json['office_statistics'] as List?) ?? const [];
    return MayorDashboardData(
      pendingCount: _toInt(summary['pending_count']),
      mayorApprovedCount: _toInt(summary['mayor_approved_count']),
      endorsedCount: _toInt(summary['endorsed_count']),
      rejectedCount: _toInt(summary['rejected_count']),
      recentRequests: recentRaw
          .whereType<Map>()
          .map(
            (e) =>
                MayorEndorsementRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      officeStatistics: officeRaw
          .whereType<Map>()
          .map((e) => MayorOfficeStat.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class MayorOfficeStat {
  const MayorOfficeStat({required this.officeName, required this.total});
  final String officeName;
  final int total;

  factory MayorOfficeStat.fromJson(Map<String, dynamic> json) =>
      MayorOfficeStat(
        officeName: (json['office_name'] ?? 'Unassigned').toString(),
        total: _toInt(json['total']),
      );
}

class MayorEndorsementListResponse {
  const MayorEndorsementListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<MayorEndorsementRequest> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  factory MayorEndorsementListResponse.empty() =>
      const MayorEndorsementListResponse(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      );

  factory MayorEndorsementListResponse.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List?) ?? const [];
    final pagination = Map<String, dynamic>.from(
      (json['pagination'] as Map?) ?? {},
    );
    return MayorEndorsementListResponse(
      items: itemsRaw
          .whereType<Map>()
          .map(
            (e) =>
                MayorEndorsementRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      total: _toInt(pagination['total']),
      page: _toInt(pagination['page'], fallback: 1),
      pageSize: _toInt(pagination['page_size'], fallback: 20),
      totalPages: _toInt(pagination['total_pages'], fallback: 1),
    );
  }
}

class MayorEndorsementRequest {
  const MayorEndorsementRequest({
    required this.id,
    required this.applicationId,
    required this.applicantName,
    required this.officeName,
    required this.submittedAt,
    required this.status,
    required this.priority,
    this.destinationOfficeId,
    this.destinationOfficeName,
    this.requestedOfficeName,
    this.submittedByName,
    this.appointmentAt,
    this.appointmentStatus = 'none',
    this.appointmentNotes,
    this.noShowCount = 0,
    this.staffNotes,
    this.mayorRemarks,
    this.rejectionReason,
    this.approvedAt,
    this.rejectedAt,
    this.officeFormApprovedAt,
    this.intakeForm = const MayorIntakeFormData(),
  });

  final String id;
  final String applicationId;
  final String applicantName;
  final String officeName;
  final DateTime submittedAt;
  final String status;
  final String priority;
  final String? destinationOfficeId;
  final String? destinationOfficeName;
  final String? requestedOfficeName;
  final String? submittedByName;
  final DateTime? appointmentAt;
  final String appointmentStatus;
  final String? appointmentNotes;
  final int noShowCount;
  final String? staffNotes;
  final String? mayorRemarks;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? officeFormApprovedAt;
  final MayorIntakeFormData intakeForm;

  String get endorseToOffice {
    final dest = (destinationOfficeName ?? '').trim();
    if (dest.isNotEmpty) return dest;
    final requested = (requestedOfficeName ?? '').trim();
    if (requested.isNotEmpty) return requested;
    return officeName.trim().isEmpty ? 'Unassigned' : officeName.trim();
  }

  String get decisionLabel {
    switch (status.toLowerCase()) {
      case 'endorsed':
        return 'Endorse';
      case 'rejected':
        return 'Do not endorse';
      case 'mayor_approved':
        return 'Mayor approved — form pending';
      default:
        return hasMetMayor ? 'Awaiting decision' : 'Awaiting meeting';
    }
  }

  String get meetingLabel {
    switch (appointmentStatus.toLowerCase()) {
      case 'scheduled':
        return 'Scheduled';
      case 'no_show':
        return 'Did not appear';
      case 'completed':
        return 'Met the Mayor';
      default:
        return appointmentAt == null ? 'Not scheduled' : 'Scheduled';
    }
  }

  bool get hasMetMayor => appointmentStatus.toLowerCase() == 'completed';

  bool get isOpenRequest => status == 'pending' || status == 'mayor_approved';

  /// 1 = intake done, 2 = wait to meet mayor, 3 = decide endorse/reject.
  int get flowStep {
    if (status == 'endorsed' ||
        status == 'rejected' ||
        status == 'mayor_approved') {
      return 3;
    }
    if (hasMetMayor) return 3;
    return 2;
  }

  String get flowStepLabel {
    switch (flowStep) {
      case 3:
        if (status == 'endorsed') return 'Step 3: Endorsed';
        if (status == 'rejected') return 'Step 3: Rejected';
        if (status == 'mayor_approved') {
          return 'Step 3: Approved — confirm office form';
        }
        return 'Step 3: Approve or reject';
      case 2:
        if (appointmentStatus == 'scheduled') {
          return 'Step 2: Scheduled — meet the Mayor';
        }
        if (appointmentStatus == 'no_show') {
          return 'Step 2: Did not appear — reschedule';
        }
        return 'Step 2: Meet the Mayor or schedule';
      default:
        return 'Step 1: Intake form submitted';
    }
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'endorsed':
        return 'Endorsed';
      case 'mayor_approved':
        return 'Awaiting Office Form';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  factory MayorEndorsementRequest.fromJson(Map<String, dynamic> json) {
    final submitted =
        DateTime.tryParse((json['submitted_at'] ?? '').toString()) ??
        DateTime.now();
    DateTime? parseOpt(dynamic v) {
      final s = (v ?? '').toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return MayorEndorsementRequest(
      id: (json['id'] ?? '').toString(),
      applicationId: (json['application_id'] ?? '').toString(),
      applicantName: (json['applicant_name'] ?? '').toString(),
      officeName: (json['office_name'] ?? '').toString(),
      submittedAt: submitted,
      status: (json['status'] ?? 'pending').toString(),
      priority: (json['priority'] ?? 'normal').toString(),
      destinationOfficeId: json['destination_office_id']?.toString(),
      destinationOfficeName:
          (json['destination_office_name'] ?? json['destination_office_label'])
              ?.toString(),
      requestedOfficeName:
          (json['requested_office_name'] ?? json['requested_office_label'])
              ?.toString(),
      submittedByName: (json['submitted_by_name'] ?? json['submitted_by_label'])
          ?.toString(),
      appointmentAt: parseOpt(json['appointment_at']),
      appointmentStatus: (json['appointment_status'] ?? 'none').toString(),
      appointmentNotes: json['appointment_notes']?.toString(),
      noShowCount: _toInt(json['no_show_count']),
      staffNotes: json['staff_notes']?.toString(),
      mayorRemarks: json['mayor_remarks']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      approvedAt: parseOpt(json['approved_at']),
      rejectedAt: parseOpt(json['rejected_at']),
      officeFormApprovedAt: parseOpt(json['office_form_approved_at']),
      intakeForm: MayorIntakeFormData.fromJson(
        Map<String, dynamic>.from((json['intake_form'] as Map?) ?? {}),
      ),
    );
  }
}

class MayorApplicant {
  const MayorApplicant({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.positionAppliedFor,
    required this.status,
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String positionAppliedFor;
  final String status;

  factory MayorApplicant.fromJson(Map<String, dynamic> json) => MayorApplicant(
    id: (json['id'] ?? '').toString(),
    fullName: (json['full_name'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    phone: (json['phone'] ?? '').toString(),
    positionAppliedFor: (json['position_applied_for'] ?? '').toString(),
    status: (json['status'] ?? '').toString(),
  );
}

class MayorDocument {
  const MayorDocument({
    required this.kind,
    required this.label,
    required this.path,
    this.fileName,
  });
  final String kind;
  final String label;
  final String? path;
  final String? fileName;

  factory MayorDocument.fromJson(Map<String, dynamic> json) => MayorDocument(
    kind: (json['kind'] ?? '').toString(),
    label: (json['label'] ?? '').toString(),
    path: json['path']?.toString(),
    fileName: json['file_name']?.toString(),
  );
}

class MayorHistoryEntry {
  const MayorHistoryEntry({
    required this.action,
    required this.createdAt,
    this.actorName,
    this.remarks,
  });

  final String action;
  final DateTime createdAt;
  final String? actorName;
  final String? remarks;

  factory MayorHistoryEntry.fromJson(Map<String, dynamic> json) =>
      MayorHistoryEntry(
        action: (json['action'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((json['created_at'] ?? '').toString()) ??
            DateTime.now(),
        actorName: json['actor_name']?.toString(),
        remarks: json['remarks']?.toString(),
      );
}

class MayorEndorsementDetails {
  const MayorEndorsementDetails({
    required this.request,
    required this.applicant,
    required this.documents,
    required this.applicationHistory,
    required this.previousEndorsements,
  });

  final MayorEndorsementRequest request;
  final MayorApplicant applicant;
  final List<MayorDocument> documents;
  final List<MayorHistoryEntry> applicationHistory;
  final List<MayorEndorsementRequest> previousEndorsements;

  factory MayorEndorsementDetails.fromJson(Map<String, dynamic> json) {
    final request = MayorEndorsementRequest.fromJson(
      Map<String, dynamic>.from((json['request'] as Map?) ?? {}),
    );
    final applicant = MayorApplicant.fromJson(
      Map<String, dynamic>.from((json['applicant'] as Map?) ?? {}),
    );
    final docs = (json['documents'] as List?) ?? const [];
    final history = (json['application_history'] as List?) ?? const [];
    final previous = (json['previous_endorsements'] as List?) ?? const [];
    return MayorEndorsementDetails(
      request: request,
      applicant: applicant,
      documents: docs
          .whereType<Map>()
          .map((e) => MayorDocument.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      applicationHistory: history
          .whereType<Map>()
          .map((e) => MayorHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      previousEndorsements: previous
          .whereType<Map>()
          .map(
            (e) =>
                MayorEndorsementRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

class MayorIntakeFormData {
  const MayorIntakeFormData({
    this.lastName = '',
    this.firstName = '',
    this.middleNameOrInitial = '',
    this.address = '',
    this.course = '',
    this.schoolAddress = '',
    this.positionApplyingFor = '',
    this.currentWorkDesignation = '',
    this.agencyCompany = '',
    this.noOfService = '',
    this.currentWorkAddress = '',
    this.prcCscNo = '',
    this.rankAndCode = '',
  });

  final String lastName;
  final String firstName;
  final String middleNameOrInitial;
  final String address;
  final String course;
  final String schoolAddress;
  final String positionApplyingFor;
  final String currentWorkDesignation;
  final String agencyCompany;
  final String noOfService;
  final String currentWorkAddress;
  final String prcCscNo;
  final String rankAndCode;

  factory MayorIntakeFormData.fromJson(Map<String, dynamic> json) =>
      MayorIntakeFormData(
        lastName: (json['last_name'] ?? '').toString(),
        firstName: (json['first_name'] ?? '').toString(),
        middleNameOrInitial: (json['middle_name_or_initial'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        course: (json['course'] ?? '').toString(),
        schoolAddress: (json['school_address'] ?? '').toString(),
        positionApplyingFor: (json['position_applying_for'] ?? '').toString(),
        currentWorkDesignation: (json['current_work_designation'] ?? '')
            .toString(),
        agencyCompany: (json['agency_company'] ?? '').toString(),
        noOfService: (json['no_of_service'] ?? '').toString(),
        currentWorkAddress: (json['current_work_address'] ?? '').toString(),
        prcCscNo: (json['prc_csc_no'] ?? '').toString(),
        rankAndCode: (json['rank_and_code'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
    'last_name': lastName.trim(),
    'first_name': firstName.trim(),
    'middle_name_or_initial': middleNameOrInitial.trim(),
    'address': address.trim(),
    'course': course.trim(),
    'school_address': schoolAddress.trim(),
    'position_applying_for': positionApplyingFor.trim(),
    'current_work_designation': currentWorkDesignation.trim(),
    'agency_company': agencyCompany.trim(),
    'no_of_service': noOfService.trim(),
    'current_work_address': currentWorkAddress.trim(),
    'prc_csc_no': prcCscNo.trim(),
    'rank_and_code': rankAndCode.trim(),
  };

  String? firstMissingLabel() {
    final pairs = <MapEntry<String, String>>[
      MapEntry(lastName, 'Last Name'),
      MapEntry(firstName, 'First Name'),
      MapEntry(middleNameOrInitial, 'Middle Name / Middle Initial'),
      MapEntry(address, 'Address'),
      MapEntry(course, 'Course'),
      MapEntry(schoolAddress, 'School Address'),
      MapEntry(positionApplyingFor, 'Position Applying for'),
      MapEntry(currentWorkDesignation, 'Current Work / Designation'),
      MapEntry(agencyCompany, 'Agency / Company'),
      MapEntry(noOfService, 'No. of Service'),
      MapEntry(currentWorkAddress, 'Add. sa Current Work'),
      MapEntry(prcCscNo, 'PRC No. / CSC No.'),
      MapEntry(rankAndCode, 'Rank and Code'),
    ];
    for (final p in pairs) {
      if (p.key.trim().isEmpty) return p.value;
    }
    return null;
  }
}

class MayorEndorsementIntakeSubmission {
  const MayorEndorsementIntakeSubmission({
    required this.priority,
    required this.intakeForm,
    this.staffNotes,
    this.requestedOfficeId,
    this.requestedOfficeName,
  });

  final String priority;
  final MayorIntakeFormData intakeForm;
  final String? staffNotes;
  final String? requestedOfficeId;
  final String? requestedOfficeName;
}

int _toInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}
