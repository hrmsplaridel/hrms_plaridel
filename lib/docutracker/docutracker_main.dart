import 'package:flutter/material.dart';
import 'docutracker_routes.dart';
import 'screens/docutracker_admin_screen.dart';
import 'screens/docutracker_dashboard_screen.dart';
import 'screens/docutracker_documents_screen.dart';
import 'screens/mobile_employee_portal.dart';
import 'services/docutracker_access_policy.dart';
import 'theme/docutracker_tokens.dart';
import 'widgets/docutracker_module_header.dart';
import 'widgets/responsive_layout.dart';
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
    return ResponsiveLayout(
      mobileBreakpoint: DocuTrackerAccessPolicy.mobileBreakpoint,
      desktop: _buildDesktopLayout(),
      // Enforce restricted mobile experience for both admins and employees.
      mobile: const MobileEmployeePortal(),
    );
  }

  Widget _buildDesktopLayout() {
    final useSidebarNav = widget.section != null;

    return ColoredBox(
      color: DocuTrackerTokens.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPad = constraints.maxWidth >= 1400 ? 16.0 : 20.0;
          return DocuTrackerResponsiveBody(
            maxWidth: DocuTrackerTokens.maxContentWidth,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DocuTrackerModuleHeader(
                  title: 'DocuTracker',
                  subtitle: useSidebarNav
                      ? 'Multi-step routing, selected assignees per step, and full audit history.'
                      : 'Workflow documents, deadlines, and actions — pick a view below.',
                  trailing: useSidebarNav ? null : _buildSectionNav(),
                ),
                const SizedBox(height: 20),
                _buildContent(),
              ],
            ),
          );
        },
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (final s in sections)
          _SectionPill(
            label: s.title,
            icon: _iconForSection(s),
            selected: _currentSection == s,
            onTap: () => setState(() => _currentSection = s),
          ),
      ],
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
        DocuTrackerSection.admin =>
          widget.isAdmin
              ? const DocuTrackerAdminScreen()
              : const DocuTrackerDocumentsScreen(isAdmin: false),
      },
    );
  }
}

class _SectionPill extends StatelessWidget {
  const _SectionPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DocuTrackerTokens.brand : DocuTrackerTokens.surfaceCream,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : DocuTrackerTokens.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : DocuTrackerTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
