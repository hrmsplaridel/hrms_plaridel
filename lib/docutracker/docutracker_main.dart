import 'package:flutter/material.dart';
import 'docutracker_routes.dart';
import 'screens/docutracker_admin_screen.dart';
import 'screens/docutracker_dashboard_screen.dart';
import 'screens/docutracker_documents_screen.dart';
import 'theme/docutracker_tokens.dart';
import 'widgets/docutracker_module_header.dart';
import 'widgets/docutracker_responsive_body.dart';

/// Main DocuTracker module entry.
/// Sections: Dashboard, Documents, and Admin (admin only).
///
/// DocuTracker alerts are opened from the dashboard top bar (document icon + badge)
/// when this module is selected.
class DocuTrackerMain extends StatefulWidget {
  const DocuTrackerMain({super.key, this.section, this.isAdmin = false});

  /// Active section when driven by sidebar; null uses internal tabs.
  final DocuTrackerSection? section;

  /// Whether current user is admin (shows Admin section).
  final bool isAdmin;

  @override
  State<DocuTrackerMain> createState() => _DocuTrackerMainState();
}

class _DocuTrackerMainState extends State<DocuTrackerMain> {
  DocuTrackerSection _currentSection = DocuTrackerSection.dashboard;

  DocuTrackerSection get _activeSection => widget.section ?? _currentSection;

  @override
  Widget build(BuildContext context) {
    final useSidebarNav = widget.section != null;

<<<<<<< HEAD
    return ColoredBox(
      color: DocuTrackerTokens.canvas,
      child: DocuTrackerResponsiveBody(
        maxWidth: DocuTrackerTokens.maxContentWidth,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DocuTrackerModuleHeader(
              title: 'DocuTracker',
              subtitle: useSidebarNav
                  ? 'Multi-step routing, selected assignees per step, and full audit history.'
                  : 'Workflow documents, deadlines, and actions — pick a view below.',
            ),
            if (!useSidebarNav) ...[
              const SizedBox(height: 20),
              _buildSectionNav(),
            ],
            const SizedBox(height: 20),
            _buildContent(),
          ],
        ),
      ),
=======
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DocuTracker',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          useSidebarNav
              ? 'Document routing and workflow tracking.'
              : 'Document routing and workflow tracking. Choose a feature below.',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 14,
          ),
        ),
        if (!useSidebarNav) ...[const SizedBox(height: 24), _buildSectionNav()],
        const SizedBox(height: 24),
        _buildContent(),
      ],
>>>>>>> origin/main
    );
  }

  Widget _buildSectionNav() {
    final sections = <DocuTrackerSection>[
      DocuTrackerSection.dashboard,
      DocuTrackerSection.documents,
      if (widget.isAdmin) DocuTrackerSection.admin,
    ];

    if (sections.length <= 1) return const SizedBox.shrink();

<<<<<<< HEAD
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<DocuTrackerSection>(
        multiSelectionEnabled: false,
        emptySelectionAllowed: false,
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        segments: [
          for (final s in sections)
            ButtonSegment<DocuTrackerSection>(
              value: s,
              icon: Icon(_iconForSection(s), size: 18),
              label: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(s.title),
=======
    final dark = AppTheme.dashIsDark(context);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: sections.map((section) {
        final isSelected = _currentSection == section;
        final bg = isSelected
            ? (dark
                ? AppTheme.primaryNavy.withValues(alpha: 0.38)
                : AppTheme.primaryNavy.withValues(alpha: 0.12))
            : (dark
                ? AppTheme.dashMutedSurfaceOf(context)
                : AppTheme.lightGray.withValues(alpha: 0.6));
        final fg = isSelected
            ? (dark ? Colors.white : AppTheme.primaryNavy)
            : AppTheme.dashTextPrimaryOf(context);
        final iconColor = isSelected
            ? (dark ? Colors.white : AppTheme.primaryNavy)
            : AppTheme.dashTextSecondaryOf(context);

        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => setState(() => _currentSection = section),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForSection(section),
                    size: 20,
                    color: iconColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: TextStyle(
                      color: fg,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
>>>>>>> origin/main
              ),
            ),
        ],
        selected: {_currentSection},
        onSelectionChanged: (Set<DocuTrackerSection> next) {
          if (next.isEmpty) return;
          setState(() => _currentSection = next.first);
        },
      ),
    );
  }

  static IconData _iconForSection(DocuTrackerSection section) =>
      switch (section) {
        DocuTrackerSection.dashboard => Icons.dashboard_rounded,
        DocuTrackerSection.documents => Icons.description_rounded,
        DocuTrackerSection.admin => Icons.admin_panel_settings_rounded,
      };

  Widget _buildContent() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: switch (_activeSection) {
        DocuTrackerSection.dashboard => DocuTrackerDashboardScreen(
          isAdmin: widget.isAdmin,
        ),
        DocuTrackerSection.documents => DocuTrackerDocumentsScreen(
          isAdmin: widget.isAdmin,
        ),
        DocuTrackerSection.admin => const DocuTrackerAdminScreen(),
      },
    );
  }
}
