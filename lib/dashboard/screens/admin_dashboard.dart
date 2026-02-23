import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/job_vacancy_announcement.dart';
import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../login/models/login_role.dart';
import 'settings_page.dart';

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
  static const _navItems = ['Dashboard', 'RSP', 'L&D', 'DTR', 'Create Account'];

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
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFFF5F6F8), const Color(0xFFF0F2F5)],
                ),
              ),
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
                              : _selectedNavIndex == 4
                                  ? const _AdminSignUpContent()
                                  : _PlaceholderContent(title: _navItems[_selectedNavIndex]),
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
  const _Sidebar({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(2, 0)),
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
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: AppTheme.primaryNavy.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 4))],
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
          const SizedBox(height: 28),
          _NavTile(icon: Icons.dashboard_rounded, label: 'Dashboard', selected: selectedIndex == 0, onTap: () => onTap(0)),
          _NavTile(icon: Icons.how_to_reg_rounded, label: 'RSP', selected: selectedIndex == 1, onTap: () => onTap(1)),
          _NavTile(icon: Icons.school_rounded, label: 'L&D', selected: selectedIndex == 2, onTap: () => onTap(2)),
          _NavTile(icon: Icons.schedule_rounded, label: 'DTR', selected: selectedIndex == 3, onTap: () => onTap(3)),
          _NavTile(icon: Icons.person_add_rounded, label: 'Create Account', selected: selectedIndex == 4, onTap: () => onTap(4)),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Material(
          color: widget.selected ? AppTheme.primaryNavy.withOpacity(0.1) : (_hover ? AppTheme.primaryNavy.withOpacity(0.06) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: widget.selected ? Border(left: BorderSide(color: AppTheme.primaryNavy, width: 3)) : null,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 23, color: active ? AppTheme.primaryNavy : AppTheme.textSecondary),
                  const SizedBox(width: 16),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: active ? AppTheme.primaryNavy : AppTheme.textPrimary,
                      fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
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
      height: isCompact ? 60 : 72,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
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
              style: IconButton.styleFrom(backgroundColor: AppTheme.offWhite),
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
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 22, color: AppTheme.textSecondary.withOpacity(0.8)),
                        const SizedBox(width: 14),
                        Text('Search dashboard...', style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.9), fontSize: 14)),
                      ],
                    ),
                  ),
          ),
          if (isCompact) const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: isCompact ? 24 : 26),
                onPressed: () {},
                style: IconButton.styleFrom(backgroundColor: AppTheme.offWhite),
              ),
              Positioned(right: 6, top: 6, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFE53935), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)))),
            ],
          ),
          SizedBox(width: isCompact ? 6 : 12),
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
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: compact ? 17 : 20, backgroundColor: AppTheme.primaryNavy, child: Icon(Icons.person_rounded, color: Colors.white, size: compact ? 18 : 22)),
            if (!compact) ...[const SizedBox(width: 12), Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary))],
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: compact ? 20 : 24, color: AppTheme.textSecondary),
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
        PopupMenuItem(value: 'settings', padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Row(children: [Icon(Icons.settings_outlined, size: 22, color: AppTheme.textSecondary), const SizedBox(width: 14), Text('Settings', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary))])),
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
        if (value == 'settings') {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
        }
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  static String _formatDate(DateTime d) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
                AppTheme.primaryNavy.withOpacity(0.08),
                AppTheme.primaryNavy.withOpacity(0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.12), width: 1),
            boxShadow: [
              BoxShadow(color: AppTheme.primaryNavy.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatDate(now), style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNavy.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.waving_hand_rounded, color: AppTheme.primaryNavy, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Welcome back, Admin!', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                              const SizedBox(height: 4),
                              Text("Here's the latest overview of the HR activities.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
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
                        boxShadow: [BoxShadow(color: AppTheme.primaryNavy.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Icon(Icons.waving_hand_rounded, color: AppTheme.primaryNavy, size: 32),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatDate(now), style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text('Welcome back, Admin!', style: TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          const SizedBox(height: 6),
                          Text("Here's the latest overview of the HR activities.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 32),
        const _SummaryCards(),
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
      final pendingCount = applications.where((a) => a.status == 'submitted').length;
      final hiringActive = announcement.hasVacancies;
      if (mounted) {
        setState(() {
          _cards = [
            _SummaryData(title: 'New Applicants', value: '$totalApplicants', subtitle: totalApplicants == 0 ? 'No applications yet' : (totalApplicants == 1 ? '1 total application' : '$totalApplicants total applications'), color: _DashboardColors.cardBlue, iconColor: _DashboardColors.accentBlue, icon: Icons.person_add_rounded),
            _SummaryData(title: 'Pending Applications', value: '$pendingCount', subtitle: pendingCount == 0 ? 'None awaiting review' : (pendingCount == 1 ? '1 awaiting document review' : '$pendingCount awaiting document review'), color: _DashboardColors.cardGreen, iconColor: _DashboardColors.accentGreen, icon: Icons.pending_actions_rounded),
            _SummaryData(title: 'Job Vacancies', value: hiringActive ? 'Open' : 'Closed', subtitle: 'Landing page', color: _DashboardColors.cardAmber, iconColor: _DashboardColors.accentAmber, icon: Icons.work_rounded),
            _SummaryData(title: 'Hiring Status', value: hiringActive ? 'Active' : 'Inactive', subtitle: 'Landing page', color: Colors.white, iconColor: AppTheme.primaryNavy, icon: Icons.campaign_rounded),
          ];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cards = [
            _SummaryData(title: 'New Applicants', value: '—', subtitle: 'Unable to load', color: _DashboardColors.cardBlue, iconColor: _DashboardColors.accentBlue, icon: Icons.person_add_rounded),
            _SummaryData(title: 'Pending Applications', value: '—', subtitle: 'Unable to load', color: _DashboardColors.cardGreen, iconColor: _DashboardColors.accentGreen, icon: Icons.pending_actions_rounded),
            _SummaryData(title: 'Job Vacancies', value: '—', subtitle: '—', color: _DashboardColors.cardAmber, iconColor: _DashboardColors.accentAmber, icon: Icons.work_rounded),
            _SummaryData(title: 'Hiring Status', value: '—', subtitle: '—', color: Colors.white, iconColor: AppTheme.primaryNavy, icon: Icons.campaign_rounded),
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
    final cards = _cards ?? [
      _SummaryData(title: 'New Applicants', value: '…', subtitle: 'Loading', color: _DashboardColors.cardBlue, iconColor: _DashboardColors.accentBlue, icon: Icons.person_add_rounded),
      _SummaryData(title: 'Pending Applications', value: '…', subtitle: 'Loading', color: _DashboardColors.cardGreen, iconColor: _DashboardColors.accentGreen, icon: Icons.pending_actions_rounded),
      _SummaryData(title: 'Job Vacancies', value: '…', subtitle: '…', color: _DashboardColors.cardAmber, iconColor: _DashboardColors.accentAmber, icon: Icons.work_rounded),
      _SummaryData(title: 'Hiring Status', value: '…', subtitle: '…', color: Colors.white, iconColor: AppTheme.primaryNavy, icon: Icons.campaign_rounded),
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
          Row(children: [Expanded(child: _SummaryCard(data: cards[0])), const SizedBox(width: 16), Expanded(child: _SummaryCard(data: cards[1]))]),
          const SizedBox(height: 16),
          Row(children: [Expanded(child: _SummaryCard(data: cards[2])), const SizedBox(width: 16), Expanded(child: _SummaryCard(data: cards[3]))]),
        ],
      );
    }
    return content;
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: data.color,
        borderRadius: BorderRadius.circular(20),
        border: data.color == Colors.white ? Border.all(color: Colors.black.withOpacity(0.06)) : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
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
          Text(data.title, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(data.value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2)),
          if (data.subtitle.isNotEmpty) ...[const SizedBox(height: 6), Text(data.subtitle, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3))],
        ],
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
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
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
                    decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.campaign_rounded, color: AppTheme.primaryNavy, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Text('Announcements', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('View All'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: AppTheme.primaryNavy, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Vacancies (Hiring)',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Text(
                  'Control whether the landing page shows "We are currently accepting applications" or "There are no job vacancies at the moment." Manage this in Job Vacancies.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.55),
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
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
                    decoration: BoxDecoration(color: _DashboardColors.accentBlue.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.pie_chart_rounded, color: _DashboardColors.accentBlue, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Text('Recruitment Overview', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
              TextButton.icon(onPressed: () {}, icon: const Icon(Icons.insights_rounded, size: 18), label: const Text('View Report'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy)),
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
                  Icon(Icons.analytics_outlined, size: 56, color: AppTheme.textSecondary.withOpacity(0.35)),
                  const SizedBox(height: 16),
                  Text('No application data yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Data will appear when applicants complete the recruitment process.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
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
                    decoration: BoxDecoration(color: _DashboardColors.accentGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.assignment_rounded, color: _DashboardColors.accentGreen, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Text('Pending Applications', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
              TextButton.icon(onPressed: () {}, icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: const Text('View All'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8))),
            ],
          ),
          const SizedBox(height: 24),
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
                Icon(Icons.info_outline_rounded, size: 20, color: AppTheme.primaryNavy.withOpacity(0.9)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Applications from the recruitment process will appear here when you connect the backend.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
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

/// RSP module: hub with buttons for each RSP feature (Job Vacancies, Applications & Exam Results).
class _RspContent extends StatefulWidget {
  const _RspContent();

  @override
  State<_RspContent> createState() => _RspContentState();
}

class _RspContentState extends State<_RspContent> {
  /// 0 = menu, 1 = Job Vacancies, 2 = Applications & Exam Results, 3 = BEI, 4 = General Exam, 5 = Mathematics, 6 = General Information
  int _rspSectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_rspSectionIndex != 0) ...[
          TextButton.icon(
            onPressed: () => setState(() => _rspSectionIndex = 0),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text('Back to RSP'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
          ),
          const SizedBox(height: 16),
        ],
        if (_rspSectionIndex == 0) ...[
          Text('RSP', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Recruitment, Selection, and Placement. Choose a feature below.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _RspFeatureCard(
                title: 'Job Vacancies (Landing Page)',
                subtitle: 'Edit the announcement shown on the landing page.',
                icon: Icons.work_rounded,
                onTap: () => setState(() => _rspSectionIndex = 1),
              ),
              _RspFeatureCard(
                title: 'Applications & Exam Results',
                subtitle: 'View applicants, attachments, and exam results.',
                icon: Icons.assignment_rounded,
                onTap: () => setState(() => _rspSectionIndex = 2),
              ),
              _RspFeatureCard(
                title: 'BEI / Exam Questions',
                subtitle: 'View and edit the 8 Behavioral Event Interview questions applicants answer.',
                icon: Icons.quiz_rounded,
                onTap: () => setState(() => _rspSectionIndex = 3),
              ),
              _RspFeatureCard(
                title: 'General Exam (LGU-Plaridel)',
                subtitle: 'View and edit the General Exam multiple-choice questions for applicants.',
                icon: Icons.assignment_turned_in_rounded,
                onTap: () => setState(() => _rspSectionIndex = 4),
              ),
              _RspFeatureCard(
                title: 'Mathematics Exam',
                subtitle: 'View and edit the Mathematics exam questions for applicants.',
                icon: Icons.calculate_rounded,
                onTap: () => setState(() => _rspSectionIndex = 5),
              ),
              _RspFeatureCard(
                title: 'General Information Exam',
                subtitle: 'View and edit the General Information exam questions for applicants.',
                icon: Icons.info_outline_rounded,
                onTap: () => setState(() => _rspSectionIndex = 6),
              ),
            ],
          ),
        ] else if (_rspSectionIndex == 1)
          const _RspJobVacanciesForm()
        else if (_rspSectionIndex == 2)
          _RspApplicationsMonitor()
        else if (_rspSectionIndex == 3)
          const _RspBeiQuestionsEditor()
        else if (_rspSectionIndex == 4)
          const _RspGeneralExamEditor()
        else if (_rspSectionIndex == 5)
          const _RspMathExamEditor()
        else
          const _RspGeneralInfoExamEditor(),
      ],
    );
  }
}

/// Default 8 BEI questions when DB has none (so admin can edit and save).
const _defaultBeiQuestions = [
  'Tell me about a time when you had to collaborate with a co-worker that you had a hard time getting along with?',
  'Describe for me a time when you were under a significant amount of pressure at work. How did you deal with it?',
  'Tell me about a time when you were ask to work on a task that you had never done before.',
  'Tell me about a time when you had to cultivate a relationship with a new client. What did you do?',
  'Describe a time when you disagreed with your boss. What did you do?',
  'Describe your greatest challenge.',
  'What was your greatest accomplishment?',
  'Tell me about a time you failed.',
];

class _RspBeiQuestionsEditor extends StatefulWidget {
  const _RspBeiQuestionsEditor();

  @override
  State<_RspBeiQuestionsEditor> createState() => _RspBeiQuestionsEditorState();
}

class _RspBeiQuestionsEditorState extends State<_RspBeiQuestionsEditor> {
  List<TextEditingController> _controllers = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestions('bei');
      final questions = list.isNotEmpty ? list : _defaultBeiQuestions;
      if (mounted) {
        for (final c in _controllers) c.dispose();
        _controllers = questions.map((q) => TextEditingController(text: q)).toList();
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        for (final c in _controllers) c.dispose();
        _controllers = _defaultBeiQuestions.map((q) => TextEditingController(text: q)).toList();
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = _controllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one question.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestions('bei', questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BEI questions saved. Applicants will see these when taking the exam.')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('8 Behavioral Event Interview (BEI) Questions', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('For New Applicant/s and Promotion/s. Edit the questions below; applicants will see these when they take the exam.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
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
              ...List.generate(_controllers.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}.', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _controllers[i],
                              onChanged: (_) => setState(() {}),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Question text...',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                filled: true,
                                fillColor: AppTheme.offWhite,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _controllers.length > 1
                            ? () {
                                _controllers[i].dispose();
                                _controllers.removeAt(i);
                                setState(() {});
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove question',
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  _controllers.add(TextEditingController());
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_saving ? 'Saving...' : 'Save BEI questions'),
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

/// One general exam item for admin edit: question + options + correct index.
class _GeneralExamItem {
  _GeneralExamItem({required this.questionController, required this.optionControllers, required this.correctIndex});
  final TextEditingController questionController;
  final List<TextEditingController> optionControllers;
  int correctIndex;
}

class _RspGeneralExamEditor extends StatefulWidget {
  const _RspGeneralExamEditor();

  @override
  State<_RspGeneralExamEditor> createState() => _RspGeneralExamEditorState();
}

class _RspGeneralExamEditorState extends State<_RspGeneralExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) c.dispose();
    }
    _items = [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions('general');
      if (mounted) {
        _disposeItems();
        if (list.isEmpty) {
          _items.add(_makeItem('', <String>['', '', '', ''], 0));
        } else {
          for (final q in list) {
            final opts = (q['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
            while (opts.length < 2) opts.add('');
            _items.add(_makeItem(q['question_text'] as String? ?? '', opts, (q['correct'] as num?)?.toInt() ?? 0));
          }
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        _disposeItems();
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
        setState(() => _loading = false);
      }
    }
  }

  _GeneralExamItem _makeItem(String question, List<String> options, int correctIndex) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options.map((o) => TextEditingController(text: o)).toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one question with 2+ options.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions('general', questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('General Exam questions saved.')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('General Exam for LGU-Plaridel Applicants', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Multiple-choice questions. Edit below; set the correct option per question. Applicants will see these after the BEI.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
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
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final optCount = item.optionControllers.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
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
                                Text('${i + 1}. Question', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: item.questionController,
                                  onChanged: (_) => setState(() {}),
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    hintText: 'Question text...',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    filled: true,
                                    fillColor: AppTheme.offWhite,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text('Options (select correct one)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                const SizedBox(height: 6),
                                ...List.generate(optCount, (j) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Radio<int>(
                                          value: j,
                                          groupValue: item.correctIndex,
                                          onChanged: (v) => setState(() => item.correctIndex = v ?? 0),
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller: item.optionControllers[j],
                                            onChanged: (_) => setState(() {}),
                                            decoration: InputDecoration(
                                              hintText: 'Option ${String.fromCharCode(97 + j)}',
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              filled: true,
                                              fillColor: AppTheme.offWhite,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                if (optCount < 6)
                                  TextButton.icon(
                                    onPressed: () {
                                      item.optionControllers.add(TextEditingController());
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add option'),
                                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
                                  ),
                              ],
                            ),
                          ),
                          if (_items.length > 1)
                            IconButton(
                              onPressed: () {
                                final removed = _items.removeAt(i);
                                removed.questionController.dispose();
                                for (final c in removed.optionControllers) c.dispose();
                                setState(() {});
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Remove question',
                              color: Colors.red.shade700,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _items.add(_makeItem('', <String>['', '', '', ''], 0));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_saving ? 'Saving...' : 'Save General Exam questions'),
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

/// Mathematics exam editor (same structure as General, exam_type 'math').
class _RspMathExamEditor extends StatefulWidget {
  const _RspMathExamEditor();

  @override
  State<_RspMathExamEditor> createState() => _RspMathExamEditorState();
}

class _RspMathExamEditorState extends State<_RspMathExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) c.dispose();
    }
    _items = [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions('math');
      if (mounted) {
        _disposeItems();
        if (list.isEmpty) {
          _items.add(_makeItem('', <String>['', '', '', ''], 0));
        } else {
          for (final q in list) {
            final opts = (q['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
            while (opts.length < 2) opts.add('');
            _items.add(_makeItem(q['question_text'] as String? ?? '', opts, (q['correct'] as num?)?.toInt() ?? 0));
          }
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        _disposeItems();
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
        setState(() => _loading = false);
      }
    }
  }

  _GeneralExamItem _makeItem(String question, List<String> options, int correctIndex) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options.map((o) => TextEditingController(text: o)).toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one question with 2+ options.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions('math', questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mathematics Exam questions saved.')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mathematics Exam', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Multiple-choice mathematics questions. Edit below; set the correct option per question. Applicants will see these after the General Exam.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
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
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final optCount = item.optionControllers.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}. Question', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: item.questionController,
                              onChanged: (_) => setState(() {}),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Question text...',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                filled: true,
                                fillColor: AppTheme.offWhite,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Options (select correct one)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            const SizedBox(height: 6),
                            ...List.generate(optCount, (j) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Radio<int>(
                                      value: j,
                                      groupValue: item.correctIndex,
                                      onChanged: (v) => setState(() => item.correctIndex = v ?? 0),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: item.optionControllers[j],
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          hintText: 'Option ${String.fromCharCode(97 + j)}',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          filled: true,
                                          fillColor: AppTheme.offWhite,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (optCount < 6)
                              TextButton.icon(
                                onPressed: () {
                                  item.optionControllers.add(TextEditingController());
                                  setState(() {});
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add option'),
                                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
                              ),
                          ],
                        ),
                      ),
                      if (_items.length > 1)
                        IconButton(
                          onPressed: () {
                            final removed = _items.removeAt(i);
                            removed.questionController.dispose();
                            for (final c in removed.optionControllers) c.dispose();
                            setState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove question',
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _items.add(_makeItem('', <String>['', '', '', ''], 0));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_saving ? 'Saving...' : 'Save Mathematics Exam questions'),
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

/// General Information exam editor (exam_type 'general_info').
class _RspGeneralInfoExamEditor extends StatefulWidget {
  const _RspGeneralInfoExamEditor();

  @override
  State<_RspGeneralInfoExamEditor> createState() => _RspGeneralInfoExamEditorState();
}

class _RspGeneralInfoExamEditorState extends State<_RspGeneralInfoExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) c.dispose();
    }
    _items = [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions('general_info');
      if (mounted) {
        _disposeItems();
        if (list.isEmpty) {
          _items.add(_makeItem('', <String>['', '', '', ''], 0));
        } else {
          for (final q in list) {
            final opts = (q['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
            while (opts.length < 2) opts.add('');
            _items.add(_makeItem(q['question_text'] as String? ?? '', opts, (q['correct'] as num?)?.toInt() ?? 0));
          }
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        _disposeItems();
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
        setState(() => _loading = false);
      }
    }
  }

  _GeneralExamItem _makeItem(String question, List<String> options, int correctIndex) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options.map((o) => TextEditingController(text: o)).toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one question with 2+ options.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions('general_info', questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('General Information Exam questions saved.')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('General Information Exam', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Multiple-choice questions on general information (e.g. constitution, labor). Edit below; set the correct option per question.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
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
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final optCount = item.optionControllers.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}. Question', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: item.questionController,
                              onChanged: (_) => setState(() {}),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Question text...',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                filled: true,
                                fillColor: AppTheme.offWhite,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Options (select correct one)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            const SizedBox(height: 6),
                            ...List.generate(optCount, (j) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Radio<int>(
                                      value: j,
                                      groupValue: item.correctIndex,
                                      onChanged: (v) => setState(() => item.correctIndex = v ?? 0),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: item.optionControllers[j],
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          hintText: 'Option ${String.fromCharCode(97 + j)}',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          filled: true,
                                          fillColor: AppTheme.offWhite,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (optCount < 6)
                              TextButton.icon(
                                onPressed: () {
                                  item.optionControllers.add(TextEditingController());
                                  setState(() {});
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add option'),
                                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
                              ),
                          ],
                        ),
                      ),
                      if (_items.length > 1)
                        IconButton(
                          onPressed: () {
                            final removed = _items.removeAt(i);
                            removed.questionController.dispose();
                            for (final c in removed.optionControllers) c.dispose();
                            setState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove question',
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _items.add(_makeItem('', <String>['', '', '', ''], 0));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_saving ? 'Saving...' : 'Save General Information Exam questions'),
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

class _RspFeatureCard extends StatelessWidget {
  const _RspFeatureCard({required this.title, required this.subtitle, required this.icon, required this.onTap});

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: AppTheme.primaryNavy),
              ),
              const SizedBox(height: 16),
              Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One vacancy form entry (headline + body controllers).
class _VacancyFormItem {
  _VacancyFormItem() : headline = TextEditingController(), body = TextEditingController();
  final TextEditingController headline;
  final TextEditingController body;
  void dispose() {
    headline.dispose();
    body.dispose();
  }
}

/// RSP: Job Vacancies announcement form for the landing page. Supports multiple job vacancy entries.
class _RspJobVacanciesForm extends StatefulWidget {
  const _RspJobVacanciesForm();

  @override
  State<_RspJobVacanciesForm> createState() => _RspJobVacanciesFormState();
}

class _RspJobVacanciesFormState extends State<_RspJobVacanciesForm> {
  bool _loading = true;
  bool _hasVacancies = true;
  final List<_VacancyFormItem> _vacancies = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    JobVacancyAnnouncementRepo.instance.fetch().then((a) {
      if (!mounted) return;
      final List<_VacancyFormItem> next = [];
      if (a.vacancies.isNotEmpty) {
        for (final v in a.vacancies) {
          final item = _VacancyFormItem();
          item.headline.text = v.headline ?? '';
          item.body.text = v.body ?? '';
          next.add(item);
        }
      } else {
        final item = _VacancyFormItem();
        item.headline.text = a.headline ?? '';
        item.body.text = a.body ?? '';
        next.add(item);
      }
      if (mounted) {
        _vacancies
          ..clear()
          ..addAll(next);
        setState(() {
          _loading = false;
          _hasVacancies = a.hasVacancies;
        });
      }
    });
  }

  @override
  void dispose() {
    for (final v in _vacancies) v.dispose();
    super.dispose();
  }

  void _addVacancy() {
    setState(() => _vacancies.add(_VacancyFormItem()));
  }

  void _removeVacancy(int index) {
    if (_vacancies.length <= 1) return;
    setState(() {
      _vacancies[index].dispose();
      _vacancies.removeAt(index);
    });
  }

  void _confirmDeleteVacancy(BuildContext context, int index) {
    if (_vacancies.length <= 1) return;
    final headline = _vacancies[index].headline.text.trim();
    final title = headline.isEmpty ? 'Position ${index + 1}' : headline;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vacancy?'),
        content: Text(
          'Remove "$title" from the list? Use this when the job hiring is done. You can add it again later if needed. Changes are saved when you tap "Save and display on landing page".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true && mounted) _removeVacancy(index);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final list = _vacancies.map((v) => JobVacancyItem(
        headline: v.headline.text.trim().isEmpty ? null : v.headline.text.trim(),
        body: v.body.text.trim().isEmpty ? null : v.body.text.trim(),
      )).toList();
      final a = JobVacancyAnnouncement(
        hasVacancies: _hasVacancies,
        headline: list.isNotEmpty ? list.first.headline : null,
        body: list.isNotEmpty ? list.first.body : null,
        vacancies: list,
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
        Text('Control what appears in the Job Vacancies section on the landing page. Add multiple entries when you have more than one position.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
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
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Job vacancy entries', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                        FilledButton.icon(
                          onPressed: _addVacancy,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Add new vacancy'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(_vacancies.length, (i) {
                      final v = _vacancies[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.offWhite.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Position ${i + 1}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                                  if (_vacancies.length > 1)
                                    OutlinedButton.icon(
                                      onPressed: () => _confirmDeleteVacancy(context, i),
                                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade700),
                                      label: Text('Delete', style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        side: BorderSide(color: Colors.red.shade400),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text('Headline (optional)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: v.headline,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Now Hiring: Human Resource Assistant',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                                maxLines: 1,
                              ),
                              const SizedBox(height: 14),
                              Text('Description (optional)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: v.body,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Short description for this position.',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  alignLabelWithHint: true,
                                ),
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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

/// RSP: List of applications and exam results for admin monitoring.
class _RspApplicationsMonitor extends StatefulWidget {
  @override
  State<_RspApplicationsMonitor> createState() => _RspApplicationsMonitorState();
}

class _RspApplicationsMonitorState extends State<_RspApplicationsMonitor> {
  List<RecruitmentApplication> _applications = [];
  Map<String, RecruitmentExamResult> _examResults = {};
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      final results = await RecruitmentRepo.instance.getExamResultsByApplication();
      if (mounted) setState(() {
        _applications = apps;
        _examResults = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Sync attachment paths from storage into DB for applications that have no path yet (e.g. upload succeeded but DB update failed before RLS fix).
  /// Requires admin to be authenticated with Supabase Auth so storage list (SELECT) is allowed.
  Future<void> _syncAttachmentsFromStorage() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      // Guard: ensure admin has a valid Supabase Auth session (required for storage list on private bucket).
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        if (mounted) {
          setState(() => _syncing = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Admin not authenticated with Supabase Auth. Please log in again.'),
            backgroundColor: Color(0xFFC62828),
          ));
        }
        debugPrint('Sync attachments: no Supabase Auth session (currentUser/session is null).');
        return;
      }
      debugPrint('Sync attachments: listing storage bucket as authenticated user.');
      final entries = await RecruitmentRepo.instance.listStorageAttachmentPaths();
      debugPrint('Sync attachments: listed ${entries.length} file(s) in storage.');
      int linked = 0;
      for (final e in entries) {
        final ok = await RecruitmentRepo.instance.setApplicationAttachmentIfMissing(
          e['applicationId']!,
          e['path']!,
          e['fileName']!,
        );
        if (ok) linked++;
      }
      if (mounted) {
        await _load();
        setState(() => _syncing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(linked > 0
              ? 'Linked $linked attachment(s) from storage. You can now view and download them.'
              : entries.isEmpty
                  ? 'No files found in storage (bucket may be empty or path structure is applicationId/filename).'
                  : 'No applications were missing attachment paths; already linked or no matching application IDs.'),
        ));
      }
    } catch (e, st) {
      debugPrint('Sync attachments failed: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() => _syncing = false);
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message.contains(RecruitmentRepo.kErrorNotAuthenticated)
              ? 'Admin not authenticated with Supabase Auth. Please log in again.'
              : 'Sync failed: $message'),
          backgroundColor: const Color(0xFFC62828),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Applications & Exam Results', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load, tooltip: 'Refresh'),
            Tooltip(
              message: 'Link files already in storage to applications that show "No file" (e.g. after fixing RLS).',
              child: TextButton.icon(
                onPressed: (_loading || _syncing) ? null : _syncAttachmentsFromStorage,
                icon: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded, size: 20),
                label: Text(_syncing ? 'Syncing...' : 'Sync attachments from storage'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Monitor all documents (basic info) and screening exam results from applicants.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: _loading
              ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
              : _applications.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text('No applications yet. Applicants will appear here after they submit Step 1 from the recruitment flow.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14))),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppTheme.primaryNavy.withOpacity(0.08)),
                        columns: const [
                          DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Exam', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Score', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Attachment', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Document review', style: TextStyle(fontWeight: FontWeight.w700))),
                        ],
                        rows: _applications.map((app) {
                          final exam = _examResults[app.id];
                          return DataRow(
                            cells: [
                              DataCell(Text(app.fullName)),
                              DataCell(Text(app.email)),
                              DataCell(Text(app.phone ?? '—')),
                              DataCell(Text(app.status)),
                              DataCell(Text(exam == null ? '—' : (exam.passed ? 'Passed' : 'Failed'))),
                              DataCell(Text(exam == null ? '—' : '${exam.scorePercent.toStringAsFixed(0)}%')),
                              DataCell(
                                app.attachmentPath != null && app.attachmentName != null
                                    ? _DownloadAttachmentButton(path: app.attachmentPath!, fileName: app.attachmentName!)
                                    : Tooltip(
                                        message: 'No file attached or attachment not saved. See docs: anon must be allowed to update attachment path after upload.',
                                        child: Text('No file', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
                                      ),
                              ),
                              DataCell(_DocumentReviewCell(app: app, onUpdated: _load)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _DocumentReviewCell extends StatelessWidget {
  const _DocumentReviewCell({required this.app, required this.onUpdated});

  final RecruitmentApplication app;
  final VoidCallback onUpdated;

  Future<void> _approve(BuildContext context) async {
    try {
      await RecruitmentRepo.instance.updateApplicationStatus(app.id, 'document_approved');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document approved. Applicant can now take the exam.')));
        onUpdated();
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _decline(BuildContext context) async {
    try {
      await RecruitmentRepo.instance.updateApplicationStatus(app.id, 'document_declined');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document declined.')));
        onUpdated();
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (app.status == 'submitted') {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.icon(
            onPressed: () => _approve(context),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Approve'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF388E3C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _decline(context),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Decline'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ],
      );
    }
    if (app.status == 'document_approved') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 20, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Approved', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
        ],
      );
    }
    if (app.status == 'document_declined') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cancel, size: 20, color: Colors.red.shade700),
          const SizedBox(width: 6),
          Text('Declined', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
        ],
      );
    }
    return Text(app.status);
  }
}

class _DownloadAttachmentButton extends StatelessWidget {
  const _DownloadAttachmentButton({required this.path, required this.fileName});

  final String path;
  final String fileName;

  Future<void> _onTap(BuildContext context) async {
    final url = await RecruitmentRepo.instance.getAttachmentDownloadUrl(path);
    if (url != null && context.mounted) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get download link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _onTap(context),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(horizontal: 8)),
    );
  }
}

/// Sign-up form inside admin dashboard: create new user accounts.
class _AdminSignUpContent extends StatefulWidget {
  const _AdminSignUpContent();

  @override
  State<_AdminSignUpContent> createState() => _AdminSignUpContentState();
}

class _AdminSignUpContentState extends State<_AdminSignUpContent> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  LoginRole _role = LoginRole.employee;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _onCreateAccount() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.isEmpty) {
      _showSnackBar('Please enter full name');
      return;
    }
    if (email.isEmpty) {
      _showSnackBar('Please enter email');
      return;
    }
    if (password.isEmpty) {
      _showSnackBar('Please enter a password');
      return;
    }
    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      _showSnackBar('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
          'role': _role == LoginRole.admin ? 'admin' : 'employee',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. User can sign in after email confirmation (if required).')),
        );
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmController.clear();
      }
    } on AuthException catch (e) {
      if (mounted) _showSnackBar(e.message);
    } catch (e) {
      if (mounted) _showSnackBar('Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Create Account', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Register a new user (Admin or Employee). They can sign in after email confirmation if enabled.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: _inputDecoration('Full Name', Icons.person_outline_rounded),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Email', Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _inputDecoration('Password', Icons.lock_outline_rounded).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppTheme.textSecondary, size: 22),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: _inputDecoration('Confirm Password', Icons.lock_outline_rounded).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppTheme.textSecondary, size: 22),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Role', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _RoleChip(
                      label: 'Admin',
                      selected: _role == LoginRole.admin,
                      onTap: () => setState(() => _role = LoginRole.admin),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RoleChip(
                      label: 'Employee',
                      selected: _role == LoginRole.employee,
                      onTap: () => setState(() => _role = LoginRole.employee),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _onCreateAccount,
                  icon: _isLoading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_add_rounded, size: 22),
                  label: Text(_isLoading ? 'Creating...' : 'Create Account'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
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

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppTheme.primaryNavy, size: 22),
      filled: true,
      fillColor: AppTheme.offWhite,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withOpacity(0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryNavy : AppTheme.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppTheme.primaryNavy : Colors.black.withOpacity(0.12)),
          ),
          child: Center(child: Text(label, style: TextStyle(color: selected ? Colors.white : AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14))),
        ),
      ),
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
