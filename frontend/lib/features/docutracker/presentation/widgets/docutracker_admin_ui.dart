import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_action.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_permission.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'docutracker_press_scale.dart';

/// Section header: title + subtitle left, optional trailing actions right.
class DocuTrackerAdminSectionHeader extends StatelessWidget {
  const DocuTrackerAdminSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTrailing = constraints.maxWidth < 480 && trailing != null;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: DocuTrackerTokens.textPrimaryOf(context),
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: DocuTrackerTokens.subtitleStyle(context)),
          ],
        );

        if (!stackTrailing) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBlock,
            if (trailing != null) ...[const SizedBox(height: 12), trailing!],
          ],
        );
      },
    );
  }
}

/// Primary admin CTA (signature orange, pill shape).
class DocuTrackerAdminPrimaryButton extends StatelessWidget {
  const DocuTrackerAdminPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DocuTrackerPressScale(
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon ?? Icons.add_circle_outline, size: 20),
        label: Text(label),
        style: DocuTrackerTokens.brandFilledStyle().copyWith(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
    );
  }
}

/// Secondary peach tonal button (e.g. Audit Logs).
class DocuTrackerAdminTonalButton extends StatelessWidget {
  const DocuTrackerAdminTonalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DocuTrackerPressScale(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.history_rounded, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: DocuTrackerTokens.textPrimaryOf(context),
          backgroundColor: DocuTrackerTokens.highlightPeach,
          side: const BorderSide(color: DocuTrackerTokens.highlightPeachBorder),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

/// Filter pill (e.g. "All Roles").
class DocuTrackerAdminFilterPill extends StatelessWidget {
  const DocuTrackerAdminFilterPill({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabels,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String?> options;
  final List<String> optionLabels;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: DocuTrackerTokens.metaStyle(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: DocuTrackerTokens.borderSubtle),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isDense: true,
              items: List.generate(options.length, (i) {
                return DropdownMenuItem<String?>(
                  value: options[i],
                  child: Text(
                    optionLabels[i],
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                );
              }),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Green/red uppercase permission tag for matrix cells.
class DocuTrackerPermissionAccessTag extends StatelessWidget {
  const DocuTrackerPermissionAccessTag({
    super.key,
    required this.label,
    required this.granted,
  });

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final bg = granted ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final fg = granted ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final border = granted ? const Color(0xFFA5D6A7) : const Color(0xFFEF9A9A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
          color: fg,
        ),
      ),
    );
  }
}

/// Sidebar stat block.
class DocuTrackerAdminStatTile extends StatelessWidget {
  const DocuTrackerAdminStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Icon(icon, size: 18, color: color.withValues(alpha: 0.85)),
        if (icon != null) const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(label, style: DocuTrackerTokens.metaStyle(context)),
      ],
    );
  }
}

/// Warm sidebar card shell.
class DocuTrackerAdminSidebarCard extends StatelessWidget {
  const DocuTrackerAdminSidebarCard({
    super.key,
    required this.title,
    required this.child,
    this.titleIcon,
    this.backgroundColor,
  });

  final String title;
  final Widget child;
  final IconData? titleIcon;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor ?? DocuTrackerTokens.surface,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
        border: Border.all(color: DocuTrackerTokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, size: 18, color: DocuTrackerTokens.brand),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Tool row in workflow sidebar (chevron list).
class DocuTrackerAdminToolRow extends StatelessWidget {
  const DocuTrackerAdminToolRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: DocuTrackerTokens.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: DocuTrackerTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal workflow stepper for active workflow cards.
class DocuTrackerWorkflowStepper extends StatelessWidget {
  const DocuTrackerWorkflowStepper({
    super.key,
    required this.steps,
    this.activeStepOrder = 1,
  });

  final List<WorkflowStep> steps;
  final int activeStepOrder;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return Text(
        'No routing defined yet — configure steps and assignees.',
        style: DocuTrackerTokens.subtitleStyle(context).copyWith(fontSize: 12),
      );
    }

    final sorted = [...steps]
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          Expanded(
            child: _StepColumn(
              step: sorted[i],
              isActive: sorted[i].stepOrder == activeStepOrder,
              isComplete: sorted[i].stepOrder < activeStepOrder,
            ),
          ),
          if (i < sorted.length - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  height: 2,
                  color: sorted[i].stepOrder < activeStepOrder
                      ? DocuTrackerTokens.brand
                      : DocuTrackerTokens.borderSubtle,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _StepColumn extends StatelessWidget {
  const _StepColumn({
    required this.step,
    required this.isActive,
    required this.isComplete,
  });

  final WorkflowStep step;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final label = (step.label ?? 'Step ${step.stepOrder}').trim();
    final role = _assigneeRoleLabel(step);

    final fill = isActive || isComplete
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.surfaceCream;
    final border = isActive || isComplete
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.borderStrong;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: DocuTrackerTokens.brand.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : Text(
                    '${step.stepOrder}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isActive
                          ? Colors.white
                          : DocuTrackerTokens.textMuted,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          role,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DocuTrackerTokens.metaStyle(context).copyWith(fontSize: 11),
        ),
      ],
    );
  }

  String _assigneeRoleLabel(WorkflowStep step) {
    final t = step.assigneeType.trim().toLowerCase();
    return switch (t) {
      'user' => 'Assignee',
      'department' => 'Dept. pool',
      'office' => 'Office',
      'role' => step.roleId ?? 'Role',
      _ => 'Reviewer',
    };
  }
}

/// Active workflow list card (mockup style).
class DocuTrackerActiveWorkflowCard extends StatelessWidget {
  const DocuTrackerActiveWorkflowCard({
    super.key,
    required this.config,
    required this.onEdit,
    required this.onMenu,
  });

  final DocumentRoutingConfig config;
  final VoidCallback onEdit;
  final VoidCallback onMenu;

  static IconData _iconForType(DocumentRoutingConfig config) {
    return switch (config.documentType.name) {
      'purchaseRequest' => Icons.shopping_cart_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final steps = config.steps.where((s) => s.enabled).toList();
    final hasSteps = steps.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: DocuTrackerTokens.cardDecoration(context: context),
          child: wide
              ? _buildWideLayout(context, steps, hasSteps)
              : _buildStackedLayout(context, steps, hasSteps),
        );
      },
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    List<WorkflowStep> steps,
    bool hasSteps,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 220, child: _buildTitleBlock(context, steps, hasSteps)),
        const SizedBox(width: 24),
        Expanded(
          child: hasSteps
              ? DocuTrackerWorkflowStepper(steps: steps, activeStepOrder: 1)
              : _emptyRouteState(context),
        ),
        IconButton(
          onPressed: onMenu,
          icon: const Icon(Icons.more_vert_rounded),
          color: DocuTrackerTokens.textMuted,
        ),
      ],
    );
  }

  Widget _buildStackedLayout(
    BuildContext context,
    List<WorkflowStep> steps,
    bool hasSteps,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildTitleBlock(context, steps, hasSteps)),
            IconButton(
              onPressed: onMenu,
              icon: const Icon(Icons.more_vert_rounded),
              color: DocuTrackerTokens.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (hasSteps)
          DocuTrackerWorkflowStepper(steps: steps, activeStepOrder: 1)
        else
          _emptyRouteState(context),
      ],
    );
  }

  Widget _buildTitleBlock(
    BuildContext context,
    List<WorkflowStep> steps,
    bool hasSteps,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: DocuTrackerTokens.brandSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconForType(config), color: DocuTrackerTokens.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                config.documentType.displayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _metaPill('v${config.version}'),
                  _metaPill('${config.reviewDeadlineHours}h SLA'),
                  _metaPill(hasSteps ? '${steps.length} steps' : 'Draft route'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyRouteState(BuildContext context) {
    return DocuTrackerPeachDashedBox(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'No routing defined yet.',
              style: DocuTrackerTokens.subtitleStyle(context),
            ),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Configure Route'),
            style: TextButton.styleFrom(
              foregroundColor: DocuTrackerTokens.brand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeach,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DocuTrackerTokens.highlightPeachBorder),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DocuTrackerTokens.textSecondary,
        ),
      ),
    );
  }
}

/// Peach dashed box — import from detail UI or duplicate minimal version.
class DocuTrackerPeachDashedBox extends StatelessWidget {
  const DocuTrackerPeachDashedBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeach,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: DocuTrackerTokens.highlightPeachBorder),
      ),
      child: child,
    );
  }
}

/// Key actions shown in permission matrix columns.
const List<DocumentAction> kPermissionMatrixActions = [
  DocumentAction.view,
  DocumentAction.edit,
  DocumentAction.approve,
  DocumentAction.download,
  DocumentAction.createDraft,
  DocumentAction.delete,
];

String permissionMatrixActionLabel(DocumentAction action) {
  return switch (action) {
    DocumentAction.createDraft => 'DRAFT',
    DocumentAction.returnDoc => 'RETURN',
    DocumentAction.submit => 'SUBMIT',
    _ => action.displayName.toUpperCase(),
  };
}

/// Resolves effective permission for a column (specific type beats wildcard).
DocumentPermission? permissionForColumn(
  List<DocumentPermission> all,
  DocumentAction action,
  String columnType,
) {
  DocumentPermission? specific;
  DocumentPermission? wild;
  for (final p in all) {
    if (p.action != action) continue;
    if (p.documentType == columnType) specific = p;
    if (p.documentType == '*') wild = p;
  }
  return specific ?? wild;
}

List<String> permissionMatrixColumnTypes(List<DocumentPermission> all) {
  final types = <String>{};
  for (final p in all) {
    types.add(p.documentType);
  }
  final list = types.toList();
  list.sort((a, b) {
    if (a == '*') return -1;
    if (b == '*') return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return list;
}

String permissionColumnHeader(String documentType) {
  if (documentType == '*') return 'All types';
  return documentTypeFromString(documentType).displayName;
}

/// One user row in the permissions matrix table.
class DocuTrackerPermissionMatrixRow extends StatelessWidget {
  const DocuTrackerPermissionMatrixRow({
    super.key,
    required this.targetLabel,
    required this.subtitle,
    required this.permissions,
    required this.columnTypes,
    required this.onEdit,
    this.isEven = false,
  });

  final String targetLabel;
  final String? subtitle;
  final List<DocumentPermission> permissions;
  final List<String> columnTypes;
  final VoidCallback onEdit;
  final bool isEven;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isEven
            ? DocuTrackerTokens.highlightPeach.withValues(alpha: 0.35)
            : DocuTrackerTokens.surface,
        border: Border(
          bottom: BorderSide(
            color: DocuTrackerTokens.borderSubtle.withValues(alpha: 0.8),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildUserCell(context)),
                    _PermissionMatrixActions(onEdit: onEdit),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final col in columnTypes)
                      SizedBox(
                        width: constraints.maxWidth > 280
                            ? (constraints.maxWidth - 24) / columnTypes.length
                            : constraints.maxWidth - 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              permissionColumnHeader(col),
                              style: DocuTrackerTokens.metaStyle(
                                context,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            _PermissionCell(
                              permissions: permissions,
                              columnType: col,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildUserCell(context)),
              for (final col in columnTypes)
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _PermissionCell(
                      permissions: permissions,
                      columnType: col,
                    ),
                  ),
                ),
              _PermissionMatrixActions(onEdit: onEdit),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUserCell(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: DocuTrackerTokens.brandSoft,
          child: Text(
            targetLabel.isNotEmpty ? targetLabel[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: DocuTrackerTokens.brand,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                targetLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: DocuTrackerTokens.metaStyle(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact actions control (avoids two IconButtons overflowing narrow columns).
class _PermissionMatrixActions extends StatelessWidget {
  const _PermissionMatrixActions({required this.onEdit});

  final VoidCallback onEdit;

  static const double _width = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Align(
        alignment: Alignment.centerRight,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.more_vert_rounded,
            size: 20,
            color: DocuTrackerTokens.textMuted,
          ),
          tooltip: 'Actions',
          onSelected: (value) {
            if (value == 'edit') onEdit();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined, size: 20),
                title: Text('Edit permissions'),
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCell extends StatelessWidget {
  const _PermissionCell({required this.permissions, required this.columnType});

  final List<DocumentPermission> permissions;
  final String columnType;

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[];
    for (final action in kPermissionMatrixActions) {
      final p = permissionForColumn(permissions, action, columnType);
      if (p == null) continue;
      tags.add(
        DocuTrackerPermissionAccessTag(
          label: permissionMatrixActionLabel(action),
          granted: p.granted,
        ),
      );
    }

    if (tags.isEmpty) {
      return Text('—', style: DocuTrackerTokens.metaStyle(context));
    }

    return Wrap(spacing: 4, runSpacing: 4, children: tags);
  }
}
