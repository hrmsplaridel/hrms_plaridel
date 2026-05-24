import 'package:flutter/material.dart';
import '../landingpage/constants/app_theme.dart';
import 'docutracker_routes.dart';
import 'screens/docutracker_admin_screen.dart';
import 'screens/docutracker_documents_screen.dart';

/// Main DocuTracker module entry.
/// Sections: Documents, Admin (for privilege management).
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
  DocuTrackerSection _currentSection = DocuTrackerSection.documents;

  DocuTrackerSection get _activeSection => widget.section ?? _currentSection;

  @override
  Widget build(BuildContext context) {
    final useSidebarNav = widget.section != null;

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
    );
  }

  Widget _buildSectionNav() {
    final sections = widget.isAdmin
        ? [DocuTrackerSection.documents, DocuTrackerSection.admin]
        : [DocuTrackerSection.documents];

    if (sections.length <= 1) return const SizedBox.shrink();

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
                  Icon(_iconForSection(section), size: 20, color: iconColor),
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
              ),
            ),
          ),
        );
      }).toList(),
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
        DocuTrackerSection.documents => DocuTrackerDocumentsScreen(
          isAdmin: widget.isAdmin,
        ),
        DocuTrackerSection.admin => const DocuTrackerAdminScreen(),
        DocuTrackerSection.dashboard => DocuTrackerDocumentsScreen(
          isAdmin: widget.isAdmin,
        ),
      },
    );
  }
}
