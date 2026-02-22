import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../landingpage/constants/app_theme.dart';

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
  static const _navItems = ['Dashboard', 'My Profile', 'My Attendance', 'My Leave', 'My Payroll', 'Announcements'];

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = user?.userMetadata?['full_name'] as String? ?? user?.email?.split('@').first ?? 'Employee';
    final email = user?.email ?? '';
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
              selectedIndex: _selectedNavIndex,
              onTap: (i) => setState(() => _selectedNavIndex = i),
            ),
          Expanded(
            child: Column(
              children: [
                _EmployeeTopBar(displayName: displayName, email: email),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(contentPadding),
                    child: _selectedNavIndex == 0
                        ? _EmployeeDashboardContent(displayName: displayName)
                        : _EmployeePlaceholderContent(title: _navItems[_selectedNavIndex]),
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

/// Dark blue sidebar: HR branding, nav (Dashboard, My Profile, My Attendance, My Leave, My Payroll, Announcements), user block, footer.
class _EmployeeSidebar extends StatelessWidget {
  const _EmployeeSidebar({
    required this.displayName,
    required this.selectedIndex,
    required this.onTap,
  });

  final String displayName;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: AppTheme.primaryNavy,
      ),
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
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
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
                          child: const Icon(Icons.shield_rounded, color: Colors.white, size: 28),
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
                        Text(
                          'Municipality of Plaridel',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'HUMAN RESOURCE MANAGEMENT SYSTEM',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _EmployeeNavTile(icon: Icons.home_rounded, label: 'Dashboard', selected: selectedIndex == 0, onTap: () => onTap(0)),
          _EmployeeNavTile(icon: Icons.person_rounded, label: 'My Profile', selected: selectedIndex == 1, onTap: () => onTap(1)),
          _EmployeeNavTile(icon: Icons.event_available_rounded, label: 'My Attendance', selected: selectedIndex == 2, onTap: () => onTap(2)),
          _EmployeeNavTile(icon: Icons.event_busy_rounded, label: 'My Leave', selected: selectedIndex == 3, onTap: () => onTap(3)),
          _EmployeeNavTile(icon: Icons.payments_rounded, label: 'My Payroll', selected: selectedIndex == 4, onTap: () => onTap(4)),
          _EmployeeNavTile(icon: Icons.campaign_rounded, label: 'Announcements', selected: selectedIndex == 5, onTap: () => onTap(5)),
          const Spacer(),
          const Divider(height: 1, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('Employee', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
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
                Text('© 2026 HRMS', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(onPressed: () {}, style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 4)), child: Text('Privacy Policy', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)))),
                    Text(' | ', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                    TextButton(onPressed: () {}, style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 4)), child: Text('Terms', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)))),
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
  const _EmployeeNavTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = selected ? const Color(0xFF3B82F6) : Colors.transparent; // light blue when active
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
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
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
  const _EmployeeTopBar({required this.displayName, required this.email});

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Container(
      height: isCompact ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.06))),
      ),
      child: Row(
        children: [
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
                        Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary),
                        const SizedBox(width: 10),
                        Text('Search', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
          ),
          if (isCompact) const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(icon: Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: isCompact ? 22 : 24), onPressed: () {}),
              Positioned(right: 10, top: 8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(10)),
                child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              )),
            ],
          ),
          const SizedBox(width: 8),
          _EmployeeUserMenu(displayName: displayName, email: email, isCompact: isCompact),
        ],
      ),
    );
  }
}

class _EmployeeUserMenu extends StatelessWidget {
  const _EmployeeUserMenu({required this.displayName, required this.email, this.isCompact = false});

  final String displayName;
  final String email;
  final bool isCompact;

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
            CircleAvatar(radius: isCompact ? 16 : 18, backgroundColor: AppTheme.primaryNavy, child: const Icon(Icons.person_rounded, color: Colors.white, size: 20)),
            if (!isCompact) ...[const SizedBox(width: 10), Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)), const SizedBox(width: 4), Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppTheme.textSecondary)],
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
                  CircleAvatar(radius: 28, backgroundColor: AppTheme.primaryNavy.withOpacity(0.12), child: Icon(Icons.person_rounded, color: AppTheme.primaryNavy, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(displayName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        if (email.isNotEmpty) ...[const SizedBox(height: 2), Text(email, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis, maxLines: 1)],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(value: 'profile', padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Row(children: [Icon(Icons.person_outline_rounded, size: 22, color: AppTheme.textSecondary), const SizedBox(width: 14), Text('My Profile', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary))])),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(value: 'signout', padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Row(children: [Icon(Icons.logout_rounded, size: 22, color: Color(0xFFC62828)), const SizedBox(width: 14), Text('Sign out', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFC62828)))])),
      ],
      onSelected: (value) {
        if (value == 'signout') {
          Supabase.instance.client.auth.signOut();
          if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        }
        if (value == 'profile') {
          // TODO: navigate when implemented
        }
      },
    );
  }
}

/// Main content: welcome, 4 cards (Clock In, Attendance, Leave Balance, My Payslip), Announcements, Upcoming Leave, Attendance Overview.
class _EmployeeDashboardContent extends StatelessWidget {
  const _EmployeeDashboardContent({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome back, $displayName!', style: TextStyle(color: AppTheme.textPrimary, fontSize: isNarrow ? 22 : 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text("Here's your latest information and updates.", style: TextStyle(color: AppTheme.textSecondary, fontSize: isNarrow ? 14 : 15)),
        const SizedBox(height: 24),
        _EmployeeSummaryCards(isNarrow: isNarrow),
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
  const _EmployeeSummaryCards({required this.isNarrow});

  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final singleColumn = w < 500;
    final twoRows = w < 800 && !singleColumn;

    Widget clockIn = _ClockInCard();
    Widget attendance = _AttendanceCard();
    Widget leaveBalance = _LeaveBalanceCard();
    Widget payslip = _PayslipCard();

    if (singleColumn) {
      return Column(
        children: [clockIn, const SizedBox(height: 16), attendance, const SizedBox(height: 16), leaveBalance, const SizedBox(height: 16), payslip],
      );
    }
    if (twoRows) {
      return Column(
        children: [
          Row(children: [Expanded(child: clockIn), const SizedBox(width: 16), Expanded(child: attendance)]),
          const SizedBox(height: 16),
          Row(children: [Expanded(child: leaveBalance), const SizedBox(width: 16), Expanded(child: payslip)]),
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

class _ClockInCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clock In', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text('08:45 AM', style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Location: Office 3rd Floor', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Clock In'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('21', style: TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('Present Days', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text('▲1 this week', style: TextStyle(color: const Color(0xFF388E3C), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy, padding: EdgeInsets.zero, minimumSize: Size.zero),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Status'), SizedBox(width: 4), Icon(Icons.arrow_forward_rounded, size: 16)]),
          ),
        ],
      ),
    );
  }
}

class _LeaveBalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Leave Balance', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text('5.5', style: TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Remaining Days', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.arrow_downward_rounded, size: 16, color: const Color(0xFF388E3C)),
            const SizedBox(width: 6),
            Text('Vacation 3.0', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.medical_services_outlined, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text('Sick 2.5', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          ]),
        ],
      ),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Payslip', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('April 2024', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
          const SizedBox(height: 8),
          Text('Php 42,500', style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Next Payday: April 30', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.campaign_rounded, color: AppTheme.primaryNavy, size: 22),
                  const SizedBox(width: 10),
                  Text('Announcements', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                ],
              ),
              TextButton(onPressed: () {}, child: const Text('View All >'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy)),
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
                Text('Employee training session on April 30 at 10:00 AM', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Text('Please attend the mandatory training session. Room 301.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.event_rounded, color: AppTheme.primaryNavy, size: 22),
                  const SizedBox(width: 10),
                  Text('Upcoming Leave', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                ],
              ),
              TextButton(onPressed: () {}, child: const Text('View More >'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vacation Leave', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Thursday, April 25, 2024', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 8),
                      Text('Please complete handover before leave.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.flight_takeoff_rounded, color: AppTheme.textSecondary.withOpacity(0.5), size: 40),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Attendance Overview', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
              TextButton(onPressed: () {}, child: const Text('View More >'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy)),
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
                  Icon(Icons.show_chart_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text('Attendance chart (April 14 – April 29)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ChartLegend(color: const Color(0xFF1976D2), label: 'Present'),
                      const SizedBox(width: 20),
                      _ChartLegend(color: const Color(0xFF81C784), label: 'Absent'),
                      const SizedBox(width: 20),
                      _ChartLegend(color: const Color(0xFFFFB74D), label: 'Late'),
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.construction_rounded, size: 56, color: AppTheme.primaryNavy.withOpacity(0.7)),
            ),
            const SizedBox(height: 24),
            Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Coming soon', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
