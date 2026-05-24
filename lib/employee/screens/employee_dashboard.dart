import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../landingpage/constants/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../dtr/dtr_provider.dart';
import '../../../data/time_record.dart';
import '../../../dtr/widgets/attendance_display.dart';
import '../../../dtr/widgets/attendance_source_badge.dart';
import '../../../docutracker/docutracker_main.dart';
import '../../../docutracker/screens/docutracker_dashboard_screen.dart';
import '../../../leave/leave_main.dart';
import '../../../leave/leave_provider.dart';
import '../../../notifications/notification_provider.dart';
import '../../../notifications/notification_tap_result.dart';
import '../../../notifications/open_notifications_panel.dart';
import '../../../leave/widgets/my_leave_loading_skeleton.dart';
import '../../../locator/screens/employee_locator_slip_screen.dart';
import '../../../leave/models/leave_type.dart';
import '../../../ld/training_daily_report_employee_screen.dart';
import '../widgets/attendance_overview/attendance_overview.dart';
import '../widgets/employee_dash_ui.dart';
import '../widgets/employee_dashboard_skeletons.dart';
import '../../shared/screens/profile_page.dart' show DashboardProfilePanel;
import '../../shared/widgets/dashboard_content_navigator.dart';
import '../../shared/widgets/dashboard_header_actions.dart';
import '../../shared/utils/time_greeting.dart';
import '../../shared/widgets/collapsible_dashboard_sidebar.dart';
import '../../shared/widgets/dashboard_mobile_bottom_nav.dart';
import '../../shared/widgets/portal_sidebar_brand.dart';

/// Main scroll padding: comfortable insets on phones (narrower gutters still breathe).
EdgeInsets _employeeMainScrollPadding(BuildContext context, {bool mobileNav = false}) {
  final mq = MediaQuery.of(context);
  final w = mq.size.width;
  final horizontal = w > 900 ? 24.0 : (w > 600 ? 20.0 : 18.0);
  final top = w < 600 ? 4.0 : 8.0;
  var bottom = 28.0 + (w < 600 ? mq.padding.bottom * 0.5 : 0.0);
  if (mobileNav) {
    bottom += DashboardMobileBottomNav.scrollPaddingExtra(context);
  }
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

/// Sidebar destinations mirrored on the mobile bottom bar (profile stays in account menu).
const _employeeMobileNavItems = [
  DashboardMobileNavItem(icon: Icons.home_outlined, label: 'Dashboard'),
  DashboardMobileNavItem(
    icon: Icons.event_available_outlined,
    label: 'My Attendance',
    shortLabel: 'Attendance',
  ),
  DashboardMobileNavItem(
    icon: Icons.event_busy_outlined,
    label: 'My Leave',
    shortLabel: 'Leave',
  ),
  DashboardMobileNavItem(
    icon: Icons.pin_drop_outlined,
    label: 'Locator Slip',
    shortLabel: 'Locator',
  ),
  DashboardMobileNavItem(
    icon: Icons.assignment_outlined,
    label: 'Training Reports',
    shortLabel: 'Training',
  ),
  DashboardMobileNavItem(icon: Icons.description_outlined, label: 'DocuTracker'),
];

double _employeeCardPadding(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 16.0 : 20.0;
}

double _employeeSectionCardPadding(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
}

/// Employee dashboard reference: dark blue sidebar (HR branding), nav items,
/// welcome + Clock In, Attendance, Leave Balance, Payslip cards,
/// Upcoming Leave, Attendance Overview.
class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard>
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
    'Locator Slip',
    'Training Reports',
    'DocuTracker',
  ];

  /// Shown only via account menu (not listed in sidebar).
  static const int _profileNavIndex = 6;
  static const _settingsPanelKey = PageStorageKey<String>('employee_settings');
  late final Widget _settingsPanel = const DashboardProfilePanel(
    key: _settingsPanelKey,
  );
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DashboardContentNavigator.openSettings(_contentNavKey);
    });
  }

  void _onNavSelected(int index) {
    if (index == _profileNavIndex) {
      _openMyProfile();
      return;
    }
    setState(() => _selectedNavIndex = index);
    DashboardContentNavigator.showHome(_contentNavKey);
  }

  Widget _employeeMainChild({required String displayName}) {
    switch (_selectedNavIndex) {
      case 0:
        return _EmployeeDashboardContent(
          displayName: displayName,
          onViewAttendance: () => setState(() => _selectedNavIndex = 1),
        );
      case 1:
        return const _EmployeeAttendanceContent();
      case 2:
        return _EmployeeLeaveMainEntry(
          key: ValueKey(_leaveNavKey),
          initialSection: _leaveInitialSection,
        );
      case 3:
        return const EmployeeLocatorSlipScreen();
      case 4:
        return const TrainingDailyReportEmployeeScreen();
      case 5:
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

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      bottomNavigationBar: isWide
          ? null
          : DashboardMobileBottomNav(
              items: _employeeMobileNavItems,
              selectedIndex:
                  _selectedNavIndex < _employeeMobileNavItems.length
                      ? _selectedNavIndex
                      : -1,
              onSelected: _onNavSelected,
            ),
      body: SafeArea(
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EmployeeSidebar(
                    railMode: true,
                    collapsed: _sidebarCollapsed,
                    showBrand: false,
                    displayName: displayName,
                    avatarPath: avatarPath,
                    selectedIndex: _selectedNavIndex,
                    onTap: _onNavSelected,
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
                              homeBuilder: () =>
                                  _employeeMainChild(displayName: displayName),
                              settingsPanel: _settingsPanel,
                              homeScrollPadding: _employeeMainScrollPadding(
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
              )
            : Column(
                children: [
                  DashboardAppHeaderBar(
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
                        homeBuilder: () =>
                            _employeeMainChild(displayName: displayName),
                        settingsPanel: _settingsPanel,
                        homeScrollPadding: _employeeMainScrollPadding(
                          context,
                          mobileNav: true,
                        ),
                        settingsScrollPadding: EdgeInsets.fromLTRB(
                          12,
                          8,
                          12,
                          28 +
                              DashboardMobileBottomNav.scrollPaddingExtra(
                                context,
                              ),
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

/// Reusable employee attendance overview container.
///
/// Employee mode: welcome line + Clock In, Attendance, Leave summary cards,
/// monthly overview, and upcoming leave.
///
/// Admin portal mode ([adminPortal]: true): Clock In only (no Attendance /
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

/// Clock In card only — used for admin My Attendance overview (no Attendance /
/// Leave Balance strip).
class _EmployeeClockInOnlySummary extends StatelessWidget {
  const _EmployeeClockInOnlySummary();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final singleColumn = w < 500;
    final clockIn = _ClockInCard();
    if (singleColumn) return clockIn;
    return Row(children: [Expanded(child: clockIn)]);
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
  const _EmployeeLeaveMainEntry({super.key, this.initialSection});

  final LeaveSection? initialSection;

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
          collapsed: compact,
          onTap: () => onTap(0),
        ),
        DashboardSidebarNavTile(
          icon: Icons.event_available_outlined,
          label: 'My Attendance',
          selected: selectedIndex == 1,
          collapsed: compact,
          onTap: () => onTap(1),
        ),
        DashboardSidebarNavTile(
          icon: Icons.event_busy_outlined,
          label: 'My Leave',
          selected: selectedIndex == 2,
          collapsed: compact,
          onTap: () => onTap(2),
        ),
        DashboardSidebarNavTile(
          icon: Icons.pin_drop_outlined,
          label: 'Locator Slip',
          selected: selectedIndex == 3,
          collapsed: compact,
          onTap: () => onTap(3),
        ),
        DashboardSidebarNavTile(
          icon: Icons.assignment_outlined,
          label: 'Training Reports',
          selected: selectedIndex == 4,
          collapsed: compact,
          onTap: () => onTap(4),
        ),
        DashboardSidebarNavTile(
          icon: Icons.description_outlined,
          label: 'DocuTracker',
          selected: selectedIndex == 5,
          collapsed: compact,
          onTap: () => onTap(5),
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
        child: _buildRail(
          context: context,
          hairline: hairline,
          canvas: canvas,
        ),
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

/// Main content: welcome, 4 cards (Clock In, Attendance, Leave Balance, My Payslip), Upcoming Leave, Attendance Overview.
class _EmployeeDashboardContent extends StatefulWidget {
  const _EmployeeDashboardContent({
    required this.displayName,
    this.onViewAttendance,
  });

  final String displayName;
  final VoidCallback? onViewAttendance;

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
        SizedBox(height: isNarrow ? 22 : 28),
        EmployeeAttendanceOverviewCard(
          onViewMore: widget.onViewAttendance,
          summaryCards: _EmployeeSummaryCards(
            isNarrow: isNarrow,
            onViewAttendance: widget.onViewAttendance,
          ),
          upcomingLeave: const _EmployeeUpcomingLeaveCard(embedded: true),
        ),
        SizedBox(height: isNarrow ? 22 : 28),
        EmployeeSectionHeader(
          title: 'DocuTracker',
          icon: Icons.folder_copy_outlined,
          subtitle: 'Your documents and routing status',
        ),
        const SizedBox(height: 14),
        Container(
          padding: EdgeInsets.all(_employeeSectionCardPadding(context)),
          decoration: EmployeeDashUi.elevatedPanel(context),
          child: const DocuTrackerDashboardScreen(
            isAdmin: false,
            showTitle: false,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _EmployeeSummaryCards extends StatelessWidget {
  const _EmployeeSummaryCards({required this.isNarrow, this.onViewAttendance});

  final bool isNarrow;
  final VoidCallback? onViewAttendance;

  /// Summary row: Clock In, Attendance, Leave balance. [_PayslipCard] omitted for now.

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final singleColumn = w < 500;
    final twoRows = w < 800 && !singleColumn;
    final cardGap = w < 600 ? 12.0 : 16.0;

    Widget clockIn = _ClockInCard();
    Widget attendance = _AttendanceCard(onViewAttendance: onViewAttendance);
    Widget leaveBalance = _LeaveBalanceCard();
    if (singleColumn) {
      return Column(
        children: [
          clockIn,
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
              Expanded(child: clockIn),
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
        Expanded(child: clockIn),
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

class _ClockInCard extends StatelessWidget {
  static const int _noonHour = 12;

  @override
  Widget build(BuildContext context) {
    return Consumer<DtrProvider>(
      builder: (context, dtr, _) {
        final record = dtr.todayRecord;
        final isHoliday =
            record != null &&
            (record.status == 'holiday' || record.holidayId != null);
        final now = DateTime.now();
        final isMorning = now.hour < _noonHour;
        final hasAmIn = record != null && record.timeIn != null;
        final hasAmOut = record != null && record.breakOut != null;
        final hasPmIn = record != null && record.breakIn != null;
        final hasPmOut = record != null && record.timeOut != null;
        final isAfternoonOnly = hasPmIn && !hasAmIn;
        final isComplete =
            (hasAmIn && hasAmOut && hasPmIn && hasPmOut) ||
            (isAfternoonOnly && hasPmOut);

        String label = 'Clock In';
        String? nextAction;
        Future<bool> Function()? onTap;
        if (isHoliday) {
          label = 'Holiday';
          nextAction = null;
          onTap = null;
        } else if (record == null) {
          if (isMorning) {
            label = 'AM In';
            nextAction = 'AM In';
            onTap = () => dtr.clockIn();
          } else {
            label = 'PM In';
            nextAction = 'PM In';
            onTap = () => dtr.clockPmInAsFirst();
          }
        } else if (!hasAmIn) {
          if (!hasPmIn) {
            label = 'PM In';
            nextAction = 'PM In';
            onTap = () => dtr.clockPmInAsFirst();
          } else if (!hasPmOut) {
            label = 'PM Out';
            nextAction = 'PM Out';
            onTap = () => dtr.clockOut();
          } else {
            label = 'Clocked Out';
            nextAction = null;
            onTap = null;
          }
        } else if (!hasAmOut) {
          label = 'AM Out';
          nextAction = 'AM Out';
          onTap = () => dtr.clockAmOut();
        } else if (!hasPmIn) {
          label = 'PM In';
          nextAction = 'PM In';
          onTap = () => dtr.clockPmIn();
        } else if (!hasPmOut) {
          label = 'PM Out';
          nextAction = 'PM Out';
          onTap = () => dtr.clockOut();
        } else {
          label = 'Clocked Out';
          nextAction = null;
          onTap = null;
        }

        // Block ALL clock actions when outside shift window (before start or after end)
        final isShiftDisabled = onTap != null && dtr.isOutsideShiftWindow;

        final narrow = MediaQuery.sizeOf(context).width < 600;
        final detailFontSize = narrow ? 10.0 : 11.0;

        return Container(
          padding: EdgeInsets.all(_employeeCardPadding(context)),
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
              if (isHoliday)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No clock in/out required',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _formatTime(
                  record?.timeOut ??
                      record?.breakIn ??
                      record?.breakOut ??
                      record?.timeIn,
                ),
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
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
              const SizedBox(height: 6),
              Text(
                'Location: —',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              if (isShiftDisabled &&
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
              if (isShiftDisabled &&
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
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: dtr.loading || onTap == null || isShiftDisabled
                      ? null
                      : () async {
                          final ok = await onTap!();
                          if (context.mounted) {
                            if (dtr.error != null) {
                              final err = dtr.error!;
                              final isShiftEndError =
                                  err.toLowerCase().contains('shift') &&
                                  (err.toLowerCase().contains('end') ||
                                      err.toLowerCase().contains('ended'));
                              if (isShiftEndError) {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Shift has ended'),
                                    content: Text(err),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(err)));
                              }
                            } else if (ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$nextAction recorded successfully.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: dtr.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isHoliday
                              ? 'Holiday'
                              : isComplete
                              ? 'Clocked Out'
                              : (nextAction ?? '—'),
                        ),
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
  const _AttendanceCard({this.onViewAttendance});

  final VoidCallback? onViewAttendance;

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

        return Container(
          padding: EdgeInsets.all(_employeeCardPadding(context)),
          decoration: EmployeeDashUi.summaryCard(
            context: context,
            tint: const Color(0xFFE8F5E9),
            accent: AttendanceOverviewColors.present,
          ),
          child: Row(
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
                        color: AttendanceOverviewColors.present.withValues(
                          alpha: 0.08,
                        ),
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
      },
    );
  }
}

class _LeaveBalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<LeaveProvider>(
      builder: (context, leave, _) {
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
            padding: EdgeInsets.all(_employeeCardPadding(context)),
          );
        }
        return Container(
          padding: EdgeInsets.all(_employeeCardPadding(context)),
          decoration: EmployeeDashUi.summaryCard(
            context: context,
            tint: const Color(0xFFF3E5F5),
            accent: AttendanceOverviewColors.onLeave,
          ),
          child: Row(
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
      padding: EdgeInsets.all(_employeeCardPadding(context)),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
  const _EmployeeUpcomingLeaveCard({this.embedded = false});

  /// When true, omits outer card chrome (for use inside [EmployeeAttendanceOverviewCard]).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final pad = embedded ? 0.0 : _employeeSectionCardPadding(context);
    final innerPad = MediaQuery.sizeOf(context).width < 600 ? 12.0 : 16.0;

    Widget titleRow() {
      return EmployeeSectionHeader(
        title: 'Upcoming Leave',
        icon: Icons.event_outlined,
        subtitle: embedded ? 'Scheduled time off' : null,
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
                  onPressed: () {},
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
                    onPressed: () {},
                    style: EmployeeDashUi.ghostAction(context),
                    child: const Text('View More'),
                  ),
                ],
              ),
            SizedBox(height: stackHeader ? 12 : 16),
            Container(
              padding: EdgeInsets.all(innerPad),
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(EmployeeDashUi.radiusMd),
                border: Border.all(color: AppTheme.dashHairlineOf(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'No upcoming leave.',
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
                      color: AttendanceOverviewColors.onLeave.withValues(
                        alpha: 0.1,
                      ),
                    ),
                    child: Icon(
                      Icons.event_rounded,
                      color: AttendanceOverviewColors.onLeave.withValues(
                        alpha: 0.55,
                      ),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
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
  }
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
    if (segs.any((s) => s.toUpperCase() == segment)) return 'On Field';
    if (segs.isEmpty &&
        segment == 'AM IN' &&
        (r.status == 'on_field' || r.locatorSlipId != null))
      return 'On Field';
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
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View your time-in/out records.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: isNarrow ? 150 : 130,
                  child: DropdownButtonFormField<int>(
                    value: _selectedMonth,
                    isExpanded: true,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      radius: 8,
                    ),
                    style: AppTheme.dashFieldTextStyle(context),
                    dropdownColor: AppTheme.dashPanelOf(context),
                    selectedItemBuilder: (context) => List.generate(
                      12,
                      (i) => Text(
                        _attendanceMonths[i],
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.dashFieldTextStyle(
                          context,
                        ).copyWith(fontSize: 14),
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
                ),
                SizedBox(
                  width: isNarrow ? 95 : 85,
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    isExpanded: true,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      radius: 8,
                    ),
                    style: AppTheme.dashFieldTextStyle(context),
                    dropdownColor: AppTheme.dashPanelOf(context),
                    selectedItemBuilder: (context) => List.generate(
                      11,
                      (i) => Text(
                        '${DateTime.now().year - 5 + i}',
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.dashFieldTextStyle(
                          context,
                        ).copyWith(fontSize: 14),
                      ),
                    ),
                    items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedYear = v;
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
                ),
                SizedBox(
                  width: isNarrow ? 115 : 105,
                  child: DropdownButtonFormField<int?>(
                    value: _selectedDay,
                    isExpanded: true,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      radius: 8,
                    ),
                    style: AppTheme.dashFieldTextStyle(context),
                    dropdownColor: AppTheme.dashPanelOf(context),
                    hint: Text(
                      'All days',
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.dashFieldTextStyle(
                        context,
                      ).copyWith(fontSize: 14),
                    ),
                    selectedItemBuilder: (context) => [
                      Text(
                        'All days',
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.dashFieldTextStyle(
                          context,
                        ).copyWith(fontSize: 14),
                      ),
                      ...List.generate(
                        _maxSelectableCalendarDay,
                        (i) => Text(
                          'Day ${i + 1}',
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.dashFieldTextStyle(
                            context,
                          ).copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All days'),
                      ),
                      ...List.generate(
                        _maxSelectableCalendarDay,
                        (i) => i + 1,
                      ).map(
                        (d) => DropdownMenuItem<int?>(
                          value: d,
                          child: Text('Day $d'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedDay = v);
                      _load();
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _selectedMonth = now.month;
                      _selectedYear = now.year;
                      _selectedDay = null;
                    });
                    _load();
                  },
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 22,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: 'Reset filters',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.lightGray.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
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
              const minTableWidth = 860.0;
              final tableWidth = constraints.maxWidth < minTableWidth
                  ? minTableWidth
                  : constraints.maxWidth;
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
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
                            color: AppTheme.lightGray.withOpacity(0.5),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Date',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'AM In',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'AM Out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'PM In',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'PM Out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'Late',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'Undertime',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text(
                                    'Remarks',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    'Source',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...visibleRecords.asMap().entries.map((entry) {
                          final i = entry.key;
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
                                  ? AppTheme.white
                                  : AppTheme.lightGray.withOpacity(0.25),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatDate(r.recordDate),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
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
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
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
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
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
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
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
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      lateStr,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      underStr,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary,
                                      ),
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
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_rounded,
                size: 56,
                color: AppTheme.primaryNavy.withOpacity(0.7),
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
