import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../landingpage/constants/app_theme.dart';
import '../providers/auth_provider.dart';
import 'docutracker_provider.dart';
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
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          useSidebarNav
              ? 'Document routing and workflow tracking.'
              : 'Document routing and workflow tracking. Choose a feature below.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: sections.map((section) {
        final isSelected = _currentSection == section;
        return Material(
          color: isSelected
              ? AppTheme.primaryNavy.withOpacity(0.12)
              : AppTheme.lightGray.withOpacity(0.6),
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
