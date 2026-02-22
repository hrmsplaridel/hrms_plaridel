import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/job_vacancy_announcement.dart';
import '../../landingpage/constants/app_theme.dart';

/// Dashboard accent colors for summary cards and accents.
class _DashboardColors {
  static const Color cardBlue = Color(0xFFE3F2FD);
  static const Color cardGreen = Color(0xFFE8F5E9);
  static const Color cardAmber = Color(0xFFFFF8E1);
  static const Color accentBlue = Color(0xFF1976D2);
  static const Color accentGreen = Color(0xFF388E3C);
  static const Color accentAmber = Color(0xFFF9A825);
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
  static const _navItems = ['Dashboard', 'RSP', 'L&D', 'DTR'];

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Admin';
    final displayName = user?.userMetadata?['full_name'] as String? ?? user?.email?.split('@').first ?? 'Admin';
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final contentPadding = width > 900 ? 24.0 : (width > 600 ? 20.0 : 16.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _Sidebar(
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
          if (isWide) _Sidebar(selectedIndex: _selectedNavIndex, onTap: (i) => setState(() => _selectedNavIndex = i)),
          Expanded(
            child: Column(
              children: [
                _TopBar(email: email, displayName: displayName, showMenuButton: !isWide),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(contentPadding),
                    child: _selectedNavIndex == 0
                        ? const _DashboardContent()
                        : _selectedNavIndex == 1
                            ? const _RspContent()
                            : _PlaceholderContent(title: _navItems[_selectedNavIndex]),
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(2, 0)),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: AppTheme.primaryNavy.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
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
          const SizedBox(height: 24),
          _NavTile(icon: Icons.dashboard_rounded, label: 'Dashboard', selected: selectedIndex == 0, onTap: () => onTap(0)),
          _NavTile(icon: Icons.how_to_reg_rounded, label: 'RSP', selected: selectedIndex == 1, onTap: () => onTap(1)),
          _NavTile(icon: Icons.school_rounded, label: 'L&D', selected: selectedIndex == 2, onTap: () => onTap(2)),
          _NavTile(icon: Icons.schedule_rounded, label: 'DTR', selected: selectedIndex == 3, onTap: () => onTap(3)),
          const Spacer(),
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
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryNavy,
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Admin', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('System Administrator', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
                Text('© 2026 HRMS', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                Text(' · ', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                TextButton(onPressed: () {}, style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 4)), child: Text('Privacy', style: TextStyle(fontSize: 11, color: AppTheme.primaryNavy))),
                Text(' · ', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                TextButton(onPressed: () {}, style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 4)), child: Text('Terms', style: TextStyle(fontSize: 11, color: AppTheme.primaryNavy))),
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
  const _NavTile({required this.icon, required this.label, required this.selected, required this.onTap});
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: widget.selected ? AppTheme.primaryNavy.withOpacity(0.1) : (_hover ? AppTheme.primaryNavy.withOpacity(0.05) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: widget.selected ? Border(left: BorderSide(color: AppTheme.primaryNavy, width: 3)) : null,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 22, color: active ? AppTheme.primaryNavy : AppTheme.textSecondary),
                  const SizedBox(width: 14),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: active ? AppTheme.primaryNavy : AppTheme.textPrimary,
                      fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.email, required this.displayName, this.showMenuButton = false});

  final String email;
  final String displayName;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Container(
      height: isCompact ? 56 : 68,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
              color: AppTheme.textPrimary,
              tooltip: 'Menu',
            ),
          if (showMenuButton && !isCompact) const SizedBox(width: 8),
          Expanded(
            child: isCompact
                ? const SizedBox.shrink()
                : Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 22, color: AppTheme.textSecondary),
                        const SizedBox(width: 12),
                        Text('Search...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
          ),
          if (isCompact) const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: isCompact ? 22 : 24),
                onPressed: () {},
              ),
              Positioned(right: 8, top: 8, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle))),
            ],
          ),
          SizedBox(width: isCompact ? 4 : 8),
          _AdminDropdown(email: email, displayName: displayName, compact: isCompact),
        ],
      ),
    );
  }
}

class _AdminDropdown extends StatelessWidget {
  const _AdminDropdown({required this.email, required this.displayName, this.compact = false});

  final String email;
  final String displayName;
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
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: compact ? 16 : 18, backgroundColor: AppTheme.primaryNavy, child: Icon(Icons.person_rounded, color: Colors.white, size: compact ? 18 : 20)),
            if (!compact) ...[const SizedBox(width: 10), Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary))],
            Icon(Icons.keyboard_arrow_down_rounded, size: compact ? 20 : 22, color: AppTheme.textSecondary),
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
                        const SizedBox(height: 2),
                        Text(email, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis, maxLines: 1),
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

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 500;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(isNarrow ? 16 : 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryNavy.withOpacity(0.06), AppTheme.primaryNavy.withOpacity(0.02)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.1)),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNavy.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.waving_hand_rounded, color: AppTheme.primaryNavy, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Welcome back, Admin!', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text("Here's the latest overview of the HR activities.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.waving_hand_rounded, color: AppTheme.primaryNavy, size: 28),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back, Admin!', style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text("Here's the latest overview of the HR activities.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 28),
        _SummaryCards(),
        const SizedBox(height: 24),
        _AnnouncementsCard(),
        const SizedBox(height: 24),
        _RecruitmentOverviewCard(),
        const SizedBox(height: 24),
        _PendingApplicationsCard(),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 700;
    final isSingleColumn = w < 480;

    final cards = [
      _SummaryData(title: 'New Applicants', value: '—', subtitle: '—', color: _DashboardColors.cardBlue, iconColor: _DashboardColors.accentBlue, icon: Icons.person_add_rounded),
      _SummaryData(title: 'Pending Applications', value: '—', subtitle: '—', color: _DashboardColors.cardGreen, iconColor: _DashboardColors.accentGreen, icon: Icons.pending_actions_rounded),
      _SummaryData(title: 'Job Vacancies', value: '—', subtitle: '—', color: _DashboardColors.cardAmber, iconColor: _DashboardColors.accentAmber, icon: Icons.work_rounded),
      _SummaryData(title: 'Hiring Status', value: 'Active', subtitle: 'Landing page', color: Colors.white, iconColor: AppTheme.primaryNavy, icon: Icons.campaign_rounded),
    ];

    if (isWide) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: _SummaryCard(data: cards[i])),
            if (i < cards.length - 1) const SizedBox(width: 16),
          ],
        ],
      );
    }
    if (isSingleColumn) {
      return Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            _SummaryCard(data: cards[i]),
            if (i < cards.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }
    return Column(
      children: [
        Row(children: [Expanded(child: _SummaryCard(data: cards[0])), const SizedBox(width: 16), Expanded(child: _SummaryCard(data: cards[1]))]),
        const SizedBox(height: 16),
        Row(children: [Expanded(child: _SummaryCard(data: cards[2])), const SizedBox(width: 16), Expanded(child: _SummaryCard(data: cards[3]))]),
      ],
    );
  }
}

class _SummaryData {
  const _SummaryData({required this.title, required this.value, required this.subtitle, required this.color, required this.iconColor, required this.icon});
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
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: data.color,
        borderRadius: BorderRadius.circular(16),
        border: data.color == Colors.white ? Border.all(color: Colors.black.withOpacity(0.08)) : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: data.iconColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: Icon(data.icon, size: 24, color: data.iconColor),
              ),
              Icon(Icons.more_horiz_rounded, size: 20, color: AppTheme.textSecondary.withOpacity(0.6)),
            ],
          ),
          const SizedBox(height: 16),
          Text(data.title, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(data.value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          if (data.subtitle.isNotEmpty) ...[const SizedBox(height: 4), Text(data.subtitle, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))],
        ],
      ),
    );
  }
}

class _AnnouncementsCard extends StatelessWidget {
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
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.campaign_rounded, color: AppTheme.primaryNavy, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Text('Announcements', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                ],
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('View All'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: AppTheme.primaryNavy, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Vacancies (Hiring)',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  'Control whether the landing page shows "We are currently accepting applications" or "There are no job vacancies at the moment." Manage this in Job Vacancies.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _DashboardColors.accentBlue.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.pie_chart_rounded, color: _DashboardColors.accentBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('Recruitment Overview', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                ],
              ),
              TextButton(onPressed: () {}, child: const Text('View Report', style: TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.offWhite.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06), style: BorderStyle.solid),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined, size: 56, color: AppTheme.textSecondary.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text('No application data yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text('Data will appear when applicants complete the recruitment process.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.insights_rounded, size: 20),
              label: const Text('View Report'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _DashboardColors.accentGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.assignment_rounded, color: _DashboardColors.accentGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('Pending Applications', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                ],
              ),
              TextButton.icon(onPressed: () {}, icon: const Icon(Icons.arrow_forward_rounded, size: 16), label: const Text('View All'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy)),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final needScroll = constraints.maxWidth < 500;
              final table = ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Table(
                  columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(1.2)},
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.08)),
                      children: [
                        _TableHeader('Applicant'),
                        _TableHeader('Type'),
                        _TableHeader('Date'),
                        _TableHeader('Status'),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16), child: Text('No applications yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14))),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8), child: Text('—', style: TextStyle(fontSize: 14))),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8), child: Text('—', style: TextStyle(fontSize: 14))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8), child: Text('—', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppTheme.offWhite, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primaryNavy.withOpacity(0.8)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Applications from the recruitment process will appear here when you connect the backend.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
    );
  }
}

/// RSP module: Job Vacancies announcement form for the landing page.
class _RspContent extends StatefulWidget {
  const _RspContent();

  @override
  State<_RspContent> createState() => _RspContentState();
}

class _RspContentState extends State<_RspContent> {
  bool _loading = true;
  bool _hasVacancies = true;
  final _headlineController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    JobVacancyAnnouncementRepo.instance.fetch().then((a) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasVacancies = a.hasVacancies;
        _headlineController.text = a.headline ?? '';
        _bodyController.text = a.body ?? '';
      });
    });
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final a = JobVacancyAnnouncement(
        hasVacancies: _hasVacancies,
        headline: _headlineController.text.trim().isEmpty ? null : _headlineController.text.trim(),
        body: _bodyController.text.trim().isEmpty ? null : _bodyController.text.trim(),
      );
      await JobVacancyAnnouncementRepo.instance.update(a);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job vacancy announcement saved. Landing page will show this.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Job Vacancies Announcement', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Control what appears in the Job Vacancies section on the landing page.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Accepting applications', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                            Switch(
                              value: _hasVacancies,
                              onChanged: (v) => setState(() => _hasVacancies = v),
                              activeTrackColor: AppTheme.primaryNavy.withOpacity(0.5),
                              activeThumbColor: AppTheme.primaryNavy,
                            ),
                          ],
                        ),
                        Text('When ON, the landing page shows that you are hiring. When OFF, it shows no vacancies.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        const SizedBox(height: 24),
                        Text('Headline (optional)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _headlineController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: _hasVacancies ? 'e.g. We are currently accepting applications.' : 'e.g. There are no job vacancies at the moment.',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: AppTheme.offWhite,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 20),
                        Text('Description (optional)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bodyController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Short message shown below the headline on the landing page.',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: AppTheme.offWhite,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 20),
                            label: Text(_saving ? 'Saving...' : 'Save and display on landing page'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryNavy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
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
        padding: EdgeInsets.symmetric(horizontal: isNarrow ? 24 : 48, vertical: isNarrow ? 32 : 48),
        margin: EdgeInsets.all(isNarrow ? 16 : 24),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
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
              child: Icon(Icons.construction_rounded, size: isNarrow ? 44 : 56, color: AppTheme.primaryNavy.withOpacity(0.7)),
            ),
            SizedBox(height: isNarrow ? 20 : 24),
            Text('$title', style: TextStyle(color: AppTheme.textPrimary, fontSize: isNarrow ? 18 : 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Coming soon', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('This section will be available in a future update.', style: TextStyle(color: AppTheme.textSecondary, fontSize: isNarrow ? 13 : 14), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
