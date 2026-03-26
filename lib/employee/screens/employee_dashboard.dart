import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../landingpage/constants/app_theme.dart';
import '../../../landingpage/screens/landing_page.dart';
import '../../../login/screens/login_page.dart';
import '../../../providers/auth_provider.dart';
import '../../../dtr/dtr_provider.dart';
import '../../../dtr/widgets/attendance_display.dart';
import '../../../dtr/widgets/attendance_source_badge.dart';
import '../../../docutracker/docutracker_main.dart';
import '../../../docutracker/screens/docutracker_dashboard_screen.dart';
import '../../../leave/leave_main.dart';
import '../../../leave/leave_provider.dart';
import '../../../leave/models/leave_type.dart';
import '../../../widgets/user_avatar.dart';
import '../../../ld/training_daily_report_employee_screen.dart';
import '../../shared/screens/profile_and_settings_page.dart';

/// Employee dashboard reference: dark blue sidebar (HR branding), nav items,
/// welcome + Clock In, Attendance, Leave Balance, Payslip cards, Announcements,
/// Upcoming Leave, Attendance Overview.
class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  int _selectedNavIndex = 0;
  static const _navItems = [
    'Dashboard',
    'My Attendance',
    'My Leave',
    'Training Reports',
    'DocuTracker',
    'Announcements',
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
    final displayName = auth.displayName.isNotEmpty
        ? auth.displayName
        : 'Employee';
    final email = auth.email;
    final avatarPath = auth.avatarPath;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final contentPadding = width > 900 ? 24.0 : (width > 600 ? 20.0 : 16.0);

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _EmployeeSidebar(
                  displayName: displayName,
                  avatarPath: avatarPath,
                  selectedIndex: _selectedNavIndex,
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
            _EmployeeSidebar(
              displayName: displayName,
              avatarPath: avatarPath,
              selectedIndex: _selectedNavIndex,
              onTap: (i) => setState(() => _selectedNavIndex = i),
            ),
          Expanded(
            child: Column(
              children: [
                _EmployeeTopBar(
                  displayName: displayName,
                  email: email,
                  avatarPath: avatarPath,
<<<<<<< HEAD
            onProfileTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileAndSettingsPage()),
              );
            },
=======
                  showMenuButton: !isWide,
                  onProfileTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProfileAndSettingsPage(),
                      ),
                    );
                  },
>>>>>>> feature/dtr-module
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(contentPadding),
                    child: _selectedNavIndex == 0
                        ? _EmployeeDashboardContent(
                            displayName: displayName,
                            onViewAttendance: () =>
                                setState(() => _selectedNavIndex = 1),
                          )
                        : _selectedNavIndex == 1
                        ? const _EmployeeAttendanceContent()
                        : _selectedNavIndex == 2
                            ? const LeaveMain(isAdmin: false)
                            : _selectedNavIndex == 3
                                ? const TrainingDailyReportEmployeeScreen()
                                : _selectedNavIndex == 4
                                    ? const DocuTrackerMain(isAdmin: false)
                                    : _EmployeePlaceholderContent(
                                        title: _navItems[_selectedNavIndex],
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

/// Dark blue sidebar: HR branding, nav (Dashboard, My Attendance, My Leave, DocuTracker, Announcements), user block, footer.
class _EmployeeSidebar extends StatelessWidget {
  const _EmployeeSidebar({
    required this.displayName,
    this.avatarPath,
    required this.selectedIndex,
    required this.onTap,
  });

  final String displayName;
  final String? avatarPath;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      decoration: const BoxDecoration(color: AppTheme.primaryNavy),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
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
          ),
          const SizedBox(height: 28),
          _EmployeeNavTile(
            icon: Icons.home_rounded,
            label: 'Dashboard',
            selected: selectedIndex == 0,
            onTap: () => onTap(0),
          ),
          _EmployeeNavTile(
            icon: Icons.event_available_rounded,
            label: 'My Attendance',
            selected: selectedIndex == 1,
            onTap: () => onTap(1),
          ),
          _EmployeeNavTile(
            icon: Icons.event_busy_rounded,
            label: 'My Leave',
            selected: selectedIndex == 2,
            onTap: () => onTap(2),
          ),
          _EmployeeNavTile(
            icon: Icons.assignment_rounded,
            label: 'Training Reports',
            selected: selectedIndex == 3,
            onTap: () => onTap(3),
          ),
          _EmployeeNavTile(
            icon: Icons.description_rounded,
            label: 'DocuTracker',
            selected: selectedIndex == 4,
            onTap: () => onTap(4),
          ),
          _EmployeeNavTile(
            icon: Icons.campaign_rounded,
            label: 'Announcements',
            selected: selectedIndex == 5,
            onTap: () => onTap(5),
          ),
          const Spacer(),
          const Divider(height: 1, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              children: [
                UserAvatar(
                  avatarPath: avatarPath,
                  radius: 24,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  placeholderIconColor: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Employee',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  '© 2026 HRMS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
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
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                    Text(
                      ' | ',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.6),
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
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
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

class _EmployeeNavTile extends StatelessWidget {
  const _EmployeeNavTile({
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
  Widget build(BuildContext context) {
    final bgColor = selected
        ? Colors.white.withOpacity(0.22)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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

/// Light gray top bar: search, notifications (badge), settings, user.
class _EmployeeTopBar extends StatelessWidget {
  const _EmployeeTopBar({
    required this.displayName,
    required this.email,
    this.avatarPath,
    this.showMenuButton = false,
    this.onProfileTap,
  });

  final String displayName;
  final String email;
  final String? avatarPath;
  final bool showMenuButton;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Container(
      height: isCompact ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        border: Border(
          bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
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
                backgroundColor: Colors.white,
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
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Search',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
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
                  size: isCompact ? 22 : 24,
                ),
                onPressed: () {},
              ),
              Positioned(
                right: 10,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          _EmployeeUserMenu(
            displayName: displayName,
            email: email,
            avatarPath: avatarPath,
            isCompact: isCompact,
            onProfileTap: onProfileTap,
          ),
        ],
      ),
    );
  }
}

class _EmployeeUserMenu extends StatelessWidget {
  const _EmployeeUserMenu({
    required this.displayName,
    required this.email,
    this.avatarPath,
    this.isCompact = false,
    this.onProfileTap,
  });

  final String displayName;
  final String email;
  final String? avatarPath;
  final bool isCompact;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(avatarPath: avatarPath, radius: isCompact ? 16 : 18),
            if (!isCompact) ...[
              const SizedBox(width: 10),
              Text(
                displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
            ],
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
                        if (email.isNotEmpty) ...[
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
          // Even though Settings content is empty for employees, they can still
          // view and update their profile details.
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileAndSettingsPage()),
          );
        }
      },
    );
  }
}

/// Main content: welcome, 4 cards (Clock In, Attendance, Leave Balance, My Payslip), Announcements, Upcoming Leave, Attendance Overview.
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
    });
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final dtr = context.read<DtrProvider>();
      if (dtr.loading) return;
      dtr.loadTodayRecord();
      final now = DateTime.now();
      dtr.loadTimeRecordsForUser(
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month + 1, 0),
      );
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back, ${widget.displayName}!',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: isNarrow ? 22 : 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Here's your latest information and updates.",
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: isNarrow ? 14 : 15,
          ),
        ),
        const SizedBox(height: 24),
        _EmployeeSummaryCards(
          isNarrow: isNarrow,
          onViewAttendance: widget.onViewAttendance,
        ),
        const SizedBox(height: 24),
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
            isAdmin: false,
            showTitle: false,
          ),
        ),
        const SizedBox(height: 24),
        _EmployeeAnnouncementsCard(),
        const SizedBox(height: 24),
        _EmployeeUpcomingLeaveCard(),
        const SizedBox(height: 24),
        _EmployeeAttendanceOverviewCard(),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _EmployeeSummaryCards extends StatelessWidget {
  const _EmployeeSummaryCards({required this.isNarrow, this.onViewAttendance});

  final bool isNarrow;
  final VoidCallback? onViewAttendance;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final singleColumn = w < 500;
    final twoRows = w < 800 && !singleColumn;

    Widget clockIn = _ClockInCard();
    Widget attendance = _AttendanceCard(onViewAttendance: onViewAttendance);
    Widget leaveBalance = _LeaveBalanceCard();
    Widget payslip = _PayslipCard();

    if (singleColumn) {
      return Column(
        children: [
          clockIn,
          const SizedBox(height: 16),
          attendance,
          const SizedBox(height: 16),
          leaveBalance,
          const SizedBox(height: 16),
          payslip,
        ],
      );
    }
    if (twoRows) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: clockIn),
              const SizedBox(width: 16),
              Expanded(child: attendance),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: leaveBalance),
              const SizedBox(width: 16),
              Expanded(child: payslip),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: clockIn),
        const SizedBox(width: 16),
        Expanded(child: attendance),
        const SizedBox(width: 16),
        Expanded(child: leaveBalance),
        const SizedBox(width: 16),
        Expanded(child: payslip),
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

        return Container(
          padding: const EdgeInsets.all(20),
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
                label,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isHoliday)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No clock in/out required',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
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
                  color: AppTheme.textPrimary,
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
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
                if (record.source != null && record.source!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  AttendanceSourceBadge(source: record.source, compact: true),
                ],
              ],
              const SizedBox(height: 6),
              Text(
                'Location: —',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
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
          padding: const EdgeInsets.all(20),
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
                'Attendance',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$presentCount',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Present Days',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                monthLabel,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: onViewAttendance,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
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
        return Container(
          padding: const EdgeInsets.all(20),
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
                'Leave Balance',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasData ? totalRemaining.toStringAsFixed(1) : '—',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Remaining Days',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Vacation ${vacationDays != null ? vacationDays.toStringAsFixed(1) : '—'}',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.medical_services_outlined,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Sick ${sickDays != null ? sickDays.toStringAsFixed(1) : '—'}',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PayslipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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

class _EmployeeAnnouncementsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.campaign_rounded,
                      color: AppTheme.primaryNavy,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Announcements',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
                child: const Text('View All >'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No announcements yet.',
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
    );
  }
}

class _EmployeeUpcomingLeaveCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.event_rounded,
                      color: AppTheme.primaryNavy,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Upcoming Leave',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
                child: const Text('View More >'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No upcoming leave.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.event_rounded,
                  color: AppTheme.textSecondary.withOpacity(0.5),
                  size: 40,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeAttendanceOverviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              Expanded(
                child: Text(
                  'Attendance Overview',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
                child: const Text('View More >'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.offWhite.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.show_chart_rounded,
                    size: 48,
                    color: AppTheme.textSecondary.withOpacity(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Attendance chart (April 14 – April 29)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ChartLegend(
                        color: const Color(0xFFE85D04),
                        label: 'Present',
                      ),
                      const SizedBox(width: 20),
                      _ChartLegend(
                        color: const Color(0xFF81C784),
                        label: 'Absent',
                      ),
                      const SizedBox(width: 20),
                      _ChartLegend(
                        color: const Color(0xFFFFB74D),
                        label: 'Late',
                      ),
                    ],
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

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
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
  const _EmployeeAttendanceContent();

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
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
      end = DateTime(_selectedYear, _selectedMonth + 1, 0);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppTheme.white,
                    ),
                    selectedItemBuilder: (context) => List.generate(
                      12,
                      (i) => Text(
                        _attendanceMonths[i],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
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
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppTheme.white,
                    ),
                    selectedItemBuilder: (context) => List.generate(
                      11,
                      (i) => Text(
                        '${DateTime.now().year - 5 + i}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
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
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppTheme.white,
                    ),
                    hint: Text(
                      'All days',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    selectedItemBuilder: (context) => [
                      const Text(
                        'All days',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14),
                      ),
                      ...List.generate(
                        _lastDayOfSelectedMonth,
                        (i) => Text(
                          'Day ${i + 1}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All days'),
                      ),
                      ...List.generate(
                        _lastDayOfSelectedMonth,
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
        if (dtr.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        if (!dtr.loading && dtr.timeRecords.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Center(
              child: Text(
                'No time records for the selected period.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
            ),
          ),
        if (!dtr.loading && dtr.timeRecords.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              const minTableWidth = 760.0;
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
                        ...dtr.timeRecords.asMap().entries.map((entry) {
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
                                      _formatTime(timeIn),
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
                                      _formatTime(breakOut),
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
                                      _formatTime(breakIn),
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
                                      _formatTime(timeOut),
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
