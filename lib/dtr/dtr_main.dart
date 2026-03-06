import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import 'dtr_routes.dart';
import 'screens/dtr_time_logs.dart';
import 'screens/dtr_reports.dart';

/// Main DTR (Daily Time Record) module entry.
/// When [section] is provided (from sidebar), shows only that section without tabs.
/// When [section] is null, falls back to internal tab navigation.
class DtrMain extends StatefulWidget {
  const DtrMain({super.key, this.section});

  /// Active section when driven by sidebar; null uses internal tabs.
  final DtrSection? section;

  @override
  State<DtrMain> createState() => _DtrMainState();
}

class _DtrMainState extends State<DtrMain> {
  DtrSection _currentSection = DtrSection.timeLogs;

  DtrSection get _activeSection => widget.section ?? _currentSection;

  @override
  Widget build(BuildContext context) {
    final useSidebarNav = widget.section != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DTR',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          useSidebarNav
              ? 'Daily Time Record.'
              : 'Daily Time Record. Choose a feature below.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        if (!useSidebarNav) ...[
          const SizedBox(height: 24),
          _buildSectionNav(),
        ],
        const SizedBox(height: 24),
        _buildContent(),
      ],
    );
  }

  Widget _buildSectionNav() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: DtrRoutes.sections.map((section) {
        final isSelected = _currentSection == section;
        return Material(
          color: isSelected
              ? AppTheme.primaryNavy.withOpacity(0.12)
              : AppTheme.lightGray,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => setState(() => _currentSection = section),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForSection(section),
                    size: 20,
                    color: isSelected
                        ? AppTheme.primaryNavy
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryNavy
                          : AppTheme.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  static IconData _iconForSection(DtrSection section) => switch (section) {
        DtrSection.timeLogs => Icons.schedule_rounded,
        DtrSection.reports => Icons.summarize_rounded,
      };

  Widget _buildContent() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: switch (_activeSection) {
        DtrSection.timeLogs => const DtrTimeLogs(),
        DtrSection.reports => const DtrReports(),
      },
    );
  }
}
