import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/routes/docutracker_routes.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_admin_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_dashboard_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_module_header.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';

/// Main DocuTracker module entry.
/// Sections: Dashboard, Documents, and Admin (admin only).
///
/// DocuTracker alerts are opened from the dashboard top bar (document icon + badge)
/// when this module is selected.
class DocuTrackerMain extends StatefulWidget {
  const DocuTrackerMain({
    super.key,
    this.section,
    this.isAdmin = false,
    this.tutorialHeaderKey,
    this.tutorialNavigationKey,
    this.tutorialContentKey,
  });

  /// Active section when driven by sidebar; null uses internal tabs.
  final DocuTrackerSection? section;

  /// Whether current user is admin (shows Admin section).
  final bool isAdmin;
  final GlobalKey? tutorialHeaderKey;
  final GlobalKey? tutorialNavigationKey;
  final GlobalKey? tutorialContentKey;

  @override
  State<DocuTrackerMain> createState() => _DocuTrackerMainState();
}

class _DocuTrackerMainState extends State<DocuTrackerMain> {
  DocuTrackerSection _currentSection = DocuTrackerSection.dashboard;

  DocuTrackerSection get _activeSection => widget.section ?? _currentSection;

  @override
  Widget build(BuildContext context) {
    final useSidebarNav = widget.section != null;

    return ColoredBox(
      color: DocuTrackerTokens.canvasOf(context),
      child: DocuTrackerResponsiveBody(
        maxWidth: DocuTrackerTokens.maxContentWidth,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: widget.tutorialHeaderKey,
              child: DocuTrackerModuleHeader(
                title: 'DocuTracker',
                subtitle: useSidebarNav
                    ? 'Multi-step routing, selected assignees per step, and full audit history.'
                    : 'Workflow documents, deadlines, and actions — pick a view below.',
              ),
            ),
            if (!useSidebarNav) ...[
              const SizedBox(height: 20),
              KeyedSubtree(
                key: widget.tutorialNavigationKey,
                child: _buildSectionNav(),
              ),
            ],
            const SizedBox(height: 20),
            KeyedSubtree(
              key: widget.tutorialContentKey,
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionNav() {
    final sections = <DocuTrackerSection>[
      DocuTrackerSection.dashboard,
      DocuTrackerSection.documents,
      if (widget.isAdmin) DocuTrackerSection.admin,
    ];

    if (sections.length <= 1) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<DocuTrackerSection>(
        multiSelectionEnabled: false,
        emptySelectionAllowed: false,
        showSelectedIcon: false,
        style: DocuTrackerTokens.sectionNavStyle(context),
        segments: [
          for (final s in sections)
            ButtonSegment<DocuTrackerSection>(
              value: s,
              icon: Icon(_iconForSection(s), size: 18),
              label: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(s.title),
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
