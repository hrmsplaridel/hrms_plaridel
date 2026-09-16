import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/routes/docutracker_routes.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_admin_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';

/// Main DocuTracker module entry.
/// Opens Documents directly and exposes Administration only to admins.
class DocuTrackerMain extends StatefulWidget {
  const DocuTrackerMain({
    super.key,
    this.section,
    this.isAdmin = false,
    this.tutorialHeaderKey,
    this.tutorialContentKey,
  });

  /// Active section when driven by sidebar; null uses internal navigation.
  final DocuTrackerSection? section;
  final bool isAdmin;
  final GlobalKey? tutorialHeaderKey;
  final GlobalKey? tutorialContentKey;

  @override
  State<DocuTrackerMain> createState() => _DocuTrackerMainState();
}

class _DocuTrackerMainState extends State<DocuTrackerMain> {
  DocuTrackerSection _currentSection = DocuTrackerSection.documents;

  DocuTrackerSection get _activeSection {
    final requested = widget.section ?? _currentSection;
    return requested == DocuTrackerSection.admin && !widget.isAdmin
        ? DocuTrackerSection.documents
        : requested;
  }

  @override
  Widget build(BuildContext context) {
    final useSidebarNav = widget.section != null;
    return ColoredBox(
      color: AppTheme.dashCanvasOf(context),
      child: DocuTrackerResponsiveBody(
        maxWidth: 1680,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(key: widget.tutorialHeaderKey, child: _buildHeader()),
            if (!useSidebarNav && widget.isAdmin) ...[
              const SizedBox(height: 20),
              _buildSectionNav(),
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

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'DocuTracker',
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Create, route, and track official documents.',
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 14,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _buildSectionNav() {
    final sections = <DocuTrackerSection>[
      DocuTrackerSection.documents,
      if (widget.isAdmin) DocuTrackerSection.admin,
    ];
    if (sections.length <= 1) return const SizedBox.shrink();

    final dark = AppTheme.dashIsDark(context);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: sections.map((section) {
        final selected = _currentSection == section;
        final background = selected
            ? AppTheme.primaryNavy.withValues(alpha: dark ? 0.38 : 0.12)
            : (dark
                  ? AppTheme.dashMutedSurfaceOf(context)
                  : AppTheme.lightGray);
        final foreground = selected
            ? (dark ? Colors.white : AppTheme.primaryNavy)
            : AppTheme.dashTextPrimaryOf(context);
        return Material(
          color: background,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => setState(() => _currentSection = section),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconForSection(section), size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

  static IconData _iconForSection(DocuTrackerSection section) =>
      switch (section) {
        DocuTrackerSection.documents => Icons.description_rounded,
        DocuTrackerSection.admin => Icons.admin_panel_settings_rounded,
      };

  Widget _buildContent() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 200),
    child: switch (_activeSection) {
      DocuTrackerSection.documents => DocuTrackerDocumentsScreen(
        isAdmin: widget.isAdmin,
        showHeader: false,
      ),
      DocuTrackerSection.admin => const DocuTrackerAdminScreen(),
    },
  );
}
