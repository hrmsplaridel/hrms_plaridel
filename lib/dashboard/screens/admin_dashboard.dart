import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/applicants_profile.dart';
import '../../data/bi_form.dart';
import '../../data/comparative_assessment.dart';
import '../../data/individual_development_plan.dart';
import '../../data/job_vacancy_announcement.dart';
import '../../data/performance_evaluation_form.dart';
import '../../data/promotion_certification.dart';
import '../../data/recruitment_application.dart';
import '../../data/selection_lineup.dart';
import '../../data/action_brainstorming_coaching.dart';
import '../../data/training_need_analysis.dart';
import '../../data/turn_around_time.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../utils/form_pdf.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../../login/models/login_role.dart';
import 'settings_page.dart';

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
                              : _selectedNavIndex == 2
                                  ? const _LdContent()
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
  /// 0 = menu, 1 = Job Vacancies, 2 = Applications, 3 = BEI, 4 = General Exam, 5 = Math, 6 = General Info, 7 = BI Form, 8 = Performance Eval, 9 = IDP, 10 = Applicants Profile, 11 = Comparative Assessment, 12 = Promotion Certification, 13 = Selection Line-up, 14 = Turn-Around Time
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
              _RspFeatureCard(
                title: 'Background Investigation (BI) Form',
                subtitle: 'Record BI form entries: applicant, respondent, and competency ratings.',
                icon: Icons.verified_user_rounded,
                onTap: () => setState(() => _rspSectionIndex = 7),
              ),
              _RspFeatureCard(
                title: 'Performance / Functional Evaluation',
                subtitle: 'Record functional areas and performance narratives for applicants.',
                icon: Icons.assessment_rounded,
                onTap: () => setState(() => _rspSectionIndex = 8),
              ),
              _RspFeatureCard(
                title: 'Individual Development Plan (IDP)',
                subtitle: 'Record employee IDP: qualifications, succession analysis, development plan.',
                icon: Icons.trending_up_rounded,
                onTap: () => setState(() => _rspSectionIndex = 9),
              ),
              _RspFeatureCard(
                title: 'Applicants Profile',
                subtitle: 'Job vacancy details and list of applicants (name, course, address, sex, age, civil status, remark).',
                icon: Icons.people_alt_rounded,
                onTap: () => setState(() => _rspSectionIndex = 10),
              ),
              _RspFeatureCard(
                title: 'Comparative Assessment (Promotion)',
                subtitle: 'Merit Promotion Board: position, minimum requirements, and candidate comparison table. Form only, no pre-filled names.',
                icon: Icons.balance_rounded,
                onTap: () => setState(() => _rspSectionIndex = 11),
              ),
              _RspFeatureCard(
                title: 'Promotion Certification / Screening',
                subtitle: 'Certification that candidates have been screened and found qualified. Form only, no pre-filled names.',
                icon: Icons.verified_rounded,
                onTap: () => setState(() => _rspSectionIndex = 12),
              ),
              _RspFeatureCard(
                title: 'Selection Line-up',
                subtitle: 'Date, agency/office, vacant position, item no., and applicants table (name, education, experience, training, eligibility). Form only.',
                icon: Icons.format_list_numbered_rounded,
                onTap: () => setState(() => _rspSectionIndex = 13),
              ),
              _RspFeatureCard(
                title: 'Turn-Around Time',
                subtitle: 'Merit Promotion Board: position, office, dates, and applicant tracking table (assessment, exam, deliberation, job offer, assumption, cost). Form only.',
                icon: Icons.schedule_rounded,
                onTap: () => setState(() => _rspSectionIndex = 14),
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
        else if (_rspSectionIndex == 6)
          const _RspGeneralInfoExamEditor()
        else if (_rspSectionIndex == 7)
          const _RspBiFormSection()
        else if (_rspSectionIndex == 8)
          const _RspPerformanceEvaluationSection()
        else if (_rspSectionIndex == 9)
          const _RspIdpSection()
        else if (_rspSectionIndex == 10)
          const _RspApplicantsProfileSection()
        else if (_rspSectionIndex == 11)
          const _RspComparativeAssessmentSection()
        else if (_rspSectionIndex == 12)
          const _RspPromotionCertificationSection()
        else if (_rspSectionIndex == 13)
          const _RspSelectionLineupSection()
        else
          const _RspTurnAroundTimeSection(),
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

/// RSP: Background Investigation (BI) Form — list entries and add/edit form.
class _RspBiFormSection extends StatefulWidget {
  const _RspBiFormSection();

  @override
  State<_RspBiFormSection> createState() => _RspBiFormSectionState();
}

class _RspBiFormSectionState extends State<_RspBiFormSection> {
  List<BiFormEntry> _entries = [];
  bool _loading = true;
  BiFormEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await BiFormRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() {
    setState(() => _editing = BiFormEntry(
      applicantName: '',
      respondentName: '',
      respondentRelationship: 'supervisor',
    ));
  }

  void _edit(BiFormEntry e) {
    setState(() => _editing = e);
  }

  void _cancelEdit() {
    setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Background Investigation (BI) Form', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Record BI evaluations: applicant and respondent details, plus competency ratings (1–5).', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _BiFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSaveBi,
            onCancel: _cancelEdit,
            onPrint: _printBi,
            onDownloadPdf: _downloadBi,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add BI entry'),
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
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No BI entries yet. Tap "Add BI entry" to add one.', style: TextStyle(color: AppTheme.textSecondary)),
          )
        else
          _BiFormList(entries: _entries, onEdit: _edit, onDelete: _onDeleteBi, onPrint: _printBi, onDownloadPdf: _downloadBi),
      ],
    );
  }

  Future<void> _onSaveBi(BiFormEntry entry) async {
    try {
      if (entry.id == null) {
        await BiFormRepo.instance.insert(entry);
      } else {
        await BiFormRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BI entry saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDeleteBi(String id) async {
    try {
      await BiFormRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BI entry deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printBi(BiFormEntry entry) async {
    try {
      final doc = FormPdf.buildBiFormPdf(entry);
      await FormPdf.printDocument(doc, name: 'BI_Form.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadBi(BiFormEntry entry) async {
    try {
      final doc = FormPdf.buildBiFormPdf(entry);
      await FormPdf.sharePdf(doc, name: 'BI_Form.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }
}

class _BiFormEditor extends StatefulWidget {
  const _BiFormEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final BiFormEntry entry;
  final void Function(BiFormEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(BiFormEntry) onPrint;
  final Future<void> Function(BiFormEntry) onDownloadPdf;

  @override
  State<_BiFormEditor> createState() => _BiFormEditorState();
}

class _BiFormEditorState extends State<_BiFormEditor> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _applicantName;
  late TextEditingController _applicantDept;
  late TextEditingController _applicantPosition;
  late TextEditingController _positionApplied;
  late TextEditingController _respondentName;
  late TextEditingController _respondentPosition;
  late String _relationship;
  late List<int?> _ratings;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _applicantName = TextEditingController(text: e.applicantName);
    _applicantDept = TextEditingController(text: e.applicantDepartment ?? '');
    _applicantPosition = TextEditingController(text: e.applicantPosition ?? '');
    _positionApplied = TextEditingController(text: e.positionAppliedFor ?? '');
    _respondentName = TextEditingController(text: e.respondentName);
    _respondentPosition = TextEditingController(text: e.respondentPosition ?? '');
    _relationship = e.respondentRelationship;
    _ratings = [e.rating1, e.rating2, e.rating3, e.rating4, e.rating5, e.rating6, e.rating7, e.rating8, e.rating9];
  }

  @override
  void dispose() {
    _applicantName.dispose();
    _applicantDept.dispose();
    _applicantPosition.dispose();
    _positionApplied.dispose();
    _respondentName.dispose();
    _respondentPosition.dispose();
    super.dispose();
  }

  BiFormEntry _buildCurrentEntry() {
    return BiFormEntry(
      id: widget.entry.id,
      applicantName: _applicantName.text.trim(),
      applicantDepartment: _applicantDept.text.trim().isEmpty ? null : _applicantDept.text.trim(),
      applicantPosition: _applicantPosition.text.trim().isEmpty ? null : _applicantPosition.text.trim(),
      positionAppliedFor: _positionApplied.text.trim().isEmpty ? null : _positionApplied.text.trim(),
      respondentName: _respondentName.text.trim(),
      respondentPosition: _respondentPosition.text.trim().isEmpty ? null : _respondentPosition.text.trim(),
      respondentRelationship: _relationship,
      rating1: _ratings[0],
      rating2: _ratings[1],
      rating3: _ratings[2],
      rating4: _ratings[3],
      rating5: _ratings[4],
      rating6: _ratings[5],
      rating7: _ratings[6],
      rating8: _ratings[7],
      rating9: _ratings[8],
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RspFormHeader(formTitle: 'BACKGROUND INVESTIGATION (BI FORM)'),
              // Two-column: Applicant under BI | Respondents
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('APPLICANT UNDER BI:', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextFormField(controller: _applicantName, decoration: rspUnderlinedField('Name:'), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
                        TextFormField(controller: _applicantDept, decoration: rspUnderlinedField('Department:')),
                        TextFormField(controller: _applicantPosition, decoration: rspUnderlinedField('Position:')),
                        TextFormField(controller: _positionApplied, decoration: rspUnderlinedField('Position Applied for in LGU-Plaridel:')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RESPONDENTS:', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextFormField(controller: _respondentName, decoration: rspUnderlinedField('Name:'), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
                        TextFormField(controller: _respondentPosition, decoration: rspUnderlinedField('Position:')),
                        const SizedBox(height: 12),
                        Text('Work relationship to the applicants: (Kindly check the appropriate box)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        const SizedBox(height: 6),
                        ...BiFormEntry.relationshipOptions.map((r) => RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(r == 'supervisor' ? 'Applicants Supervisor' : r == 'peer' ? 'Applicants Peer/ Co-Employee' : 'Applicants Subordinates', style: const TextStyle(fontSize: 13)),
                              value: r,
                              groupValue: _relationship,
                              onChanged: (v) => setState(() => _relationship = v!),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // I. ON COMPETENCIES
              Text('I. ON COMPETENCIES', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
              Text('Core and Organizational Competencies:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('Using the following rating guide please check (/) the appropriate box opposite each behavioral Indicator:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: AppTheme.lightGray)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rating Guide:', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('5- Shows Strength', style: TextStyle(fontSize: 11)),
                        Text('4- Very Proficient', style: TextStyle(fontSize: 11)),
                        Text('3- Proficient', style: TextStyle(fontSize: 11)),
                        Text('2- Minimal Development', style: TextStyle(fontSize: 11)),
                        Text('1- Much Development Needed', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Competency table: AREA | CORE DESCRIPTION | 5 | 4 | 3 | 2 | 1
              Table(
                border: TableBorder.all(color: Colors.black87),
                columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(4), 2: FlexColumnWidth(0.4), 3: FlexColumnWidth(0.4), 4: FlexColumnWidth(0.4), 5: FlexColumnWidth(0.4), 6: FlexColumnWidth(0.4)},
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.08)),
                    children: [
                      _tableCell('AREA', bold: true),
                      _tableCell('CORE DISCRIPTION', bold: true),
                      _tableCell('5', bold: true),
                      _tableCell('4', bold: true),
                      _tableCell('3', bold: true),
                      _tableCell('2', bold: true),
                      _tableCell('1', bold: true),
                    ],
                  ),
                  ...List.generate(9, (i) => TableRow(
                    children: [
                      _tableCell('${i + 1}'),
                      _tableCell(BiFormEntry.competencyDescriptions[i], small: true),
                      _ratingCell(i, 5),
                      _ratingCell(i, 4),
                      _ratingCell(i, 3),
                      _ratingCell(i, 2),
                      _ratingCell(i, 1),
                    ],
                  )),
                ],
              ),
              const SizedBox(height: 24),
              const RspFormFooter(),
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 12),
                  TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                  IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCell(String text, {bool bold = false, bool small = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(text, style: TextStyle(fontSize: small ? 9 : 11, fontWeight: bold ? FontWeight.bold : null)),
    );
  }

  Widget _ratingCell(int rowIndex, int rating) {
    final selected = _ratings[rowIndex] == rating;
    return InkWell(
      onTap: () => setState(() => _ratings[rowIndex] = rating),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(selected ? '/' : '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _BiFormList extends StatelessWidget {
  const _BiFormList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<BiFormEntry> entries;
  final void Function(BiFormEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(BiFormEntry) onPrint;
  final Future<void> Function(BiFormEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Applicant')),
          DataColumn(label: Text('Respondent')),
          DataColumn(label: Text('Relationship')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(e.applicantName)),
              DataCell(Text(e.respondentName)),
              DataCell(Text(e.respondentRelationship)),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                  IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                  IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete BI entry?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true && e.id != null) onDelete(e.id!);
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// RSP: Performance / Functional Evaluation — list entries and add/edit form.
class _RspPerformanceEvaluationSection extends StatefulWidget {
  const _RspPerformanceEvaluationSection();

  @override
  State<_RspPerformanceEvaluationSection> createState() => _RspPerformanceEvaluationSectionState();
}

class _RspPerformanceEvaluationSectionState extends State<_RspPerformanceEvaluationSection> {
  List<PerformanceEvaluationEntry> _entries = [];
  bool _loading = true;
  PerformanceEvaluationEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await PerformanceEvaluationRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() {
    setState(() => _editing = const PerformanceEvaluationEntry());
  }

  void _edit(PerformanceEvaluationEntry e) {
    setState(() => _editing = e);
  }

  void _cancelEdit() {
    setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Performance / Functional Evaluation', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Record functional areas and performance narratives for applicants.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _PerformanceFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSavePerf,
            onCancel: _cancelEdit,
            onPrint: _printPerf,
            onDownloadPdf: _downloadPerf,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add evaluation'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No evaluations yet. Tap "Add evaluation" to add one.', style: TextStyle(color: AppTheme.textSecondary)),
          )
        else
          _PerformanceFormList(entries: _entries, onEdit: _edit, onDelete: _onDeletePerf, onPrint: _printPerf, onDownloadPdf: _downloadPerf),
      ],
    );
  }

  Future<void> _onSavePerf(PerformanceEvaluationEntry entry) async {
    try {
      if (entry.id == null) {
        await PerformanceEvaluationRepo.instance.insert(entry);
      } else {
        await PerformanceEvaluationRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evaluation saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDeletePerf(String id) async {
    try {
      await PerformanceEvaluationRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evaluation deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printPerf(PerformanceEvaluationEntry entry) async {
    try {
      final doc = FormPdf.buildPerformanceEvaluationPdf(entry);
      await FormPdf.printDocument(doc, name: 'Performance_Evaluation.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadPerf(PerformanceEvaluationEntry entry) async {
    try {
      final doc = FormPdf.buildPerformanceEvaluationPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Performance_Evaluation.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }
}

class _PerformanceFormEditor extends StatefulWidget {
  const _PerformanceFormEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final PerformanceEvaluationEntry entry;
  final void Function(PerformanceEvaluationEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(PerformanceEvaluationEntry) onPrint;
  final Future<void> Function(PerformanceEvaluationEntry) onDownloadPdf;

  @override
  State<_PerformanceFormEditor> createState() => _PerformanceFormEditorState();
}

class _PerformanceFormEditorState extends State<_PerformanceFormEditor> {
  late TextEditingController _applicantName;
  late TextEditingController _otherArea;
  late TextEditingController _perf3Years;
  late TextEditingController _challenges;
  late TextEditingController _compliance;
  late List<bool> _functionalChecks;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _applicantName = TextEditingController(text: e.applicantName ?? '');
    _otherArea = TextEditingController(text: e.otherFunctionalArea ?? '');
    _perf3Years = TextEditingController(text: e.performance3Years ?? '');
    _challenges = TextEditingController(text: e.challengesCoping ?? '');
    _compliance = TextEditingController(text: e.complianceAttendance ?? '');
    _functionalChecks = List.generate(PerformanceEvaluationEntry.functionalAreaOptions.length, (i) => e.functionalAreas.contains(PerformanceEvaluationEntry.functionalAreaOptions[i]));
  }

  @override
  void dispose() {
    _applicantName.dispose();
    _otherArea.dispose();
    _perf3Years.dispose();
    _challenges.dispose();
    _compliance.dispose();
    super.dispose();
  }

  PerformanceEvaluationEntry _buildCurrentEntry() {
    final areas = <String>[];
    for (var i = 0; i < _functionalChecks.length; i++) {
      if (_functionalChecks[i]) areas.add(PerformanceEvaluationEntry.functionalAreaOptions[i]);
    }
    return PerformanceEvaluationEntry(
      id: widget.entry.id,
      applicantName: _applicantName.text.trim().isEmpty ? null : _applicantName.text.trim(),
      functionalAreas: areas,
      otherFunctionalArea: _otherArea.text.trim().isEmpty ? null : _otherArea.text.trim(),
      performance3Years: _perf3Years.text.trim().isEmpty ? null : _perf3Years.text.trim(),
      challengesCoping: _challenges.text.trim().isEmpty ? null : _challenges.text.trim(),
      complianceAttendance: _compliance.text.trim().isEmpty ? null : _compliance.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    const options = PerformanceEvaluationEntry.functionalAreaOptions;
    const leftCount = 6; // Left column: first 6; right column: rest + Other
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
            const RspFormHeader(formTitle: 'Performance / Functional Evaluation'),
            Text('A. Functional Areas:', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Please check (/) the boxes opposite the functional area where the applicant can perform effectively.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < leftCount && i < options.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(options[i], style: const TextStyle(fontSize: 13)),
                          value: _functionalChecks[i],
                          onChanged: (v) => setState(() => _functionalChecks[i] = v ?? false),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = leftCount; i < options.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(options[i], style: const TextStyle(fontSize: 13)),
                          value: _functionalChecks[i],
                          onChanged: (v) => setState(() => _functionalChecks[i] = v ?? false),
                        ),
                      const SizedBox(height: 8),
                      Text('Other (Please specify)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      TextFormField(controller: _otherArea, decoration: rspUnderlinedField(''), maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('I. On performance and other relevant information.', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('Please tell us about the work performance of the applicants in the last three (3) years. What are the applicant\'s outstanding accomplishments recognition received and significant contributions to your office if any?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            TextFormField(controller: _perf3Years, decoration: rspUnderlinedField(''), maxLines: 4),
            const SizedBox(height: 16),
            Text('What do you think are the challenges or difficulties of the applicant in performing his/her duties and responsibilities in his/her position? How did the applicant cope with these challenges?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            TextFormField(controller: _challenges, decoration: rspUnderlinedField(''), maxLines: 4),
            const SizedBox(height: 16),
            Text('In terms of compliance with rules and regulation, please provide us information on the applicant\'s attendance to flag ceremonies/ retreats and other office programs and activities?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            TextFormField(controller: _compliance, decoration: rspUnderlinedField(''), maxLines: 4),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceFormList extends StatelessWidget {
  const _PerformanceFormList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<PerformanceEvaluationEntry> entries;
  final void Function(PerformanceEvaluationEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(PerformanceEvaluationEntry) onPrint;
  final Future<void> Function(PerformanceEvaluationEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Applicant')),
          DataColumn(label: Text('Functional areas')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(e.applicantName ?? '—')),
              DataCell(Text(e.functionalAreas.isEmpty ? '—' : e.functionalAreas.join(', '))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                  IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                  IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete evaluation?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true && e.id != null) onDelete(e.id!);
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// RSP: Individual Development Plan (IDP) — list entries and add/edit form.
class _RspIdpSection extends StatefulWidget {
  const _RspIdpSection();

  @override
  State<_RspIdpSection> createState() => _RspIdpSectionState();
}

class _RspIdpSectionState extends State<_RspIdpSection> {
  List<IdpEntry> _entries = [];
  bool _loading = true;
  IdpEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await IdpRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const IdpEntry());
  void _edit(IdpEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(IdpEntry entry) async {
    try {
      if (entry.id == null) {
        await IdpRepo.instance.insert(entry);
      } else {
        await IdpRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IDP saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await IdpRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IDP deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printIdp(IdpEntry entry) async {
    try {
      final doc = FormPdf.buildIdpPdf(entry);
      await FormPdf.printDocument(doc, name: 'IDP.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadIdp(IdpEntry entry) async {
    try {
      final doc = FormPdf.buildIdpPdf(entry);
      await FormPdf.sharePdf(doc, name: 'IDP.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Individual Development Plan (IDP)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Record employee IDP: personal/position info, qualifications, succession analysis, and development plan rows.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _IdpFormEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printIdp, onDownloadPdf: _downloadIdp),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add IDP')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No IDP entries yet. Tap "Add IDP" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else
          _IdpList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printIdp, onDownloadPdf: _downloadIdp),
      ],
    );
  }
}

class _IdpFormEditor extends StatefulWidget {
  const _IdpFormEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final IdpEntry entry;
  final void Function(IdpEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(IdpEntry) onPrint;
  final Future<void> Function(IdpEntry) onDownloadPdf;

  @override
  State<_IdpFormEditor> createState() => _IdpFormEditorState();
}

class _IdpFormEditorState extends State<_IdpFormEditor> {
  late List<TextEditingController> _controllers;
  late String? _performanceRating;
  late String? _competenceRating;
  late String? _successionPriorityRating;
  late List<Map<String, TextEditingController>> _planRows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _controllers = [
      TextEditingController(text: e.name ?? ''),
      TextEditingController(text: e.position ?? ''),
      TextEditingController(text: e.category ?? ''),
      TextEditingController(text: e.division ?? ''),
      TextEditingController(text: e.department ?? ''),
      TextEditingController(text: e.education ?? ''),
      TextEditingController(text: e.experience ?? ''),
      TextEditingController(text: e.training ?? ''),
      TextEditingController(text: e.eligibility ?? ''),
      TextEditingController(text: e.targetPosition1 ?? ''),
      TextEditingController(text: e.targetPosition2 ?? ''),
      TextEditingController(text: e.avgRating ?? ''),
      TextEditingController(text: e.opcr ?? ''),
      TextEditingController(text: e.ipcr ?? ''),
      TextEditingController(text: e.competencyDescription ?? ''),
      TextEditingController(text: e.successionPriorityScore ?? ''),
      TextEditingController(text: e.preparedBy ?? ''),
      TextEditingController(text: e.reviewedBy ?? ''),
      TextEditingController(text: e.notedBy ?? ''),
      TextEditingController(text: e.approvedBy ?? ''),
    ];
    _performanceRating = e.performanceRating;
    _competenceRating = e.competenceRating;
    _successionPriorityRating = e.successionPriorityRating;
    _planRows = e.developmentPlanRows.isEmpty
        ? [_rowControllers('', '', '', '')]
        : e.developmentPlanRows.map((r) => _rowControllers(r.objectives ?? '', r.ldProgram ?? '', r.requirements ?? '', r.timeFrame ?? '')).toList();
  }

  Map<String, TextEditingController> _rowControllers(String obj, String ld, String req, String tf) {
    return {
      'objectives': TextEditingController(text: obj),
      'ld_program': TextEditingController(text: ld),
      'requirements': TextEditingController(text: req),
      'time_frame': TextEditingController(text: tf),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final row in _planRows) {
      for (final c in row.values) c.dispose();
    }
    super.dispose();
  }

  void _addPlanRow() {
    setState(() => _planRows.add(_rowControllers('', '', '', '')));
  }

  void _removePlanRow(int index) {
    if (_planRows.length <= 1) return;
    setState(() {
      for (final c in _planRows[index].values) c.dispose();
      _planRows.removeAt(index);
    });
  }

  IdpEntry _buildCurrentEntry() {
    final rows = _planRows.map((r) => IdpPlanRow(
      objectives: r['objectives']!.text.trim().isEmpty ? null : r['objectives']!.text.trim(),
      ldProgram: r['ld_program']!.text.trim().isEmpty ? null : r['ld_program']!.text.trim(),
      requirements: r['requirements']!.text.trim().isEmpty ? null : r['requirements']!.text.trim(),
      timeFrame: r['time_frame']!.text.trim().isEmpty ? null : r['time_frame']!.text.trim(),
    )).toList();
    return IdpEntry(
      id: widget.entry.id,
      name: _controllers[0].text.trim().isEmpty ? null : _controllers[0].text.trim(),
      position: _controllers[1].text.trim().isEmpty ? null : _controllers[1].text.trim(),
      category: _controllers[2].text.trim().isEmpty ? null : _controllers[2].text.trim(),
      division: _controllers[3].text.trim().isEmpty ? null : _controllers[3].text.trim(),
      department: _controllers[4].text.trim().isEmpty ? null : _controllers[4].text.trim(),
      education: _controllers[5].text.trim().isEmpty ? null : _controllers[5].text.trim(),
      experience: _controllers[6].text.trim().isEmpty ? null : _controllers[6].text.trim(),
      training: _controllers[7].text.trim().isEmpty ? null : _controllers[7].text.trim(),
      eligibility: _controllers[8].text.trim().isEmpty ? null : _controllers[8].text.trim(),
      targetPosition1: _controllers[9].text.trim().isEmpty ? null : _controllers[9].text.trim(),
      targetPosition2: _controllers[10].text.trim().isEmpty ? null : _controllers[10].text.trim(),
      avgRating: _controllers[11].text.trim().isEmpty ? null : _controllers[11].text.trim(),
      opcr: _controllers[12].text.trim().isEmpty ? null : _controllers[12].text.trim(),
      ipcr: _controllers[13].text.trim().isEmpty ? null : _controllers[13].text.trim(),
      performanceRating: _performanceRating,
      competencyDescription: _controllers[14].text.trim().isEmpty ? null : _controllers[14].text.trim(),
      competenceRating: _competenceRating,
      successionPriorityScore: _controllers[15].text.trim().isEmpty ? null : _controllers[15].text.trim(),
      successionPriorityRating: _successionPriorityRating,
      developmentPlanRows: rows,
      preparedBy: _controllers[16].text.trim().isEmpty ? null : _controllers[16].text.trim(),
      reviewedBy: _controllers[17].text.trim().isEmpty ? null : _controllers[17].text.trim(),
      notedBy: _controllers[18].text.trim().isEmpty ? null : _controllers[18].text.trim(),
      approvedBy: _controllers[19].text.trim().isEmpty ? null : _controllers[19].text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

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
            const RspFormHeader(formTitle: 'INDIVIDUAL DEVELOPMENT PLAN', subtitle: 'LOCAL GOVERNMENT UNIT OF PLARIDEL'),
            Text('Personal & position', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _field('Name', _controllers[0]),
            _field('Position', _controllers[1]),
            _field('Category', _controllers[2]),
            _field('Division', _controllers[3]),
            _field('Department', _controllers[4]),
            const SizedBox(height: 20),
            Text('Qualifications', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field('Education', _controllers[5]),
            _field('Experience', _controllers[6]),
            _field('Training', _controllers[7]),
            _field('Eligibility', _controllers[8]),
            const SizedBox(height: 20),
            Text('Succession analysis – target positions', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field('Target position 1', _controllers[9]),
            _field('Target position 2', _controllers[10]),
            const SizedBox(height: 20),
            Text('Performance (avg 2 latest SPMS-IPCR)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field('Average rating', _controllers[11]),
            _field('OPCR', _controllers[12]),
            _field('IPCR', _controllers[13]),
            Wrap(
              spacing: 8,
              children: IdpEntry.performanceRatingOptions.map((v) => ChoiceChip(
                label: Text(v.replaceAll('_', ' ')),
                selected: _performanceRating == v,
                onSelected: (_) => setState(() => _performanceRating = v),
              )).toList(),
            ),
            const SizedBox(height: 20),
            Text('Competence assessment', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field('Competency', _controllers[14]),
            Wrap(
              spacing: 8,
              children: IdpEntry.competenceRatingOptions.map((v) => ChoiceChip(
                label: Text(v[0].toUpperCase() + v.substring(1)),
                selected: _competenceRating == v,
                onSelected: (_) => setState(() => _competenceRating = v),
              )).toList(),
            ),
            const SizedBox(height: 20),
            Text('Succession priority', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field('Total score', _controllers[15]),
            Wrap(
              spacing: 8,
              children: IdpEntry.successionPriorityOptions.map((v) => ChoiceChip(
                label: Text(v == 'priority_2' ? 'Priority 2' : v == 'priority_3' ? 'Priority 3' : 'Priority'),
                selected: _successionPriorityRating == v,
                onSelected: (_) => setState(() => _successionPriorityRating = v),
              )).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Development plan (objectives, L&D program, requirements, time frame)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addPlanRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add row')),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_planRows.length, (i) {
              final r = _planRows[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: TextFormField(controller: r['objectives'], decoration: const InputDecoration(labelText: 'Objectives', border: OutlineInputBorder(), isDense: true))),
                    const SizedBox(width: 8),
                    Expanded(child: TextFormField(controller: r['ld_program'], decoration: const InputDecoration(labelText: 'L&D program', border: OutlineInputBorder(), isDense: true))),
                    const SizedBox(width: 8),
                    Expanded(child: TextFormField(controller: r['requirements'], decoration: const InputDecoration(labelText: 'Requirements', border: OutlineInputBorder(), isDense: true))),
                    const SizedBox(width: 8),
                    Expanded(child: TextFormField(controller: r['time_frame'], decoration: const InputDecoration(labelText: 'Time frame', border: OutlineInputBorder(), isDense: true))),
                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: _planRows.length > 1 ? () => _removePlanRow(i) : null),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            Text('Signatures (optional)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field('Prepared by', _controllers[16]),
            _field('Reviewed by', _controllers[17]),
            _field('Noted by', _controllers[18]),
            _field('Approved by', _controllers[19]),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
    );
  }
}

class _IdpList extends StatelessWidget {
  const _IdpList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<IdpEntry> entries;
  final void Function(IdpEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(IdpEntry) onPrint;
  final Future<void> Function(IdpEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Department')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.name ?? '—')),
            DataCell(Text(e.position ?? '—')),
            DataCell(Text(e.department ?? '—')),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete IDP?'),
                        content: const Text('This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true && e.id != null) onDelete(e.id!);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            )),
          ],
        )).toList(),
      ),
    );
  }
}

/// RSP: Applicants Profile — job vacancy details + list of applicants.
class _RspApplicantsProfileSection extends StatefulWidget {
  const _RspApplicantsProfileSection();

  @override
  State<_RspApplicantsProfileSection> createState() => _RspApplicantsProfileSectionState();
}

class _RspApplicantsProfileSectionState extends State<_RspApplicantsProfileSection> {
  List<ApplicantsProfileEntry> _entries = [];
  bool _loading = true;
  ApplicantsProfileEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApplicantsProfileRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const ApplicantsProfileEntry());
  void _edit(ApplicantsProfileEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ApplicantsProfileEntry entry) async {
    try {
      if (entry.id == null) {
        await ApplicantsProfileRepo.instance.insert(entry);
      } else {
        await ApplicantsProfileRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Applicants profile saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await ApplicantsProfileRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Applicants profile deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printProfile(ApplicantsProfileEntry entry) async {
    try {
      final doc = FormPdf.buildApplicantsProfilePdf(entry);
      await FormPdf.printDocument(doc, name: 'Applicants_Profile.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadProfile(ApplicantsProfileEntry entry) async {
    try {
      final doc = FormPdf.buildApplicantsProfilePdf(entry);
      await FormPdf.sharePdf(doc, name: 'Applicants_Profile.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Applicants Profile', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Job vacancy details (position, requirements, dates) and list of applicants (name, course, address, sex, age, civil status, remark).', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _ApplicantsProfileFormEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printProfile, onDownloadPdf: _downloadProfile),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add profile')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No applicants profiles yet. Tap "Add profile" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else
          _ApplicantsProfileList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printProfile, onDownloadPdf: _downloadProfile),
      ],
    );
  }
}

class _ApplicantsProfileFormEditor extends StatefulWidget {
  const _ApplicantsProfileFormEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final ApplicantsProfileEntry entry;
  final void Function(ApplicantsProfileEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ApplicantsProfileEntry) onPrint;
  final Future<void> Function(ApplicantsProfileEntry) onDownloadPdf;

  @override
  State<_ApplicantsProfileFormEditor> createState() => _ApplicantsProfileFormEditorState();
}

class _ApplicantsProfileFormEditorState extends State<_ApplicantsProfileFormEditor> {
  late TextEditingController _positionApplied;
  late TextEditingController _minRequirements;
  late TextEditingController _datePosting;
  late TextEditingController _closingDate;
  late TextEditingController _preparedBy;
  late TextEditingController _checkedBy;
  late List<Map<String, TextEditingController>> _applicantRows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _positionApplied = TextEditingController(text: e.positionAppliedFor ?? '');
    _minRequirements = TextEditingController(text: e.minimumRequirements ?? '');
    _datePosting = TextEditingController(text: e.dateOfPosting ?? '');
    _closingDate = TextEditingController(text: e.closingDate ?? '');
    _preparedBy = TextEditingController(text: e.preparedBy ?? '');
    _checkedBy = TextEditingController(text: e.checkedBy ?? '');
    _applicantRows = e.applicants.isEmpty
        ? [_applicantRow('', '', '', '', '', '', '')]
        : e.applicants.map((a) => _applicantRow(a.name ?? '', a.course ?? '', a.address ?? '', a.sex ?? '', a.age ?? '', a.civilStatus ?? '', a.remarkDisability ?? '')).toList();
  }

  Map<String, TextEditingController> _applicantRow(String name, String course, String address, String sex, String age, String civil, String remark) {
    return {
      'name': TextEditingController(text: name),
      'course': TextEditingController(text: course),
      'address': TextEditingController(text: address),
      'sex': TextEditingController(text: sex),
      'age': TextEditingController(text: age),
      'civil_status': TextEditingController(text: civil),
      'remark_disability': TextEditingController(text: remark),
    };
  }

  @override
  void dispose() {
    _positionApplied.dispose();
    _minRequirements.dispose();
    _datePosting.dispose();
    _closingDate.dispose();
    _preparedBy.dispose();
    _checkedBy.dispose();
    for (final row in _applicantRows) {
      for (final c in row.values) c.dispose();
    }
    super.dispose();
  }

  void _addApplicant() {
    setState(() => _applicantRows.add(_applicantRow('', '', '', '', '', '', '')));
  }

  void _removeApplicant(int index) {
    if (_applicantRows.length <= 1) return;
    setState(() {
      for (final c in _applicantRows[index].values) c.dispose();
      _applicantRows.removeAt(index);
    });
  }

  ApplicantsProfileEntry _buildCurrentEntry() {
    final applicants = _applicantRows.map((r) => ApplicantsProfileApplicant(
      name: r['name']!.text.trim().isEmpty ? null : r['name']!.text.trim(),
      course: r['course']!.text.trim().isEmpty ? null : r['course']!.text.trim(),
      address: r['address']!.text.trim().isEmpty ? null : r['address']!.text.trim(),
      sex: r['sex']!.text.trim().isEmpty ? null : r['sex']!.text.trim(),
      age: r['age']!.text.trim().isEmpty ? null : r['age']!.text.trim(),
      civilStatus: r['civil_status']!.text.trim().isEmpty ? null : r['civil_status']!.text.trim(),
      remarkDisability: r['remark_disability']!.text.trim().isEmpty ? null : r['remark_disability']!.text.trim(),
    )).toList();
    return ApplicantsProfileEntry(
      id: widget.entry.id,
      positionAppliedFor: _positionApplied.text.trim().isEmpty ? null : _positionApplied.text.trim(),
      minimumRequirements: _minRequirements.text.trim().isEmpty ? null : _minRequirements.text.trim(),
      dateOfPosting: _datePosting.text.trim().isEmpty ? null : _datePosting.text.trim(),
      closingDate: _closingDate.text.trim().isEmpty ? null : _closingDate.text.trim(),
      applicants: applicants,
      preparedBy: _preparedBy.text.trim().isEmpty ? null : _preparedBy.text.trim(),
      checkedBy: _checkedBy.text.trim().isEmpty ? null : _checkedBy.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

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
            const RspFormHeader(formTitle: 'APPLICANTS PROFILE'),
            TextFormField(controller: _positionApplied, decoration: rspUnderlinedField('Position Applied for:')),
            TextFormField(controller: _minRequirements, decoration: rspUnderlinedField('Minimum Requirements:')),
            TextFormField(controller: _datePosting, decoration: rspUnderlinedField('Date of Posting:')),
            TextFormField(controller: _closingDate, decoration: rspUnderlinedField('Closing Date:')),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Applicants', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addApplicant, icon: const Icon(Icons.add, size: 18), label: const Text('Add applicant')),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('COURSE')),
                  DataColumn(label: Text('ADDRESS')),
                  DataColumn(label: Text('SEX')),
                  DataColumn(label: Text('AGE')),
                  DataColumn(label: Text('CIVIL STATUS')),
                  DataColumn(label: Text('REMARK (DISABILITY)')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_applicantRows.length, (i) {
                  final r = _applicantRows[i];
                  return DataRow(
                    cells: [
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['name'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 90, child: TextFormField(controller: r['course'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 140, child: TextFormField(controller: r['address'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 50, child: TextFormField(controller: r['sex'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 45, child: TextFormField(controller: r['age'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 90, child: TextFormField(controller: r['civil_status'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['remark_disability'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _applicantRows.length > 1 ? () => _removeApplicant(i) : null)),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Prepared by:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  TextFormField(controller: _preparedBy, decoration: rspUnderlinedField('')),
                  Text('(e.g. HRMDO Staff)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ])),
                const SizedBox(width: 24),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Checked by:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  TextFormField(controller: _checkedBy, decoration: rspUnderlinedField('')),
                  Text('(e.g. HRMDO)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ])),
              ],
            ),
            const SizedBox(height: 24),
            const RspFormFooter(),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicantsProfileList extends StatelessWidget {
  const _ApplicantsProfileList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<ApplicantsProfileEntry> entries;
  final void Function(ApplicantsProfileEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ApplicantsProfileEntry) onPrint;
  final Future<void> Function(ApplicantsProfileEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position applied for')),
          DataColumn(label: Text('Posting date')),
          DataColumn(label: Text('Applicants')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.positionAppliedFor ?? '—')),
            DataCell(Text(e.dateOfPosting ?? '—')),
            DataCell(Text('${e.applicants.length}')),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete applicants profile?'),
                        content: const Text('This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true && e.id != null) onDelete(e.id!);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            )),
          ],
        )).toList(),
      ),
    );
  }
}

/// RSP: Comparative Assessment of Candidates for Promotion — form only, no names/values pre-filled.
class _RspComparativeAssessmentSection extends StatefulWidget {
  const _RspComparativeAssessmentSection();

  @override
  State<_RspComparativeAssessmentSection> createState() => _RspComparativeAssessmentSectionState();
}

class _RspComparativeAssessmentSectionState extends State<_RspComparativeAssessmentSection> {
  List<ComparativeAssessmentEntry> _entries = [];
  bool _loading = true;
  ComparativeAssessmentEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ComparativeAssessmentRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const ComparativeAssessmentEntry());
  void _edit(ComparativeAssessmentEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ComparativeAssessmentEntry entry) async {
    try {
      if (entry.id == null) await ComparativeAssessmentRepo.instance.insert(entry);
      else await ComparativeAssessmentRepo.instance.update(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comparative assessment saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await ComparativeAssessmentRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printCa(ComparativeAssessmentEntry entry) async {
    try {
      final doc = FormPdf.buildComparativeAssessmentPdf(entry);
      await FormPdf.printDocument(doc, name: 'Comparative_Assessment.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadCa(ComparativeAssessmentEntry entry) async {
    try {
      final doc = FormPdf.buildComparativeAssessmentPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Comparative_Assessment.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comparative Assessment of Candidates for Promotion', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Position, minimum requirements, and candidate comparison table. Form only—no names or values pre-filled.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _ComparativeAssessmentEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printCa, onDownloadPdf: _downloadCa),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add assessment')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No assessments yet. Tap "Add assessment" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else _ComparativeAssessmentList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printCa, onDownloadPdf: _downloadCa),
      ],
    );
  }
}

class _ComparativeAssessmentEditor extends StatefulWidget {
  const _ComparativeAssessmentEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final ComparativeAssessmentEntry entry;
  final void Function(ComparativeAssessmentEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ComparativeAssessmentEntry) onPrint;
  final Future<void> Function(ComparativeAssessmentEntry) onDownloadPdf;

  @override
  State<_ComparativeAssessmentEditor> createState() => _ComparativeAssessmentEditorState();
}

class _ComparativeAssessmentEditorState extends State<_ComparativeAssessmentEditor> {
  late TextEditingController _position;
  late TextEditingController _edu;
  late TextEditingController _exp;
  late TextEditingController _elig;
  late TextEditingController _training;
  late List<Map<String, TextEditingController>> _rows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _position = TextEditingController(text: e.positionToBeFilled ?? '');
    _edu = TextEditingController(text: e.minReqEducation ?? '');
    _exp = TextEditingController(text: e.minReqExperience ?? '');
    _elig = TextEditingController(text: e.minReqEligibility ?? '');
    _training = TextEditingController(text: e.minReqTraining ?? '');
    _rows = e.candidates.isEmpty
        ? [_caRow('', '', '', '', '', '', '', '')]
        : e.candidates.map((c) => _caRow(c.candidateName ?? '', c.presentPositionSalary ?? '', c.education ?? '', c.trainingHrs ?? '', c.relatedExperience ?? '', c.eligibility ?? '', c.performanceRating ?? '', c.remarks ?? '')).toList();
  }

  Map<String, TextEditingController> _caRow(String n, String pos, String edu, String hrs, String rel, String elig, String perf, String rem) {
    return {
      'name': TextEditingController(text: n),
      'present_position_salary': TextEditingController(text: pos),
      'education': TextEditingController(text: edu),
      'training_hrs': TextEditingController(text: hrs),
      'related_experience': TextEditingController(text: rel),
      'eligibility': TextEditingController(text: elig),
      'performance_rating': TextEditingController(text: perf),
      'remarks': TextEditingController(text: rem),
    };
  }

  @override
  void dispose() {
    _position.dispose();
    _edu.dispose();
    _exp.dispose();
    _elig.dispose();
    _training.dispose();
    for (final row in _rows) { for (final c in row.values) c.dispose(); }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_caRow('', '', '', '', '', '', '', '')));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() { for (final c in _rows[i].values) c.dispose(); _rows.removeAt(i); });
  }

  ComparativeAssessmentEntry _buildCurrentEntry() {
    final candidates = _rows.map((r) => ComparativeAssessmentCandidate(
      candidateName: r['name']!.text.trim().isEmpty ? null : r['name']!.text.trim(),
      presentPositionSalary: r['present_position_salary']!.text.trim().isEmpty ? null : r['present_position_salary']!.text.trim(),
      education: r['education']!.text.trim().isEmpty ? null : r['education']!.text.trim(),
      trainingHrs: r['training_hrs']!.text.trim().isEmpty ? null : r['training_hrs']!.text.trim(),
      relatedExperience: r['related_experience']!.text.trim().isEmpty ? null : r['related_experience']!.text.trim(),
      eligibility: r['eligibility']!.text.trim().isEmpty ? null : r['eligibility']!.text.trim(),
      performanceRating: r['performance_rating']!.text.trim().isEmpty ? null : r['performance_rating']!.text.trim(),
      remarks: r['remarks']!.text.trim().isEmpty ? null : r['remarks']!.text.trim(),
    )).toList();
    return ComparativeAssessmentEntry(
      id: widget.entry.id,
      positionToBeFilled: _position.text.trim().isEmpty ? null : _position.text.trim(),
      minReqEducation: _edu.text.trim().isEmpty ? null : _edu.text.trim(),
      minReqExperience: _exp.text.trim().isEmpty ? null : _exp.text.trim(),
      minReqEligibility: _elig.text.trim().isEmpty ? null : _elig.text.trim(),
      minReqTraining: _training.text.trim().isEmpty ? null : _training.text.trim(),
      candidates: candidates,
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.06))),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeaderBoard(formTitle: 'COMPARATIVE ASSESSMENT OF CANDIDATES FOR PROMOTION'),
            Text('POSITION TO BE FILLED:', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 13, fontWeight: FontWeight.w600)),
            TextFormField(controller: _position, decoration: rspUnderlinedField('')),
            const SizedBox(height: 12),
            Text('MINIMUM REQUIREMENTS:', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _edu, decoration: rspUnderlinedField('EDUCATION :')),
            TextFormField(controller: _exp, decoration: rspUnderlinedField('EXPERIENCE :')),
            TextFormField(controller: _elig, decoration: rspUnderlinedField('ELIGIBILITY :')),
            TextFormField(controller: _training, decoration: rspUnderlinedField('TRAINING :')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Candidates', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add row')),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('CANDIDATES')),
                  DataColumn(label: Text('Present Position/Salary Grade/Monthly Salary')),
                  DataColumn(label: Text('EDUCATION')),
                  DataColumn(label: Text('No. of hrs. Related Training')),
                  DataColumn(label: Text('Related Experienced')),
                  DataColumn(label: Text('Eligibility')),
                  DataColumn(label: Text('Performance Rating')),
                  DataColumn(label: Text('REMARKS')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['name'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Name')))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['present_position_salary'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 90, child: TextFormField(controller: r['education'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 70, child: TextFormField(controller: r['training_hrs'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['related_experience'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['eligibility'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['performance_rating'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 90, child: TextFormField(controller: r['remarks'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _rows.length > 1 ? () => _removeRow(i) : null)),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparativeAssessmentList extends StatelessWidget {
  const _ComparativeAssessmentList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<ComparativeAssessmentEntry> entries;
  final void Function(ComparativeAssessmentEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ComparativeAssessmentEntry) onPrint;
  final Future<void> Function(ComparativeAssessmentEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Candidates')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.positionToBeFilled ?? '—')),
            DataCell(Text('${e.candidates.length}')),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete?'), content: const Text('This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete'))]));
                    if (ok == true && e.id != null) onDelete(e.id!);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            )),
          ],
        )).toList(),
      ),
    );
  }
}

/// RSP: Promotion Certification / Screening — form only, no names/values pre-filled.
class _RspPromotionCertificationSection extends StatefulWidget {
  const _RspPromotionCertificationSection();

  @override
  State<_RspPromotionCertificationSection> createState() => _RspPromotionCertificationSectionState();
}

class _RspPromotionCertificationSectionState extends State<_RspPromotionCertificationSection> {
  List<PromotionCertificationEntry> _entries = [];
  bool _loading = true;
  PromotionCertificationEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await PromotionCertificationRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const PromotionCertificationEntry());
  void _edit(PromotionCertificationEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(PromotionCertificationEntry entry) async {
    try {
      if (entry.id == null) await PromotionCertificationRepo.instance.insert(entry);
      else await PromotionCertificationRepo.instance.update(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Promotion certification saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await PromotionCertificationRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printPc(PromotionCertificationEntry entry) async {
    try {
      final doc = FormPdf.buildPromotionCertificationPdf(entry);
      await FormPdf.printDocument(doc, name: 'Promotion_Certification.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadPc(PromotionCertificationEntry entry) async {
    try {
      final doc = FormPdf.buildPromotionCertificationPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Promotion_Certification.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Promotion Certification / Screening', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Certification that candidate(s) have been screened and found qualified for promotion. Form only—no names or values pre-filled.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _PromotionCertificationEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printPc, onDownloadPdf: _downloadPc),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add certification')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No certifications yet. Tap "Add certification" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else _PromotionCertificationList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printPc, onDownloadPdf: _downloadPc),
      ],
    );
  }
}

class _PromotionCertificationEditor extends StatefulWidget {
  const _PromotionCertificationEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final PromotionCertificationEntry entry;
  final void Function(PromotionCertificationEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(PromotionCertificationEntry) onPrint;
  final Future<void> Function(PromotionCertificationEntry) onDownloadPdf;

  @override
  State<_PromotionCertificationEditor> createState() => _PromotionCertificationEditorState();
}

class _PromotionCertificationEditorState extends State<_PromotionCertificationEditor> {
  late TextEditingController _position;
  late TextEditingController _day;
  late TextEditingController _month;
  late TextEditingController _year;
  late TextEditingController _signName;
  late TextEditingController _signTitle;
  late List<Map<String, TextEditingController>> _rows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _position = TextEditingController(text: e.positionForPromotion ?? '');
    _day = TextEditingController(text: e.dateDay ?? '');
    _month = TextEditingController(text: e.dateMonth ?? '');
    _year = TextEditingController(text: e.dateYear ?? '');
    _signName = TextEditingController(text: e.signatoryName ?? '');
    _signTitle = TextEditingController(text: e.signatoryTitle ?? '');
    _rows = e.candidates.isEmpty
        ? [_pcRow('', '', '', '', '', '')]
        : e.candidates.map((c) => _pcRow(c.name ?? '', c.col1 ?? '', c.col2 ?? '', c.col3 ?? '', c.col4 ?? '', c.col5 ?? '')).toList();
  }

  Map<String, TextEditingController> _pcRow(String name, String c1, String c2, String c3, String c4, String c5) {
    return {
      'name': TextEditingController(text: name),
      'col1': TextEditingController(text: c1),
      'col2': TextEditingController(text: c2),
      'col3': TextEditingController(text: c3),
      'col4': TextEditingController(text: c4),
      'col5': TextEditingController(text: c5),
    };
  }

  @override
  void dispose() {
    _position.dispose();
    _day.dispose();
    _month.dispose();
    _year.dispose();
    _signName.dispose();
    _signTitle.dispose();
    for (final row in _rows) { for (final c in row.values) c.dispose(); }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_pcRow('', '', '', '', '', '')));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() { for (final c in _rows[i].values) c.dispose(); _rows.removeAt(i); });
  }

  PromotionCertificationEntry _buildCurrentEntry() {
    final candidates = _rows.map((r) => PromotionCertificationCandidate(
      name: r['name']!.text.trim().isEmpty ? null : r['name']!.text.trim(),
      col1: r['col1']!.text.trim().isEmpty ? null : r['col1']!.text.trim(),
      col2: r['col2']!.text.trim().isEmpty ? null : r['col2']!.text.trim(),
      col3: r['col3']!.text.trim().isEmpty ? null : r['col3']!.text.trim(),
      col4: r['col4']!.text.trim().isEmpty ? null : r['col4']!.text.trim(),
      col5: r['col5']!.text.trim().isEmpty ? null : r['col5']!.text.trim(),
    )).toList();
    return PromotionCertificationEntry(
      id: widget.entry.id,
      positionForPromotion: _position.text.trim().isEmpty ? null : _position.text.trim(),
      candidates: candidates,
      dateDay: _day.text.trim().isEmpty ? null : _day.text.trim(),
      dateMonth: _month.text.trim().isEmpty ? null : _month.text.trim(),
      dateYear: _year.text.trim().isEmpty ? null : _year.text.trim(),
      signatoryName: _signName.text.trim().isEmpty ? null : _signName.text.trim(),
      signatoryTitle: _signTitle.text.trim().isEmpty ? null : _signTitle.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.06))),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(formTitle: 'Promotion Certification / Screening'),
            Text('Position for promotion:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _position, decoration: rspUnderlinedField('')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Candidates (name + 5 columns)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add row')),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('1')),
                  DataColumn(label: Text('2')),
                  DataColumn(label: Text('3')),
                  DataColumn(label: Text('4')),
                  DataColumn(label: Text('5')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['name'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Name')))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['col1'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['col2'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['col3'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['col4'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 80, child: TextFormField(controller: r['col5'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _rows.length > 1 ? () => _removeRow(i) : null)),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            const Text('We hereby certify that the above candidate(s) have been screened and found to be qualified for promotion to the above position.', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Done this ', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                SizedBox(width: 60, child: TextFormField(controller: _day, decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder(), hintText: 'day'))),
                const Text(' day of '),
                SizedBox(width: 80, child: TextFormField(controller: _month, decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder(), hintText: 'month'))),
                const Text(', '),
                SizedBox(width: 50, child: TextFormField(controller: _year, decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder(), hintText: 'year'))),
                const Text('.'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Signatory (e.g. Secretariat)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field(_signName, 'Name'),
            _field(_signTitle, 'Title'),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
    );
  }
}

class _PromotionCertificationList extends StatelessWidget {
  const _PromotionCertificationList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<PromotionCertificationEntry> entries;
  final void Function(PromotionCertificationEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(PromotionCertificationEntry) onPrint;
  final Future<void> Function(PromotionCertificationEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Candidates')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.positionForPromotion ?? '—')),
            DataCell(Text('${e.candidates.length}')),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete?'), content: const Text('This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete'))]));
                    if (ok == true && e.id != null) onDelete(e.id!);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            )),
          ],
        )).toList(),
      ),
    );
  }
}

/// RSP: Selection Line-up — date, agency/office, vacant position, item no., applicants table. Form only, no pre-filled names.
class _RspSelectionLineupSection extends StatefulWidget {
  const _RspSelectionLineupSection();

  @override
  State<_RspSelectionLineupSection> createState() => _RspSelectionLineupSectionState();
}

class _RspSelectionLineupSectionState extends State<_RspSelectionLineupSection> {
  List<SelectionLineupEntry> _entries = [];
  bool _loading = true;
  SelectionLineupEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SelectionLineupRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const SelectionLineupEntry());
  void _edit(SelectionLineupEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(SelectionLineupEntry entry) async {
    try {
      if (entry.id == null) await SelectionLineupRepo.instance.insert(entry);
      else await SelectionLineupRepo.instance.update(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selection line-up saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await SelectionLineupRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printSl(SelectionLineupEntry entry) async {
    try {
      final doc = FormPdf.buildSelectionLineupPdf(entry);
      await FormPdf.printDocument(doc, name: 'Selection_Lineup.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadSl(SelectionLineupEntry entry) async {
    try {
      final doc = FormPdf.buildSelectionLineupPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Selection_Lineup.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selection Line-up', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Date, name of agency/office, vacant position, item no., and applicants table (name, education, experience, training, eligibility). Form only—no pre-filled names.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _SelectionLineupEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printSl, onDownloadPdf: _downloadSl),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add line-up')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No selection line-ups yet. Tap "Add line-up" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else _SelectionLineupList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printSl, onDownloadPdf: _downloadSl),
      ],
    );
  }
}

class _SelectionLineupEditor extends StatefulWidget {
  const _SelectionLineupEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final SelectionLineupEntry entry;
  final void Function(SelectionLineupEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(SelectionLineupEntry) onPrint;
  final Future<void> Function(SelectionLineupEntry) onDownloadPdf;

  @override
  State<_SelectionLineupEditor> createState() => _SelectionLineupEditorState();
}

class _SelectionLineupEditorState extends State<_SelectionLineupEditor> {
  late TextEditingController _date;
  late TextEditingController _agency;
  late TextEditingController _position;
  late TextEditingController _itemNo;
  late TextEditingController _preparedName;
  late TextEditingController _preparedTitle;
  late List<Map<String, TextEditingController>> _rows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _date = TextEditingController(text: e.date ?? '');
    _agency = TextEditingController(text: e.nameOfAgencyOffice ?? '');
    _position = TextEditingController(text: e.vacantPosition ?? '');
    _itemNo = TextEditingController(text: e.itemNo ?? '');
    _preparedName = TextEditingController(text: e.preparedByName ?? '');
    _preparedTitle = TextEditingController(text: e.preparedByTitle ?? '');
    _rows = e.applicants.isEmpty
        ? [_slRow('', '', '', '', '')]
        : e.applicants.map((a) => _slRow(a.name ?? '', a.education ?? '', a.experience ?? '', a.training ?? '', a.eligibility ?? '')).toList();
  }

  Map<String, TextEditingController> _slRow(String name, String edu, String exp, String train, String elig) {
    return {
      'name': TextEditingController(text: name),
      'education': TextEditingController(text: edu),
      'experience': TextEditingController(text: exp),
      'training': TextEditingController(text: train),
      'eligibility': TextEditingController(text: elig),
    };
  }

  @override
  void dispose() {
    _date.dispose();
    _agency.dispose();
    _position.dispose();
    _itemNo.dispose();
    _preparedName.dispose();
    _preparedTitle.dispose();
    for (final row in _rows) { for (final c in row.values) c.dispose(); }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_slRow('', '', '', '', '')));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() { for (final c in _rows[i].values) c.dispose(); _rows.removeAt(i); });
  }

  SelectionLineupEntry _buildCurrentEntry() {
    final applicants = _rows.map((r) => SelectionLineupApplicant(
      name: r['name']!.text.trim().isEmpty ? null : r['name']!.text.trim(),
      education: r['education']!.text.trim().isEmpty ? null : r['education']!.text.trim(),
      experience: r['experience']!.text.trim().isEmpty ? null : r['experience']!.text.trim(),
      training: r['training']!.text.trim().isEmpty ? null : r['training']!.text.trim(),
      eligibility: r['eligibility']!.text.trim().isEmpty ? null : r['eligibility']!.text.trim(),
    )).toList();
    return SelectionLineupEntry(
      id: widget.entry.id,
      date: _date.text.trim().isEmpty ? null : _date.text.trim(),
      nameOfAgencyOffice: _agency.text.trim().isEmpty ? null : _agency.text.trim(),
      vacantPosition: _position.text.trim().isEmpty ? null : _position.text.trim(),
      itemNo: _itemNo.text.trim().isEmpty ? null : _itemNo.text.trim(),
      applicants: applicants,
      preparedByName: _preparedName.text.trim().isEmpty ? null : _preparedName.text.trim(),
      preparedByTitle: _preparedTitle.text.trim().isEmpty ? null : _preparedTitle.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.06))),
      child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(formTitle: 'SELECTION LINE-UP'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(width: 180, child: TextFormField(controller: _date, decoration: rspUnderlinedField('Date'))),
              ],
            ),
            const SizedBox(height: 12),
            Text('Name of Agency/Office:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _agency, decoration: rspUnderlinedField('')),
            Text('Vacant Position:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _position, decoration: rspUnderlinedField('')),
            Text('Item No.:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _itemNo, decoration: rspUnderlinedField('')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Name of applicants (table)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add applicant')),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('NAME OF APPLICANTS')),
                  DataColumn(label: Text('EDUCATION')),
                  DataColumn(label: Text('EXPERIENCE')),
                  DataColumn(label: Text('TRAINING')),
                  DataColumn(label: Text('ELIGIBILITY')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(SizedBox(width: 140, child: TextFormField(controller: r['name'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Name')))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['education'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['experience'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['training'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['eligibility'], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _rows.length > 1 ? () => _removeRow(i) : null)),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Text('Prepared by', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _field(_preparedName, 'Name'),
            _field(_preparedTitle, 'Title'),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
    );
  }
}

class _SelectionLineupList extends StatelessWidget {
  const _SelectionLineupList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<SelectionLineupEntry> entries;
  final void Function(SelectionLineupEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(SelectionLineupEntry) onPrint;
  final Future<void> Function(SelectionLineupEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Vacant position')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Applicants')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.vacantPosition ?? '—')),
            DataCell(Text(e.date ?? '—')),
            DataCell(Text('${e.applicants.length}')),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete?'), content: const Text('This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete'))]));
                    if (ok == true && e.id != null) onDelete(e.id!);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            )),
          ],
        )).toList(),
      ),
    );
  }
}

/// RSP: Turn-Around Time — position, office, dates, applicant tracking table. Form only, no pre-filled names.
class _RspTurnAroundTimeSection extends StatefulWidget {
  const _RspTurnAroundTimeSection();

  @override
  State<_RspTurnAroundTimeSection> createState() => _RspTurnAroundTimeSectionState();
}

class _RspTurnAroundTimeSectionState extends State<_RspTurnAroundTimeSection> {
  List<TurnAroundTimeEntry> _entries = [];
  bool _loading = true;
  TurnAroundTimeEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TurnAroundTimeRepo.instance.list();
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const TurnAroundTimeEntry());
  void _edit(TurnAroundTimeEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(TurnAroundTimeEntry entry) async {
    try {
      if (entry.id == null) await TurnAroundTimeRepo.instance.insert(entry);
      else await TurnAroundTimeRepo.instance.update(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn-around time saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await TurnAroundTimeRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printTat(TurnAroundTimeEntry entry) async {
    try {
      final doc = FormPdf.buildTurnAroundTimePdf(entry);
      await FormPdf.printDocument(doc, name: 'Turn_Around_Time.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadTat(TurnAroundTimeEntry entry) async {
    try {
      final doc = FormPdf.buildTurnAroundTimePdf(entry);
      await FormPdf.sharePdf(doc, name: 'Turn_Around_Time.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Turn-Around Time', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Position, office, dates, and applicant tracking (assessment, exam, deliberation, job offer, assumption, cost). Form only—no pre-filled names.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _TurnAroundTimeEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printTat, onDownloadPdf: _downloadTat),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add turn-around time')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No turn-around time entries yet. Tap "Add turn-around time" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else _TurnAroundTimeList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printTat, onDownloadPdf: _downloadTat),
      ],
    );
  }
}

class _TurnAroundTimeEditor extends StatefulWidget {
  const _TurnAroundTimeEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final TurnAroundTimeEntry entry;
  final void Function(TurnAroundTimeEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(TurnAroundTimeEntry) onPrint;
  final Future<void> Function(TurnAroundTimeEntry) onDownloadPdf;

  @override
  State<_TurnAroundTimeEditor> createState() => _TurnAroundTimeEditorState();
}

class _TurnAroundTimeEditorState extends State<_TurnAroundTimeEditor> {
  late List<TextEditingController> _header;
  late List<TextEditingController> _signatory;
  late List<Map<String, TextEditingController>> _rows;

  static const List<String> _rowKeys = [
    'name', 'date_initial_assessment', 'date_contract_exam', 'skills_trade_exam_result',
    'date_deliberation', 'date_job_offer', 'acceptance_date', 'date_assumption_to_duty',
    'no_of_days_to_fill_up', 'overall_cost_per_hire',
  ];

  Map<String, TextEditingController> _tatRow(Map<String, String> values) {
    return Map.fromEntries(_rowKeys.map((k) => MapEntry(k, TextEditingController(text: values[k] ?? ''))));
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _header = [
      TextEditingController(text: e.position ?? ''),
      TextEditingController(text: e.office ?? ''),
      TextEditingController(text: e.noOfVacantPosition ?? ''),
      TextEditingController(text: e.dateOfPublication ?? ''),
      TextEditingController(text: e.endSearch ?? ''),
      TextEditingController(text: e.qs ?? ''),
    ];
    _signatory = [
      TextEditingController(text: e.preparedByName ?? ''),
      TextEditingController(text: e.preparedByTitle ?? ''),
      TextEditingController(text: e.notedByName ?? ''),
      TextEditingController(text: e.notedByTitle ?? ''),
    ];
    _rows = e.applicants.isEmpty
        ? [_tatRow({})]
        : e.applicants.map((a) => _tatRow({
              'name': a.name ?? '',
              'date_initial_assessment': a.dateInitialAssessment ?? '',
              'date_contract_exam': a.dateContractExam ?? '',
              'skills_trade_exam_result': a.skillsTradeExamResult ?? '',
              'date_deliberation': a.dateDeliberation ?? '',
              'date_job_offer': a.dateJobOffer ?? '',
              'acceptance_date': a.acceptanceDate ?? '',
              'date_assumption_to_duty': a.dateAssumptionToDuty ?? '',
              'no_of_days_to_fill_up': a.noOfDaysToFillUp ?? '',
              'overall_cost_per_hire': a.overallCostPerHire ?? '',
            })).toList();
  }

  @override
  void dispose() {
    for (final c in _header) c.dispose();
    for (final c in _signatory) c.dispose();
    for (final row in _rows) { for (final c in row.values) c.dispose(); }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_tatRow({})));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() { for (final c in _rows[i].values) c.dispose(); _rows.removeAt(i); });
  }

  TurnAroundTimeEntry _buildCurrentEntry() {
    final applicants = _rows.map((r) => TurnAroundTimeApplicant(
      name: r['name']!.text.trim().isEmpty ? null : r['name']!.text.trim(),
      dateInitialAssessment: r['date_initial_assessment']!.text.trim().isEmpty ? null : r['date_initial_assessment']!.text.trim(),
      dateContractExam: r['date_contract_exam']!.text.trim().isEmpty ? null : r['date_contract_exam']!.text.trim(),
      skillsTradeExamResult: r['skills_trade_exam_result']!.text.trim().isEmpty ? null : r['skills_trade_exam_result']!.text.trim(),
      dateDeliberation: r['date_deliberation']!.text.trim().isEmpty ? null : r['date_deliberation']!.text.trim(),
      dateJobOffer: r['date_job_offer']!.text.trim().isEmpty ? null : r['date_job_offer']!.text.trim(),
      acceptanceDate: r['acceptance_date']!.text.trim().isEmpty ? null : r['acceptance_date']!.text.trim(),
      dateAssumptionToDuty: r['date_assumption_to_duty']!.text.trim().isEmpty ? null : r['date_assumption_to_duty']!.text.trim(),
      noOfDaysToFillUp: r['no_of_days_to_fill_up']!.text.trim().isEmpty ? null : r['no_of_days_to_fill_up']!.text.trim(),
      overallCostPerHire: r['overall_cost_per_hire']!.text.trim().isEmpty ? null : r['overall_cost_per_hire']!.text.trim(),
    )).toList();
    return TurnAroundTimeEntry(
      id: widget.entry.id,
      position: _header[0].text.trim().isEmpty ? null : _header[0].text.trim(),
      office: _header[1].text.trim().isEmpty ? null : _header[1].text.trim(),
      noOfVacantPosition: _header[2].text.trim().isEmpty ? null : _header[2].text.trim(),
      dateOfPublication: _header[3].text.trim().isEmpty ? null : _header[3].text.trim(),
      endSearch: _header[4].text.trim().isEmpty ? null : _header[4].text.trim(),
      qs: _header[5].text.trim().isEmpty ? null : _header[5].text.trim(),
      applicants: applicants,
      preparedByName: _signatory[0].text.trim().isEmpty ? null : _signatory[0].text.trim(),
      preparedByTitle: _signatory[1].text.trim().isEmpty ? null : _signatory[1].text.trim(),
      notedByName: _signatory[2].text.trim().isEmpty ? null : _signatory[2].text.trim(),
      notedByTitle: _signatory[3].text.trim().isEmpty ? null : _signatory[3].text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Name of Applicant', 'Date of Initial Assesment', 'Date of Contract for trade and written exam', 'Skills Trade/ Exam Result', 'Date of Deliberation', 'Date of Job Offer', 'Acceptance date of Job Offer', 'Date of Assumption to Duty', 'No. of Days to Fill-Up Position', 'Overall Cost per hire'];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.06))),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeaderBoard(formTitle: 'TURN-AROUND TIME', officeName: 'MGO-Plaridel, Misamis Occidental'),
            Text('Position:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _header[0], decoration: rspUnderlinedField('')),
            Text('Office:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _header[1], decoration: rspUnderlinedField('')),
            Text('No. of Vacant Position:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _header[2], decoration: rspUnderlinedField('')),
            Text('Date of Publication:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _header[3], decoration: rspUnderlinedField('')),
            Text('End Search:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _header[4], decoration: rspUnderlinedField('')),
            Text('Q.S.:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            TextFormField(controller: _header[5], decoration: rspUnderlinedField('')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Applicants (turn-around tracking)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add applicant')),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (var i = 0; i < _rowKeys.length; i++) DataColumn(label: Text(labels[i], style: const TextStyle(fontSize: 11))),
                  const DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      for (final k in _rowKeys) DataCell(SizedBox(width: 90, child: TextFormField(controller: r[k], decoration: const InputDecoration(isDense: true, border: OutlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _rows.length > 1 ? () => _removeRow(i) : null)),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Text('Prepared by / Noted by', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.w600)),
            _f(_signatory[0], 'Prepared by (name)'),
            _f(_signatory[1], 'Prepared by (title)'),
            _f(_signatory[2], 'Noted by (name)'),
            _f(_signatory[3], 'Noted by (title)'),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _f(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
    );
  }
}

class _TurnAroundTimeList extends StatelessWidget {
  const _TurnAroundTimeList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

  final List<TurnAroundTimeEntry> entries;
  final void Function(TurnAroundTimeEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(TurnAroundTimeEntry) onPrint;
  final Future<void> Function(TurnAroundTimeEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Office')),
          DataColumn(label: Text('Applicants')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.position ?? '—')),
            DataCell(Text(e.office ?? '—')),
            DataCell(Text('${e.applicants.length}')),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete?'), content: const Text('This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete'))]));
                    if (ok == true && e.id != null) onDelete(e.id!);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            )),
          ],
        )).toList(),
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
              backgroundColor: const Color(0xFFE85D04),
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
          Text('L&D', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Learning & Development. Choose a feature below.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _RspFeatureCard(
                title: 'Training Need Analysis and Consolidated Report',
                subtitle: 'FOR CY [year], DEPARTMENT. Table: Name/Position, Goal, Behavior, Skills/Knowledge, Need for Training, Training Recommendations.',
                icon: Icons.school_rounded,
                onTap: () => setState(() => _ldSectionIndex = 1),
              ),
              _RspFeatureCard(
                title: 'Action Brainstorming and Coaching Worksheet',
                subtitle: 'DEPARTMENT, DATE. Table: Name, Stop Doing, Do Less Of, Keep Doing, Do More Of, Start Doing, Goal. Certified by Department Head.',
                icon: Icons.lightbulb_outline_rounded,
                onTap: () => setState(() => _ldSectionIndex = 2),
              ),
            ],
          ),
        ] else if (_ldSectionIndex == 1)
          const _TrainingNeedAnalysisSection()
        else
          const _ActionBrainstormingSection(),
      ],
    );
  }
}

class _TrainingNeedAnalysisSection extends StatefulWidget {
  const _TrainingNeedAnalysisSection();

  @override
  State<_TrainingNeedAnalysisSection> createState() => _TrainingNeedAnalysisSectionState();
}

class _TrainingNeedAnalysisSectionState extends State<_TrainingNeedAnalysisSection> {
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
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const TrainingNeedAnalysisEntry());
  void _edit(TrainingNeedAnalysisEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(TrainingNeedAnalysisEntry entry) async {
    try {
      if (entry.id == null) await TrainingNeedAnalysisRepo.instance.insert(entry);
      else await TrainingNeedAnalysisRepo.instance.update(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Training Need Analysis saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await TrainingNeedAnalysisRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printTna(TrainingNeedAnalysisEntry entry) async {
    try {
      final doc = FormPdf.buildTrainingNeedAnalysisPdf(entry);
      await FormPdf.printDocument(doc, name: 'Training_Need_Analysis.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadTna(TrainingNeedAnalysisEntry entry) async {
    try {
      final doc = FormPdf.buildTrainingNeedAnalysisPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Training_Need_Analysis.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Training Need Analysis and Consolidated Report', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('FOR CY [year], DEPARTMENT. Table: Name/Position, Goal, Behavior, Skills/Knowledge, Need for Training, Training Recommendations.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _TrainingNeedAnalysisFormEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printTna, onDownloadPdf: _downloadTna),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add report')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No Training Need Analysis reports yet. Tap "Add report" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else
          _TrainingNeedAnalysisList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printTna, onDownloadPdf: _downloadTna),
      ],
    );
  }
}

class _TrainingNeedAnalysisFormEditor extends StatefulWidget {
  const _TrainingNeedAnalysisFormEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final TrainingNeedAnalysisEntry entry;
  final void Function(TrainingNeedAnalysisEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(TrainingNeedAnalysisEntry) onPrint;
  final Future<void> Function(TrainingNeedAnalysisEntry) onDownloadPdf;

  @override
  State<_TrainingNeedAnalysisFormEditor> createState() => _TrainingNeedAnalysisFormEditorState();
}

class _TrainingNeedAnalysisFormEditorState extends State<_TrainingNeedAnalysisFormEditor> {
  late TextEditingController _cyYear;
  late TextEditingController _department;
  late List<Map<String, TextEditingController>> _rows;

  static Map<String, TextEditingController> _rowControllers(String namePos, String goal, String behavior, String skills, String need, String rec) {
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
        : e.rows.map((r) => _rowControllers(r.namePosition ?? '', r.goal ?? '', r.behavior ?? '', r.skillsKnowledge ?? '', r.needForTraining ?? '', r.trainingRecommendations ?? '')).toList();
  }

  @override
  void dispose() {
    _cyYear.dispose();
    _department.dispose();
    for (final row in _rows) { for (final c in row.values) c.dispose(); }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_rowControllers('', '', '', '', '', '')));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) c.dispose();
      _rows.removeAt(i);
    });
  }

  TrainingNeedAnalysisEntry _buildCurrentEntry() {
    final list = _rows.map((r) => TrainingNeedAnalysisRow(
      namePosition: r['name_position']!.text.trim().isEmpty ? null : r['name_position']!.text.trim(),
      goal: r['goal']!.text.trim().isEmpty ? null : r['goal']!.text.trim(),
      behavior: r['behavior']!.text.trim().isEmpty ? null : r['behavior']!.text.trim(),
      skillsKnowledge: r['skills_knowledge']!.text.trim().isEmpty ? null : r['skills_knowledge']!.text.trim(),
      needForTraining: r['need_for_training']!.text.trim().isEmpty ? null : r['need_for_training']!.text.trim(),
      trainingRecommendations: r['training_recommendations']!.text.trim().isEmpty ? null : r['training_recommendations']!.text.trim(),
    )).toList();
    return TrainingNeedAnalysisEntry(
      id: widget.entry.id,
      cyYear: _cyYear.text.trim().isEmpty ? null : _cyYear.text.trim(),
      department: _department.text.trim().isEmpty ? null : _department.text.trim(),
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
            Text('AND CONSOLIDATED REPORT', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextFormField(controller: _cyYear, decoration: rspUnderlinedField('FOR CY (e.g. 2025):')),
            TextFormField(controller: _department, decoration: rspUnderlinedField('DEPARTMENT:')),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Table', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add row')),
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
                      DataCell(SizedBox(width: 140, child: TextFormField(controller: r['name_position'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['goal'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['behavior'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['skills_knowledge'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 120, child: TextFormField(controller: r['need_for_training'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 140, child: TextFormField(controller: r['training_recommendations'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _rows.length > 1 ? () => _removeRow(i) : null)),
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
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingNeedAnalysisList extends StatelessWidget {
  const _TrainingNeedAnalysisList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

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
              DataCell(Text(e.cyYear ?? '—')),
              DataCell(Text(e.department ?? '—')),
              DataCell(Text('${e.rows.length}')),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                  IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                  IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete this report?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true && e.id != null) onDelete(e.id!);
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// L&D: Action Brainstorming and Coaching Worksheet — department, date, instruction, table (Name, Stop Doing, Do Less Of, Keep Doing, Do More Of, Start Doing, Goal), Certified by.
class _ActionBrainstormingSection extends StatefulWidget {
  const _ActionBrainstormingSection();

  @override
  State<_ActionBrainstormingSection> createState() => _ActionBrainstormingSectionState();
}

class _ActionBrainstormingSectionState extends State<_ActionBrainstormingSection> {
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
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _entries = []; _loading = false; });
    }
  }

  void _startNew() => setState(() => _editing = const ActionBrainstormingEntry());
  void _edit(ActionBrainstormingEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ActionBrainstormingEntry entry) async {
    try {
      if (entry.id == null) await ActionBrainstormingRepo.instance.insert(entry);
      else await ActionBrainstormingRepo.instance.update(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action Brainstorming worksheet saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await ActionBrainstormingRepo.instance.delete(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.'))); _load(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _printAb(ActionBrainstormingEntry entry) async {
    try {
      final doc = FormPdf.buildActionBrainstormingCoachingPdf(entry);
      await FormPdf.printDocument(doc, name: 'Action_Brainstorming_Coaching.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _downloadAb(ActionBrainstormingEntry entry) async {
    try {
      final doc = FormPdf.buildActionBrainstormingCoachingPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Action_Brainstorming_Coaching.pdf');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF ready to save or share.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Action Brainstorming and Coaching Worksheet', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Use the worksheet to brainstorm/coach staff on new ideas to move the department closer to department goal.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _ActionBrainstormingFormEditor(key: ValueKey(_editing?.id ?? 'new'), entry: _editing!, onSave: _onSave, onCancel: _cancelEdit, onPrint: _printAb, onDownloadPdf: _downloadAb),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(onPressed: _loading ? null : _startNew, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add worksheet')),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No worksheets yet. Tap "Add worksheet" to add one.', style: TextStyle(color: AppTheme.textSecondary)))
        else
          _ActionBrainstormingList(entries: _entries, onEdit: _edit, onDelete: _onDelete, onPrint: _printAb, onDownloadPdf: _downloadAb),
      ],
    );
  }
}

class _ActionBrainstormingFormEditor extends StatefulWidget {
  const _ActionBrainstormingFormEditor({super.key, required this.entry, required this.onSave, required this.onCancel, required this.onPrint, required this.onDownloadPdf});

  final ActionBrainstormingEntry entry;
  final void Function(ActionBrainstormingEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ActionBrainstormingEntry) onPrint;
  final Future<void> Function(ActionBrainstormingEntry) onDownloadPdf;

  @override
  State<_ActionBrainstormingFormEditor> createState() => _ActionBrainstormingFormEditorState();
}

class _ActionBrainstormingFormEditorState extends State<_ActionBrainstormingFormEditor> {
  late TextEditingController _department;
  late TextEditingController _date;
  late TextEditingController _certifiedBy;
  late TextEditingController _certificationDate;
  late List<Map<String, TextEditingController>> _rows;

  static Map<String, TextEditingController> _rowCtrl(String name, String stop, String less, String keep, String more, String start, String goal) {
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
        : e.rows.map((r) => _rowCtrl(r.name ?? '', r.stopDoing ?? '', r.doLessOf ?? '', r.keepDoing ?? '', r.doMoreOf ?? '', r.startDoing ?? '', r.goal ?? '')).toList();
    if (_rows.length < 15) while (_rows.length < 15) _rows.add(_rowCtrl('', '', '', '', '', '', ''));
  }

  @override
  void dispose() {
    _department.dispose();
    _date.dispose();
    _certifiedBy.dispose();
    _certificationDate.dispose();
    for (final row in _rows) { for (final c in row.values) c.dispose(); }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_rowCtrl('', '', '', '', '', '', '')));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) c.dispose();
      _rows.removeAt(i);
    });
  }

  ActionBrainstormingEntry _buildCurrentEntry() {
    final list = _rows.map((r) => ActionBrainstormingRow(
      name: r['name']!.text.trim().isEmpty ? null : r['name']!.text.trim(),
      stopDoing: r['stop_doing']!.text.trim().isEmpty ? null : r['stop_doing']!.text.trim(),
      doLessOf: r['do_less_of']!.text.trim().isEmpty ? null : r['do_less_of']!.text.trim(),
      keepDoing: r['keep_doing']!.text.trim().isEmpty ? null : r['keep_doing']!.text.trim(),
      doMoreOf: r['do_more_of']!.text.trim().isEmpty ? null : r['do_more_of']!.text.trim(),
      startDoing: r['start_doing']!.text.trim().isEmpty ? null : r['start_doing']!.text.trim(),
      goal: r['goal']!.text.trim().isEmpty ? null : r['goal']!.text.trim(),
    )).toList();
    return ActionBrainstormingEntry(
      id: widget.entry.id,
      department: _department.text.trim().isEmpty ? null : _department.text.trim(),
      date: _date.text.trim().isEmpty ? null : _date.text.trim(),
      rows: list,
      certifiedBy: _certifiedBy.text.trim().isEmpty ? null : _certifiedBy.text.trim(),
      certificationDate: _certificationDate.text.trim().isEmpty ? null : _certificationDate.text.trim(),
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
            const RspFormHeader(formTitle: 'ACTION BRAINSTORMING AND COACHING WORKSHEET'),
            TextFormField(controller: _department, decoration: rspUnderlinedField('DEPARTMENT:')),
            TextFormField(controller: _date, decoration: rspUnderlinedField('DATE:')),
            const SizedBox(height: 12),
            Text('Instruction: Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Table', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add row')),
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
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['name'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['stop_doing'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['do_less_of'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['keep_doing'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['do_more_of'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['start_doing'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(SizedBox(width: 100, child: TextFormField(controller: r['goal'], decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder())))),
                      DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _rows.length > 1 ? () => _removeRow(i) : null)),
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
                      Text('Certified by:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      TextFormField(controller: _certifiedBy, decoration: rspUnderlinedField('')),
                      Text('Department Head', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Date:', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      TextFormField(controller: _certificationDate, decoration: rspUnderlinedField('')),
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
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                IconButton(onPressed: () => widget.onPrint(_buildCurrentEntry()), icon: const Icon(Icons.print_rounded), tooltip: 'Print'),
                IconButton(onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Download PDF'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBrainstormingList extends StatelessWidget {
  const _ActionBrainstormingList({required this.entries, required this.onEdit, required this.onDelete, required this.onPrint, required this.onDownloadPdf});

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
              DataCell(Text(e.department ?? '—')),
              DataCell(Text(e.date ?? '—')),
              DataCell(Text('${e.rows.length}')),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => onEdit(e), child: const Text('Edit')),
                  IconButton(onPressed: () => onPrint(e), icon: const Icon(Icons.print_rounded, size: 20), tooltip: 'Print'),
                  IconButton(onPressed: () => onDownloadPdf(e), icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), tooltip: 'Download PDF'),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete this worksheet?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true && e.id != null) onDelete(e.id!);
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              )),
            ],
          );
        }).toList(),
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
