import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_fab.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_source_badge.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_main.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_dashboard_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/features/notifications/presentation/widgets/open_notifications_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/my_leave_loading_skeleton.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/pages/employee_locator_slip_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/employee/pages/training_daily_report_employee_screen.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/employee/pages/ld_training_requirements_employee_screen.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/attendance_overview/attendance_overview.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/employee_dash_ui.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/employee_dashboard_layout_metrics.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/employee_dashboard_skeletons.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_attendance_mobile_list.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_shell.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_summary_mobile_layout.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart'
    show DashboardProfilePanel;
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/utils/time_greeting.dart';
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';

/// Employee dashboard reference: dark blue sidebar (HR branding), nav items,
/// welcome + Biometric Attendance, Attendance, Leave Balance, Payslip cards,
/// Upcoming Leave, Attendance Overview.
class EmployeeDashboardDesktopPage extends StatefulWidget {
  const EmployeeDashboardDesktopPage({super.key});

  @override
  State<EmployeeDashboardDesktopPage> createState() =>
      _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboardDesktopPage>
    with WidgetsBindingObserver {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;
  LeaveSection? _leaveInitialSection;
  int _leaveNavKey = 0;
  Timer? _notificationPollTimer;

  static const _navItems = [
    'Dashboard',
    'My Attendance',
    'My Leave',
    'Locator Requests',
    'Training Reports',
    'Training Requirements',
    'DocuTracker',
  ];

  /// Shown only via account menu (not listed in sidebar).
  static const int _profileNavIndex = 7;
  static const _settingsPanelKey = PageStorageKey<String>('employee_settings');
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<State<StatefulWidget>> _locatorSlipKey =
      GlobalKey<State<StatefulWidget>>();

  Widget _settingsPanel() =>
      DashboardProfilePanel(key: _settingsPanelKey, onBack: _closeMyProfile);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().refreshUnreadCount();
      _notificationPollTimer?.cancel();
      _notificationPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        context.read<NotificationProvider>().refreshUnreadCount();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationProvider>().refreshUnreadCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationPollTimer?.cancel();
    super.dispose();
  }

  void _prefetchDocuTrackerNotificationsIfNeeded(int index) {
    if (index != 6) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DocuTrackerProvider>().loadNotifications(forceRefresh: true);
    });
  }

  Future<void> _handleOpenNotifications() async {
    final result = await openNotificationsPanel(context);
    if (!mounted) return;
    await context.read<NotificationProvider>().refreshUnreadCount();
    if (!mounted) return;
    _applyNotificationTapResult(result);
  }

  void _applyNotificationTapResult(NotificationTapResult? result) {
    if (result == null || result.kind == NotificationTapKind.none) return;
    switch (result.kind) {
      case NotificationTapKind.employeeLeaveApprovals:
      case NotificationTapKind.employeeLeaveRequests:
        final section = result.employeeLeaveSection;
        if (section == null) return;
        setState(() {
          _selectedNavIndex = 2;
          _leaveInitialSection = section;
          _leaveNavKey++;
        });
        DashboardContentNavigator.showHome(_contentNavKey);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _leaveInitialSection = null);
        });
        break;
      case NotificationTapKind.employeeMyAttendance:
        setState(() => _selectedNavIndex = 1);
        DashboardContentNavigator.showHome(_contentNavKey);
        break;
      case NotificationTapKind.employeeLocatorApprovals:
      case NotificationTapKind.employeeLocatorRequests:
        setState(() => _selectedNavIndex = 3);
        DashboardContentNavigator.showHome(_contentNavKey);
        break;
      case NotificationTapKind.adminDtrLocatorManagement:
      case NotificationTapKind.adminDtrLeaveManagement:
      case NotificationTapKind.adminRecruitment:
      case NotificationTapKind.adminTrainingReports:
      case NotificationTapKind.none:
        break;
    }
  }

  void _openMyProfile() {
    if (DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    )) {
      setState(() => _selectedNavIndex = _profileNavIndex);
      return;
    }
    setState(() => _selectedNavIndex = _profileNavIndex);
    DashboardContentNavigator.openSettings(_contentNavKey);
  }

  void _closeMyProfile() {
    final nav = _contentNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
    if (!mounted) return;
    if (_selectedNavIndex == _profileNavIndex) {
      setState(() => _selectedNavIndex = 0);
      DashboardContentNavigator.showHome(_contentNavKey);
    }
  }

  void _onNavSelected(int index) {
    if (index == _profileNavIndex) {
      _openMyProfile();
      return;
    }
    final settingsOnTop = DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    );
    if (_selectedNavIndex == index && !settingsOnTop) return;
    if (_selectedNavIndex != index) {
      setState(() => _selectedNavIndex = index);
    }
    DashboardContentNavigator.showHome(_contentNavKey);
  }

  void _openLeaveRequestsFromDashboard() {
    setState(() {
      _selectedNavIndex = 2;
      _leaveInitialSection = LeaveSection.requests;
      _leaveNavKey++;
    });
    DashboardContentNavigator.showHome(_contentNavKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _leaveInitialSection = null);
    });
  }

  void _openEmployeeLocatorRequestForm() {
    final state = _locatorSlipKey.currentState;
    if (state == null) return;
    try {
      final result = (state as dynamic).openCreateForm();
      if (result is Future<void>) {
        unawaited(result);
      }
    } catch (_) {
      // The locator page owns the form. If it is not mounted yet, do nothing.
    }
  }

  Future<void> _openEmployeeLeaveRequestForm() async {
    final result = await openResponsiveLeaveFormHost<String?>(
      context: context,
      builder: (_) => _buildEmployeeLeaveRequestForm(),
    );
    if (!mounted || result == null) return;
    if (result != kLeaveFormResultDraftSaved &&
        result != kLeaveFormResultSubmitted) {
      return;
    }
    final userId = context.read<AuthProvider>().user?.id;
    if (userId != null && userId.isNotEmpty) {
      await context.read<LeaveProvider>().loadMyLeaveData(userId);
    }
    if (!mounted) return;
    showLeaveFormSuccessSnackBar(context, result);
  }

  void _openDtrAssistant() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EmployeeDtrAssistantPage()),
    );
  }

  bool get _showDtrAssistantFab =>
      _selectedNavIndex == 0 ||
      _selectedNavIndex == 1 ||
      _selectedNavIndex == 2 ||
      _selectedNavIndex == 3;

  Widget _buildEmployeeLeaveRequestForm() {
    return LeaveRequestFormScreen(
      onSaveDraft: (LeaveRequest request) async {
        final provider = context.read<LeaveProvider>();
        if (request.id != null && request.id!.isNotEmpty) {
          final updated = await provider.updateRequest(request);
          return updated != null;
        }
        final saved = await provider.saveDraft(request);
        return saved != null;
      },
      onSubmitRequest: (LeaveRequest request) async {
        final provider = context.read<LeaveProvider>();
        if (request.id != null && request.id!.isNotEmpty) {
          final updated = await provider.updateRequest(
            request.copyWith(status: LeaveRequestStatus.pending),
          );
          return updated != null;
        }
        final saved = await provider.submitRequest(request);
        return saved != null;
      },
      onSubmitRequestWithAttachment:
          (LeaveRequest request, List<int> fileBytes, String fileName) async {
            final provider = context.read<LeaveProvider>();
            final saved = await provider.submitRequestWithAttachment(
              request: request,
              fileBytes: fileBytes,
              fileName: fileName,
            );
            return saved != null;
          },
    );
  }

  Widget _employeeMainChild({
    required String displayName,
    required bool useMobileLeaveFab,
    required bool useMobileLocatorFab,
  }) {
    switch (_selectedNavIndex) {
      case 0:
        return _EmployeeDashboardContent(
          displayName: displayName,
          onViewAttendance: () => setState(() => _selectedNavIndex = 1),
          onViewLeave: _openLeaveRequestsFromDashboard,
        );
      case 1:
        return const _EmployeeAttendanceContent();
      case 2:
        return _EmployeeLeaveMainEntry(
          key: ValueKey(_leaveNavKey),
          initialSection: _leaveInitialSection,
          onFileLeavePressed: _openEmployeeLeaveRequestForm,
          hideFileLeaveAction: useMobileLeaveFab,
        );
      case 3:
        return EmployeeLocatorSlipScreen(key: _locatorSlipKey);
      case 4:
        return const TrainingDailyReportEmployeeScreen();
      case 5:
        return const LdTrainingRequirementsEmployeeScreen();
      case 6:
        return const DocuTrackerMain(isAdmin: false);
      case _profileNavIndex:
        return const SizedBox.shrink();
      default:
        return _EmployeePlaceholderContent(title: _navItems[_selectedNavIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AuthProvider, String?>((a) => a.user?.id);
    if (userId != null && userId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final dtr = context.read<DtrProvider>();
        if (dtr.userId != userId) dtr.setUserFromApi(userId);
      });
    }
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty ? a.displayName : 'Employee',
    );
    final avatarPath = context.select<AuthProvider, String?>(
      (a) => a.avatarPath,
    );
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final useMobileLeaveFab = width < 600 && _selectedNavIndex == 2;
    final useMobileLocatorFab = !isWide && _selectedNavIndex == 3;

    if (!isWide) {
      return EmployeeDashboardMobileShell(
        width: width,
        avatarPath: avatarPath,
        displayName: displayName,
        selectedIndex: _selectedNavIndex,
        navigatorKey: _contentNavKey,
        homeBuilder:
            ({
              required bool useMobileLeaveFab,
              required bool useMobileLocatorFab,
            }) => _employeeMainChild(
              displayName: displayName,
              useMobileLeaveFab: useMobileLeaveFab,
              useMobileLocatorFab: useMobileLocatorFab,
            ),
        settingsPanel: _settingsPanel(),
        onNavSelected: _onNavSelected,
        onProfile: _openMyProfile,
        onViewAllNotifications: _handleOpenNotifications,
        onNotificationTap: _applyNotificationTapResult,
        onFileLeave: _openEmployeeLeaveRequestForm,
        onFileLocator: _openEmployeeLocatorRequestForm,
        onDtrAssistant: _openDtrAssistant,
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      body: Stack(
        children: [
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EmployeeSidebar(
                  railMode: true,
                  collapsed: _sidebarCollapsed,
                  showBrand: false,
                  displayName: displayName,
                  avatarPath: avatarPath,
                  selectedIndex: _selectedNavIndex,
                  onTap: (i) {
                    _onNavSelected(i);
                    _prefetchDocuTrackerNotificationsIfNeeded(i);
                  },
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
                        onViewAllNotifications: _handleOpenNotifications,
                        onNotificationTap: _applyNotificationTapResult,
                        trailing: DashboardAccountMenuButton(
                          avatarPath: avatarPath,
                          compact: width < 600,
                          tooltip: displayName,
                          onProfile: () => _openMyProfile(),
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: AppTheme.dashCanvasOf(context),
                          child: DashboardContentNavigator(
                            navigatorKey: _contentNavKey,
                            homeCacheKey: _selectedNavIndex,
                            homeRefreshKey: Object.hash(
                              _selectedNavIndex,
                              _leaveNavKey,
                              displayName,
                              useMobileLeaveFab,
                              useMobileLocatorFab,
                            ),
                            homeBuilder: () => _employeeMainChild(
                              displayName: displayName,
                              useMobileLeaveFab: useMobileLeaveFab,
                              useMobileLocatorFab: useMobileLocatorFab,
                            ),
                            settingsPanel: _settingsPanel(),
                            homeScrollPadding: employeeMainScrollPadding(
                              context,
                            ),
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
            ),
          ),
          if (_showDtrAssistantFab)
            DraggableDtrAssistantLauncher(
              onPressed: _openDtrAssistant,
              initialRight: 24,
              initialBottom: 24,
            ),
        ],
      ),
    );
  }
}

/// Reusable employee attendance overview container.
///
/// Employee mode: welcome line + Biometric Attendance, Attendance, Leave summary cards,
/// monthly overview, and upcoming leave.
///
/// Admin portal mode ([adminPortal]: true): Biometric Attendance only (no Attendance /
/// Leave Balance cards), no upcoming leave, monthly overview, then the full
/// **My Attendance** table on the same scroll — admin-only layout.
class EmployeeAttendanceOverviewSection extends StatelessWidget {
  const EmployeeAttendanceOverviewSection({
    super.key,
    required this.displayName,
    this.onViewAttendance,
    this.adminPortal = false,
  });

  final String displayName;
  final VoidCallback? onViewAttendance;
  final bool adminPortal;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isNarrow = w < 600;
    final isTiny = w < 360;
    final welcomeSize = isTiny ? 17.0 : (isNarrow ? 19.0 : 24.0);
    final subtitleSize = isNarrow ? 13.5 : 15.0;

    final header = adminPortal
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Attendance',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: welcomeSize,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'View your time-in/out records.',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: subtitleSize,
                  height: 1.35,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                personalizedTimeGreeting(displayName),
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: welcomeSize,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: -0.35,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                "Here's your latest information and updates.",
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: subtitleSize,
                  height: 1.35,
                ),
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(height: isNarrow ? 18 : 24),
        EmployeeAttendanceOverviewCard(
          onViewMore: adminPortal ? null : onViewAttendance,
          summaryCards: adminPortal
              ? const _EmployeeClockInOnlySummary()
              : _EmployeeSummaryCards(
                  isNarrow: isNarrow,
                  onViewAttendance: onViewAttendance,
                ),
          upcomingLeave: adminPortal
              ? null
              : const _EmployeeUpcomingLeaveCard(embedded: true),
        ),
        if (adminPortal) ...[
          const SizedBox(height: 24),
          const EmployeeAttendanceDetailsSection(showPageHeader: false),
        ],
      ],
    );
  }
}

/// Biometric Attendance card only — used for admin My Attendance overview (no Attendance /
/// Leave Balance strip).
class _EmployeeClockInOnlySummary extends StatelessWidget {
  const _EmployeeClockInOnlySummary();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final singleColumn = w < 500;
    final biometricAttendance = _BiometricAttendanceCard();
    if (singleColumn) return biometricAttendance;
    return Row(children: [Expanded(child: biometricAttendance)]);
  }
}

/// Reusable detailed "My Attendance" table/list.
class EmployeeAttendanceDetailsSection extends StatelessWidget {
  const EmployeeAttendanceDetailsSection({
    super.key,
    this.showPageHeader = true,
  });

  final bool showPageHeader;

  @override
  Widget build(BuildContext context) {
    return _EmployeeAttendanceContent(showPageHeader: showPageHeader);
  }
}

class _EmployeeLeaveMainEntry extends StatefulWidget {
  const _EmployeeLeaveMainEntry({
    super.key,
    this.initialSection,
    this.onFileLeavePressed,
    this.hideFileLeaveAction = false,
  });

  final LeaveSection? initialSection;
  final VoidCallback? onFileLeavePressed;
  final bool hideFileLeaveAction;

  @override
  State<_EmployeeLeaveMainEntry> createState() =>
      _EmployeeLeaveMainEntryState();
}

class _EmployeeLeaveMainEntryState extends State<_EmployeeLeaveMainEntry> {
  Future<bool>? _deptHeadFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _deptHeadFuture ??= context.read<LeaveProvider>().checkIsDepartmentHead();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _deptHeadFuture,
      builder: (context, snapshot) {
        final isDeptHead = snapshot.data ?? false;
        if (snapshot.connectionState != ConnectionState.done) {
          final compact = MediaQuery.sizeOf(context).width < 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Leave Management',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'View leave balances, file requests, and track approvals.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              MyLeaveLoadingSkeleton(compact: compact),
            ],
          );
        }
        return LeaveMain(
          isAdmin: false,
          isDepartmentHead: isDeptHead,
          initialSection: widget.initialSection,
          onFileLeavePressed: widget.onFileLeavePressed,
          hideEmployeeFileLeaveAction: widget.hideFileLeaveAction,
        );
      },
    );
  }
}

/// Light sidebar: clean nav (same destinations as before), user block, footer.
class _EmployeeSidebar extends StatelessWidget {
  const _EmployeeSidebar({
    required this.displayName,
    this.avatarPath,
    required this.selectedIndex,
    required this.onTap,
    this.showBrand = true,
    this.railMode = false,
    this.collapsed = false,
  });

  final String displayName;
  final String? avatarPath;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool showBrand;
  final bool railMode;
  final bool collapsed;

  Widget _buildNavList({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: railMode ? 12 : (showBrand ? 4 : 12)),
        DashboardSidebarNavTile(
          icon: Icons.home_outlined,
          label: 'Dashboard',
          selected: selectedIndex == 0,
          onTap: () => onTap(0),
        ),
        DashboardSidebarNavTile(
          icon: Icons.event_available_outlined,
          label: 'My Attendance',
          selected: selectedIndex == 1,
          onTap: () => onTap(1),
        ),
        DashboardSidebarNavTile(
          icon: Icons.event_busy_outlined,
          label: 'My Leave',
          selected: selectedIndex == 2,
          onTap: () => onTap(2),
        ),
        DashboardSidebarNavTile(
          icon: Icons.pin_drop_outlined,
          label: 'Locator Requests',
          selected: selectedIndex == 3,
          onTap: () => onTap(3),
        ),
        DashboardSidebarNavTile(
          icon: Icons.assignment_outlined,
          label: 'Training Reports',
          selected: selectedIndex == 4,
          onTap: () => onTap(4),
        ),
        DashboardSidebarNavTile(
          icon: Icons.fact_check_outlined,
          label: 'Training Requirements',
          selected: selectedIndex == 5,
          onTap: () => onTap(5),
        ),
        DashboardSidebarNavTile(
          icon: Icons.description_outlined,
          label: 'DocuTracker',
          selected: selectedIndex == 6,
          onTap: () => onTap(6),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, {required bool compact}) {
    final t = SidebarCollapseScope.maybeOf(context) ?? (compact ? 1.0 : 0.0);
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
          padding: EdgeInsets.fromLTRB(
            lerpDouble(12, 8, t)!,
            4,
            lerpDouble(12, 8, t)!,
            lerpDouble(10, 8, t)!,
          ),
          child: DashboardSidebarProfileCard(
            displayName: displayName,
            subtitle: 'Employee',
            avatarPath: avatarPath,
          ),
        ),
        Opacity(
          opacity: fadeExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Text(
                  '© ${DateTime.now().year} HRMS',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(
                      context,
                    ).withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryNavy,
                        ),
                      ),
                    ),
                    Text(
                      ' | ',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: Text(
                        'Terms',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: lerpDouble(16, 12, t)!),
      ],
    );
  }

  Widget _buildRail({
    required BuildContext context,
    required Color hairline,
    required Color canvas,
  }) {
    return DashboardSidebarRailFrame(
      hairline: hairline,
      canvas: canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SidebarRailHeader(),
          Expanded(
            child: Builder(
              builder: (context) {
                final t = SidebarCollapseScope.of(context);
                return ColoredBox(
                  color: Color.lerp(canvas, Colors.transparent, t)!,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildNavList(compact: false),
                        ),
                      ),
                      _buildFooter(context, compact: false),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final canvas = AppTheme.dashCanvasOf(context);
    final panel = AppTheme.dashPanelOf(context);

    if (railMode) {
      return AnimatedSidebarWidth(
        collapsed: collapsed,
        child: _buildRail(context: context, hairline: hairline, canvas: canvas),
      );
    }

    return Container(
      width: kDashboardSidebarWidth,
      decoration: BoxDecoration(
        color: panel,
        border: Border(right: BorderSide(color: hairline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(1, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          if (showBrand) const PortalSidebarBrand(),
          Expanded(
            child: SingleChildScrollView(child: _buildNavList(compact: false)),
          ),
          _buildFooter(context, compact: false),
        ],
      ),
    );
  }
}

/// Main content: welcome, 4 cards (Biometric Attendance, Attendance, Leave Balance, My Payslip), Upcoming Leave, Attendance Overview.
class _EmployeeDashboardContent extends StatefulWidget {
  const _EmployeeDashboardContent({
    required this.displayName,
    this.onViewAttendance,
    this.onViewLeave,
  });

  final String displayName;
  final VoidCallback? onViewAttendance;
  final VoidCallback? onViewLeave;

  @override
  State<_EmployeeDashboardContent> createState() =>
      _EmployeeDashboardContentState();
}

class _EmployeeDashboardContentState extends State<_EmployeeDashboardContent> {
  Timer? _pollingTimer;
  StreamSubscription<DtrUpdateEvent>? _dtrUpdateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dtr = context.read<DtrProvider>();
      dtr.loadTodayRecord();
      dtr.loadMyShiftToday();
      final uid = context.read<AuthProvider>().user?.id;
      if (uid != null && uid.isNotEmpty) {
        context.read<LeaveProvider>().loadMyLeaveData(uid);
      }
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      dtr.loadTimeRecordsForUser(startDate: start, endDate: end);
      _dtrUpdateSub = dtr.onDtrEvent.listen((event) {
        if (!mounted) return;
        final userId = context.read<AuthProvider>().user?.id;
        if (!event.affectsUser(userId)) return;
        final currentDtr = context.read<DtrProvider>();
        if (currentDtr.loading) return;
        currentDtr.loadTodayRecord();
      });
    });
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final dtr = context.read<DtrProvider>();
      if (dtr.loading) return;
      dtr.loadTodayRecord();
      // Month list is loaded by [EmployeeAttendanceOverviewCard] / My Attendance;
      // avoid overwriting the provider with a fixed "current month" every tick.
    });
  }

  @override
  void dispose() {
    _dtrUpdateSub?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isNarrow = w < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmployeeWelcomeBanner(
          displayName: widget.displayName,
          isNarrow: isNarrow,
        ),
        SizedBox(height: isNarrow ? 14 : 28),
        EmployeeAttendanceOverviewCard(
          onViewMore: widget.onViewAttendance,
          summaryCards: _EmployeeSummaryCards(
            isNarrow: isNarrow,
            onViewAttendance: widget.onViewAttendance,
          ),
          upcomingLeave: _EmployeeUpcomingLeaveCard(
            embedded: true,
            onViewMore: widget.onViewLeave,
          ),
        ),
        SizedBox(height: isNarrow ? 18 : 28),
        EmployeeSectionHeader(
          title: 'DocuTracker',
          icon: Icons.folder_copy_outlined,
          subtitle: 'Your documents and routing status',
        ),
        SizedBox(height: isNarrow ? 10 : 14),
        Container(
          padding: EdgeInsets.all(
            isNarrow ? 12 : employeeSectionCardPadding(context),
          ),
          decoration: EmployeeDashUi.elevatedPanel(context),
          child: const DocuTrackerDashboardScreen(
            isAdmin: false,
            showTitle: false,
            embedded: true,
          ),
        ),
        SizedBox(height: isNarrow ? 20 : 32),
      ],
    );
  }
}

class _EmployeeSummaryCards extends StatelessWidget {
  const _EmployeeSummaryCards({required this.isNarrow, this.onViewAttendance});

  final bool isNarrow;
  final VoidCallback? onViewAttendance;

  /// Summary row: Biometric Attendance, Attendance, Leave balance. [_PayslipCard] omitted for now.

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final singleColumn = w < 500;
    final twoRows = w < 800 && !singleColumn;
    final cardGap = w < 600 ? 12.0 : 16.0;

    Widget biometricAttendance = _BiometricAttendanceCard(compact: w < 600);
    Widget attendance = _AttendanceCard(
      onViewAttendance: onViewAttendance,
      compact: w < 600,
    );
    Widget leaveBalance = _LeaveBalanceCard(compact: w < 600);
    if (w < 600) {
      return EmployeeSummaryMobileLayout(
        clockIn: biometricAttendance,
        attendance: attendance,
        leaveBalance: leaveBalance,
        gap: cardGap,
      );
    }
    if (singleColumn) {
      return Column(
        children: [
          biometricAttendance,
          SizedBox(height: cardGap),
          attendance,
          SizedBox(height: cardGap),
          leaveBalance,
        ],
      );
    }
    if (twoRows) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: biometricAttendance),
              SizedBox(width: cardGap),
              Expanded(child: attendance),
            ],
          ),
          SizedBox(height: cardGap),
          Row(children: [Expanded(child: leaveBalance)]),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: biometricAttendance),
        SizedBox(width: cardGap),
        Expanded(child: attendance),
        SizedBox(width: cardGap),
        Expanded(child: leaveBalance),
      ],
    );
  }
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '—';
  final local = dt.toLocal();
  final h = local.hour;
  final m = local.minute;
  final ampm = h >= 12 ? 'PM' : 'AM';
  final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
  return '$h12:${m.toString().padLeft(2, '0')} $ampm';
}

class _BiometricAttendanceCard extends StatelessWidget {
  const _BiometricAttendanceCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<DtrProvider>(
      builder: (context, dtr, _) {
        final record = dtr.todayRecord;
        final isHoliday =
            record != null &&
            (record.status == 'holiday' || record.holidayId != null);
        final hasAmIn = record != null && record.timeIn != null;
        final hasAmOut = record != null && record.breakOut != null;
        final hasPmIn = record != null && record.breakIn != null;
        final hasPmOut = record != null && record.timeOut != null;
        final isAfternoonOnly = hasPmIn && !hasAmIn;
        final isComplete =
            (hasAmIn && hasAmOut && hasPmIn && hasPmOut) ||
            (isAfternoonOnly && hasPmOut);
        final latestPunch =
            record?.timeOut ??
            record?.breakIn ??
            record?.breakOut ??
            record?.timeIn;
        final label = isHoliday
            ? 'Holiday'
            : isComplete
            ? 'Attendance Complete'
            : 'Today\'s Attendance';
        final primaryValue = isHoliday
            ? 'No log required'
            : latestPunch == null
            ? 'No punch yet'
            : _formatTime(latestPunch);
        final statusText = isHoliday
            ? 'No attendance log required for today.'
            : record == null
            ? 'Your biometric punches will appear here.'
            : isComplete
            ? 'Your attendance for today is complete.'
            : 'Your latest punch has been recorded. Your next punch will appear here automatically.';

        final narrow = MediaQuery.sizeOf(context).width < 600;
        final compactLayout = compact || narrow;
        final detailFontSize = compactLayout ? 10.0 : 11.0;

        return Container(
          padding: EdgeInsets.all(
            compactLayout ? 12 : employeeCardPadding(context),
          ),
          decoration: EmployeeDashUi.summaryCard(
            context: context,
            tint: const Color(0xFFFFF7ED),
            accent: AppTheme.primaryNavy,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: EmployeeDashUi.metricLabel(context),
              ),
              SizedBox(height: compactLayout ? 8 : 12),
              Text(
                primaryValue,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: compactLayout ? 22 : 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: compactLayout ? 11 : 12,
                  height: 1.35,
                ),
              ),
              if (record != null &&
                  (record.timeIn != null || record.breakIn != null)) ...[
                const SizedBox(height: 6),
                Text(
                  record.timeIn != null
                      ? 'AM In: ${_formatTime(record.timeIn)}  AM Out: ${_formatTime(record.breakOut)}  PM In: ${_formatTime(record.breakIn)}  PM Out: ${_formatTime(record.timeOut)}'
                      : 'AM: Absent  PM In: ${_formatTime(record.breakIn)}  PM Out: ${_formatTime(record.timeOut)}',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: detailFontSize,
                    height: 1.35,
                  ),
                  softWrap: true,
                ),
                if (record.source != null && record.source!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  AttendanceSourceBadge(source: record.source, compact: true),
                ],
              ],
              if (!compactLayout) ...[
                const SizedBox(height: 6),
                Text(
                  'Location: —',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                  ),
                ),
              ],
              SizedBox(height: compactLayout ? 10 : 16),
              if (!isHoliday &&
                  dtr.isBeforeShiftStart &&
                  dtr.myShiftStartFormatted != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Shift starts at ${dtr.myShiftStartFormatted}',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (!isHoliday &&
                  dtr.isPastShiftEnd &&
                  dtr.myShiftEndFormatted != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Shift has ended (${dtr.myShiftEndFormatted})',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compactLayout ? 12 : 14,
                  vertical: compactLayout ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: isComplete
                      ? Colors.green.withValues(alpha: 0.08)
                      : AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isComplete
                        ? Colors.green.withValues(alpha: 0.22)
                        : AppTheme.primaryNavy.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isComplete
                          ? Icons.check_circle_rounded
                          : Icons.fingerprint_rounded,
                      size: compactLayout ? 17 : 18,
                      color: isComplete
                          ? Colors.green.shade700
                          : AppTheme.primaryNavy,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isComplete
                            ? 'Today\'s attendance is complete'
                            : latestPunch == null
                            ? 'Use the biometric device to record attendance'
                            : 'Recorded through the biometric device',
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: compactLayout ? 11 : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({this.onViewAttendance, this.compact = false});

  final VoidCallback? onViewAttendance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<DtrProvider>(
      builder: (context, dtr, _) {
        final presentCount = dtr.timeRecords
            .where((r) => r.timeIn != null)
            .length;
        final now = DateTime.now();
        final monthLabel =
            '${now.year}-${now.month.toString().padLeft(2, '0')}';

        final compactLayout = compact || MediaQuery.sizeOf(context).width < 600;
        final content = Container(
          padding: EdgeInsets.all(
            compactLayout ? 12 : employeeCardPadding(context),
          ),
          decoration: EmployeeDashUi.summaryCard(
            context: context,
            tint: const Color(0xFFE8F5E9),
            accent: AttendanceOverviewColors.present,
          ),
          child: compactLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ATTENDANCE',
                            style: EmployeeDashUi.metricLabel(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.event_available_rounded,
                          color: AttendanceOverviewColors.present,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$presentCount',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Present Days',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      monthLabel,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ATTENDANCE',
                            style: EmployeeDashUi.metricLabel(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '$presentCount',
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Present Days',
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AttendanceOverviewColors.present
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              monthLabel,
                              style: TextStyle(
                                color: AppTheme.dashTextSecondaryOf(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: onViewAttendance,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryNavy,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('View details'),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded, size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const EmployeeSummaryIconAccent(
                      icon: Icons.event_available_rounded,
                      color: AttendanceOverviewColors.present,
                    ),
                  ],
                ),
        );

        if (!compactLayout || onViewAttendance == null) return content;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onViewAttendance,
            borderRadius: BorderRadius.circular(EmployeeDashUi.radiusMd),
            child: content,
          ),
        );
      },
    );
  }
}

class _LeaveBalanceCard extends StatelessWidget {
  const _LeaveBalanceCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<LeaveProvider>(
      builder: (context, leave, _) {
        final compactLayout = compact || MediaQuery.sizeOf(context).width < 600;
        final totalRemaining = leave.balances.fold<double>(
          0,
          (sum, b) => sum + b.remainingDays,
        );
        final vacation = leave.balances
            .where((b) => b.leaveType == LeaveType.vacationLeave)
            .toList();
        final sick = leave.balances
            .where((b) => b.leaveType == LeaveType.sickLeave)
            .toList();
        final vacationDays = vacation.isNotEmpty
            ? vacation.first.remainingDays
            : null;
        final sickDays = sick.isNotEmpty ? sick.first.remainingDays : null;

        final hasData = leave.balances.isNotEmpty;
        if (leave.loading && !hasData) {
          return LeaveBalanceSummaryCardSkeleton(
            padding: EdgeInsets.all(
              compactLayout ? 12 : employeeCardPadding(context),
            ),
          );
        }
        return Container(
          padding: EdgeInsets.all(
            compactLayout ? 12 : employeeCardPadding(context),
          ),
          decoration: EmployeeDashUi.summaryCard(
            context: context,
            tint: const Color(0xFFF3E5F5),
            accent: AttendanceOverviewColors.onLeave,
          ),
          child: compactLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'LEAVE',
                            style: EmployeeDashUi.metricLabel(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.event_note_rounded,
                          color: AttendanceOverviewColors.onLeave,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasData ? totalRemaining.toStringAsFixed(1) : '—',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Remaining Days',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'VL ${vacationDays != null ? vacationDays.toStringAsFixed(1) : '—'} / SL ${sickDays != null ? sickDays.toStringAsFixed(1) : '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'LEAVE BALANCE',
                            style: EmployeeDashUi.metricLabel(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            hasData ? totalRemaining.toStringAsFixed(1) : '—',
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Remaining Days',
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _LeaveBalanceMiniLine(
                                  icon: Icons.beach_access_rounded,
                                  label: 'Vacation',
                                  value: vacationDays != null
                                      ? vacationDays.toStringAsFixed(1)
                                      : '—',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _LeaveBalanceMiniLine(
                                  icon: Icons.medical_services_outlined,
                                  label: 'Sick',
                                  value: sickDays != null
                                      ? sickDays.toStringAsFixed(1)
                                      : '—',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const EmployeeSummaryIconAccent(
                      icon: Icons.event_note_rounded,
                      color: AttendanceOverviewColors.onLeave,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _LeaveBalanceMiniLine extends StatelessWidget {
  const _LeaveBalanceMiniLine({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.dashTextSecondaryOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Re-enable in [_EmployeeSummaryCards] when payroll / payslip is ready.
// ignore: unused_element
class _PayslipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(employeeCardPadding(context)),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Payslip',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '—',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '—',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Next Payday: —',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('View Payslip'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeUpcomingLeaveCard extends StatelessWidget {
  const _EmployeeUpcomingLeaveCard({this.embedded = false, this.onViewMore});

  /// When true, omits outer card chrome (for use inside [EmployeeAttendanceOverviewCard]).
  final bool embedded;
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    final pad = embedded ? 0.0 : employeeSectionCardPadding(context);
    final innerPad = MediaQuery.sizeOf(context).width < 600 ? 12.0 : 16.0;

    Widget titleRow() {
      return EmployeeSectionHeader(
        title: 'Upcoming Leave',
        icon: Icons.event_outlined,
        subtitle: embedded ? 'Scheduled time off' : null,
      );
    }

    return Consumer<LeaveProvider>(
      builder: (context, provider, _) {
        final upcoming = provider.upcomingApprovedRequests;
        final showLoading =
            provider.loading && provider.requests.isEmpty && upcoming.isEmpty;
        final showError =
            provider.error != null && provider.requests.isEmpty && !showLoading;

        Widget leaveBody() {
          if (showLoading) {
            return _UpcomingLeaveMessage(
              icon: Icons.event_available_rounded,
              message: 'Loading upcoming leave...',
              showSpinner: true,
            );
          }

          if (showError) {
            return const _UpcomingLeaveMessage(
              icon: Icons.event_busy_rounded,
              message: 'Unable to load upcoming leave.',
            );
          }

          if (upcoming.isEmpty) {
            return const _UpcomingLeaveMessage(
              icon: Icons.event_rounded,
              message: 'No upcoming leave.',
            );
          }

          final visible = upcoming.take(2).toList();
          final remaining = upcoming.length - visible.length;
          return Container(
            padding: EdgeInsets.all(innerPad),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(EmployeeDashUi.radiusMd),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  _UpcomingLeaveTile(request: visible[i]),
                  if (i < visible.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(
                        height: 1,
                        color: AppTheme.dashHairlineOf(context),
                      ),
                    ),
                ],
                if (remaining > 0) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+$remaining more scheduled',
                      style: TextStyle(
                        color: AppTheme.primaryNavy,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, c) {
            final stackHeader = c.maxWidth < 400;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stackHeader) ...[
                  titleRow(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onViewMore,
                      style: EmployeeDashUi.ghostAction(context),
                      child: const Text('View More'),
                    ),
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleRow()),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onViewMore,
                        style: EmployeeDashUi.ghostAction(context),
                        child: const Text('View More'),
                      ),
                    ],
                  ),
                SizedBox(height: stackHeader ? 12 : 16),
                leaveBody(),
              ],
            );

            if (embedded) {
              return content;
            }

            return Container(
              padding: EdgeInsets.all(pad),
              decoration: EmployeeDashUi.elevatedPanel(context),
              child: content,
            );
          },
        );
      },
    );
  }
}

class _UpcomingLeaveMessage extends StatelessWidget {
  const _UpcomingLeaveMessage({
    required this.icon,
    required this.message,
    this.showSpinner = false,
  });

  final IconData icon;
  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final innerPad = MediaQuery.sizeOf(context).width < 600 ? 12.0 : 16.0;
    return Container(
      padding: EdgeInsets.all(innerPad),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(EmployeeDashUi.radiusMd),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          if (showSpinner) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AttendanceOverviewColors.onLeave,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AttendanceOverviewColors.onLeave.withValues(alpha: 0.1),
            ),
            child: Icon(
              icon,
              color: AttendanceOverviewColors.onLeave.withValues(alpha: 0.55),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingLeaveTile extends StatelessWidget {
  const _UpcomingLeaveTile({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final typeLabel = _employeeLeaveTypeLabel(request);
    final dateLabel = _employeeLeaveDateRange(request);
    final daysLabel = _employeeLeaveDaysLabel(request);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AttendanceOverviewColors.onLeave.withValues(alpha: 0.1),
          ),
          child: Icon(
            Icons.event_available_rounded,
            color: AttendanceOverviewColors.onLeave,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (daysLabel != null) ...[
                const SizedBox(height: 3),
                Text(
                  daysLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(
                      context,
                    ).withValues(alpha: 0.88),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AttendanceOverviewColors.onLeave.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Approved',
            style: TextStyle(
              color: AttendanceOverviewColors.onLeave,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

String _employeeLeaveTypeLabel(LeaveRequest request) {
  final custom = request.customLeaveTypeText?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final display = request.leaveTypeDisplayName?.trim();
  if (display != null && display.isNotEmpty) return display;
  return request.leaveType.displayName;
}

String _employeeLeaveDateRange(LeaveRequest request) {
  final start = request.startDate;
  final end = request.endDate;
  if (start == null && end == null) return 'Date not set';
  if (start == null) return _employeeLeaveDate(end!);
  if (end == null || _sameEmployeeLeaveDate(start, end)) {
    return _employeeLeaveDate(start);
  }
  return '${_employeeLeaveDate(start)} - ${_employeeLeaveDate(end)}';
}

String _employeeLeaveDate(DateTime date) {
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

bool _sameEmployeeLeaveDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String? _employeeLeaveDaysLabel(LeaveRequest request) {
  final approvedWithPay = request.approvedDaysWithPay;
  final approvedWithoutPay = request.approvedDaysWithoutPay;
  final hasApprovedDays = approvedWithPay != null || approvedWithoutPay != null;
  final days = hasApprovedDays
      ? (approvedWithPay ?? 0) + (approvedWithoutPay ?? 0)
      : request.workingDaysApplied;
  if (days == null || !days.isFinite || days <= 0) return null;
  final whole = days.roundToDouble();
  final value = (days - whole).abs() < 0.01
      ? whole.toStringAsFixed(0)
      : days.toStringAsFixed(1);
  return '$value ${days == 1 ? 'day' : 'days'}';
}

const List<String> _attendanceMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// My Attendance: employee's own time records.
class _EmployeeAttendanceContent extends StatefulWidget {
  const _EmployeeAttendanceContent({this.showPageHeader = true});

  /// When false, omits the title/subtitle (e.g. embedded under admin overview).
  final bool showPageHeader;

  @override
  State<_EmployeeAttendanceContent> createState() =>
      _EmployeeAttendanceContentState();
}

class _EmployeeAttendanceContentState
    extends State<_EmployeeAttendanceContent> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _selectedDay;
  bool _didApplyMobileDefault = false;
  String _mobileAttendanceMode = 'today';

  int get _lastDayOfSelectedMonth {
    final end = DateTime(_selectedYear, _selectedMonth + 1, 0);
    return end.day;
  }

  /// Latest day selectable in the current month/year (no future day picker values).
  int get _maxSelectableCalendarDay {
    final now = DateTime.now();
    final last = _lastDayOfSelectedMonth;
    if (_selectedYear < now.year ||
        (_selectedYear == now.year && _selectedMonth < now.month)) {
      return last;
    }
    if (_selectedYear > now.year ||
        (_selectedYear == now.year && _selectedMonth > now.month)) {
      return last;
    }
    return now.day < last ? now.day : last;
  }

  DateTime get _todayDateOnly {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  void _clampSelectedDayIfNeeded() {
    if (_selectedDay == null) return;
    final last = _lastDayOfSelectedMonth;
    final maxD = _maxSelectableCalendarDay;
    if (_selectedDay! > last) {
      _selectedDay = null;
      return;
    }
    if (_selectedDay! > maxD) {
      _selectedDay = maxD;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    _clampSelectedDayIfNeeded();
    final dtr = context.read<DtrProvider>();
    final lastDay = _lastDayOfSelectedMonth;
    final day =
        (_selectedDay != null && _selectedDay! >= 1 && _selectedDay! <= lastDay)
        ? _selectedDay!
        : 0;
    final DateTime start;
    final DateTime end;
    if (day >= 1) {
      start = DateTime(_selectedYear, _selectedMonth, day);
      end = start;
    } else {
      start = DateTime(_selectedYear, _selectedMonth, 1);
      final monthEnd = DateTime(_selectedYear, _selectedMonth + 1, 0);
      // For current month, don't fetch future days.
      end = monthEnd.isAfter(_todayDateOnly) ? _todayDateOnly : monthEnd;
    }
    await dtr.loadTimeRecordsForUser(startDate: start, endDate: end);
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  static String _formatTimeWithLocator(
    TimeRecord r,
    DateTime? dt,
    String segment,
  ) {
    if (dt != null) return _formatTime(dt);
    final segs = r.locatorSlipSegments ?? const <String>[];
    if (segs.any((s) => s.toUpperCase() == segment)) {
      return r.locatorSlipSlotLabel;
    }
    if (segs.isEmpty &&
        segment == 'AM IN' &&
        (r.status == 'on_field' || r.locatorSlipId != null)) {
      return r.locatorSlipSlotLabel;
    }
    return '—';
  }

  static const List<String> _shortWeekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String _formatDate(DateTime d) {
    final weekday = _shortWeekdays[d.weekday - 1];
    return '${d.day} $weekday';
  }

  void _selectDay(int? day, {String mobileMode = 'day'}) {
    setState(() {
      _mobileAttendanceMode = day == null ? 'monthly' : mobileMode;
      _selectedDay = day;
    });
    _load();
  }

  void _selectToday() {
    final today = _todayDateOnly;
    setState(() {
      _mobileAttendanceMode = 'today';
      _selectedMonth = today.month;
      _selectedYear = today.year;
      _selectedDay = today.day;
    });
    _load();
  }

  void _applyMobileDefaultIfNeeded() {
    if (_didApplyMobileDefault || _selectedDay != null) return;
    _didApplyMobileDefault = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _selectToday();
    });
  }

  Widget _buildMobileModeSelector() {
    final mode = _selectedDay == null ? 'monthly' : _mobileAttendanceMode;
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'today',
          icon: Icon(Icons.today_rounded, size: 16),
          label: Text('Today'),
        ),
        ButtonSegment(
          value: 'day',
          icon: Icon(Icons.calendar_view_day_rounded, size: 16),
          label: Text('Day'),
        ),
        ButtonSegment(
          value: 'monthly',
          icon: Icon(Icons.calendar_month_rounded, size: 16),
          label: Text('Monthly'),
        ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          AppTheme.dashFieldTextStyle(
            context,
          ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      onSelectionChanged: (values) {
        final value = values.first;
        if (value == 'today') {
          _selectToday();
        } else if (value == 'monthly') {
          _selectDay(null);
        } else if (value == 'day') {
          final today = _todayDateOnly;
          final day =
              _selectedDay ??
              (_selectedYear == today.year && _selectedMonth == today.month
                  ? today.day
                  : 1);
          _selectDay(day, mobileMode: 'day');
        }
      },
    );
  }

  Widget _buildMobileMonthCalendar() {
    if (_selectedDay == null || _mobileAttendanceMode == 'monthly') {
      return const SizedBox.shrink();
    }
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final firstDay = DateTime(_selectedYear, _selectedMonth, 1);
    final leadingBlanks = firstDay.weekday - 1;
    final maxSelectableDay = _maxSelectableCalendarDay;
    final totalCells = ((leadingBlanks + _lastDayOfSelectedMonth + 6) ~/ 7) * 7;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, index) {
              final day = index - leadingBlanks + 1;
              if (day < 1 || day > _lastDayOfSelectedMonth) {
                return const SizedBox.shrink();
              }
              final selected = _selectedDay == day;
              final disabled = day > maxSelectableDay;
              final isToday =
                  _selectedYear == _todayDateOnly.year &&
                  _selectedMonth == _todayDateOnly.month &&
                  day == _todayDateOnly.day;
              final bg = selected
                  ? AppTheme.primaryNavy
                  : isToday
                  ? AppTheme.primaryNavy.withValues(alpha: 0.1)
                  : AppTheme.dashMutedSurfaceOf(context);
              final fg = selected
                  ? Colors.white
                  : disabled
                  ? AppTheme.dashTextSecondaryOf(
                      context,
                    ).withValues(alpha: 0.45)
                  : AppTheme.dashTextPrimaryOf(context);

              return Material(
                color: bg,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: disabled
                      ? null
                      : () => _selectDay(day, mobileMode: 'day'),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected || isToday
                            ? AppTheme.primaryNavy.withValues(alpha: 0.65)
                            : AppTheme.dashHairlineOf(context),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: fg,
                          fontSize: 13,
                          fontWeight: selected || isToday
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileAttendanceList(List<TimeRecord> records) {
    return EmployeeAttendanceMobileList(
      records: records,
      formatDate: _formatDate,
      formatTime: _formatTimeWithLocator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final today = _todayDateOnly;
    final visibleRecords = List.of(dtr.timeRecords)
      ..removeWhere((r) {
        final rd = DateTime(
          r.recordDate.year,
          r.recordDate.month,
          r.recordDate.day,
        );
        return rd.isAfter(today);
      })
      ..sort(
        (a, b) => a.recordDate.compareTo(b.recordDate),
      ); // Day 1..N ascending

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showPageHeader) ...[
          Text(
            'My Attendance',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View your time-in/out records.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            if (isNarrow) _applyMobileDefaultIfNeeded();
            final monthWidth = isNarrow ? 150.0 : 172.0;
            final yearWidth = isNarrow ? 100.0 : 112.0;
            final dayWidth = isNarrow ? 115.0 : 144.0;
            const fieldPadding = EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            );

            Widget monthField() => SizedBox(
              width: monthWidth,
              child: DropdownButtonFormField<int>(
                initialValue: _selectedMonth,
                isExpanded: true,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  contentPadding: fieldPadding,
                  radius: 8,
                ),
                style: AppTheme.dashFieldTextStyle(context),
                dropdownColor: AppTheme.dashPanelOf(context),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
                selectedItemBuilder: (context) => List.generate(
                  12,
                  (i) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _attendanceMonths[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.dashFieldTextStyle(
                        context,
                      ).copyWith(fontSize: 14),
                    ),
                  ),
                ),
                items: List.generate(12, (i) => i + 1)
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                          _attendanceMonths[m - 1],
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedMonth = v;
                      if (isNarrow && _mobileAttendanceMode == 'today') {
                        _mobileAttendanceMode = 'day';
                      }
                      if (_selectedDay != null &&
                          _selectedDay! > _lastDayOfSelectedMonth) {
                        _selectedDay = null;
                      }
                      _clampSelectedDayIfNeeded();
                    });
                    _load();
                  }
                },
              ),
            );

            Widget yearField() => SizedBox(
              width: yearWidth,
              child: DropdownButtonFormField<int>(
                initialValue: _selectedYear,
                isExpanded: true,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  contentPadding: fieldPadding,
                  radius: 8,
                ),
                style: AppTheme.dashFieldTextStyle(context),
                dropdownColor: AppTheme.dashPanelOf(context),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
                selectedItemBuilder: (context) => List.generate(
                  11,
                  (i) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${DateTime.now().year - 5 + i}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.dashFieldTextStyle(
                        context,
                      ).copyWith(fontSize: 14),
                    ),
                  ),
                ),
                items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedYear = v;
                      if (isNarrow && _mobileAttendanceMode == 'today') {
                        _mobileAttendanceMode = 'day';
                      }
                      if (_selectedDay != null &&
                          _selectedDay! > _lastDayOfSelectedMonth) {
                        _selectedDay = null;
                      }
                      _clampSelectedDayIfNeeded();
                    });
                    _load();
                  }
                },
              ),
            );

            Widget dayField() => SizedBox(
              width: dayWidth,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedDay,
                isExpanded: true,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  contentPadding: fieldPadding,
                  radius: 8,
                ),
                style: AppTheme.dashFieldTextStyle(context),
                dropdownColor: AppTheme.dashPanelOf(context),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
                hint: Text(
                  'All days',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.dashFieldTextStyle(
                    context,
                  ).copyWith(fontSize: 14),
                ),
                selectedItemBuilder: (context) => [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'All days',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.dashFieldTextStyle(
                        context,
                      ).copyWith(fontSize: 14),
                    ),
                  ),
                  ...List.generate(
                    _maxSelectableCalendarDay,
                    (i) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Day ${i + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.dashFieldTextStyle(
                          context,
                        ).copyWith(fontSize: 14),
                      ),
                    ),
                  ),
                ],
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('All days'),
                  ),
                  ...List.generate(_maxSelectableCalendarDay, (i) => i + 1).map(
                    (d) =>
                        DropdownMenuItem<int?>(value: d, child: Text('Day $d')),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _selectedDay = v);
                  _load();
                },
              ),
            );

            final refreshButton = IconButton(
              onPressed: () {
                final now = DateTime.now();
                setState(() {
                  _mobileAttendanceMode = isNarrow ? 'today' : 'monthly';
                  _selectedMonth = now.month;
                  _selectedYear = now.year;
                  _selectedDay = isNarrow ? now.day : null;
                });
                _load();
              },
              icon: Icon(
                Icons.refresh_rounded,
                size: 22,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              tooltip: 'Reset filters',
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [monthField(), yearField(), refreshButton],
                  ),
                  const SizedBox(height: 12),
                  _buildMobileModeSelector(),
                  const SizedBox(height: 12),
                  _buildMobileMonthCalendar(),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                monthField(),
                const SizedBox(width: 12),
                yearField(),
                const SizedBox(width: 12),
                dayField(),
                const SizedBox(width: 4),
                refreshButton,
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (dtr.loading) const EmployeeTimeRecordsLoadingSkeleton(),
        if (!dtr.loading && visibleRecords.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No time records for the selected period.',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!dtr.loading && visibleRecords.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return _buildMobileAttendanceList(visibleRecords);
              }

              const minTableWidth = 860.0;
              final tableWidth = constraints.maxWidth < minTableWidth
                  ? minTableWidth
                  : constraints.maxWidth;
              final cellStyle = TextStyle(
                fontSize: 13,
                color: AppTheme.dashTextPrimaryOf(context),
              );
              final headerStyle = TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.dashTextPrimaryOf(context),
              );
              return Container(
                clipBehavior: Clip.antiAlias,
                decoration: AppTheme.dashSurfaceCard(context, radius: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.dashMutedSurfaceOf(context),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: AppTheme.dashHairlineOf(context),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('Date', style: headerStyle),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('AM In', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('AM Out', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('PM In', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('PM Out', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('Late', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('Undertime', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text('Remarks', style: headerStyle),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text('Source', style: headerStyle),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...visibleRecords.asMap().entries.map((entry) {
                          final i = entry.key;
                          final isLastRow = i == visibleRecords.length - 1;
                          final r = entry.value;
                          final timeIn = r.timeIn?.toLocal();
                          final breakOut = r.breakOut?.toLocal();
                          final breakIn = r.breakIn?.toLocal();
                          final timeOut = r.timeOut?.toLocal();
                          final remark = getAttendanceRemark(r);
                          final lateStr = formatLateMinutes(r);
                          final underStr = formatUndertimeMinutes(r);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: i % 2 == 0
                                  ? AppTheme.dashPanelOf(context)
                                  : AppTheme.dashMutedSurfaceOf(context),
                              borderRadius: isLastRow
                                  ? const BorderRadius.vertical(
                                      bottom: Radius.circular(12),
                                    )
                                  : null,
                              border: i > 0
                                  ? Border(
                                      top: BorderSide(
                                        color: AppTheme.dashHairlineOf(context),
                                      ),
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatDate(r.recordDate),
                                    style: cellStyle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      _formatTimeWithLocator(
                                        r,
                                        timeIn,
                                        'AM IN',
                                      ),
                                      style: cellStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      _formatTimeWithLocator(
                                        r,
                                        breakOut,
                                        'AM OUT',
                                      ),
                                      style: cellStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      _formatTimeWithLocator(
                                        r,
                                        breakIn,
                                        'PM IN',
                                      ),
                                      style: cellStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      _formatTimeWithLocator(
                                        r,
                                        timeOut,
                                        'PM OUT',
                                      ),
                                      style: cellStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      lateStr,
                                      style: cellStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      underStr,
                                      style: cellStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: AttendanceRemarksChip(
                                      remark: remark,
                                      isHoliday:
                                          r.status == 'holiday' ||
                                          r.holidayId != null,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: AttendanceSourceBadge(
                                      source: r.source,
                                      compact: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _EmployeePlaceholderContent extends StatelessWidget {
  const _EmployeePlaceholderContent({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_rounded,
                size: 56,
                color: AppTheme.primaryNavy.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming soon',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
