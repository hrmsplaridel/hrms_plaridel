import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../../api/user_facing_api_error.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../data/job_vacancy_announcement.dart';
import '../../../data/recruitment_application.dart';
import '../../../data/action_brainstorming_coaching.dart';
import '../../../data/training_need_analysis.dart';
import '../../../data/training_daily_report.dart';
import '../../ld/widgets/training_daily_report_date_filter.dart';
import '../../../landingpage/constants/app_theme.dart';
import '../../../utils/form_pdf.dart';
import '../../../widgets/read_only_saved_entry_dialog.dart';
import '../../../widgets/rsp_form_header_footer.dart';
import '../../../widgets/rsp_ld_saved_records_browser.dart';
import '../../../widgets/rsp_ld_record_actions.dart';
import '../../../widgets/training_daily_report_read_only_view.dart';
import '../../../widgets/training_report_attachment_preview.dart';
import '../../shared/screens/profile_page.dart' show DashboardProfilePanel;
import '../../shared/widgets/dashboard_content_navigator.dart';
import '../../shared/widgets/dashboard_header_actions.dart';
import '../../shared/utils/time_greeting.dart';
import '../../shared/widgets/collapsible_dashboard_sidebar.dart';
import '../../shared/widgets/portal_sidebar_brand.dart';
import '../../../dtr/dtr_main.dart';
import '../../../dtr/dtr_provider.dart';
import '../../../dtr/widgets/real_time_clock.dart';
import '../../../dtr/screens/dtr_dashboard.dart';
import '../../../dtr/dtr_routes.dart';
import '../../../dtr/manage/manage_employee.dart';
import '../../../dtr/manage/manage_assignment.dart';
import '../../../dtr/manage/manage_department.dart';
import '../../../dtr/manage/manage_position.dart';
import '../../../dtr/manage/manage_shift.dart';
import '../../../dtr/manage/manage_holiday.dart';
import '../../../dtr/manage/manage_attendance_policy.dart';
import '../../../dtr/manage/manage_biometric_devices.dart';
import '../../../docutracker/docutracker_main.dart';
import '../../../docutracker/docutracker_provider.dart';
import '../../../docutracker/screens/docutracker_dashboard_screen.dart';
import '../../../leave/leave_main.dart';
import '../../../leave/leave_provider.dart';
import '../../../leave/models/leave_request.dart';
import '../../../leave/screens/employee_leave_screen.dart';
import '../../../leave/screens/leave_request_form_screen.dart';
import '../../../leave/utils/responsive_leave_form_host.dart';
import '../../../locator/screens/admin_locator_management_screen.dart';
import '../../../recruitment/screens/rsp_admin_screen.dart';
import '../../../widgets/feature_card.dart';
import '../../../employee/screens/employee_dashboard.dart';
import '../../../notifications/notification_provider.dart';
import '../../../notifications/notification_tap_result.dart';
import '../../../notifications/open_notifications_panel.dart';

/// Dashboard accent colors for summary cards and accents (orange theme).
class _DashboardColors {
  static const Color cardApplicants = Color(0xFFFFF7ED);
  static const Color cardPending = Color(0xFFFFF1F0);
  static const Color cardVacancies = Color(0xFFFFFBEB);
  static const Color cardHiring = Color(0xFFF0F4FF);
  static const Color accentOrange = Color(0xFFE85D04);
  static const Color accentCoral = Color(0xFFDC4A2D);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentNavy = Color(0xFF1A237E);

  // Legacy aliases used by summary data loaders.
  static const Color cardBlue = cardApplicants;
  static const Color cardGreen = cardPending;
  static const Color cardAmber = cardVacancies;
  static const Color accentBlue = accentOrange;
  static const Color accentGreen = accentCoral;
}

/// Shared visual primitives for the admin dashboard home view.
class _AdminDashUi {
  _AdminDashUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;

  static BoxDecoration welcomeBanner(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radiusLg),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [const Color(0xFF252D3D), const Color(0xFF1E2430)]
            : [const Color(0xFFFFF8F3), Colors.white, const Color(0xFFF8FAFF)],
      ),
      border: Border.all(
        color: dark
            ? AppTheme.dashHairlineOf(context)
            : _DashboardColors.accentOrange.withValues(alpha: 0.14),
      ),
      boxShadow: [
        BoxShadow(
          color: _DashboardColors.accentOrange.withValues(
            alpha: dark ? 0.12 : 0.08,
          ),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration elevatedPanel(BuildContext context) {
    final base = AppTheme.dashSurfaceCard(context, radius: radiusLg);
    final dark = AppTheme.dashIsDark(context);
    return base.copyWith(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.05),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: _DashboardColors.accentOrange.withValues(
            alpha: dark ? 0.06 : 0.03,
          ),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration summaryCard({
    required BuildContext context,
    required Color tint,
    required Color accent,
  }) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radiusMd),
      color: dark ? const Color(0xFF1E2430) : tint,
      border: Border.all(color: accent.withValues(alpha: dark ? 0.35 : 0.18)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: dark ? 0.15 : 0.1),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.2 : 0.035),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static ButtonStyle ghostAction(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: AppTheme.primaryNavy,
      backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    );
  }
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryNavy.withValues(alpha: 0.14),
                  AppTheme.letterheadNavy.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(icon, color: AppTheme.primaryNavy, size: 22),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  letterSpacing: -0.35,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _AdminWelcomeBanner extends StatelessWidget {
  const _AdminWelcomeBanner({required this.isNarrow});

  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty ? a.displayName : 'Admin',
    );
    final greeting = personalizedTimeGreeting(displayName);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.15),
            ),
          ),
          child: const Text(
            'Admin Portal',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          greeting,
          style: TextStyle(
            color: primary,
            fontSize: isNarrow ? 22 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Here's the latest overview of the HR activities.",
          style: TextStyle(
            color: secondary,
            fontSize: isNarrow ? 14 : 15,
            height: 1.45,
          ),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isNarrow ? 20 : 26),
      decoration: _AdminDashUi.welcomeBanner(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: isNarrow ? -28 : -16,
            top: isNarrow ? -36 : -24,
            child: Container(
              width: isNarrow ? 120 : 160,
              height: isNarrow ? 120 : 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: isNarrow ? -20 : -8,
            bottom: isNarrow ? -24 : -16,
            child: Container(
              width: isNarrow ? 80 : 100,
              height: isNarrow ? 80 : 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.letterheadNavy.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          if (isNarrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerRight,
                  child: RealTimeClock(),
                ),
                const SizedBox(height: 16),
                copy,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 20),
                const RealTimeClock(),
              ],
            ),
        ],
      ),
    );
  }
}

enum AdminMenu {
  dashboard,
  myAttendance,
  myLeave,
  myProfile,
  dtr,
  rsp,
  ld,
  docutracker,
  createAccount,
}

/// Admin dashboard matching reference layout; features only from existing system:
/// Dashboard, Job Vacancies (Hiring), Recruitment (Applications).
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with WidgetsBindingObserver {
  AdminMenu _selectedMenu = AdminMenu.dashboard;
  bool _sidebarCollapsed = false;
  final GlobalKey<_DtrContentState> _dtrContentKey =
      GlobalKey<_DtrContentState>();
  static const _settingsPanelKey = PageStorageKey<String>('admin_settings');
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  Widget _settingsPanel() =>
      DashboardProfilePanel(key: _settingsPanelKey, onBack: _closeMyProfile);
  Timer? _notificationPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(FormPdf.warmupPrintAssets());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().refreshUnreadCount();
      context.read<DocuTrackerProvider>().loadNotifications();
      _notificationPollTimer?.cancel();
      _notificationPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        context.read<NotificationProvider>().refreshUnreadCount();
        context.read<DocuTrackerProvider>().loadNotifications();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationProvider>().refreshUnreadCount();
      context.read<DocuTrackerProvider>().loadNotifications();
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
      case NotificationTapKind.adminDtrLeaveManagement:
        setState(() => _selectedMenu = AdminMenu.dtr);
        DashboardContentNavigator.showHome(_contentNavKey);
        // DTR mounts on the next frame(s) after the nested navigator rebuilds home.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dtrContentKey.currentState?.openLeaveManagement();
          });
        });
        break;
      case NotificationTapKind.adminDtrLocatorManagement:
        setState(() => _selectedMenu = AdminMenu.dtr);
        DashboardContentNavigator.showHome(_contentNavKey);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dtrContentKey.currentState?.openLocatorManagement();
          });
        });
        break;
      case NotificationTapKind.adminRecruitment:
        setState(() => _selectedMenu = AdminMenu.rsp);
        DashboardContentNavigator.showHome(_contentNavKey);
        break;
      case NotificationTapKind.adminTrainingReports:
        setState(() => _selectedMenu = AdminMenu.ld);
        DashboardContentNavigator.showHome(_contentNavKey);
        break;
      case NotificationTapKind.none:
      case NotificationTapKind.employeeLeaveApprovals:
      case NotificationTapKind.employeeLeaveRequests:
      case NotificationTapKind.employeeLocatorApprovals:
      case NotificationTapKind.employeeLocatorRequests:
      case NotificationTapKind.employeeMyAttendance:
        break;
    }
  }

  void _onMenuSelected(AdminMenu menu) {
    if (menu == AdminMenu.myProfile) {
      _openMyProfile();
      return;
    }
    setState(() => _selectedMenu = menu);
    DashboardContentNavigator.showHome(_contentNavKey);
    if (menu == AdminMenu.docutracker) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<DocuTrackerProvider>().loadNotifications(
          forceRefresh: true,
        );
      });
    }
  }

  void _openMyProfile() {
    if (DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    )) {
      setState(() => _selectedMenu = AdminMenu.myProfile);
      return;
    }
    setState(() => _selectedMenu = AdminMenu.myProfile);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DashboardContentNavigator.openSettings(_contentNavKey);
    });
  }

  void _closeMyProfile() {
    final nav = _contentNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
    if (!mounted) return;
    if (_selectedMenu == AdminMenu.myProfile) {
      setState(() => _selectedMenu = AdminMenu.dashboard);
      DashboardContentNavigator.showHome(_contentNavKey);
    }
  }

  /// Same flow as [LeaveMain] — admin My Portal must pass a handler or File Leave stays disabled.
  Future<void> _openMyLeaveRequestForm() async {
    final result = await openResponsiveLeaveFormHost<String?>(
      context: context,
      builder: (_) => _buildAdminLeaveRequestForm(),
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

  Widget _buildAdminLeaveRequestForm() {
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

  Widget _buildContent(String displayName) {
    switch (_selectedMenu) {
      case AdminMenu.dashboard:
        return const _DashboardContent();
      case AdminMenu.myAttendance:
        return EmployeeAttendanceOverviewSection(
          displayName: displayName,
          adminPortal: true,
        );
      case AdminMenu.myLeave:
        return EmployeeLeaveScreen(onFileLeavePressed: _openMyLeaveRequestForm);
      case AdminMenu.myProfile:
        return _settingsPanel();
      case AdminMenu.dtr:
        return _DtrContent(key: _dtrContentKey);
      case AdminMenu.rsp:
        return RspAdminContent(
          onOpenCreateAccount: () => _onMenuSelected(AdminMenu.createAccount),
        );
      case AdminMenu.ld:
        return const _LdContent();
      case AdminMenu.docutracker:
        return const DocuTrackerMain(isAdmin: true);
      case AdminMenu.createAccount:
        return const _AdminSignUpContent();
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
    final email = context.select<AuthProvider, String>(
      (a) => a.email.isNotEmpty ? a.email : 'Admin',
    );
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty ? a.displayName : 'Admin',
    );
    final avatarPath = context.select<AuthProvider, String?>(
      (a) => a.avatarPath,
    );
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final contentPadding = width > 900 ? 28.0 : (width > 600 ? 22.0 : 18.0);

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _Sidebar(
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
                  _Sidebar(
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
                              homeBuilder: () => _buildContent(displayName),
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
                      onViewAllNotifications: _handleOpenNotifications,
                      onNotificationTap: _applyNotificationTapResult,
                      trailing: DashboardAccountMenuButton(
                        avatarPath: avatarPath,
                        compact: width < 600,
                        tooltip: displayName,
                        onProfile: () => _openMyProfile(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: AppTheme.dashCanvasOf(context),
                      child: DashboardContentNavigator(
                        navigatorKey: _contentNavKey,
                        homeBuilder: () => _buildContent(displayName),
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedMenu,
    this.avatarPath,
    required this.email,
    required this.displayName,
    required this.onTap,
    this.showBrand = true,
    this.railMode = false,
    this.collapsed = false,
  });

  final AdminMenu selectedMenu;
  final String? avatarPath;
  final String email;
  final String displayName;
  final ValueChanged<AdminMenu> onTap;
  final bool showBrand;

  /// Full-height rail with one straight right edge through header + nav.
  final bool railMode;
  final bool collapsed;

  Widget _buildNavList(BuildContext context, {required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: railMode ? 12 : (showBrand ? 4 : 12)),
        DashboardSidebarNavTile(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          selected: selectedMenu == AdminMenu.dashboard,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.dashboard),
        ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.dashHairlineOf(context),
            ),
          ),
        DashboardSidebarSectionLabel('MY PORTAL', collapsed: compact),
        DashboardSidebarNavTile(
          icon: Icons.schedule_outlined,
          label: 'My Attendance',
          selected: selectedMenu == AdminMenu.myAttendance,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.myAttendance),
        ),
        DashboardSidebarNavTile(
          icon: Icons.event_note_outlined,
          label: 'My Leave',
          selected: selectedMenu == AdminMenu.myLeave,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.myLeave),
        ),
        DashboardSidebarSectionLabel('MANAGEMENT', collapsed: compact),
        DashboardSidebarNavTile(
          icon: Icons.how_to_reg_outlined,
          label: 'RSP',
          selected: selectedMenu == AdminMenu.rsp,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.rsp),
        ),
        DashboardSidebarNavTile(
          icon: Icons.school_outlined,
          label: 'L&D',
          selected: selectedMenu == AdminMenu.ld,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.ld),
        ),
        DashboardSidebarNavTile(
          icon: Icons.access_time_outlined,
          label: 'DTR',
          selected: selectedMenu == AdminMenu.dtr,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.dtr),
        ),
        DashboardSidebarNavTile(
          icon: Icons.folder_outlined,
          label: 'DocuTracker',
          selected: selectedMenu == AdminMenu.docutracker,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.docutracker),
        ),
        DashboardSidebarNavTile(
          icon: Icons.person_add_outlined,
          label: 'Create Account',
          selected: selectedMenu == AdminMenu.createAccount,
          collapsed: compact,
          onTap: () => onTap(AdminMenu.createAccount),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildFooter(
    BuildContext context, {
    required bool compact,
    required int year,
  }) {
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
            subtitle: email.isNotEmpty ? email : 'System Administrator',
            avatarPath: avatarPath,
          ),
        ),
        Opacity(
          opacity: fadeExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 0,
              children: [
                Text(
                  '\u00a9 $year HRMS',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '\u00b7',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 0,
                    ),
                  ),
                  child: Text(
                    'Privacy',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '\u00b7',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 0,
                    ),
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
          ),
        ),
        SizedBox(height: lerpDouble(18, 12, t)!),
      ],
    );
  }

  Widget _buildRail({
    required BuildContext context,
    required Color hairline,
    required Color canvas,
    required int year,
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
                          child: _buildNavList(context, compact: false),
                        ),
                      ),
                      _buildFooter(context, compact: false, year: year),
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
    final year = DateTime.now().year;
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
          year: year,
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
            child: SingleChildScrollView(
              child: _buildNavList(context, compact: false),
            ),
          ),
          _buildFooter(context, compact: false, year: year),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  static bool _sectionVisible(String query, List<String> keywords) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final k in keywords) {
      final kl = k.toLowerCase();
      if (kl.contains(q) || q.contains(kl)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 500;
    const q = '';

    final showWelcome = _sectionVisible(q, [
      'welcome',
      'overview',
      'hello',
      'admin',
      'dashboard',
      'hr',
      'activities',
      'latest',
      'date',
      'back',
    ]);
    final showSummary = _sectionVisible(q, [
      'summary',
      'applicant',
      'applications',
      'pending',
      'vacancy',
      'vacancies',
      'hiring',
      'job',
      'jobs',
      'new',
      'metric',
      'stats',
      'open',
      'closed',
      'status',
      'card',
    ]);
    final showDocu = _sectionVisible(q, [
      'docu',
      'tracker',
      'document',
      'docutracker',
    ]);
    final showDtr = _sectionVisible(q, [
      'dtr',
      'time',
      'record',
      'attendance',
      'clock',
      'daily',
      'employee',
      'biometric',
      'device',
    ]);
    final showAnnouncements = _sectionVisible(q, [
      'announcement',
      'announcements',
      'landing',
      'news',
    ]);
    final showRecruitment = _sectionVisible(q, [
      'recruit',
      'recruitment',
      'rsp',
      'overview',
      'hiring',
    ]);
    final showPending = _sectionVisible(q, [
      'pending',
      'application',
      'review',
      'submitted',
      'declined',
      'approved',
      'applicant',
    ]);

    final anySection =
        showWelcome ||
        showSummary ||
        showDocu ||
        showDtr ||
        showAnnouncements ||
        showRecruitment ||
        showPending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (q.trim().isNotEmpty && !anySection)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F3),
                borderRadius: BorderRadius.circular(_AdminDashUi.radiusMd),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    color: AppTheme.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Walang tumugma sa “$q”. Subukan: docu, dtr, recruit, pending, time, announcement…',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (showWelcome) _AdminWelcomeBanner(isNarrow: isNarrow),
        if (showWelcome && showSummary) const SizedBox(height: 28),
        if (showSummary) const _SummaryCards(),
        if ((showWelcome || showSummary) && showDocu)
          const SizedBox(height: 28),
        if (showDocu) ...[
          _AdminSectionHeader(
            title: 'DocuTracker',
            icon: Icons.folder_copy_outlined,
            subtitle: 'Document tracking and routing overview',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: _AdminDashUi.elevatedPanel(context),
            child: const DocuTrackerDashboardScreen(
              isAdmin: true,
              showTitle: false,
            ),
          ),
        ],
        if ((showWelcome || showSummary || showDocu) && showDtr)
          const SizedBox(height: 28),
        if (showDtr) ...[
          _AdminSectionHeader(
            title: 'Daily Time Record',
            icon: Icons.schedule_rounded,
            subtitle: 'Attendance, shifts, and workforce time records',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: _AdminDashUi.elevatedPanel(context),
            child: const DtrDashboard(),
          ),
        ],
        if ((showWelcome || showSummary || showDocu || showDtr) &&
            showAnnouncements)
          const SizedBox(height: 28),
        if (showAnnouncements) _AnnouncementsCard(),
        if ((showWelcome ||
                showSummary ||
                showDocu ||
                showDtr ||
                showAnnouncements) &&
            showRecruitment)
          const SizedBox(height: 28),
        if (showRecruitment) _RecruitmentOverviewCard(),
        if ((showWelcome ||
                showSummary ||
                showDocu ||
                showDtr ||
                showAnnouncements ||
                showRecruitment) &&
            showPending)
          const SizedBox(height: 28),
        if (showPending) _PendingApplicationsCard(),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SummaryCards extends StatefulWidget {
  const _SummaryCards();

  @override
  State<_SummaryCards> createState() => _SummaryCardsState();
}

class _SummaryCardsState extends State<_SummaryCards> {
  List<_SummaryData>? _cards;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final applications = await RecruitmentRepo.instance.listApplications();
      final announcement = await JobVacancyAnnouncementRepo.instance.fetch();
      final totalApplicants = applications.length;
      final pendingCount = applications
          .where((a) => a.status == 'submitted')
          .length;
      final hiringActive = announcement.hasVacancies;
      if (mounted) {
        setState(() {
          _cards = [
            _SummaryData(
              title: 'New Applicants',
              value: '$totalApplicants',
              subtitle: totalApplicants == 0
                  ? 'No applications yet'
                  : (totalApplicants == 1
                        ? '1 total application'
                        : '$totalApplicants total applications'),
              color: _DashboardColors.cardBlue,
              iconColor: _DashboardColors.accentBlue,
              icon: Icons.person_add_rounded,
            ),
            _SummaryData(
              title: 'Pending Applications',
              value: '$pendingCount',
              subtitle: pendingCount == 0
                  ? 'None awaiting review'
                  : (pendingCount == 1
                        ? '1 awaiting document review'
                        : '$pendingCount awaiting document review'),
              color: _DashboardColors.cardGreen,
              iconColor: _DashboardColors.accentGreen,
              icon: Icons.pending_actions_rounded,
            ),
            _SummaryData(
              title: 'Job Vacancies',
              value: hiringActive ? 'Open' : 'Closed',
              subtitle: 'Landing page',
              color: _DashboardColors.cardAmber,
              iconColor: _DashboardColors.accentAmber,
              icon: Icons.work_rounded,
            ),
            _SummaryData(
              title: 'Hiring Status',
              value: hiringActive ? 'Active' : 'Inactive',
              subtitle: 'Landing page',
              color: _DashboardColors.cardHiring,
              iconColor: _DashboardColors.accentNavy,
              icon: Icons.campaign_rounded,
            ),
          ];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cards = [
            _SummaryData(
              title: 'New Applicants',
              value: 'â€”',
              subtitle: 'Unable to load',
              color: _DashboardColors.cardBlue,
              iconColor: _DashboardColors.accentBlue,
              icon: Icons.person_add_rounded,
            ),
            _SummaryData(
              title: 'Pending Applications',
              value: 'â€”',
              subtitle: 'Unable to load',
              color: _DashboardColors.cardGreen,
              iconColor: _DashboardColors.accentGreen,
              icon: Icons.pending_actions_rounded,
            ),
            _SummaryData(
              title: 'Job Vacancies',
              value: 'â€”',
              subtitle: 'â€”',
              color: _DashboardColors.cardAmber,
              iconColor: _DashboardColors.accentAmber,
              icon: Icons.work_rounded,
            ),
            _SummaryData(
              title: 'Hiring Status',
              value: 'â€”',
              subtitle: 'â€”',
              color: Colors.white,
              iconColor: AppTheme.primaryNavy,
              icon: Icons.campaign_rounded,
            ),
          ];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 700;
    final isSingleColumn = w < 480;
    final cards =
        _cards ??
        [
          _SummaryData(
            title: 'New Applicants',
            value: 'â€¦',
            subtitle: 'Loading',
            color: _DashboardColors.cardBlue,
            iconColor: _DashboardColors.accentBlue,
            icon: Icons.person_add_rounded,
          ),
          _SummaryData(
            title: 'Pending Applications',
            value: 'â€¦',
            subtitle: 'Loading',
            color: _DashboardColors.cardGreen,
            iconColor: _DashboardColors.accentGreen,
            icon: Icons.pending_actions_rounded,
          ),
          _SummaryData(
            title: 'Job Vacancies',
            value: 'â€¦',
            subtitle: 'â€¦',
            color: _DashboardColors.cardAmber,
            iconColor: _DashboardColors.accentAmber,
            icon: Icons.work_rounded,
          ),
          _SummaryData(
            title: 'Hiring Status',
            value: 'â€¦',
            subtitle: 'â€¦',
            color: _DashboardColors.cardHiring,
            iconColor: _DashboardColors.accentNavy,
            icon: Icons.campaign_rounded,
          ),
        ];

    Widget content;
    if (isWide) {
      content = Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: _SummaryCard(data: cards[i])),
            if (i < cards.length - 1) const SizedBox(width: 18),
          ],
        ],
      );
    } else if (isSingleColumn) {
      content = Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            _SummaryCard(data: cards[i]),
            if (i < cards.length - 1) const SizedBox(height: 14),
          ],
        ],
      );
    } else {
      content = Column(
        children: [
          Row(
            children: [
              Expanded(child: _SummaryCard(data: cards[0])),
              const SizedBox(width: 18),
              Expanded(child: _SummaryCard(data: cards[1])),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _SummaryCard(data: cards[2])),
              const SizedBox(width: 16),
              Expanded(child: _SummaryCard(data: cards[3])),
            ],
          ),
        ],
      );
    }
    return content;
  }
}

class _SummaryData {
  const _SummaryData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.iconColor,
    required this.icon,
  });
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final Color iconColor;
  final IconData icon;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      decoration: _AdminDashUi.summaryCard(
        context: context,
        tint: data.color,
        accent: data.iconColor,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title.toUpperCase(),
                    style: TextStyle(
                      color: secondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    data.value,
                    style: TextStyle(
                      color: primary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                  if (data.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      data.subtitle,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    data.iconColor.withValues(alpha: 0.18),
                    data.iconColor.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: data.iconColor.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(data.icon, size: 24, color: data.iconColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _AdminDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminSectionHeader(
            title: 'Announcements',
            icon: Icons.campaign_outlined,
            subtitle: 'Landing page hiring visibility',
            trailing: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('View All'),
              style: _AdminDashUi.ghostAction(context),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(_AdminDashUi.radiusMd),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Vacancies (Hiring)',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Control whether the landing page shows "We are currently accepting applications" or "There are no job vacancies at the moment." Manage this in Job Vacancies.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 14,
                    height: 1.55,
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

class _RecruitmentOverviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 480;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _AdminDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminSectionHeader(
            title: 'Recruitment Overview',
            icon: Icons.pie_chart_rounded,
            subtitle: 'Application pipeline and hiring metrics',
            trailing: isCompact
                ? null
                : TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.insights_rounded, size: 16),
                    label: const Text('View Report'),
                    style: _AdminDashUi.ghostAction(context),
                  ),
          ),
          if (isCompact) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.insights_rounded, size: 16),
                label: const Text('View Report'),
                style: _AdminDashUi.ghostAction(context),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(_AdminDashUi.radiusMd),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _DashboardColors.accentOrange.withValues(
                        alpha: 0.1,
                      ),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      size: 40,
                      color: _DashboardColors.accentOrange.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No application data yet',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Data will appear when applicants complete the recruitment process.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.insights_rounded, size: 20),
              label: const Text('View Report'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingApplicationsCard extends StatefulWidget {
  @override
  State<_PendingApplicationsCard> createState() => _PendingApplicationsCardState();
}

class _PendingApplicationsCardState extends State<_PendingApplicationsCard> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<RecruitmentApplication> _all = const [];

  List<RecruitmentApplication> get _pending => _all
      .where((a) => a.status == 'submitted')
      .toList()
    ..sort(
      (a, b) =>
          (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
    );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      if (!mounted) return;
      setState(() {
        _all = apps;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingApiError(e));
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _dateLabel(BuildContext context, DateTime? dt) {
    if (dt == null) return '—';
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 480;
    final pending = _pending;
    final pendingPreview = pending.take(5).toList();
    final allCount = _all.length;
    final pendingCount = pending.length;
    final inProgressCount = _all
        .where(
          (a) =>
              a.status == 'document_approved' ||
              a.status == 'exam_taken' ||
              a.status == 'passed',
        )
        .length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _AdminDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminSectionHeader(
            title: 'Pending Applications',
            icon: Icons.assignment_rounded,
            subtitle: 'Applicants awaiting document review',
            trailing: isCompact
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Refresh list',
                        onPressed: _refreshing ? null : () => _load(refresh: true),
                        icon: _refreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Open the Recruitment module to review all applicants.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('View All'),
                        style: _AdminDashUi.ghostAction(context),
                      ),
                    ],
                  ),
          ),
          if (isCompact) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: 'Refresh list',
                  onPressed: _refreshing ? null : () => _load(refresh: true),
                  icon: _refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                ),
                TextButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Open the Recruitment module to review all applicants.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View All'),
                  style: _AdminDashUi.ghostAction(context),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PendingKpiChip(
                label: 'Pending Review',
                value: '$pendingCount',
                icon: Icons.hourglass_top_rounded,
                color: AppTheme.primaryNavy,
              ),
              _PendingKpiChip(
                label: 'In Progress',
                value: '$inProgressCount',
                icon: Icons.timelapse_rounded,
                color: const Color(0xFF1565C0),
              ),
              _PendingKpiChip(
                label: 'Total Applicants',
                value: '$allCount',
                icon: Icons.groups_rounded,
                color: const Color(0xFF6A1B9A),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(_AdminDashUi.radiusMd),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Could not load applications. $_error',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final needScroll = constraints.maxWidth < 560;
                final table = ClipRRect(
                  borderRadius: BorderRadius.circular(_AdminDashUi.radiusMd),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.3),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(1.4),
                      3: FlexColumnWidth(1.2),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryNavy.withValues(alpha: 0.1),
                              AppTheme.dashMutedSurfaceOf(context),
                            ],
                          ),
                        ),
                        children: const [
                          _TableHeader('Applicant'),
                          _TableHeader('Type'),
                          _TableHeader('Date'),
                          _TableHeader('Status'),
                        ],
                      ),
                      if (pendingPreview.isEmpty)
                        TableRow(
                          decoration: BoxDecoration(
                            color: AppTheme.dashPanelOf(context),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 16,
                              ),
                              child: Text(
                                'No pending applications',
                                style: TextStyle(
                                  color: AppTheme.dashTextSecondaryOf(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _PendingCell(text: '—'),
                            _PendingCell(text: '—'),
                            _PendingCell(text: '—'),
                          ],
                        )
                      else
                        ...pendingPreview.map(
                          (a) => TableRow(
                            decoration: BoxDecoration(
                              color: AppTheme.dashPanelOf(context),
                              border: Border(
                                top: BorderSide(
                                  color: AppTheme.dashHairlineOf(context),
                                ),
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.fullName.trim().isEmpty
                                          ? '(Unnamed applicant)'
                                          : a.fullName.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppTheme.dashTextPrimaryOf(context),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      a.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppTheme.dashTextSecondaryOf(context),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _PendingCell(
                                text: (a.positionAppliedFor?.trim().isNotEmpty ??
                                        false)
                                    ? a.positionAppliedFor!.trim()
                                    : 'Recruitment',
                              ),
                              _PendingCell(
                                text: _dateLabel(context, a.createdAt),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 8,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'Pending',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryNavy,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
                if (needScroll) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 520),
                      child: table,
                    ),
                  );
                }
                return table;
              },
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(_AdminDashUi.radiusMd),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tips_and_updates_rounded,
                    size: 18,
                    color: AppTheme.primaryNavy,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    pendingCount > 0
                        ? 'You have $pendingCount application(s) waiting for document review. Open Recruitment > RSP to approve or decline documents.'
                        : 'No documents are waiting for review right now. New recruitment submissions will appear here automatically.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
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

class _PendingCell extends StatelessWidget {
  const _PendingCell({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
    );
  }
}

class _PendingKpiChip extends StatelessWidget {
  const _PendingKpiChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.5,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
    );
  }
}

/// DTR module: hub with feature cards (like RSP). Choose a feature below.
class _DtrContent extends StatefulWidget {
  const _DtrContent({super.key});

  @override
  State<_DtrContent> createState() => _DtrContentState();
}

class _DtrContentState extends State<_DtrContent> {
  /// 0 = menu, 1 = Time Logs, 2 = Reports, 3 = Employees, 4 = Assignment,
  /// 5 = Department, 6 = Position, 7 = Shift, 8 = Leave Management,
  /// 9–10 = Holiday / Policy via [_ManageContent], 11 = Biometric Devices,
  /// 12 = Locator Slip Management
  int _dtrSectionIndex = 0;
  int? _pendingDtrSectionIndex;

  /// When opening **Assignment** from Employees, pre-select this employee once.
  String? _prefillAssignmentEmployeeId;

  /// Opens **Leave Management** (same as tapping the DTR hub card). Used after notification taps.
  void openLeaveManagement() {
    _openDtrSection(8);
  }

  /// Opens **Locator Slip Management** (notification deep-link).
  void openLocatorManagement() {
    _openDtrSection(12);
  }

  void _goToAssignmentWithEmployee(String employeeId) {
    if (!mounted) return;
    setState(() {
      _prefillAssignmentEmployeeId = employeeId;
    });
    _openDtrSection(4);
  }

  void _openDtrSection(int index) {
    if (!mounted) return;
    if (index == 0) {
      setState(() {
        _pendingDtrSectionIndex = null;
        _dtrSectionIndex = 0;
      });
      return;
    }
    if (_dtrSectionIndex == index && _pendingDtrSectionIndex == null) return;
    setState(() => _pendingDtrSectionIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingDtrSectionIndex != index) return;
      setState(() {
        _dtrSectionIndex = index;
        _pendingDtrSectionIndex = null;
      });
    });
  }

  String _dtrSectionTitle(int index) => switch (index) {
    1 => 'Time Logs',
    2 => 'Reports',
    3 => 'Employees',
    4 => 'Assignment',
    5 => 'Department',
    6 => 'Position',
    7 => 'Shift',
    8 => 'Leave Management',
    9 => 'Holiday Management',
    10 => 'Attendance Policy',
    11 => 'Biometric Devices',
    12 => 'Locator Slip Management',
    _ => 'DTR',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_dtrSectionIndex != 0 || _pendingDtrSectionIndex != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openDtrSection(0),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Back to DTR'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_pendingDtrSectionIndex != null)
                _DtrOpeningPanel(
                  title: _dtrSectionTitle(_pendingDtrSectionIndex!),
                )
              else if (_dtrSectionIndex == 0) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DTR',
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Daily Time Record. Choose a feature below.',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                    const RealTimeClock(),
                  ],
                ),
                const SizedBox(height: 24),
                FeatureCardGrid(
                  children: [
                    FeatureCard(
                      title: 'Time Logs',
                      subtitle:
                          'Manage and correct daily time-in/out records. Add, edit, or delete entries.',
                      icon: Icons.schedule_rounded,
                      onTap: () => _openDtrSection(1),
                    ),
                    FeatureCard(
                      title: 'Reports',
                      subtitle: 'View attendance and tardiness reports.',
                      icon: Icons.summarize_rounded,
                      onTap: () => _openDtrSection(2),
                    ),
                    FeatureCard(
                      title: 'Employees',
                      subtitle: 'Manage employee profiles and accounts.',
                      icon: Icons.people_rounded,
                      onTap: () => _openDtrSection(3),
                    ),
                    FeatureCard(
                      title: 'Assignment',
                      subtitle:
                          'Assign employees to departments, positions, and shifts.',
                      icon: Icons.assignment_rounded,
                      onTap: () => _openDtrSection(4),
                    ),
                    FeatureCard(
                      title: 'Department',
                      subtitle: 'Manage departments.',
                      icon: Icons.business_rounded,
                      onTap: () => _openDtrSection(5),
                    ),
                    FeatureCard(
                      title: 'Office',
                      subtitle:
                          'Manage branch or site offices (DocuTracker routing).',
                      icon: Icons.domain_rounded,
                      onTap: () => setState(() => _dtrSectionIndex = 13),
                    ),
                    FeatureCard(
                      title: 'Position',
                      subtitle: 'Manage positions.',
                      icon: Icons.work_rounded,
                      onTap: () => _openDtrSection(6),
                    ),
                    FeatureCard(
                      title: 'Shift',
                      subtitle: 'Manage work shifts and schedules.',
                      icon: Icons.access_time_rounded,
                      onTap: () => _openDtrSection(7),
                    ),
                    FeatureCard(
                      title: 'Leave Management',
                      subtitle:
                          'Review employee leave requests, approvals, and leave-related records.',
                      icon: Icons.event_note_rounded,
                      onTap: () => _openDtrSection(8),
                    ),
                    FeatureCard(
                      title: 'Locator Slip Management',
                      subtitle:
                          'Review locator slip approvals, department-head endorsements, and HR final decisions.',
                      icon: Icons.pin_drop_rounded,
                      onTap: () => _openDtrSection(12),
                    ),
                    FeatureCard(
                      title: 'Holiday Management',
                      subtitle:
                          'Define regular, special, and local holidays for DTR and payroll.',
                      icon: Icons.calendar_today_rounded,
                      onTap: () => _openDtrSection(9),
                    ),
                    FeatureCard(
                      title: 'Attendance Policy',
                      subtitle:
                          'Set grace period, late/absent/undertime rules, and default policy.',
                      icon: Icons.policy_rounded,
                      onTap: () => _openDtrSection(10),
                    ),
                    FeatureCard(
                      title: 'Biometric Devices',
                      subtitle:
                          'Register and manage biometric time clocks linked to your database.',
                      icon: Icons.fingerprint_rounded,
                      onTap: () => _openDtrSection(11),
                    ),
                  ],
                ),
              ] else if (_dtrSectionIndex == 1)
                DtrMain(section: DtrSection.timeLogs)
              else if (_dtrSectionIndex == 2)
                DtrMain(section: DtrSection.reports)
              else if (_dtrSectionIndex == 8)
                const LeaveMain(isAdmin: true)
              else if (_dtrSectionIndex == 11)
                const ManageBiometricDevices()
              else if (_dtrSectionIndex == 12)
                const AdminLocatorManagementScreen()
              else
                _ManageContent(
                  subIndex: _dtrSectionIndex - 3,
                  onOpenAssignmentForEmployee: _goToAssignmentWithEmployee,
                  prefillAssignmentEmployeeId: _dtrSectionIndex == 4
                      ? _prefillAssignmentEmployeeId
                      : null,
                  onPrefillAssignmentConsumed: () {
                    if (_prefillAssignmentEmployeeId != null) {
                      setState(() => _prefillAssignmentEmployeeId = null);
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DtrOpeningPanel extends StatelessWidget {
  const _DtrOpeningPanel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Opening $title...',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Create Account: full form displayed directly (single place for adding employees).
class _AdminSignUpContent extends StatelessWidget {
  const _AdminSignUpContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.person_add_rounded,
                color: AppTheme.primaryNavy,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Account',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add a new employee or admin. Enter full profile details; they can sign in with email and password.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          constraints: const BoxConstraints(maxWidth: 1040),
          decoration: BoxDecoration(
            color: AppTheme.dashIsDark(context)
                ? AppTheme.dashPanelOf(context)
                : const Color(0xFFF0F3F1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: AppTheme.dashIsDark(context) ? 0.35 : 0.06,
                ),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: const AddEmployeeForm(),
        ),
      ],
    );
  }
}

/// L&D (Learning & Development) module: hub with Training Need Analysis and Consolidated Report.
class _LdContent extends StatefulWidget {
  const _LdContent();

  @override
  State<_LdContent> createState() => _LdContentState();
}

class _LdContentState extends State<_LdContent> {
  int _ldSectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_ldSectionIndex != 0) ...[
          TextButton.icon(
            onPressed: () => setState(() => _ldSectionIndex = 0),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text('Back to L&D'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (_ldSectionIndex == 0) ...[
          Text(
            'L&D',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Learning & Development. Choose a feature below.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FeatureCardGrid(
            children: [
              FeatureCard(
                title: 'Training Need Analysis and Consolidated Report',
                subtitle:
                    'FOR CY [year], DEPARTMENT. Table: Name/Position, Goal, Behavior, Skills/Knowledge, Need for Training, Training Recommendations.',
                icon: Icons.school_rounded,
                onTap: () => setState(() => _ldSectionIndex = 1),
              ),
              FeatureCard(
                title: 'Action Brainstorming and Coaching Worksheet',
                subtitle:
                    'DEPARTMENT, DATE. Table: Name, Stop Doing, Do Less Of, Keep Doing, Do More Of, Start Doing, Goal. Certified by Department Head.',
                icon: Icons.lightbulb_outline_rounded,
                onTap: () => setState(() => _ldSectionIndex = 2),
              ),
              FeatureCard(
                title: 'Training Daily Reports (Monitoring)',
                subtitle:
                    'Monitor daily reports submitted by employees under training, with attachments and status.',
                icon: Icons.assignment_turned_in_outlined,
                onTap: () => setState(() => _ldSectionIndex = 3),
              ),
            ],
          ),
        ] else if (_ldSectionIndex == 1)
          const _TrainingNeedAnalysisSection()
        else if (_ldSectionIndex == 2)
          const _ActionBrainstormingSection()
        else
          const _LdTrainingReportsSection(),
      ],
    );
  }
}

Widget _ldSectionHeader(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryNavy.withValues(alpha: 0.14),
              AppTheme.primaryNavyLight.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.2),
          ),
        ),
        child: Icon(icon, size: 26, color: AppTheme.primaryNavy),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _ldSectionToolbar(
  BuildContext context, {
  required bool loading,
  required String addLabel,
  required VoidCallback onAdd,
  required VoidCallback onRefresh,
  required VoidCallback onViewRecords,
}) {
  final narrow = MediaQuery.sizeOf(context).width < 720;
  final addBtn = FilledButton.icon(
    onPressed: loading ? null : onAdd,
    icon: const Icon(Icons.add_rounded, size: 20),
    label: Text(addLabel),
    style: FilledButton.styleFrom(
      backgroundColor: AppTheme.primaryNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
  final refreshBtn = OutlinedButton.icon(
    onPressed: loading ? null : onRefresh,
    icon: const Icon(Icons.refresh_rounded, size: 20),
    label: const Text('Refresh'),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppTheme.primaryNavy,
      side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.45)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
  final recordsBtn = OutlinedButton.icon(
    onPressed: loading ? null : onViewRecords,
    icon: const Icon(Icons.folder_open_outlined, size: 20),
    label: const Text('View records'),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppTheme.primaryNavy,
      side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.45)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.dashMutedSurfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
    ),
    child: narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              addBtn,
              const SizedBox(height: 10),
              refreshBtn,
              const SizedBox(height: 10),
              recordsBtn,
            ],
          )
        : Row(
            children: [
              addBtn,
              const Spacer(),
              refreshBtn,
              const SizedBox(width: 10),
              recordsBtn,
            ],
          ),
  );
}

Widget _ldEmptyRecordsPlaceholder({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 40,
              color: AppTheme.primaryNavy.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LdSavedEntryCard extends StatelessWidget {
  const _LdSavedEntryCard({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDownloadPdf,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final Future<void> Function() onPrint;
  final Future<void> Function() onDownloadPdf;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
                            title,
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              letterSpacing: -0.2,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.topic_rounded,
                                size: 15,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: AppTheme.dashTextSecondaryOf(
                                      context,
                                    ),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        meta,
                        style: const TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: hairline),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Wrap(
                      spacing: kRspLdRecordActionGap,
                      runSpacing: kRspLdRecordActionGap,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onView,
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('View'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryNavy,
                            side: BorderSide(
                              color: AppTheme.primaryNavy.withValues(
                                alpha: 0.45,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryNavy,
                            side: BorderSide(
                              color: AppTheme.primaryNavy.withValues(
                                alpha: 0.45,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: kRspLdRecordActionGap,
                      runSpacing: kRspLdRecordActionGap,
                      children: [
                        IconButton(
                          onPressed: () => onPrint(),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                          style: rspLdRecordIconButtonStyle(),
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                          style: rspLdRecordIconButtonStyle(),
                        ),
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Colors.red.shade700,
                          ),
                          label: Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingNeedAnalysisSection extends StatefulWidget {
  const _TrainingNeedAnalysisSection();

  @override
  State<_TrainingNeedAnalysisSection> createState() =>
      _TrainingNeedAnalysisSectionState();
}

class _TrainingNeedAnalysisSectionState
    extends State<_TrainingNeedAnalysisSection> {
  List<TrainingNeedAnalysisEntry> _entries = [];
  bool _loading = true;
  TrainingNeedAnalysisEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TrainingNeedAnalysisRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _startNew() =>
      setState(() => _editing = const TrainingNeedAnalysisEntry());
  void _edit(TrainingNeedAnalysisEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(TrainingNeedAnalysisEntry entry) async {
    try {
      if (entry.id == null) {
        await TrainingNeedAnalysisRepo.instance.insert(entry);
      } else {
        await TrainingNeedAnalysisRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Training Need Analysis saved.')),
        );
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await TrainingNeedAnalysisRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printTna(TrainingNeedAnalysisEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildTrainingNeedAnalysisPdf(entry),
        filename: 'Training_Need_Analysis.pdf',
        format: FormPdf.pageLetterLandscape,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadTna(TrainingNeedAnalysisEntry entry) async {
    try {
      final doc = await FormPdf.buildTrainingNeedAnalysisPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Training_Need_Analysis.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved Training Need Analysis reports',
      emptyMessage: 'No reports yet.',
      loading: _loading,
      items: _entries.map((e) {
        final cy = e.cyYear ?? '—';
        final dept = e.department ?? '—';
        return SavedRecordListItem(
          title: 'CY $cy — $dept',
          subtitle: '${e.rows.length} table row(s)',
          detailDialogTitle: 'Training Need Analysis — CY $cy',
          previewContentWidth: 1100,
          previewBuilder: () => _TrainingNeedAnalysisFormEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printTna(e),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ldSectionHeader(
          context,
          icon: Icons.school_rounded,
          title: 'Training Need Analysis and Consolidated Report',
          subtitle:
              'FOR CY [year], DEPARTMENT. Table: Name/Position, Goal, Behavior, Skills/Knowledge, Need for Training, Training Recommendations.',
        ),
        const SizedBox(height: 22),
        _ldSectionToolbar(
          context,
          loading: _loading,
          addLabel: 'Add report',
          onAdd: _startNew,
          onRefresh: _load,
          onViewRecords: _openSavedRecordsBrowser,
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          _TrainingNeedAnalysisFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printTna,
            onDownloadPdf: _downloadTna,
          ),
          const SizedBox(height: 20),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          _ldEmptyRecordsPlaceholder(
            icon: Icons.school_outlined,
            title: 'No reports yet',
            subtitle:
                'Tap "Add report" to create a Training Need Analysis and Consolidated Report.',
          )
        else
          _TrainingNeedAnalysisList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printTna,
            onDownloadPdf: _downloadTna,
          ),
      ],
    );
  }
}

String _formatLdTrainingDailySubmittedAt(DateTime utc) {
  final l = utc.toLocal();
  String z2(int x) => x.toString().padLeft(2, '0');
  return '${l.year}-${z2(l.month)}-${z2(l.day)} ${z2(l.hour)}:${z2(l.minute)}:${z2(l.second)}';
}

/// L&D: Training Daily Reports monitoring content (embedded in L&D page, not a separate screen).
class _LdTrainingReportsSection extends StatefulWidget {
  const _LdTrainingReportsSection();

  @override
  State<_LdTrainingReportsSection> createState() =>
      _LdTrainingReportsSectionState();
}

class _LdTrainingReportsSectionState extends State<_LdTrainingReportsSection> {
  final _searchController = TextEditingController();
  bool _loading = false;
  List<TrainingDailyReport> _reports = [];
  DateTime? _filterByDate;
  final Set<DateTime> _reportDatesCache = {};
  final Map<DateTime, int> _countByDay = {};

  List<DateTime> get _datesWithReports {
    final list = _reportDatesCache.toList()
      ..sort((a, b) => b.compareTo(a));
    if (_filterByDate != null &&
        !list.any((d) => d == _filterByDate)) {
      list.insert(0, _filterByDate!);
    }
    return list;
  }

  void _onFilterDateChanged(DateTime? day) {
    setState(() => _filterByDate = day);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateQ = _filterByDate != null
          ? TrainingDailyReportDateUtils.formatQuery(_filterByDate!)
          : null;
      final list = await TrainingDailyReportRepo.instance.listAllReports(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        fromDate: dateQ,
        toDate: dateQ,
      );
      if (!mounted) return;
      setState(() {
        _reports = list;
        _loading = false;
        if (_filterByDate == null) {
          _reportDatesCache.clear();
          _countByDay.clear();
          for (final r in list) {
            final d = TrainingDailyReportDateUtils.toLocalDate(r.submittedAt);
            _reportDatesCache.add(d);
            _countByDay[d] = (_countByDay[d] ?? 0) + 1;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markSeen(TrainingDailyReport report) async {
    try {
      final updated = await TrainingDailyReportRepo.instance.markAsSeen(
        report.id,
      );
      if (!mounted) return;
      setState(() {
        final idx = _reports.indexWhere((r) => r.id == report.id);
        if (idx != -1) _reports[idx] = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked report as seen.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark as seen: $e')));
    }
  }

  Future<void> _confirmAndDelete(TrainingDailyReport report) async {
    final who = report.employeeName ?? 'Unknown employee';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          'This permanently removes the record from the system. '
          'Attachments linked to this report will also be removed.\n\n'
          '$who — ${report.title}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TrainingDailyReportRepo.instance.deleteReport(report.id);
      if (!mounted) return;
      setState(() {
        _reports.removeWhere((r) => r.id == report.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${userFacingApiError(e)}')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrowToolbar = MediaQuery.sizeOf(context).width < 720;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.14),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                ),
              ),
              child: const Icon(
                Icons.assignment_outlined,
                size: 26,
                color: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Training Daily Reports',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.45,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Monitor daily reports from employees under training, review attachments, and mark them as seen.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.dashMutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: narrowToolbar
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: AppTheme.dashInputDecoration(
                        context,
                        hintText: 'Search by name, title, or notes…',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppTheme.dashTextSecondaryOf(context),
                          size: 22,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Refresh'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: AppTheme.dashInputDecoration(
                          context,
                          hintText: 'Search by name, title, or notes…',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: AppTheme.dashTextSecondaryOf(context),
                            size: 22,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Refresh'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        TrainingDailyReportDateFilterBar(
          filterByDate: _filterByDate,
          datesWithReports: _datesWithReports,
          onDateChanged: _onFilterDateChanged,
          countForDay: (day) => _countByDay[day] ?? 0,
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_reports.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _filterByDate != null
                          ? Icons.event_busy_rounded
                          : Icons.assignment_outlined,
                      size: 40,
                      color: AppTheme.primaryNavy.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _filterByDate != null
                        ? 'No reports on ${TrainingDailyReportDateUtils.formatDisplay(_filterByDate!)}'
                        : 'No reports match your search',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _filterByDate != null
                        ? 'Pick another date from the calendar or tap Show all.'
                        : 'Try another keyword or refresh after employees submit.',
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
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final r = _reports[index];
              return _LdReportCard(
                report: r,
                onViewFile: r.attachmentUrl != null
                    ? () => showTrainingReportAttachmentPreview(
                        context,
                        url: r.attachmentUrl!,
                        fileName: r.attachmentName,
                        mimeType: r.attachmentType,
                      )
                    : null,
                onMarkSeen: () => _markSeen(r),
                onDelete: () => _confirmAndDelete(r),
              );
            },
          ),
      ],
    );
  }
}

class _LdReportCard extends StatelessWidget {
  const _LdReportCard({
    required this.report,
    this.onViewFile,
    required this.onMarkSeen,
    required this.onDelete,
  });

  final TrainingDailyReport report;
  final VoidCallback? onViewFile;
  final VoidCallback onMarkSeen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final desc = (r.description ?? '').trim();
    final submitted = _formatLdTrainingDailySubmittedAt(r.submittedAt);
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final name = r.employeeName ?? 'Unknown employee';
    final parts = name.trim().split(RegExp(r'\s+'));
    var initials = '';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials += parts.first[0].toUpperCase();
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      initials += parts.last[0].toUpperCase();
    }
    if (initials.isEmpty) initials = '?';

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryNavy.withValues(alpha: 0.16),
                        AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: AppTheme.dashIsDark(context)
                          ? AppTheme.primaryNavyLight
                          : AppTheme.primaryNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
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
                                  name,
                                  style: TextStyle(
                                    color: primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.topic_rounded,
                                      size: 15,
                                      color: secondary.withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        r.title,
                                        style: TextStyle(
                                          color: secondary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _LdStatusChip(status: r.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: muted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: hairline),
                        ),
                        child: Text(
                          desc.isEmpty ? 'No description provided.' : desc,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: desc.isEmpty
                                ? secondary.withValues(alpha: 0.75)
                                : primary,
                            fontSize: 13.5,
                            height: 1.45,
                            fontStyle: desc.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: secondary.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Submitted $submitted',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: hairline),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => showReadOnlySavedEntryDialog(
                                  context,
                                  title: 'Training daily report',
                                  subtitle: r.title.trim().isNotEmpty
                                      ? r.title
                                      : r.submittedAt
                                            .toLocal()
                                            .toString()
                                            .split('.')
                                            .first,
                                  previewBuilder: () =>
                                      TrainingDailyReportReadOnlyView(
                                        report: r,
                                      ),
                                  contentWidth: 640,
                                ),
                                icon: const Icon(
                                  Icons.article_outlined,
                                  size: 18,
                                ),
                                label: const Text('View form'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryNavy,
                                  side: BorderSide(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              if (onViewFile != null)
                                OutlinedButton.icon(
                                  onPressed: onViewFile,
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('View file'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryNavy,
                                    side: BorderSide(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: onDelete,
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.red.shade700,
                                ),
                                label: Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              FilledButton(
                                onPressed: onMarkSeen,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Mark as seen',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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

class _LdStatusChip extends StatelessWidget {
  const _LdStatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    Color color;
    switch (status.toLowerCase()) {
      case 'seen':
        color = const Color(0xFF0EA5E9);
        break;
      case 'reviewed':
        color = dark ? const Color(0xFF9FA8DA) : Colors.indigo;
        break;
      case 'approved':
        color = dark ? const Color(0xFF81C784) : Colors.green;
        break;
      case 'needs_revision':
      case 'needs-revision':
        color = dark ? const Color(0xFFFFB74D) : Colors.orange;
        break;
      case 'submitted':
        color = dark ? const Color(0xFFB0BEC5) : Colors.blueGrey;
        break;
      default:
        color = dark ? const Color(0xFFB0BEC5) : Colors.grey.shade700;
    }
    final label = status.isEmpty
        ? '—'
        : (status[0].toUpperCase() + status.substring(1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: dark ? 0.22 : 0.14),
        border: Border.all(color: color.withValues(alpha: dark ? 0.45 : 0.28)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TrainingNeedAnalysisFormEditor extends StatefulWidget {
  const _TrainingNeedAnalysisFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final TrainingNeedAnalysisEntry entry;
  final bool readOnly;
  final void Function(TrainingNeedAnalysisEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(TrainingNeedAnalysisEntry) onPrint;
  final Future<void> Function(TrainingNeedAnalysisEntry) onDownloadPdf;

  @override
  State<_TrainingNeedAnalysisFormEditor> createState() =>
      _TrainingNeedAnalysisFormEditorState();
}

class _TrainingNeedAnalysisFormEditorState
    extends State<_TrainingNeedAnalysisFormEditor> {
  late TextEditingController _cyYear;
  late TextEditingController _department;
  late List<Map<String, TextEditingController>> _rows;

  static Map<String, TextEditingController> _rowControllers(
    String namePos,
    String goal,
    String behavior,
    String skills,
    String need,
    String rec,
  ) {
    return {
      'name_position': TextEditingController(text: namePos),
      'goal': TextEditingController(text: goal),
      'behavior': TextEditingController(text: behavior),
      'skills_knowledge': TextEditingController(text: skills),
      'need_for_training': TextEditingController(text: need),
      'training_recommendations': TextEditingController(text: rec),
    };
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _cyYear = TextEditingController(text: e.cyYear ?? '');
    _department = TextEditingController(text: e.department ?? '');
    _rows = e.rows.isEmpty
        ? [_rowControllers('', '', '', '', '', '')]
        : e.rows
              .map(
                (r) => _rowControllers(
                  r.namePosition ?? '',
                  r.goal ?? '',
                  r.behavior ?? '',
                  r.skillsKnowledge ?? '',
                  r.needForTraining ?? '',
                  r.trainingRecommendations ?? '',
                ),
              )
              .toList();
  }

  @override
  void dispose() {
    _cyYear.dispose();
    _department.dispose();
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    if (widget.readOnly) return;
    setState(() => _rows.add(_rowControllers('', '', '', '', '', '')));
  }

  void _removeRow(int i) {
    if (widget.readOnly) return;
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  TrainingNeedAnalysisEntry _buildCurrentEntry() {
    final list = _rows
        .map(
          (r) => TrainingNeedAnalysisRow(
            namePosition: r['name_position']!.text.trim().isEmpty
                ? null
                : r['name_position']!.text.trim(),
            goal: r['goal']!.text.trim().isEmpty
                ? null
                : r['goal']!.text.trim(),
            behavior: r['behavior']!.text.trim().isEmpty
                ? null
                : r['behavior']!.text.trim(),
            skillsKnowledge: r['skills_knowledge']!.text.trim().isEmpty
                ? null
                : r['skills_knowledge']!.text.trim(),
            needForTraining: r['need_for_training']!.text.trim().isEmpty
                ? null
                : r['need_for_training']!.text.trim(),
            trainingRecommendations:
                r['training_recommendations']!.text.trim().isEmpty
                ? null
                : r['training_recommendations']!.text.trim(),
          ),
        )
        .toList();
    return TrainingNeedAnalysisEntry(
      id: widget.entry.id,
      cyYear: _cyYear.text.trim().isEmpty ? null : _cyYear.text.trim(),
      department: _department.text.trim().isEmpty
          ? null
          : _department.text.trim(),
      rows: list,
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(formTitle: 'TRAINING NEED ANALYSIS'),
            Text(
              'AND CONSOLIDATED REPORT',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _cyYear,
                readOnly: ro,
                decoration: rspUnderlinedField('FOR CY (e.g. 2025):'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _department,
                readOnly: ro,
                decoration: rspUnderlinedField('DEPARTMENT:'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Table',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!ro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add row'),
                  ),
                ],
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('NAME/POSITION')),
                  DataColumn(label: Text('GOAL')),
                  DataColumn(label: Text('BEHAVIOR')),
                  DataColumn(label: Text('SKILLS/KNOWLEDGE')),
                  DataColumn(label: Text('NEED FOR TRAINING')),
                  DataColumn(label: Text('TRAINING RECOMMENDATIONS')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            controller: r['name_position'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['goal'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['behavior'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['skills_knowledge'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['need_for_training'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            controller: r['training_recommendations'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        ro
                            ? const SizedBox(width: 40)
                            : IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                ),
                                onPressed: _rows.length > 1
                                    ? () => _removeRow(i)
                                    : null,
                              ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
            if (!ro) ...[
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => widget.onPrint(_buildCurrentEntry()),
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Print',
                  ),
                  IconButton(
                    onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Download PDF',
                  ),
                ],
              ),
            ] else ...[
              if (widget.entry.createdAt != null)
                Text(
                  'Created: ${widget.entry.createdAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrainingNeedAnalysisList extends StatelessWidget {
  const _TrainingNeedAnalysisList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<TrainingNeedAnalysisEntry> entries;
  final void Function(TrainingNeedAnalysisEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(TrainingNeedAnalysisEntry) onPrint;
  final Future<void> Function(TrainingNeedAnalysisEntry) onDownloadPdf;

  Future<void> _confirmDelete(
    BuildContext context,
    TrainingNeedAnalysisEntry e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && e.id != null) onDelete(e.id!);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final e = entries[index];
        final cy = e.cyYear?.trim().isNotEmpty == true ? e.cyYear! : '—';
        final dept = e.department?.trim().isNotEmpty == true
            ? e.department!
            : 'No department';
        return _LdSavedEntryCard(
          title: 'CY $cy',
          subtitle: dept,
          meta: '${e.rows.length} row${e.rows.length == 1 ? '' : 's'}',
          onView: () => showReadOnlySavedEntryDialog(
            context,
            title: 'Training need analysis',
            subtitle: 'CY ${e.cyYear ?? '—'} · ${e.department ?? '—'}',
            previewBuilder: () => _TrainingNeedAnalysisFormEditor(
              readOnly: true,
              entry: e,
              onSave: (_) {},
              onCancel: () {},
              onPrint: (_) async {},
              onDownloadPdf: (_) async {},
            ),
            contentWidth: 1100,
            onPrint: () => onPrint(e),
          ),
          onEdit: () => onEdit(e),
          onPrint: () => onPrint(e),
          onDownloadPdf: () => onDownloadPdf(e),
          onDelete: () => _confirmDelete(context, e),
        );
      },
    );
  }
}

/// L&D: Action Brainstorming and Coaching Worksheet â€” department, date, instruction, table (Name, Stop Doing, Do Less Of, Keep Doing, Do More Of, Start Doing, Goal), Certified by.
class _ActionBrainstormingSection extends StatefulWidget {
  const _ActionBrainstormingSection();

  @override
  State<_ActionBrainstormingSection> createState() =>
      _ActionBrainstormingSectionState();
}

class _ActionBrainstormingSectionState
    extends State<_ActionBrainstormingSection> {
  List<ActionBrainstormingEntry> _entries = [];
  bool _loading = true;
  ActionBrainstormingEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ActionBrainstormingRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _startNew() =>
      setState(() => _editing = const ActionBrainstormingEntry());
  void _edit(ActionBrainstormingEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ActionBrainstormingEntry entry) async {
    try {
      if (entry.id == null) {
        await ActionBrainstormingRepo.instance.insert(entry);
      } else {
        await ActionBrainstormingRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action Brainstorming worksheet saved.'),
          ),
        );
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await ActionBrainstormingRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printAb(ActionBrainstormingEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildActionBrainstormingCoachingPdf(entry),
        filename: 'Action_Brainstorming_Coaching.pdf',
        format: FormPdf.pageLetterLandscape,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadAb(ActionBrainstormingEntry entry) async {
    try {
      final doc = await FormPdf.buildActionBrainstormingCoachingPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Action_Brainstorming_Coaching.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved Action Brainstorming worksheets',
      emptyMessage: 'No worksheets yet.',
      loading: _loading,
      items: _entries.map((e) {
        final dept = e.department?.trim().isNotEmpty == true
            ? e.department!
            : '(No department)';
        return SavedRecordListItem(
          title: dept,
          subtitle: '${e.date ?? "—"} · ${e.rows.length} row(s)',
          detailDialogTitle: 'Action Brainstorming — $dept',
          previewContentWidth: 1280,
          previewBuilder: () => _ActionBrainstormingFormEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printAb(e),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ldSectionHeader(
          context,
          icon: Icons.lightbulb_outline_rounded,
          title: 'Action Brainstorming and Coaching Worksheet',
          subtitle:
              'Use the worksheet to brainstorm/coach staff on new ideas to move the department closer to department goal.',
        ),
        const SizedBox(height: 22),
        _ldSectionToolbar(
          context,
          loading: _loading,
          addLabel: 'Add worksheet',
          onAdd: _startNew,
          onRefresh: _load,
          onViewRecords: _openSavedRecordsBrowser,
        ),
        const SizedBox(height: 20),
        if (_editing != null) ...[
          _ActionBrainstormingFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printAb,
            onDownloadPdf: _downloadAb,
          ),
          const SizedBox(height: 20),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          _ldEmptyRecordsPlaceholder(
            icon: Icons.lightbulb_outline,
            title: 'No worksheets yet',
            subtitle:
                'Tap "Add worksheet" to create an Action Brainstorming and Coaching Worksheet.',
          )
        else
          _ActionBrainstormingList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printAb,
            onDownloadPdf: _downloadAb,
          ),
      ],
    );
  }
}

class _ActionBrainstormingFormEditor extends StatefulWidget {
  const _ActionBrainstormingFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final ActionBrainstormingEntry entry;
  final bool readOnly;
  final void Function(ActionBrainstormingEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ActionBrainstormingEntry) onPrint;
  final Future<void> Function(ActionBrainstormingEntry) onDownloadPdf;

  @override
  State<_ActionBrainstormingFormEditor> createState() =>
      _ActionBrainstormingFormEditorState();
}

class _ActionBrainstormingFormEditorState
    extends State<_ActionBrainstormingFormEditor> {
  late TextEditingController _department;
  late TextEditingController _date;
  late TextEditingController _certifiedBy;
  late TextEditingController _certificationDate;
  late List<Map<String, TextEditingController>> _rows;

  static Map<String, TextEditingController> _rowCtrl(
    String name,
    String stop,
    String less,
    String keep,
    String more,
    String start,
    String goal,
  ) {
    return {
      'name': TextEditingController(text: name),
      'stop_doing': TextEditingController(text: stop),
      'do_less_of': TextEditingController(text: less),
      'keep_doing': TextEditingController(text: keep),
      'do_more_of': TextEditingController(text: more),
      'start_doing': TextEditingController(text: start),
      'goal': TextEditingController(text: goal),
    };
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _department = TextEditingController(text: e.department ?? '');
    _date = TextEditingController(text: e.date ?? '');
    _certifiedBy = TextEditingController(text: e.certifiedBy ?? '');
    _certificationDate = TextEditingController(text: e.certificationDate ?? '');
    _rows = e.rows.isEmpty
        ? List.generate(15, (_) => _rowCtrl('', '', '', '', '', '', ''))
        : e.rows
              .map(
                (r) => _rowCtrl(
                  r.name ?? '',
                  r.stopDoing ?? '',
                  r.doLessOf ?? '',
                  r.keepDoing ?? '',
                  r.doMoreOf ?? '',
                  r.startDoing ?? '',
                  r.goal ?? '',
                ),
              )
              .toList();
    if (_rows.length < 15) {
      while (_rows.length < 15) {
        _rows.add(_rowCtrl('', '', '', '', '', '', ''));
      }
    }
  }

  @override
  void dispose() {
    _department.dispose();
    _date.dispose();
    _certifiedBy.dispose();
    _certificationDate.dispose();
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    if (widget.readOnly) return;
    setState(() => _rows.add(_rowCtrl('', '', '', '', '', '', '')));
  }

  void _removeRow(int i) {
    if (widget.readOnly) return;
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  ActionBrainstormingEntry _buildCurrentEntry() {
    final list = _rows
        .map(
          (r) => ActionBrainstormingRow(
            name: r['name']!.text.trim().isEmpty
                ? null
                : r['name']!.text.trim(),
            stopDoing: r['stop_doing']!.text.trim().isEmpty
                ? null
                : r['stop_doing']!.text.trim(),
            doLessOf: r['do_less_of']!.text.trim().isEmpty
                ? null
                : r['do_less_of']!.text.trim(),
            keepDoing: r['keep_doing']!.text.trim().isEmpty
                ? null
                : r['keep_doing']!.text.trim(),
            doMoreOf: r['do_more_of']!.text.trim().isEmpty
                ? null
                : r['do_more_of']!.text.trim(),
            startDoing: r['start_doing']!.text.trim().isEmpty
                ? null
                : r['start_doing']!.text.trim(),
            goal: r['goal']!.text.trim().isEmpty
                ? null
                : r['goal']!.text.trim(),
          ),
        )
        .toList();
    return ActionBrainstormingEntry(
      id: widget.entry.id,
      department: _department.text.trim().isEmpty
          ? null
          : _department.text.trim(),
      date: _date.text.trim().isEmpty ? null : _date.text.trim(),
      rows: list,
      certifiedBy: _certifiedBy.text.trim().isEmpty
          ? null
          : _certifiedBy.text.trim(),
      certificationDate: _certificationDate.text.trim().isEmpty
          ? null
          : _certificationDate.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(
              formTitle: 'ACTION BRAINSTORMING AND COACHING WORKSHEET',
            ),
            const SizedBox(height: 16),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _department,
                readOnly: ro,
                decoration: rspUnderlinedField('DEPARTMENT:'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _date,
                readOnly: ro,
                decoration: rspUnderlinedField('DATE:'),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Instruction: Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Table',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!ro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add row'),
                  ),
                ],
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('STOP DOING')),
                  DataColumn(label: Text('DO LESS OF')),
                  DataColumn(label: Text('KEEP DOING')),
                  DataColumn(label: Text('DO MORE OF')),
                  DataColumn(label: Text('START DOING')),
                  DataColumn(label: Text('GOAL')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['name'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['stop_doing'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['do_less_of'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['keep_doing'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['do_more_of'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['start_doing'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['goal'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        ro
                            ? const SizedBox(width: 40)
                            : IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                ),
                                onPressed: _rows.length > 1
                                    ? () => _removeRow(i)
                                    : null,
                              ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Certified by:',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      RspSpacedOutlineField(
                        child: TextFormField(
                          controller: _certifiedBy,
                          readOnly: ro,
                          decoration: rspUnderlinedField(''),
                        ),
                      ),
                      Text(
                        'Department Head',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date:',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      RspSpacedOutlineField(
                        child: TextFormField(
                          controller: _certificationDate,
                          readOnly: ro,
                          decoration: rspUnderlinedField(''),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
            if (!ro) ...[
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => widget.onPrint(_buildCurrentEntry()),
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Print',
                  ),
                  IconButton(
                    onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Download PDF',
                  ),
                ],
              ),
            ] else ...[
              if (widget.entry.createdAt != null)
                Text(
                  'Created: ${widget.entry.createdAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBrainstormingList extends StatelessWidget {
  const _ActionBrainstormingList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<ActionBrainstormingEntry> entries;
  final void Function(ActionBrainstormingEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ActionBrainstormingEntry) onPrint;
  final Future<void> Function(ActionBrainstormingEntry) onDownloadPdf;

  Future<void> _confirmDelete(
    BuildContext context,
    ActionBrainstormingEntry e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this worksheet?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && e.id != null) onDelete(e.id!);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final e = entries[index];
        final dept = e.department?.trim().isNotEmpty == true
            ? e.department!
            : 'No department';
        final date = e.date?.trim().isNotEmpty == true ? e.date! : '—';
        return _LdSavedEntryCard(
          title: dept,
          subtitle: date,
          meta: '${e.rows.length} row${e.rows.length == 1 ? '' : 's'}',
          onView: () => showReadOnlySavedEntryDialog(
            context,
            title: 'Action brainstorming worksheet',
            subtitle: '${e.department ?? '—'} · ${e.date ?? '—'}',
            previewBuilder: () => _ActionBrainstormingFormEditor(
              readOnly: true,
              entry: e,
              onSave: (_) {},
              onCancel: () {},
              onPrint: (_) async {},
              onDownloadPdf: (_) async {},
            ),
            contentWidth: 1280,
            onPrint: () => onPrint(e),
          ),
          onEdit: () => onEdit(e),
          onPrint: () => onPrint(e),
          onDownloadPdf: () => onDownloadPdf(e),
          onDelete: () => _confirmDelete(context, e),
        );
      },
    );
  }
}

class _ManageContent extends StatelessWidget {
  const _ManageContent({
    required this.subIndex,
    this.onOpenAssignmentForEmployee,
    this.prefillAssignmentEmployeeId,
    this.onPrefillAssignmentConsumed,
  });

  final int subIndex;
  final void Function(String employeeId)? onOpenAssignmentForEmployee;
  final String? prefillAssignmentEmployeeId;
  final VoidCallback? onPrefillAssignmentConsumed;

  static const _titles = [
    'Employees',
    'Assignment',
    'Department',
    'Position',
    'Shift',
    'Holiday',
    'Attendance Policy',
  ];

  @override
  Widget build(BuildContext context) {
    if (subIndex == 0) {
      return ManageEmployee(
        onOpenAssignmentForEmployee: onOpenAssignmentForEmployee,
      );
    }
    if (subIndex == 1) {
      return ManageAssignment(
        initialEmployeeId: prefillAssignmentEmployeeId,
        onInitialEmployeeConsumed: onPrefillAssignmentConsumed,
      );
    }
    if (subIndex == 2) {
      return const ManageDepartment();
    }
    if (subIndex == 3) {
      return const ManagePosition();
    }
    if (subIndex == 4) {
      return const ManageShift();
    }
    if (subIndex == 6) {
      return const ManageHoliday();
    }
    if (subIndex == 7) {
      return const ManageAttendancePolicy();
    }
    final title = subIndex >= 0 && subIndex < _titles.length
        ? _titles[subIndex]
        : 'Manage';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage $title. Content coming soon.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}
