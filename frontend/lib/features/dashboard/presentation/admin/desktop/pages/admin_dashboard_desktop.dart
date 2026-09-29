import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/action_brainstorming_section.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/ld_training_daily_reports_section.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/idp_admin_section.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/learning_application_plan_section.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/training_need_analysis_section.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/ld_training_requirements_admin_section.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/widgets/ld_admin_hub.dart';
import 'package:hrms_plaridel/features/forms/presentation/admin/pages/form_background_upload_page.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart'
    show DashboardProfilePanel;
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/utils/time_greeting.dart';
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';
import 'package:hrms_plaridel/features/dtr/dtr_main.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/real_time_clock.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/pages/dtr_dashboard.dart';
import 'package:hrms_plaridel/features/dtr/dtr_routes.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';
import 'package:hrms_plaridel/features/dtr/management/departments/pages/manage_department.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/pages/manage_position.dart';
import 'package:hrms_plaridel/features/dtr/management/shifts/pages/manage_shift.dart';
import 'package:hrms_plaridel/features/dtr/management/holidays/pages/manage_holiday.dart';
import 'package:hrms_plaridel/features/dtr/management/attendance_policies/pages/manage_attendance_policy.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/pages/manage_biometric_devices.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_main.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_dashboard_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/employee_leave_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';
import 'package:hrms_plaridel/shared/widgets/feature_card.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/features/notifications/presentation/widgets/open_notifications_panel.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/recruitment_hub_analytics.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/recruitment_monitoring_stats.dart';
import 'package:hrms_plaridel/shared/widgets/admin_welcome_status_card.dart';

/// Dashboard accent colors for home-view chrome (orange theme).
class _DashboardColors {
  static const Color accentOrange = Color(0xFFE85D04);
}

/// Shared visual primitives for the admin dashboard home view.
class _AdminDashUi {
  _AdminDashUi._();

  static const double radiusLg = 20;
  static const double radiusMd = 16;

  static BoxDecoration welcomeBanner(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: dark ? AppTheme.dashPanelOf(context) : Colors.white,
      border: Border.all(
        color: dark
            ? AppTheme.dashHairlineOf(context)
            : _DashboardColors.accentOrange.withValues(alpha: 0.16),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.22 : 0.045),
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
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({
    required this.title,
    this.icon,
    this.subtitle,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;

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
    final firstName = greetingFirstName(displayName);
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'A';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 720 || isNarrow;
        final tablet = !stack && constraints.maxWidth < 1080;
        final avatarSize = stack ? 52.0 : (tablet ? 58.0 : 62.0);

        final greetingBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: stack ? 20 : 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(width: stack ? 14 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 14,
                          color: AppTheme.primaryNavy,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Admin Portal',
                          style: TextStyle(
                            color: AppTheme.primaryNavy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    greeting,
                    style: TextStyle(
                      color: primary,
                      fontSize: stack ? 22 : (tablet ? 26 : 30),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Here's the latest overview of HR activities for Plaridel.",
                    style: TextStyle(
                      color: secondary,
                      fontSize: stack ? 13.5 : 14.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final status = AdminWelcomeStatusCard(
          layout: WelcomeStatusLayout.adminHeader,
          fillWidth: stack,
        );

        return Container(
          constraints: BoxConstraints(minHeight: stack ? 0 : 150),
          padding: EdgeInsets.all(stack ? 18 : (tablet ? 22 : 26)),
          decoration: _AdminDashUi.welcomeBanner(context),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [greetingBlock, const SizedBox(height: 16), status],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: greetingBlock),
                    SizedBox(width: tablet ? 24 : 32),
                    status,
                  ],
                ),
        );
      },
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
  String? _pendingRspApplicationId;
  String? _pendingRspFinalReqApplicationId;
  String? _rspHireReturnApplicationId;
  int _rspHomeEpoch = 0;
  static const _settingsPanelKey = PageStorageKey<String>('admin_settings');
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();
  late final Widget _settingsPanelWidget;

  Widget _settingsPanel() => _settingsPanelWidget;
  Timer? _notificationPollTimer;
  String? _pendingSourceModule;
  String? _pendingSourceTable;
  String? _pendingSourceRecordId;
  int _docuTrackerDeepLinkKey = 0;

  @override
  void initState() {
    super.initState();
    _settingsPanelWidget = DashboardProfilePanel(
      key: _settingsPanelKey,
      onBack: _closeMyProfile,
    );
    WidgetsBinding.instance.addObserver(this);
    FormPdf.warmupThenPrefetchBackgrounds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().refreshUnreadCount();
      context.read<DocuTrackerProvider>().loadNotifications();
      context.read<DocuTrackerProvider>().loadSourceSignatureRequests();
      _notificationPollTimer?.cancel();
      _notificationPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        context.read<NotificationProvider>().refreshUnreadCount();
        context.read<DocuTrackerProvider>().loadNotifications();
        context.read<DocuTrackerProvider>().loadSourceSignatureRequests();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationProvider>().refreshUnreadCount();
      context.read<DocuTrackerProvider>().loadNotifications();
      context.read<DocuTrackerProvider>().loadSourceSignatureRequests();
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
        final applicationId = result.referenceId?.trim().isNotEmpty == true
            ? result.referenceId!.trim()
            : null;
        _dismissRspApplicantDetails();
        setState(() {
          _selectedMenu = AdminMenu.rsp;
          _pendingRspApplicationId = applicationId;
          _rspHomeEpoch++;
        });
        DashboardContentNavigator.showHome(_contentNavKey);
        break;
      case NotificationTapKind.adminTrainingReports:
        setState(() => _selectedMenu = AdminMenu.ld);
        DashboardContentNavigator.showHome(_contentNavKey);
        break;
      case NotificationTapKind.docuTrackerDocuments:
        setState(() {
          _selectedMenu = AdminMenu.docutracker;
          if (result.hasSourceSignatureDeepLink) {
            _pendingSourceModule = result.sourceModule;
            _pendingSourceTable = result.sourceTable;
            _pendingSourceRecordId = result.sourceRecordId;
            _docuTrackerDeepLinkKey++;
          }
        });
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

  void _dismissRspApplicantDetails() {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.popUntil(
      (route) => route.settings.name != RspAdminContent.applicantDetailsRoute,
    );
  }

  void _clearRspNotificationDeepLink({required bool rebuildRspHome}) {
    if (_pendingRspApplicationId == null &&
        _pendingRspFinalReqApplicationId == null &&
        !rebuildRspHome) {
      return;
    }
    _pendingRspApplicationId = null;
    _pendingRspFinalReqApplicationId = null;
    if (rebuildRspHome) _rspHomeEpoch++;
  }

  void _openCreateAccountFromRspHire() {
    final hire = context.read<RecruitmentHirePrefill>();
    final applicationId = hire.applicationId?.trim();
    _rspHireReturnApplicationId =
        (applicationId != null && applicationId.isNotEmpty)
        ? applicationId
        : null;
    _onMenuSelected(AdminMenu.createAccount);
  }

  void _onCreateAccountFinished() {
    final applicationId = _rspHireReturnApplicationId?.trim();
    _rspHireReturnApplicationId = null;
    if (applicationId == null || applicationId.isEmpty) return;
    _dismissRspApplicantDetails();
    setState(() {
      _selectedMenu = AdminMenu.rsp;
      _pendingRspApplicationId = null;
      _pendingRspFinalReqApplicationId = applicationId;
      _rspHomeEpoch++;
    });
    DashboardContentNavigator.showHome(_contentNavKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Account created. Send the login credentials from Final Requirements.',
        ),
      ),
    );
  }

  void _onMenuSelected(AdminMenu menu) {
    if (menu != AdminMenu.createAccount) {
      _rspHireReturnApplicationId = null;
    }
    if (menu == AdminMenu.myProfile) {
      _dismissRspApplicantDetails();
      _openMyProfile();
      return;
    }
    final settingsOnTop = DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    );
    if (_selectedMenu == menu && !settingsOnTop) return;
    _dismissRspApplicantDetails();
    _clearRspNotificationDeepLink(rebuildRspHome: menu == AdminMenu.rsp);
    if (_selectedMenu != menu) {
      setState(() => _selectedMenu = menu);
    } else {
      setState(() {});
    }
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
    DashboardContentNavigator.openSettings(_contentNavKey);
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
    showLeaveFormSuccessSnackBar(context, result);
    final userId = context.read<AuthProvider>().user?.id;
    if (userId != null && userId.isNotEmpty) {
      await context.read<LeaveProvider>().loadMyLeaveData(userId);
    }
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
        return _DashboardContent();
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
          onOpenCreateAccount: _openCreateAccountFromRspHire,
          initialApplicationId: _pendingRspApplicationId,
          initialFinalRequirementsApplicationId:
              _pendingRspFinalReqApplicationId,
          onInitialApplicationConsumed: () {
            if (_pendingRspApplicationId == null &&
                _pendingRspFinalReqApplicationId == null) {
              return;
            }
            setState(() {
              _pendingRspApplicationId = null;
              _pendingRspFinalReqApplicationId = null;
            });
          },
        );
      case AdminMenu.ld:
        return const _LdContent();
      case AdminMenu.docutracker:
        return DocuTrackerMain(
          key: ValueKey('admin-docutracker-$_docuTrackerDeepLinkKey'),
          isAdmin: true,
          openSourceModule: _pendingSourceModule,
          openSourceTable: _pendingSourceTable,
          openSourceRecordId: _pendingSourceRecordId,
          onSourceDeepLinkConsumed: () {
            if (!mounted) return;
            setState(() {
              _pendingSourceModule = null;
              _pendingSourceTable = null;
              _pendingSourceRecordId = null;
            });
          },
        );
      case AdminMenu.createAccount:
        return _AdminSignUpContent(
          onAccountCreated: _rspHireReturnApplicationId != null
              ? _onCreateAccountFinished
              : null,
        );
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
                              homeCacheKey: _selectedMenu,
                              homeRefreshKey: Object.hash(
                                _selectedMenu,
                                displayName,
                                contentPadding,
                                _rspHomeEpoch,
                              ),
                              homeBuilder: () => _buildContent(displayName),
                              settingsPanel: _settingsPanel(),
                              homeScrollPadding: EdgeInsets.all(contentPadding),
                              settingsScrollPadding:
                                  kDashboardSettingsScrollPadding,
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
                        homeCacheKey: _selectedMenu,
                        homeRefreshKey: Object.hash(
                          _selectedMenu,
                          displayName,
                          contentPadding,
                          _rspHomeEpoch,
                        ),
                        homeBuilder: () => _buildContent(displayName),
                        settingsPanel: _settingsPanel(),
                        homeScrollPadding: EdgeInsets.all(contentPadding),
                        settingsScrollPadding: kDashboardSettingsScrollPadding,
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
    final pendingSignatures = context.select<DocuTrackerProvider, int>(
      (p) => p.pendingSourceSignatureActionCount,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: railMode ? 12 : (showBrand ? 4 : 12)),
        DashboardSidebarNavTile(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          selected: selectedMenu == AdminMenu.dashboard,
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
        DashboardSidebarSectionLabel('MY PORTAL'),
        DashboardSidebarNavTile(
          icon: Icons.schedule_outlined,
          label: 'My Attendance',
          selected: selectedMenu == AdminMenu.myAttendance,
          onTap: () => onTap(AdminMenu.myAttendance),
        ),
        DashboardSidebarNavTile(
          icon: Icons.event_note_outlined,
          label: 'My Leave',
          selected: selectedMenu == AdminMenu.myLeave,
          onTap: () => onTap(AdminMenu.myLeave),
        ),
        DashboardSidebarSectionLabel('MANAGEMENT'),
        DashboardSidebarNavTile(
          icon: Icons.how_to_reg_outlined,
          label: 'RSP',
          selected: selectedMenu == AdminMenu.rsp,
          onTap: () => onTap(AdminMenu.rsp),
        ),
        DashboardSidebarNavTile(
          icon: Icons.school_outlined,
          label: 'L&D',
          selected: selectedMenu == AdminMenu.ld,
          onTap: () => onTap(AdminMenu.ld),
        ),
        DashboardSidebarNavTile(
          icon: Icons.access_time_outlined,
          label: 'DTR',
          selected: selectedMenu == AdminMenu.dtr,
          onTap: () => onTap(AdminMenu.dtr),
        ),
        DashboardSidebarNavTile(
          icon: Icons.folder_outlined,
          label: 'DocuTracker',
          selected: selectedMenu == AdminMenu.docutracker,
          badgeCount: pendingSignatures,
          onTap: () => onTap(AdminMenu.docutracker),
        ),
        DashboardSidebarNavTile(
          icon: Icons.person_add_outlined,
          label: 'Create Account',
          selected: selectedMenu == AdminMenu.createAccount,
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
    final showRecruitment = _sectionVisible(q, [
      'recruit',
      'recruitment',
      'rsp',
      'overview',
      'hiring',
      'pending',
      'application',
      'review',
      'submitted',
      'declined',
      'approved',
      'applicant',
    ]);

    final showRspMonitoring = showSummary || showRecruitment;
    final anySection = showWelcome || showRspMonitoring || showDocu || showDtr;

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
                      'Walang tumugma sa “$q”. Subukan: docu, dtr, recruit, pending, time…',
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
        if (showWelcome && showRspMonitoring) const SizedBox(height: 20),
        if (showRspMonitoring) const RecruitmentOverviewCard(),
        if ((showWelcome || showRspMonitoring) && showDocu)
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
        if ((showWelcome || showRspMonitoring || showDocu) && showDtr)
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
        const SizedBox(height: 32),
      ],
    );
  }
}

class _AdminDashboardShimmer extends StatelessWidget {
  const _AdminDashboardShimmer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Shimmer.fromColors(
      baseColor: dark
          ? const Color(0xFF2A3140)
          : AppTheme.lightGray.withValues(alpha: 0.55),
      highlightColor: dark ? const Color(0xFF3D4451) : AppTheme.white,
      period: const Duration(milliseconds: 1200),
      child: child,
    );
  }
}

class _AdminDashboardBone extends StatelessWidget {
  const _AdminDashboardBone({
    required this.height,
    this.radius = 7,
  });

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppTheme.dashMutedSurfaceOf(context),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _RecruitmentHubLoadingSkeleton extends StatelessWidget {
  const _RecruitmentHubLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return _AdminDashboardShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960 ? 4 : 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < 4; i++)
                    SizedBox(
                      width: columns == 4
                          ? (constraints.maxWidth - 36) / 4
                          : (constraints.maxWidth - 12) / 2,
                      child: const _AdminDashboardBone(height: 92, radius: 14),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const _AdminDashboardBone(height: 120, radius: 14),
          const SizedBox(height: 14),
          const _AdminDashboardBone(height: 180, radius: 14),
          const SizedBox(height: 14),
          const _AdminDashboardBone(height: 160, radius: 14),
        ],
      ),
    );
  }
}

class RecruitmentOverviewCard extends StatefulWidget {
  const RecruitmentOverviewCard({
    super.key,
    this.loadApplications,
    this.loadAnnouncement,
  });

  final Future<List<RecruitmentApplication>> Function()? loadApplications;
  final Future<JobVacancyAnnouncement> Function()? loadAnnouncement;

  @override
  State<RecruitmentOverviewCard> createState() =>
      _RecruitmentOverviewCardState();
}

class _RecruitmentOverviewCardState extends State<RecruitmentOverviewCard> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<RecruitmentApplication> _all = const [];
  JobVacancyAnnouncement? _announcement;
  bool _vacancyLoadFailed = false;

  List<RecruitmentApplication> get _activePipeline =>
      _all.where((a) {
        if (a.status == 'failed' || a.status == 'document_declined') {
          return false;
        }
        return a.isActiveInPipeline ||
            a.hiredUserId != null ||
            a.status == 'registered';
      }).toList()..sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
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

    unawaited(_loadVacancyAnnouncement());

    try {
      final apps = await (widget.loadApplications?.call() ??
          RecruitmentRepo.instance.listApplications());
      if (!mounted) return;
      setState(() {
        _all = apps.where((a) => !a.isFromMayorModule).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadVacancyAnnouncement() async {
    try {
      final announcement = await (widget.loadAnnouncement?.call() ??
          JobVacancyAnnouncementRepo.instance.fetch());
      if (!mounted) return;
      setState(() {
        _announcement = announcement;
        _vacancyLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _vacancyLoadFailed = true);
    }
  }

  String _dateLabel(DateTime? dt) {
    if (dt == null) return '—';
    return MaterialLocalizations.of(context).formatMediumDate(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final stats = RecruitmentMonitoringStats.fromApps(_all);
    final activePreview = _activePipeline.take(8).toList();
    final hiringOpen = _vacancyLoadFailed ? null : _announcement?.hasVacancies;
    final listedCount = _announcement?.listedVacancies.length;

    return Column(
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
                    'Recruitment Overview',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitor applications, recruitment progress, and hiring activity.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : () => _load(refresh: true),
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const _RecruitmentHubLoadingSkeleton()
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
          RecruitmentHubAnalyticsPanel(
            stats: stats,
            activeApplications: activePreview,
            dateLabel: _dateLabel,
            hiringOpen: hiringOpen,
            listedPositionCount: listedCount,
          ),
      ],
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
  static const int _maxCachedFeatures = 4;

  /// 0 = menu, 1 = Time Logs, 2 = Reports, 3 = Employees, 4 = Assignment,
  /// 5 = Department, 6 = Position, 7 = Shift, 8 = Leave Management,
  /// 9–10 = Holiday / Policy via [_ManageContent], 11 = Biometric Devices,
  /// 12 = Locator Slip Management
  int _dtrSectionIndex = 0;
  final Map<int, _DtrFeatureCacheEntry> _featureCache = {};
  int _featureCacheClock = 0;

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
      // Assignment must be rebuilt so the new one-time prefill reaches it.
      _featureCache.remove(4);
    });
    _openDtrSection(4);
  }

  void _openDtrSection(int index) {
    if (!mounted) return;
    if (index == 0) {
      setState(() {
        _dtrSectionIndex = 0;
      });
      return;
    }
    if (_dtrSectionIndex == index) return;
    setState(() => _dtrSectionIndex = index);
  }

  Widget _buildDtrFeature(int index) {
    if (index == 1) return DtrMain(section: DtrSection.timeLogs);
    if (index == 2) return DtrMain(section: DtrSection.reports);
    if (index == 8) return const LeaveMain(isAdmin: true);
    if (index == 11) return const ManageBiometricDevices();
    if (index == 12) return const AdminLocatorManagementScreen();
    return _ManageContent(
      subIndex: index - 3,
      onOpenAssignmentForEmployee: _goToAssignmentWithEmployee,
      prefillAssignmentEmployeeId: index == 4
          ? _prefillAssignmentEmployeeId
          : null,
      onPrefillAssignmentConsumed: () {
        if (_prefillAssignmentEmployeeId != null) {
          setState(() => _prefillAssignmentEmployeeId = null);
        }
      },
    );
  }

  void _ensureActiveFeatureCached() {
    final index = _dtrSectionIndex;
    if (index == 0) return;
    final existing = _featureCache[index];
    if (existing != null) {
      existing.lastUsed = ++_featureCacheClock;
      return;
    }
    _featureCache[index] = _DtrFeatureCacheEntry(
      index: index,
      child: KeyedSubtree(
        key: ValueKey<String>('dtr_feature_$index'),
        child: _buildDtrFeature(index),
      ),
      lastUsed: ++_featureCacheClock,
    );
    if (_featureCache.length <= _maxCachedFeatures) return;
    final removable =
        _featureCache.values.where((entry) => entry.index != index).toList()
          ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    while (_featureCache.length > _maxCachedFeatures && removable.isNotEmpty) {
      _featureCache.remove(removable.removeAt(0).index);
    }
  }

  Widget _buildCachedFeatureStack() {
    _ensureActiveFeatureCached();
    final entries = _featureCache.values.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          Offstage(
            offstage: entry.index != _dtrSectionIndex,
            child: TickerMode(
              enabled: entry.index == _dtrSectionIndex,
              child: entry.child,
            ),
          ),
      ],
    );
  }

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
              if (_dtrSectionIndex != 0) ...[
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
              if (_dtrSectionIndex == 0) ...[
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
              ] else
                _buildCachedFeatureStack(),
            ],
          );
        },
      ),
    );
  }
}

class _DtrFeatureCacheEntry {
  _DtrFeatureCacheEntry({
    required this.index,
    required this.child,
    required this.lastUsed,
  });

  final int index;
  final Widget child;
  int lastUsed;
}

/// Create Account: full form displayed directly (single place for adding employees).
class _AdminSignUpContent extends StatelessWidget {
  const _AdminSignUpContent({this.onAccountCreated});

  final VoidCallback? onAccountCreated;

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
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
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
          child: AddEmployeeForm(onAccountCreated: onAccountCreated),
        ),
      ],
    );
  }
}

class _LdFormPickerItem {
  const _LdFormPickerItem({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.format,
  });

  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
  final String format;
}

const _ldFormPickerItems = <_LdFormPickerItem>[
  _LdFormPickerItem(
    keyName: 'training_need_analysis',
    title: 'Training Need Analysis',
    subtitle:
        'Consolidate CY training needs by department: goals, skill gaps, and recommendations.',
    icon: Icons.school_rounded,
    format: 'Analysis form',
  ),
  _LdFormPickerItem(
    keyName: 'action_brainstorming',
    title: 'Action Brainstorming Worksheet',
    subtitle:
        'Coaching actions per employee: stop/start behaviors, goals, and department certification.',
    icon: Icons.lightbulb_outline_rounded,
    format: 'Coaching form',
  ),
  _LdFormPickerItem(
    keyName: 'idp',
    title: 'Individual Development Plan (IDP)',
    subtitle:
        'Record qualifications, succession analysis, and employee development actions.',
    icon: Icons.trending_up_rounded,
    format: 'Development form',
  ),
  _LdFormPickerItem(
    keyName: 'learning_application_plan',
    title: 'Learning Application Plan',
    subtitle:
        'Document how learning from training will be applied in the workplace.',
    icon: Icons.menu_book_rounded,
    format: 'Application plan',
  ),
];

/// L&D: "Forms" hub — pick Training Need Analysis, Action Brainstorming, IDP, or Learning Application Plan.
class _LdFormsSection extends StatefulWidget {
  const _LdFormsSection({required this.onBackToLd});

  final VoidCallback onBackToLd;

  @override
  State<_LdFormsSection> createState() => _LdFormsSectionState();
}

class _LdFormsSectionState extends State<_LdFormsSection> {
  _LdFormPickerItem? _selected;
  bool _showPrintBackground = false;

  Widget _buildSelectedForm(_LdFormPickerItem item) {
    switch (item.keyName) {
      case 'training_need_analysis':
        return const TrainingNeedAnalysisAdminSection();
      case 'action_brainstorming':
        return const ActionBrainstormingAdminSection();
      case 'idp':
        return const IdpAdminSection();
      case 'learning_application_plan':
        return const LearningApplicationPlanAdminSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBreadcrumb() {
    final navy = AppTheme.primaryNavy;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final selectedItem = _selected;
    final inBackground = _showPrintBackground;
    return Row(
      children: [
        TextButton.icon(
          onPressed: selectedItem == null && !inBackground
              ? widget.onBackToLd
              : () => setState(() {
                  _selected = null;
                  _showPrintBackground = false;
                }),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          label: const Text('Back'),
          style: TextButton.styleFrom(foregroundColor: navy),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
        const SizedBox(width: 2),
        Text(
          'Forms',
          style: TextStyle(
            color: selectedItem == null && !inBackground ? navy : secondary,
            fontSize: 13,
            fontWeight: selectedItem == null && !inBackground
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        if (selectedItem != null) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              selectedItem.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        if (inBackground) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
          const SizedBox(width: 2),
          const Flexible(
            child: Text(
              'Print background',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _formGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        Widget row(_LdFormPickerItem item) => _LdFormPickerRow(
          item: item,
          onTap: () => setState(() => _selected = item),
        );
        if (columns == 1) {
          return Column(
            children: [
              for (final item in _ldFormPickerItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: row(item),
                ),
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in _ldFormPickerItems)
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: row(item),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showPrintBackground) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 12),
          FormBackgroundUploadPage(
            module: 'ld',
            embedded: true,
            onBack: () => setState(() => _showPrintBackground = false),
          ),
        ],
      );
    }

    if (_selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 12),
          _buildSelectedForm(_selected!),
        ],
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBreadcrumb(),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(isNarrow ? 20 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.dashIsDark(context)
                  ? [const Color(0xFF252D3D), const Color(0xFF1E2430)]
                  : [
                      const Color(0xFFFFF8F3),
                      Colors.white,
                      const Color(0xFFF5F8FF),
                    ],
            ),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy.withValues(alpha: 0.16),
                      AppTheme.letterheadNavy.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.14),
                  ),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppTheme.primaryNavy,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Forms',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select a form or set a print background.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FormsPrintBackgroundEntry(
          onOpen: () => setState(() => _showPrintBackground = true),
        ),
        const SizedBox(height: 16),
        _formGrid(),
      ],
    );
  }
}

class _LdFormPickerRow extends StatefulWidget {
  const _LdFormPickerRow({required this.item, required this.onTap});

  final _LdFormPickerItem item;
  final VoidCallback onTap;

  @override
  State<_LdFormPickerRow> createState() => _LdFormPickerRowState();
}

class _LdFormPickerRowState extends State<_LdFormPickerRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.primaryNavy;
    final dark = AppTheme.dashIsDark(context);
    final baseBg = AppTheme.dashPanelOf(context);
    final baseBorder = AppTheme.dashHairlineOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovering ? -2 : 0, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _hovering
              ? color.withValues(alpha: dark ? 0.1 : 0.05)
              : baseBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering ? color.withValues(alpha: 0.5) : baseBorder,
            width: _hovering ? 1.4 : 1,
          ),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: dark ? 0.22 : 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: dark ? 0.28 : 0.14),
                        color.withValues(alpha: dark ? 0.16 : 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Icon(widget.item.icon, size: 22, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.item.subtitle,
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: dark ? 0.16 : 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.item.format,
                          style: TextStyle(
                            color: color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _hovering ? color : color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: _hovering ? Colors.white : color,
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

/// L&D (Learning & Development) module: hub with grouped Forms, daily reports, and requirements.
class _LdContent extends StatefulWidget {
  const _LdContent();

  @override
  State<_LdContent> createState() => _LdContentState();
}

class _LdContentState extends State<_LdContent> {
  int _ldSectionIndex = 0;

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
              if (_ldSectionIndex != 0 &&
                  _ldSectionIndex != 1 &&
                  _ldSectionIndex != 5) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _ldSectionIndex = 0),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Back to L&D'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_ldSectionIndex == 0)
                LdAdminHub(
                  onOpenSection: (index) =>
                      setState(() => _ldSectionIndex = index),
                )
              else if (_ldSectionIndex == 1)
                _LdFormsSection(
                  onBackToLd: () => setState(() => _ldSectionIndex = 0),
                )
              else if (_ldSectionIndex == 3)
                const LdTrainingDailyReportsSection()
              else if (_ldSectionIndex == 5)
                LdTrainingRequirementsAdminSection(
                  onBackToLd: () => setState(() => _ldSectionIndex = 0),
                )
              else
                const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }
}

/// L&D: Training Need Analysis and Consolidated Report -- moved to
/// training_need_analysis_section.dart (TrainingNeedAnalysisAdminSection).

/// L&D: Action Brainstorming and Coaching Worksheet -- moved to
/// action_brainstorming_section.dart (ActionBrainstormingAdminSection).

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
