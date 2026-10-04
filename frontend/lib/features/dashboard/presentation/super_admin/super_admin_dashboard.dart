import 'package:flutter/material.dart';
import 'password_reset_requests_page.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/system_audit_page.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';
import 'package:hrms_plaridel/shared/widgets/sign_out_flow.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/dtr_access_page.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/system_health_page.dart';

enum _SuperAdminPage {
  createAccount,
  accountAccess,
  auditLog,
  systemHealth,
  passwordResets,
}

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  _SuperAdminPage _selectedPage = _SuperAdminPage.createAccount;
  bool _sidebarCollapsed = false;
  final _accessKey = GlobalKey<DtrAccessPageState>();
  bool _leaving = false;

  Future<void> _selectPage(_SuperAdminPage page) async {
    if (_selectedPage == page || _leaving) return;
    _leaving = true;
    try {
      if (!await (_accessKey.currentState?.confirmLeave() ??
              Future.value(true)) ||
          !mounted) {
        return;
      }
      setState(() => _selectedPage = page);
    } finally {
      _leaving = false;
    }
  }

  Future<void> _signOut() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (!await (_accessKey.currentState?.confirmLeave() ??
              Future.value(true)) ||
          !mounted) {
        return;
      }
      await performDashboardSignOut(context);
    } finally {
      _leaving = false;
    }
  }

  Widget _content() {
    if (_selectedPage == _SuperAdminPage.passwordResets) {
      return const PasswordResetRequestsPage();
    }
    if (_selectedPage == _SuperAdminPage.systemHealth) {
      return const SystemHealthPage();
    }
    if (_selectedPage == _SuperAdminPage.accountAccess) {
      return DtrAccessPage(key: _accessKey);
    }
    if (_selectedPage == _SuperAdminPage.auditLog) {
      return const SystemAuditPage();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create Account',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              const AddEmployeeForm(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName.isNotEmpty
        ? auth.displayName
        : 'Super Admin';
    final isWide = MediaQuery.sizeOf(context).width > 900;
    final sidebar = _SuperAdminSidebar(
      selectedPage: _selectedPage,
      displayName: displayName,
      subtitle: auth.email.isNotEmpty ? auth.email : 'System Administrator',
      avatarPath: auth.avatarPath,
      onSelect: _selectPage,
    );

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      drawer: isWide ? null : Drawer(child: SafeArea(child: sidebar)),
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              AnimatedSidebarWidth(
                collapsed: _sidebarCollapsed,
                child: sidebar,
              ),
            Expanded(
              child: Column(
                children: [
                  Builder(
                    builder: (headerContext) => DashboardAppHeaderBar(
                      showBrand: false,
                      showNotifications: false,
                      showMenuButton: !isWide,
                      onMenuPressed: isWide
                          ? null
                          : () => Scaffold.of(headerContext).openDrawer(),
                      showSidebarToggle: isWide,
                      sidebarCollapsed: _sidebarCollapsed,
                      onSidebarToggle: isWide
                          ? () => setState(
                              () => _sidebarCollapsed = !_sidebarCollapsed,
                            )
                          : null,
                      trailing: IconButton(
                        tooltip: 'Sign out',
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout_outlined),
                      ),
                    ),
                  ),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuperAdminSidebar extends StatelessWidget {
  const _SuperAdminSidebar({
    required this.selectedPage,
    required this.displayName,
    required this.subtitle,
    required this.avatarPath,
    required this.onSelect,
  });

  final _SuperAdminPage selectedPage;
  final String displayName;
  final String subtitle;
  final String? avatarPath;
  final ValueChanged<_SuperAdminPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;

    void select(_SuperAdminPage page) {
      if (isDrawer) Navigator.of(context).pop();
      onSelect(page);
    }

    return DashboardSidebarRailFrame(
      hairline: AppTheme.dashHairlineOf(context),
      canvas: AppTheme.dashCanvasOf(context),
      child: Column(
        children: [
          if (isDrawer)
            const PortalSidebarBrand()
          else
            const SidebarRailHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12),
              children: [
                const DashboardSidebarSectionLabel('SYSTEM ADMINISTRATION'),
                DashboardSidebarNavTile(
                  icon: Icons.lock_reset,
                  label: 'Password Reset Requests',
                  selected: selectedPage == _SuperAdminPage.passwordResets,
                  onTap: () => select(_SuperAdminPage.passwordResets),
                ),
                DashboardSidebarNavTile(
                  icon: Icons.person_add_outlined,
                  label: 'Create Account',
                  selected: selectedPage == _SuperAdminPage.createAccount,
                  onTap: () => select(_SuperAdminPage.createAccount),
                ),
                DashboardSidebarNavTile(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Manage Access',
                  selected: selectedPage == _SuperAdminPage.accountAccess,
                  onTap: () => select(_SuperAdminPage.accountAccess),
                ),
                DashboardSidebarNavTile(
                  icon: Icons.manage_search_outlined,
                  label: 'Audit Log',
                  selected: selectedPage == _SuperAdminPage.auditLog,
                  onTap: () => select(_SuperAdminPage.auditLog),
                ),
                DashboardSidebarNavTile(
                  icon: Icons.monitor_heart_outlined,
                  label: 'System Health',
                  selected: selectedPage == _SuperAdminPage.systemHealth,
                  onTap: () => select(_SuperAdminPage.systemHealth),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: DashboardSidebarProfileCard(
              displayName: displayName,
              subtitle: subtitle,
              avatarPath: avatarPath,
            ),
          ),
        ],
      ),
    );
  }
}
