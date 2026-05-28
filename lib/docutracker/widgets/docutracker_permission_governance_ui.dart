import 'package:flutter/material.dart';

import '../models/document_action.dart';
import '../theme/docutracker_tokens.dart';
import 'docutracker_press_scale.dart';

/// Warm governance shell for the permission editor (mockup-aligned).
class DocuTrackerPermissionGovernanceHeader extends StatelessWidget {
  const DocuTrackerPermissionGovernanceHeader({
    super.key,
    required this.onBack,
    required this.selectedTab,
    required this.onTabSelected,
  });

  final VoidCallback onBack;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;

  static const _tabs = ['Role Governance', 'User Override', 'Effective Preview'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTabs = constraints.maxWidth < 720;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: DocuTrackerTokens.textPrimaryOf(context),
                  tooltip: 'Back',
                ),
                Expanded(
                  child: Text(
                    'Permissions Governance',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: DocuTrackerTokens.textPrimaryOf(context),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: RichText(
                text: TextSpan(
                  style: DocuTrackerTokens.subtitleStyle(context).copyWith(height: 1.45),
                  children: const [
                    TextSpan(
                      text:
                          'Define role-based access control (RBAC) for document lifecycles. '
                          'Changes here apply to all users in the selected role unless ',
                    ),
                    TextSpan(
                      text: 'overridden at individual user levels',
                      style: TextStyle(
                        color: DocuTrackerTokens.brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        );

        final tabStrip = DocuTrackerPermissionGovernanceTabStrip(
          labels: _tabs,
          selectedIndex: selectedTab,
          onSelected: onTabSelected,
        );

        if (stackTabs) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 14),
              tabStrip,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            tabStrip,
          ],
        );
      },
    );
  }
}

class DocuTrackerPermissionGovernanceTabStrip extends StatelessWidget {
  const DocuTrackerPermissionGovernanceTabStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: DocuTrackerTokens.borderSubtle),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < labels.length; i++)
            DocuTrackerPressScale(
              pressedScale: 0.98,
              child: Material(
                color: selectedIndex == i
                    ? DocuTrackerTokens.highlightPeach
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: () => onSelected(i),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: selectedIndex == i
                          ? Border.all(
                              color: DocuTrackerTokens.brand.withValues(
                                alpha: 0.45,
                              ),
                            )
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selectedIndex == i
                            ? DocuTrackerTokens.brand
                            : DocuTrackerTokens.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DocuTrackerPermissionGovernanceTypeFilter extends StatelessWidget {
  const DocuTrackerPermissionGovernanceTypeFilter({
    super.key,
    required this.selectedType,
    required this.typeLabels,
    required this.onTypeSelected,
    required this.onReload,
    this.loading = false,
  });

  final String selectedType;
  final List<({String value, String label})> typeLabels;
  final ValueChanged<String> onTypeSelected;
  final VoidCallback onReload;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: DocuTrackerTokens.cardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackReload = constraints.maxWidth < 640;
          final pills = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Filter by Type:',
                style: DocuTrackerTokens.metaStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              for (final t in typeLabels)
                _TypePill(
                  label: t.label,
                  selected: selectedType == t.value,
                  onTap: loading ? null : () => onTypeSelected(t.value),
                ),
            ],
          );

          final reload = DocuTrackerPressScale(
            child: TextButton.icon(
              onPressed: loading ? null : onReload,
              icon: Icon(
                Icons.refresh_rounded,
                size: 18,
                color: DocuTrackerTokens.brand.withValues(
                  alpha: loading ? 0.4 : 1,
                ),
              ),
              label: Text(
                'Reload Policy',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: DocuTrackerTokens.brand.withValues(
                    alpha: loading ? 0.4 : 1,
                  ),
                ),
              ),
            ),
          );

          if (stackReload) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                pills,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: reload),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: pills),
              reload,
            ],
          );
        },
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DocuTrackerTokens.brand : DocuTrackerTokens.surfaceCream,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : DocuTrackerTokens.brand,
            ),
          ),
        ),
      ),
    );
  }
}

/// Role × action matrix with accent bars and orange toggles.
class DocuTrackerPermissionGovernanceMatrix extends StatelessWidget {
  const DocuTrackerPermissionGovernanceMatrix({
    super.key,
    required this.roleIds,
    required this.roleTitle,
    required this.roleDescription,
    required this.roleAccentColor,
    required this.actions,
    required this.draftByRole,
    required this.enabled,
    required this.onToggle,
    this.footerText,
    this.onAddRole,
  });

  final List<String> roleIds;
  final String Function(String canonicalRole) roleTitle;
  final String Function(String canonicalRole) roleDescription;
  final Color Function(String canonicalRole) roleAccentColor;
  final List<DocumentAction> actions;
  final Map<String, Map<String, bool>> draftByRole;
  final bool enabled;
  final void Function(String roleLabel, DocumentAction action, bool value)
  onToggle;
  final String? footerText;
  final VoidCallback? onAddRole;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DocuTrackerTokens.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            color: DocuTrackerTokens.highlightPeach.withValues(alpha: 0.55),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'ROLE ENTITY',
                    style: DocuTrackerTokens.metaStyle(context).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: DocuTrackerTokens.textSecondary,
                    ),
                  ),
                ),
                for (final a in actions)
                  Expanded(
                    child: Text(
                      _columnLabel(a),
                      textAlign: TextAlign.center,
                      style: DocuTrackerTokens.metaStyle(context).copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.35,
                        color: DocuTrackerTokens.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < roleIds.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: DocuTrackerTokens.borderSubtle.withValues(alpha: 0.8),
              ),
            _RoleMatrixRow(
              accentColor: roleAccentColor(roleIds[i]),
              title: roleTitle(roleIds[i]),
              description: roleDescription(roleIds[i]),
              actions: actions,
              grantedByAction: draftByRole[roleIds[i]] ?? const {},
              enabled: enabled,
              onToggle: (action, v) => onToggle(roleIds[i], action, v),
            ),
          ],
          if (footerText != null || onAddRole != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              color: DocuTrackerTokens.highlightPeach.withValues(alpha: 0.35),
              child: Row(
                children: [
                  if (footerText != null)
                    Expanded(
                      child: Text(
                        footerText!,
                        style: DocuTrackerTokens.metaStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (onAddRole != null)
                    TextButton(
                      onPressed: onAddRole,
                      child: const Text(
                        '+ Add custom role',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: DocuTrackerTokens.brand,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _columnLabel(DocumentAction action) {
    return switch (action) {
      DocumentAction.view => 'VIEW',
      DocumentAction.createDraft => 'CREATE DRAFT',
      DocumentAction.download => 'DOWNLOAD',
      DocumentAction.submit => 'SUBMIT',
      DocumentAction.delete => 'DELETE',
      _ => action.displayName.toUpperCase(),
    };
  }
}

class _RoleMatrixRow extends StatelessWidget {
  const _RoleMatrixRow({
    required this.accentColor,
    required this.title,
    required this.description,
    required this.actions,
    required this.grantedByAction,
    required this.enabled,
    required this.onToggle,
  });

  final Color accentColor;
  final String title;
  final String description;
  final List<DocumentAction> actions;
  final Map<String, bool> grantedByAction;
  final bool enabled;
  final void Function(DocumentAction action, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: accentColor),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: DocuTrackerTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: DocuTrackerTokens.metaStyle(context).copyWith(height: 1.3),
                  ),
                ],
              ),
            ),
          ),
          for (final a in actions)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: DocuTrackerPermissionGovernanceToggle(
                    value: grantedByAction[a.name] ?? false,
                    onChanged: enabled ? (v) => onToggle(a, v) : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DocuTrackerPermissionGovernanceToggle extends StatelessWidget {
  const DocuTrackerPermissionGovernanceToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: DocuTrackerTokens.brand,
          activeThumbColor: Colors.white,
          inactiveTrackColor: DocuTrackerTokens.brandSoft,
          inactiveThumbColor: Colors.white,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Text(
          value ? 'ALLOW' : 'DENY',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: value ? DocuTrackerTokens.brand : DocuTrackerTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class DocuTrackerPermissionGovernanceSidebar extends StatelessWidget {
  const DocuTrackerPermissionGovernanceSidebar({
    super.key,
    this.onViewAuditLog,
  });

  final VoidCallback? onViewAuditLog;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF3D2C24),
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.brand.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: DocuTrackerTokens.brandMuted,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Security Insight',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Applying the "Least Privilege" principle ensures users only have access to data required for their specific job function.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: onViewAuditLog,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: DocuTrackerTokens.brandMuted,
                ),
                child: const Text(
                  'View Audit Log →',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.highlightPeach.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
            border: Border.all(color: DocuTrackerTokens.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Role Summaries',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              _SummaryLine(
                color: DocuTrackerTokens.brand,
                title: 'High Clearance',
                subtitle: 'Admin, Executives',
              ),
              const SizedBox(height: 10),
              _SummaryLine(
                color: DocuTrackerTokens.escalatedBlue,
                title: 'Standard Access',
                subtitle: 'HR, Supervisors',
              ),
              const SizedBox(height: 10),
              _SummaryLine(
                color: DocuTrackerTokens.textMuted,
                title: 'Limited Review',
                subtitle: 'Employees, Guests',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 32,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              Text(subtitle, style: DocuTrackerTokens.metaStyle(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class DocuTrackerPermissionGovernanceFooter extends StatelessWidget {
  const DocuTrackerPermissionGovernanceFooter({
    super.key,
    required this.pendingChanges,
    required this.lastSavedLabel,
    required this.onReset,
    required this.onSave,
    this.loading = false,
  });

  final int pendingChanges;
  final String lastSavedLabel;
  final VoidCallback? onReset;
  final VoidCallback? onSave;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surface,
        border: Border(
          top: BorderSide(color: DocuTrackerTokens.borderSubtle),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 560;
          final status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    color: DocuTrackerTokens.textMuted.withValues(alpha: 0.85),
                    size: 22,
                  ),
                  if (pendingChanges > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: DocuTrackerTokens.brand,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pendingChanges > 0
                          ? '$pendingChanges unsaved change${pendingChanges == 1 ? '' : 's'} pending'
                          : 'No unsaved changes',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: DocuTrackerTokens.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      lastSavedLabel,
                      style: DocuTrackerTokens.metaStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: loading ? null : onReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: DocuTrackerTokens.textPrimaryOf(context),
                  side: const BorderSide(color: DocuTrackerTokens.borderStrong),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: loading ? null : onSave,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Save changes'),
                style: DocuTrackerTokens.brandFilledStyle().copyWith(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          );

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: status),
              actions,
            ],
          );
        },
      ),
    );
  }
}
