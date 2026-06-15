import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_need_analysis.dart';
import 'package:hrms_plaridel/shared/widgets/feature_card.dart';

class LdHubFeature {
  const LdHubFeature({
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

const _ldHubFeatures = <LdHubFeature>[
  LdHubFeature(
    category: 'Planning & analysis',
    title: 'Training Need Analysis',
    subtitle:
        'Consolidate CY training needs by department: goals, skill gaps, and recommendations.',
    icon: Icons.school_rounded,
    sectionIndex: 1,
  ),
  LdHubFeature(
    category: 'Planning & analysis',
    title: 'Action Brainstorming Worksheet',
    subtitle:
        'Coaching actions per employee: stop/start behaviors, goals, and department certification.',
    icon: Icons.lightbulb_outline_rounded,
    sectionIndex: 2,
  ),
  LdHubFeature(
    category: 'Employee development',
    title: 'Individual Development Plan (IDP)',
    subtitle:
        'Record qualifications, succession analysis, and employee development actions.',
    icon: Icons.trending_up_rounded,
    sectionIndex: 4,
  ),
  LdHubFeature(
    category: 'Monitoring',
    title: 'Training Daily Reports',
    subtitle:
        'Review daily training submissions from employees, open attachments, and mark as seen.',
    icon: Icons.assignment_turned_in_outlined,
    sectionIndex: 3,
  ),
  LdHubFeature(
    category: 'Monitoring',
    title: 'Training Requirements',
    subtitle:
        'Monitor pre-training (invitation letter) and post-training (LAP, certificates) submissions.',
    icon: Icons.fact_check_outlined,
    sectionIndex: 5,
  ),
];

/// Enhanced L&D hub: hero banner, live stats, search, and grouped feature cards.
class LdAdminHub extends StatefulWidget {
  const LdAdminHub({super.key, required this.onOpenSection});

  final ValueChanged<int> onOpenSection;

  @override
  State<LdAdminHub> createState() => _LdAdminHubState();
}

class _LdAdminHubState extends State<LdAdminHub> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _statsLoading = true;
  int _savedForms = 0;
  int _dailyReports = 0;
  int _pendingReports = 0;

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
    setState(() => _statsLoading = true);
    try {
      final tna = await TrainingNeedAnalysisRepo.instance.list();
      final abc = await ActionBrainstormingRepo.instance.list();
      final idp = await IdpRepo.instance.list();
      final reports = await TrainingDailyReportRepo.instance.listAllReports();
      if (!mounted) return;
      setState(() {
        _savedForms = tna.length + abc.length + idp.length;
        _dailyReports = reports.length;
        _pendingReports =
            reports.where((r) => r.status == 'submitted').length;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _statsLoading = false);
    }
  }

  bool _matches(LdHubFeature f) {
    if (_query.isEmpty) return true;
    final hay = '${f.title} ${f.subtitle} ${f.category}'.toLowerCase();
    return hay.contains(_query);
  }

  List<LdHubFeature> get _filtered =>
      _ldHubFeatures.where(_matches).toList(growable: false);

  Map<String, List<LdHubFeature>> get _grouped {
    final map = <String, List<LdHubFeature>>{};
    for (final f in _filtered) {
      map.putIfAbsent(f.category, () => []).add(f);
    }
    return map;
  }

  static const _categoryOrder = [
    'Planning & analysis',
    'Employee development',
    'Monitoring',
  ];

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final hasResults = _filtered.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LdHubHeroBanner(
          statsLoading: _statsLoading,
          featureCount: _ldHubFeatures.length,
          savedForms: _savedForms,
          dailyReports: _dailyReports,
          pendingReports: _pendingReports,
          onRefresh: _loadStats,
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search L&D features…',
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
                    'No L&D features match "$_query". Try training, IDP, coaching, or reports.',
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
              _LdHubCategoryHeader(
                title: category,
                count: grouped[category]!.length,
              ),
              const SizedBox(height: 12),
              FeatureCardGrid(
                cardHeight: 248,
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

class _LdHubHeroBanner extends StatelessWidget {
  const _LdHubHeroBanner({
    required this.statsLoading,
    required this.featureCount,
    required this.savedForms,
    required this.dailyReports,
    required this.pendingReports,
    required this.onRefresh,
  });

  final bool statsLoading;
  final int featureCount;
  final int savedForms;
  final int dailyReports;
  final int pendingReports;
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
                  const Color(0xFFFFF5EE),
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
                    colors: [Color(0xFFE85D04), Color(0xFFFF8A50)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE85D04).withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
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
                        color: const Color(0xFFE85D04).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFE85D04).withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Text(
                        'Learning · Development · Coaching',
                        style: TextStyle(
                          color: Color(0xFFC2410C),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'L&D Hub',
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
                      'Plan training needs, coach employees, track IDPs, and monitor daily training reports.',
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
              _LdHubStatChip(
                label: 'Features',
                value: '$featureCount',
                icon: Icons.grid_view_rounded,
                color: AppTheme.primaryNavy,
              ),
              _LdHubStatChip(
                label: 'Saved forms',
                value: statsLoading ? '…' : '$savedForms',
                icon: Icons.folder_open_rounded,
                color: const Color(0xFF1565C0),
              ),
              _LdHubStatChip(
                label: 'Daily reports',
                value: statsLoading ? '…' : '$dailyReports',
                icon: Icons.assignment_outlined,
                color: const Color(0xFF6A1B9A),
              ),
              _LdHubStatChip(
                label: 'Awaiting review',
                value: statsLoading ? '…' : '$pendingReports',
                icon: Icons.mark_email_unread_outlined,
                color: pendingReports > 0
                    ? const Color(0xFFE85D04)
                    : AppTheme.dashTextSecondaryOf(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LdHubStatChip extends StatelessWidget {
  const _LdHubStatChip({
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

class _LdHubCategoryHeader extends StatelessWidget {
  const _LdHubCategoryHeader({required this.title, required this.count});

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
            color: const Color(0xFFE85D04),
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
            color: const Color(0xFFE85D04).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFFC2410C),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
