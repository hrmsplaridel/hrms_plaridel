import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/auth_provider.dart';
import '../../../data/job_vacancy_announcement.dart';
import '../../../data/recruitment_application.dart';
import '../../../data/action_brainstorming_coaching.dart';
import '../../../data/training_need_analysis.dart';
import '../../../data/training_daily_report.dart';
import '../../../landingpage/constants/app_theme.dart';
import '../../../landingpage/screens/landing_page.dart';
import '../../../login/screens/login_page.dart';
import '../../../utils/form_pdf.dart';
import '../../../widgets/rsp_form_header_footer.dart';
import '../../../widgets/user_avatar.dart';
import '../../shared/screens/profile_and_settings_page.dart';
import '../../../dtr/dtr_main.dart';
import '../../../dtr/dtr_provider.dart';
import '../../../dtr/screens/dtr_dashboard.dart';
import '../../../dtr/dtr_routes.dart';
import '../../../dtr/manage/manage_employee.dart';
import '../../../dtr/manage/manage_assignment.dart';
import '../../../dtr/manage/manage_department.dart';
import '../../../dtr/manage/manage_position.dart';
import '../../../dtr/manage/manage_shift.dart';
import '../../../dtr/manage/manage_holiday.dart';
import '../../../dtr/manage/manage_attendance_policy.dart';
import '../../../dtr/manage/manage_attendance_adjustment.dart';
import '../../../docutracker/docutracker_main.dart';
import '../../../docutracker/screens/docutracker_dashboard_screen.dart';
import '../../../leave/leave_main.dart';
import '../../../recruitment/screens/rsp_admin_screen.dart';
import '../../../widgets/feature_card.dart';

/// Dashboard accent colors for summary cards and accents (orange theme).
class _DashboardColors {
  static const Color cardBlue = Color(0xFFFFF3E0);
  static const Color cardGreen = Color(0xFFFFECB3);
  static const Color cardAmber = Color(0xFFFFE0B2);
  static const Color accentBlue = Color(0xFFE85D04);
  static const Color accentGreen = Color(0xFFBF360C);
  static const Color accentAmber = Color(0xFFFF9800);
}

/// Admin dashboard matching reference layout; features only from existing system:
/// Dashboard, Job Vacancies (Hiring), Recruitment (Applications).
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedNavIndex = 0;
  static const _navItems = [
    'Dashboard',
    'RSP',
    'L&D',
    'DTR',
    'DocuTracker',
    'Create Account',
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Sync DTR current user from API auth (so clock in/out and time records use correct user).
    if (auth.user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final dtr = context.read<DtrProvider>();
        if (dtr.userId != auth.user?.id) dtr.setUserFromApi(auth.user?.id);
      });
    }
    final email = auth.email.isNotEmpty ? auth.email : 'Admin';
    final displayName = auth.displayName.isNotEmpty
        ? auth.displayName
        : 'Admin';
    final avatarPath = auth.avatarPath;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final contentPadding = width > 900 ? 24.0 : (width > 600 ? 20.0 : 16.0);

    return Scaffold(
      // Light orange background for the main admin dashboard.
      backgroundColor: const Color(0xFFFFF3E0),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _Sidebar(
                  selectedIndex: _selectedNavIndex,
                  avatarPath: avatarPath,
                  onTap: (i) {
                    setState(() => _selectedNavIndex = i);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ),
      body: Row(
        children: [
          if (isWide)
            _Sidebar(
              selectedIndex: _selectedNavIndex,
              avatarPath: avatarPath,
              onTap: (i) => setState(() => _selectedNavIndex = i),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF8F9FA),
                    const Color(0xFFF1F3F5),
                    const Color(0xFFEEF1F4),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Column(
                children: [
                  _TopBar(
                    email: email,
                    displayName: displayName,
                    avatarPath: avatarPath,
                    showMenuButton: !isWide,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(contentPadding),
                      child: _selectedNavIndex == 0
                          ? const _DashboardContent()
                          : _selectedNavIndex == 1
                          ? const RspAdminContent()
                          : _selectedNavIndex == 2
                          ? const _LdContent()
                          : _selectedNavIndex == 3
                          ? const _DtrContent()
                          : _selectedNavIndex == 4
                          ? const DocuTrackerMain(isAdmin: true)
                          : _selectedNavIndex == 5
                          ? const _AdminSignUpContent()
                          : _PlaceholderContent(
                              title: _navItems[_selectedNavIndex],
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
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedIndex,
    this.avatarPath,
    required this.onTap,
  });

  final int selectedIndex;
  final String? avatarPath;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(2, 0),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(1, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryNavy.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/Plaridel Logo.jpg',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: AppTheme.primaryNavy,
                        child: const Icon(
                          Icons.shield_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Municipality of Plaridel',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'HUMAN RESOURCE MANAGEMENT SYSTEM',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavTile(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    selected: selectedIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  _NavTile(
                    icon: Icons.how_to_reg_rounded,
                    label: 'RSP',
                    selected: selectedIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  _NavTile(
                    icon: Icons.school_rounded,
                    label: 'L&D',
                    selected: selectedIndex == 2,
                    onTap: () => onTap(2),
                  ),
                  _NavTile(
                    icon: Icons.access_time_rounded,
                    label: 'DTR',
                    selected: selectedIndex == 3,
                    onTap: () => onTap(3),
                  ),
                  _NavTile(
                    icon: Icons.folder_rounded,
                    label: 'DocuTracker',
                    selected: selectedIndex == 4,
                    onTap: () => onTap(4),
                  ),
                  _NavTile(
                    icon: Icons.person_add_rounded,
                    label: 'Create Account',
                    selected: selectedIndex == 5,
                    onTap: () => onTap(5),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.offWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  UserAvatar(avatarPath: avatarPath, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Admin',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'System Administrator',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                Text(
                  'Â© 2026 HRMS',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
                Text(
                  ' Â· ',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text(
                    'Privacy',
                    style: TextStyle(fontSize: 11, color: AppTheme.primaryNavy),
                  ),
                ),
                Text(
                  ' Â· ',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text(
                    'Terms',
                    style: TextStyle(fontSize: 11, color: AppTheme.primaryNavy),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: widget.selected
                ? AppTheme.primaryNavy.withOpacity(0.1)
                : (_hover
                      ? AppTheme.primaryNavy.withOpacity(0.06)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: widget.selected
                      ? Border(
                          left: BorderSide(
                            color: AppTheme.primaryNavy,
                            width: 3,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 23,
                      color: active
                          ? AppTheme.primaryNavy
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: active
                            ? AppTheme.primaryNavy
                            : AppTheme.textPrimary,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.email,
    required this.displayName,
    this.avatarPath,
    this.showMenuButton = false,
  });

  final String email;
  final String displayName;
  final String? avatarPath;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Container(
      height: isCompact ? 60 : 72,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
              color: AppTheme.textPrimary,
              tooltip: 'Menu',
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.offWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          if (showMenuButton && !isCompact) const SizedBox(width: 12),
          Expanded(
            child: isCompact
                ? const SizedBox.shrink()
                : Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.offWhite,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 22,
                          color: AppTheme.textSecondary.withOpacity(0.8),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Search dashboard...',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (isCompact) const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.textPrimary,
                  size: isCompact ? 24 : 26,
                ),
                onPressed: () {},
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.offWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: isCompact ? 6 : 12),
          _AdminDropdown(
            email: email,
            displayName: displayName,
            avatarPath: avatarPath,
            compact: isCompact,
          ),
        ],
      ),
    );
  }
}

class _AdminDropdown extends StatelessWidget {
  const _AdminDropdown({
    required this.email,
    required this.displayName,
    this.avatarPath,
    this.compact = false,
  });

  final String email;
  final String displayName;
  final String? avatarPath;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(avatarPath: avatarPath, radius: compact ? 17 : 20),
            if (!compact) ...[
              const SizedBox(width: 12),
              Text(
                displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: compact ? 20 : 24,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    avatarPath: avatarPath,
                    radius: 28,
                    backgroundColor: AppTheme.primaryNavy.withOpacity(0.12),
                    placeholderIconColor: AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'profile_settings',
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 22,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 14),
              Text(
                'Profile & Settings',
                style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.settings_outlined,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'signout',
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 22, color: Color(0xFFC62828)),
              const SizedBox(width: 14),
              Text(
                'Sign out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC62828),
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'signout') {
          await context.read<AuthProvider>().signOut();
          if (context.mounted) {
            final dest = kIsWeb ? const LandingPage() : const LoginPage();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => dest),
              (route) => false,
            );
          }
        }
        if (value == 'profile_settings') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileAndSettingsPage()),
          );
        }
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  static String _formatDate(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 500;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(isNarrow ? 20 : 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryNavy.withOpacity(0.1),
                AppTheme.primaryNavy.withOpacity(0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.primaryNavy.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDate(now),
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNavy.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.waving_hand_rounded,
                            color: AppTheme.primaryNavy,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back, Admin!- Hello Boi Paldooooooooooo',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Here's the latest overview of the HR activities.",
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryNavy.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.waving_hand_rounded,
                        color: AppTheme.primaryNavy,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(now),
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Welcome back, Admin!',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Here's the latest overview of the HR activities.",
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 32),
        const _SummaryCards(),
        const SizedBox(height: 28),
        Text(
          'DocuTracker',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const DocuTrackerDashboardScreen(
            isAdmin: true,
            showTitle: false,
          ),
        ),
        const SizedBox(height: 28),
        // DTR snapshot (same cards + recent activity as DTR dashboard),
        // embedded directly in the main admin dashboard.
        Text(
          'Daily Time Record',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const DtrDashboard(),
        ),
        const SizedBox(height: 28),
        _AnnouncementsCard(),
        const SizedBox(height: 28),
        _RecruitmentOverviewCard(),
        const SizedBox(height: 28),
        _PendingApplicationsCard(),
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
              color: Colors.white,
              iconColor: AppTheme.primaryNavy,
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
            color: Colors.white,
            iconColor: AppTheme.primaryNavy,
            icon: Icons.campaign_rounded,
          ),
        ];

    Widget content;
    if (isWide) {
      content = Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: _SummaryCard(data: cards[i])),
            if (i < cards.length - 1) const SizedBox(width: 16),
          ],
        ],
      );
    } else if (isSingleColumn) {
      content = Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            _SummaryCard(data: cards[i]),
            if (i < cards.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    } else {
      content = Column(
        children: [
          Row(
            children: [
              Expanded(child: _SummaryCard(data: cards[0])),
              const SizedBox(width: 16),
              Expanded(child: _SummaryCard(data: cards[1])),
            ],
          ),
          const SizedBox(height: 16),
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
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: data.color,
          borderRadius: BorderRadius.circular(20),
          border: data.color == Colors.white
              ? Border.all(color: Colors.black.withOpacity(0.06))
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: data.iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(data.icon, size: 26, color: data.iconColor),
            ),
            const SizedBox(height: 20),
            Text(
              data.title,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),
            if (data.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                data.subtitle,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.campaign_rounded,
                      color: AppTheme.primaryNavy,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Announcements',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('View All'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(color: AppTheme.primaryNavy, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Vacancies (Hiring)',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Control whether the landing page shows "We are currently accepting applications" or "There are no job vacancies at the moment." Manage this in Job Vacancies.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _DashboardColors.accentBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.pie_chart_rounded,
                        color: _DashboardColors.accentBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        'Recruitment Overview',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.insights_rounded, size: 18),
                    label: const Text('View Report'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _DashboardColors.accentBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.pie_chart_rounded,
                        color: _DashboardColors.accentBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Recruitment Overview',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.insights_rounded, size: 18),
                  label: const Text('View Report'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.offWhite.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 56,
                    color: AppTheme.textSecondary.withOpacity(0.35),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No application data yet',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Data will appear when applicants complete the recruitment process.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
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

class _PendingApplicationsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 480;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _DashboardColors.accentGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.assignment_rounded,
                        color: _DashboardColors.accentGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        'Pending Applications',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('View All'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _DashboardColors.accentGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.assignment_rounded,
                        color: _DashboardColors.accentGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Pending Applications',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final needScroll = constraints.maxWidth < 500;
              final table = ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(1.5),
                    3: FlexColumnWidth(1.2),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withOpacity(0.08),
                      ),
                      children: [
                        _TableHeader('Applicant'),
                        _TableHeader('Type'),
                        _TableHeader('Date'),
                        _TableHeader('Status'),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          child: Text(
                            'No applications yet',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          child: Text('â€”', style: TextStyle(fontSize: 14)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          child: Text('â€”', style: TextStyle(fontSize: 14)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          child: Text(
                            'â€”',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              if (needScroll) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 400),
                    child: table,
                  ),
                );
              }
              return table;
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AppTheme.primaryNavy.withOpacity(0.9),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Applications from the recruitment process will appear here when you connect the backend.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.4,
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

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

/// DTR module: hub with feature cards (like RSP). Choose a feature below.
class _DtrContent extends StatefulWidget {
  const _DtrContent();

  @override
  State<_DtrContent> createState() => _DtrContentState();
}

class _DtrContentState extends State<_DtrContent> {
  /// 0 = menu, 1 = Time Logs, 2 = Reports, 3 = Employees, 4 = Assignment,
  /// 5 = Department, 6 = Position, 7 = Shift, 8 = Leave Management
  int _dtrSectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_dtrSectionIndex != 0) ...[
          TextButton.icon(
            onPressed: () => setState(() => _dtrSectionIndex = 0),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text('Back to DTR'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
          ),
          const SizedBox(height: 16),
        ],
        if (_dtrSectionIndex == 0) ...[
          Text(
            'DTR',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Daily Time Record. Choose a feature below.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              FeatureCard(
                title: 'Time Logs',
                subtitle:
                    'Manage and correct daily time-in/out records. Add, edit, or delete entries.',
                icon: Icons.schedule_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 1),
              ),
              FeatureCard(
                title: 'Reports',
                subtitle: 'View attendance and tardiness reports.',
                icon: Icons.summarize_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 2),
              ),
              FeatureCard(
                title: 'Employees',
                subtitle: 'Manage employee profiles and accounts.',
                icon: Icons.people_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 3),
              ),
              FeatureCard(
                title: 'Assignment',
                subtitle:
                    'Assign employees to departments, positions, and shifts.',
                icon: Icons.assignment_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 4),
              ),
              FeatureCard(
                title: 'Department',
                subtitle: 'Manage departments.',
                icon: Icons.business_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 5),
              ),
              FeatureCard(
                title: 'Position',
                subtitle: 'Manage positions.',
                icon: Icons.work_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 6),
              ),
              FeatureCard(
                title: 'Shift',
                subtitle: 'Manage work shifts and schedules.',
                icon: Icons.access_time_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 7),
              ),
              FeatureCard(
                title: 'Leave Management',
                subtitle:
                    'Review employee leave requests, approvals, and leave-related records.',
                icon: Icons.event_note_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 8),
              ),
              FeatureCard(
                title: 'Holiday Management',
                subtitle:
                    'Define regular, special, and local holidays for DTR and payroll.',
                icon: Icons.calendar_today_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 9),
              ),
              FeatureCard(
                title: 'Attendance Policy',
                subtitle:
                    'Set grace period, late/absent/undertime rules, and default policy.',
                icon: Icons.policy_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 10),
              ),
              FeatureCard(
                title: 'Attendance Adjustment',
                subtitle:
                    'Review and approve or reject DTR correction requests.',
                icon: Icons.edit_calendar_rounded,
                onTap: () => setState(() => _dtrSectionIndex = 11),
              ),
            ],
          ),
        ] else if (_dtrSectionIndex == 1)
          DtrMain(section: DtrSection.timeLogs)
        else if (_dtrSectionIndex == 2)
          DtrMain(section: DtrSection.reports)
        else if (_dtrSectionIndex == 8)
          const LeaveMain(isAdmin: true)
        else
          _ManageContent(subIndex: _dtrSectionIndex - 3),
      ],
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
                      color: AppTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add a new employee or admin. Enter full profile details; they can sign in with email and password.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
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
          constraints: const BoxConstraints(maxWidth: 900),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
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
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
          ),
          const SizedBox(height: 16),
        ],
        if (_ldSectionIndex == 0) ...[
          Text(
            'L&D',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Learning & Development. Choose a feature below.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
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
      final doc = await FormPdf.buildTrainingNeedAnalysisPdf(entry);
      await FormPdf.printDocument(doc, name: 'Training_Need_Analysis.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Training Need Analysis and Consolidated Report',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'FOR CY [year], DEPARTMENT. Table: Name/Position, Goal, Behavior, Skills/Knowledge, Need for Training, Training Recommendations.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _TrainingNeedAnalysisFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printTna,
            onDownloadPdf: _downloadTna,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add report'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No Training Need Analysis reports yet. Tap "Add report" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TrainingDailyReportRepo.instance.listAllReports(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _reports = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markSeen(TrainingDailyReport report) async {
    try {
      final updated =
          await TrainingDailyReportRepo.instance.markAsSeen(report.id);
      if (!mounted) return;
      setState(() {
        final idx = _reports.indexWhere((r) => r.id == report.id);
        if (idx != -1) _reports[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked report as seen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark as seen: $e')),
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
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Training Daily Reports',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Monitor daily reports from employees under training, review attachments, and mark them as seen.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search',
                        hintText: 'Employee name or report title',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_reports.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.textSecondary.withOpacity(0.9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No training daily reports found.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: _reports
                      .map(
                        (r) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withOpacity(0.05),
                            ),
                            color: Colors.grey.shade50,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.employeeName ?? 'Unknown employee',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  _LdStatusChip(status: r.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                r.title,
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r.description ?? 'No description provided.',
                                maxLines: isWide ? 3 : 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Submitted ${r.submittedAt.toLocal()}',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (r.attachmentUrl != null)
                                    TextButton.icon(
                                      onPressed: () async {
                                        final url = r.attachmentUrl;
                                        if (url == null) return;

                                        await showDialog<void>(
                                          context: context,
                                          builder: (ctx) {
                                            return Dialog(
                                              insetPadding:
                                                  const EdgeInsets.all(24),
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                  maxWidth: 900,
                                                  maxHeight: 700,
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          const Text(
                                                            'Attachment preview',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          IconButton(
                                                            tooltip: 'Close',
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                        ctx)
                                                                    .pop(),
                                                            icon: const Icon(
                                                                Icons.close),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      Expanded(
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          child:
                                                              InteractiveViewer(
                                                            minScale: 0.5,
                                                            maxScale: 4,
                                                            child: Image
                                                                .network(
                                                              url,
                                                              fit: BoxFit
                                                                  .contain,
                                                              errorBuilder: (_,
                                                                  __, ___) {
                                                                return Center(
                                                                  child:
                                                                      Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      const Text(
                                                                        'Preview for this file type is not supported.',
                                                                        style: TextStyle(
                                                                            fontSize:
                                                                                13),
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              8),
                                                                      TextButton
                                                                          .icon(
                                                                        onPressed:
                                                                            () async {
                                                                          final uri =
                                                                              Uri.parse(url);
                                                                          await launchUrl(
                                                                            uri,
                                                                            mode:
                                                                                LaunchMode.externalApplication,
                                                                          );
                                                                        },
                                                                        icon: const Icon(
                                                                            Icons.open_in_new_rounded),
                                                                        label: const Text(
                                                                            'Open in new tab'),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('View file'),
                                    ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => _markSeen(r),
                                    child: const Text('Mark as seen'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LdStatusChip extends StatelessWidget {
  const _LdStatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toLowerCase()) {
      case 'seen':
        color = Colors.blueGrey;
        break;
      case 'reviewed':
        color = Colors.indigo;
        break;
      case 'approved':
        color = Colors.green;
        break;
      case 'needs_revision':
      case 'needs-revision':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TrainingNeedAnalysisFormEditor extends StatefulWidget {
  const _TrainingNeedAnalysisFormEditor({
    super.key,
    required this.entry,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final TrainingNeedAnalysisEntry entry;
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

  void _addRow() =>
      setState(() => _rows.add(_rowControllers('', '', '', '', '', '')));
  void _removeRow(int i) {
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

  void _save() => widget.onSave(_buildCurrentEntry());

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
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
            TextFormField(
              controller: _cyYear,
              decoration: rspUnderlinedField('FOR CY (e.g. 2025):'),
            ),
            TextFormField(
              controller: _department,
              decoration: rspUnderlinedField('DEPARTMENT:'),
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
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add row'),
                ),
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
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['goal'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['behavior'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['skills_knowledge'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['need_for_training'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            controller: r['training_recommendations'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        IconButton(
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('CY')),
          DataColumn(label: Text('Department')),
          DataColumn(label: Text('Rows')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(e.cyYear ?? 'â€”')),
              DataCell(Text(e.department ?? 'â€”')),
              DataCell(Text('${e.rows.length}')),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => onEdit(e),
                      child: const Text('Edit'),
                    ),
                    IconButton(
                      onPressed: () => onPrint(e),
                      icon: const Icon(Icons.print_rounded, size: 20),
                      tooltip: 'Print',
                    ),
                    IconButton(
                      onPressed: () => onDownloadPdf(e),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      tooltip: 'Download PDF',
                    ),
                    TextButton(
                      onPressed: () async {
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
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && e.id != null) onDelete(e.id!);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
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
      final doc = await FormPdf.buildActionBrainstormingCoachingPdf(entry);
      await FormPdf.printDocument(
        doc,
        name: 'Action_Brainstorming_Coaching.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Action Brainstorming and Coaching Worksheet',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Use the worksheet to brainstorm/coach staff on new ideas to move the department closer to department goal.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _ActionBrainstormingFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printAb,
            onDownloadPdf: _downloadAb,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add worksheet'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No worksheets yet. Tap "Add worksheet" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
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
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final ActionBrainstormingEntry entry;
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

  void _addRow() =>
      setState(() => _rows.add(_rowCtrl('', '', '', '', '', '', '')));
  void _removeRow(int i) {
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

  void _save() => widget.onSave(_buildCurrentEntry());

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(
              formTitle: 'ACTION BRAINSTORMING AND COACHING WORKSHEET',
            ),
            TextFormField(
              controller: _department,
              decoration: rspUnderlinedField('DEPARTMENT:'),
            ),
            TextFormField(
              controller: _date,
              decoration: rspUnderlinedField('DATE:'),
            ),
            const SizedBox(height: 12),
            Text(
              'Instruction: Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
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
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add row'),
                ),
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
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['stop_doing'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['do_less_of'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['keep_doing'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['do_more_of'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['start_doing'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['goal'],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        IconButton(
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
                      TextFormField(
                        controller: _certifiedBy,
                        decoration: rspUnderlinedField(''),
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
                      TextFormField(
                        controller: _certificationDate,
                        decoration: rspUnderlinedField(''),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Department')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Rows')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(e.department ?? 'â€”')),
              DataCell(Text(e.date ?? 'â€”')),
              DataCell(Text('${e.rows.length}')),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => onEdit(e),
                      child: const Text('Edit'),
                    ),
                    IconButton(
                      onPressed: () => onPrint(e),
                      icon: const Icon(Icons.print_rounded, size: 20),
                      tooltip: 'Print',
                    ),
                    IconButton(
                      onPressed: () => onDownloadPdf(e),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      tooltip: 'Download PDF',
                    ),
                    TextButton(
                      onPressed: () async {
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
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && e.id != null) onDelete(e.id!);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ManageContent extends StatelessWidget {
  const _ManageContent({required this.subIndex});

  final int subIndex;

  static const _titles = [
    'Employees',
    'Assignment',
    'Department',
    'Position',
    'Shift',
    'Holiday',
    'Attendance Policy',
    'Attendance Adjustment',
  ];

  @override
  Widget build(BuildContext context) {
    if (subIndex == 0) {
      return const ManageEmployee();
    }
    if (subIndex == 1) {
      return const ManageAssignment();
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
    if (subIndex == 8) {
      return const ManageAttendanceAdjustment();
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

class _PlaceholderContent extends StatelessWidget {
  const _PlaceholderContent({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 500;
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 24 : 48,
          vertical: isNarrow ? 32 : 48,
        ),
        margin: EdgeInsets.all(isNarrow ? 16 : 24),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(isNarrow ? 20 : 24),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_rounded,
                size: isNarrow ? 44 : 56,
                color: AppTheme.primaryNavy.withOpacity(0.7),
              ),
            ),
            SizedBox(height: isNarrow ? 20 : 24),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: isNarrow ? 18 : 22,
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
            const SizedBox(height: 12),
            Text(
              'This section will be available in a future update.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: isNarrow ? 13 : 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
