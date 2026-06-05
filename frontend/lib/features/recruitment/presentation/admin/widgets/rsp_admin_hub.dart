import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/shared/widgets/feature_card.dart';

class RspHubFeature {
  const RspHubFeature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sectionIndex,
    required this.category,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int sectionIndex;
  final String category;
}

const _rspHubFeatures = <RspHubFeature>[
  RspHubFeature(
    category: 'Recruitment',
    title: 'Job Vacancies (Landing Page)',
    subtitle: 'Edit the announcement shown on the landing page.',
    icon: Icons.work_rounded,
    sectionIndex: 1,
  ),
  RspHubFeature(
    category: 'Recruitment',
    title: 'Applications',
    subtitle: 'View applicants, attachments, and document review status.',
    icon: Icons.assignment_rounded,
    sectionIndex: 2,
  ),
  RspHubFeature(
    category: 'Recruitment',
    title: 'Exam Results',
    subtitle: 'View screening exam scores, grade BEI, and pass/fail results.',
    icon: Icons.fact_check_rounded,
    sectionIndex: 16,
  ),
  RspHubFeature(
    category: 'Recruitment',
    title: 'Scheduling',
    subtitle:
        'Deliberation for exam passers and orientation after final requirements are approved.',
    icon: Icons.calendar_month_rounded,
    sectionIndex: 15,
  ),
  RspHubFeature(
    category: 'Recruitment',
    title: 'Final Requirements',
    subtitle:
        'Review medical certificate, drug test, and NBI clearance — then create account and email credentials.',
    icon: Icons.health_and_safety_rounded,
    sectionIndex: 19,
  ),
  RspHubFeature(
    category: 'Exams & screening',
    title: 'BEI / Exam Questions',
    subtitle:
        'View and edit the 8 Behavioral Event Interview questions applicants answer.',
    icon: Icons.quiz_rounded,
    sectionIndex: 3,
  ),
  RspHubFeature(
    category: 'Exams & screening',
    title: 'General Exam (LGU-Plaridel)',
    subtitle:
        'View and edit the General Exam multiple-choice questions for applicants.',
    icon: Icons.assignment_turned_in_rounded,
    sectionIndex: 4,
  ),
  RspHubFeature(
    category: 'Exams & screening',
    title: 'Mathematics Exam',
    subtitle: 'View and edit the Mathematics exam questions for applicants.',
    icon: Icons.calculate_rounded,
    sectionIndex: 5,
  ),
  RspHubFeature(
    category: 'Exams & screening',
    title: 'General Information Exam',
    subtitle:
        'View and edit the General Information exam questions for applicants.',
    icon: Icons.info_outline_rounded,
    sectionIndex: 6,
  ),
  RspHubFeature(
    category: 'Forms & records',
    title: 'Background Investigation (BI Form)',
    subtitle:
        'Record BI form entries: applicant, respondent, and competency ratings.',
    icon: Icons.verified_user_rounded,
    sectionIndex: 7,
  ),
  RspHubFeature(
    category: 'Forms & records',
    title: 'Applicants Profile',
    subtitle:
        'Job vacancy details and list of applicants (name, course, address, sex, age, civil status, remark).',
    icon: Icons.people_alt_rounded,
    sectionIndex: 10,
  ),
  RspHubFeature(
    category: 'Forms & records',
    title: 'Selection Line-Up',
    subtitle:
        'Date, agency/office, vacant position, item no., and applicants table.',
    icon: Icons.format_list_numbered_rounded,
    sectionIndex: 13,
  ),
  RspHubFeature(
    category: 'Forms & records',
    title: 'Computation of Points',
    subtitle:
        'Personnel Selection Board scoring: education, eligibility, experience, training, and ranking.',
    icon: Icons.calculate_rounded,
    sectionIndex: 17,
  ),
  RspHubFeature(
    category: 'Forms & records',
    title: 'Work Experience Sheet',
    subtitle:
        'Position, department, minimum standards, job description of last work, and applicant signature.',
    icon: Icons.work_history_rounded,
    sectionIndex: 18,
  ),
  RspHubFeature(
    category: 'Forms & records',
    title: 'Turn Around Time',
    subtitle:
        'Position, office, dates, and applicant tracking through hiring milestones.',
    icon: Icons.schedule_rounded,
    sectionIndex: 14,
  ),
];

/// Enhanced RSP hub: hero banner, live stats, search, and grouped feature cards.
class RspAdminHub extends StatefulWidget {
  const RspAdminHub({super.key, required this.onOpenSection});

  final ValueChanged<int> onOpenSection;

  @override
  State<RspAdminHub> createState() => _RspAdminHubState();
}

class _RspAdminHubState extends State<RspAdminHub> {
  final _searchController = TextEditingController();
  String _query = '';
  int _totalApplicants = 0;
  int _pendingReview = 0;
  bool _hiringOpen = false;
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      final announcement = await JobVacancyAnnouncementRepo.instance.fetch();
      if (!mounted) return;
      setState(() {
        _totalApplicants = apps.length;
        _pendingReview = apps.where((a) => a.status == 'submitted').length;
        _hiringOpen = announcement.hasVacancies;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _statsLoading = false);
    }
  }

  bool _matches(RspHubFeature f) {
    if (_query.isEmpty) return true;
    final hay = '${f.title} ${f.subtitle} ${f.category}'.toLowerCase();
    return hay.contains(_query);
  }

  List<RspHubFeature> get _filtered =>
      _rspHubFeatures.where(_matches).toList(growable: false);

  Map<String, List<RspHubFeature>> get _grouped {
    final map = <String, List<RspHubFeature>>{};
    for (final f in _filtered) {
      map.putIfAbsent(f.category, () => []).add(f);
    }
    return map;
  }

  static const _categoryOrder = [
    'Recruitment',
    'Exams & screening',
    'Forms & records',
  ];

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final hasResults = _filtered.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RspHubHeroBanner(
          statsLoading: _statsLoading,
          totalApplicants: _totalApplicants,
          pendingReview: _pendingReview,
          hiringOpen: _hiringOpen,
          featureCount: _rspHubFeatures.length,
          onRefresh: _loadStats,
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search RSP features…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => _searchController.clear(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
            filled: true,
            fillColor: AppTheme.dashMutedSurfaceOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppTheme.dashHairlineOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppTheme.dashHairlineOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppTheme.primaryNavy,
                width: 1.5,
              ),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (!hasResults)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No RSP features match "$_query". Try recruitment, exam, promotion, or forms.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final category in _categoryOrder)
            if (grouped.containsKey(category)) ...[
              _RspHubCategoryHeader(
                title: category,
                count: grouped[category]!.length,
              ),
              const SizedBox(height: 12),
              FeatureCardGrid(
                cardHeight: 268,
                children: [
                  for (final f in grouped[category]!)
                    FeatureCard(
                      title: f.title,
                      subtitle: f.subtitle,
                      icon: f.icon,
                      showActionArrow: true,
                      onTap: () => widget.onOpenSection(f.sectionIndex),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
      ],
    );
  }
}

class _RspHubHeroBanner extends StatelessWidget {
  const _RspHubHeroBanner({
    required this.statsLoading,
    required this.totalApplicants,
    required this.pendingReview,
    required this.hiringOpen,
    required this.featureCount,
    required this.onRefresh,
  });

  final bool statsLoading;
  final int totalApplicants;
  final int pendingReview;
  final bool hiringOpen;
  final int featureCount;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF252D3D), const Color(0xFF1E2430)]
              : [
                  const Color(0xFFFFF8F3),
                  Colors.white,
                  const Color(0xFFF8FAFF),
                ],
        ),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: dark ? 0.25 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.15),
                        ),
                      ),
                      child: const Text(
                        'Recruitment · Selection · Placement',
                        style: TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'RSP Hub',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage hiring, exams, applicant records, and promotion board workflows.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh stats',
                onPressed: statsLoading ? null : onRefresh,
                icon: statsLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                color: AppTheme.primaryNavy,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _RspHubStatChip(
                label: 'Features',
                value: '$featureCount',
                icon: Icons.grid_view_rounded,
                color: AppTheme.primaryNavy,
              ),
              _RspHubStatChip(
                label: 'Applicants',
                value: statsLoading ? '…' : '$totalApplicants',
                icon: Icons.people_outline_rounded,
                color: const Color(0xFF1565C0),
              ),
              _RspHubStatChip(
                label: 'Pending review',
                value: statsLoading ? '…' : '$pendingReview',
                icon: Icons.hourglass_top_rounded,
                color: const Color(0xFF6A1B9A),
              ),
              _RspHubStatChip(
                label: 'Hiring',
                value: statsLoading ? '…' : (hiringOpen ? 'Open' : 'Closed'),
                icon: Icons.campaign_outlined,
                color: hiringOpen
                    ? const Color(0xFF2E7D32)
                    : AppTheme.dashTextSecondaryOf(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RspHubStatChip extends StatelessWidget {
  const _RspHubStatChip({
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
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RspHubCategoryHeader extends StatelessWidget {
  const _RspHubCategoryHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
