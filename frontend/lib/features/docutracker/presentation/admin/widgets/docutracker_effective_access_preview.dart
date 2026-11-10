import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/docutracker_effective_access_preview.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_select_field.dart';
import 'package:hrms_plaridel/features/docutracker/security/docutracker_roles.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

const _actionLabels = <String, String>{
  'view': 'View',
  'create_draft': 'Create draft',
  'submit': 'Submit',
  'download': 'Download',
  'release': 'Release',
};

const _actionIcons = <String, IconData>{
  'view': Icons.visibility_outlined,
  'create_draft': Icons.edit_note_outlined,
  'submit': Icons.send_outlined,
  'download': Icons.download_outlined,
  'release': Icons.outbox_outlined,
};

/// Read-only preview of one employee's saved System Access.
class DocuTrackerEffectiveAccessPreviewCard extends StatelessWidget {
  const DocuTrackerEffectiveAccessPreviewCard({
    super.key,
    required this.employees,
    required this.selectedUserId,
    required this.documentType,
    required this.documentTypes,
    required this.documentTypeLabel,
    required this.roleLabel,
    required this.hasUnsavedChanges,
    required this.loading,
    required this.preview,
    required this.error,
    required this.onUserChanged,
    this.onDocumentTypeChanged,
  });

  final List<EmployeeDirectoryEntry> employees;
  final String? selectedUserId;
  final String documentType;
  final List<String> documentTypes;
  final String Function(String value) documentTypeLabel;
  final String Function(String roleId) roleLabel;
  final bool hasUnsavedChanges;
  final bool loading;
  final DocuTrackerEffectiveAccessPreview? preview;
  final String? error;
  final ValueChanged<String> onUserChanged;
  final ValueChanged<String>? onDocumentTypeChanged;

  EmployeeDirectoryEntry? get _selectedEmployee {
    final id = selectedUserId;
    if (id == null) return null;
    for (final entry in employees) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedEmployee;
    final muted = DocuTrackerTokens.metaStyle(context);
    final typeLabel = documentTypeLabel(documentType);

    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Container(
      key: const ValueKey('effective-access-preview'),
      padding: EdgeInsets.fromLTRB(
        isPhone ? 14 : 22,
        isPhone ? 16 : 22,
        isPhone ? 14 : 22,
        isPhone ? 18 : 24,
      ),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PreviewHeader(),
          SizedBox(height: isPhone ? 14 : 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 600;
              final employee = _EmployeeAccessPicker(
                employees: employees,
                selectedUserId: employees.any((e) => e.id == selectedUserId)
                    ? selectedUserId
                    : null,
                roleLabel: roleLabel,
                onUserChanged: onUserChanged,
              );
              final documentTypeField = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel('Document type'),
                  const SizedBox(height: 6),
                  DocuTrackerSelectField<String>(
                    key: ValueKey('permission-document-type-$documentType'),
                    label: 'Document type',
                    externalLabel: true,
                    value: documentTypes.contains(documentType)
                        ? documentType
                        : '*',
                    options: [
                      for (final value in documentTypes)
                        DocuTrackerSelectOption(
                          value: value,
                          label: documentTypeLabel(value),
                          subtitle: value == '*'
                              ? 'Used when a type has no setting of its own'
                              : 'Only this document type',
                        ),
                    ],
                    onChanged: onDocumentTypeChanged,
                  ),
                ],
              );

              final selectors = stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        employee,
                        const SizedBox(height: 16),
                        documentTypeField,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: employee),
                        const SizedBox(width: 20),
                        Expanded(child: documentTypeField),
                      ],
                    );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selectors,
                  if (selected != null) ...[
                    const SizedBox(height: 14),
                    _SelectedEmployeeSummary(
                      employee: selected,
                      roleLabel: roleLabel,
                      previewName: preview?.userName,
                      previewRole: preview?.userRole,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const _PrecedencePanel(),
          const SizedBox(height: 10),
          Text(
            hasUnsavedChanges
                ? 'This preview is the last saved policy. It does not include the unsaved edits on this screen.'
                : 'This preview is the last saved policy.',
            key: const ValueKey('effective-access-basis'),
            style: muted.copyWith(
              color: hasUnsavedChanges
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.textSecondaryOf(context),
              fontWeight: hasUnsavedChanges ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          _PermissionResultsSection(
            selected: selected,
            documentTypeLabel: typeLabel,
            loading: loading,
            error: error,
            preview: preview,
            hasSelection: selectedUserId != null,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: DocuTrackerTokens.textSecondaryOf(context),
          height: 1.2,
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFB91C1C)),
            ),
        ],
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader();

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Effective access preview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: primary,
                height: 1.15,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: DocuTrackerTokens.brandSoftOf(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Read-only preview',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DocuTrackerTokens.toneOf(
                    context,
                    DocuTrackerTokens.brand,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'See the effective document permissions for an employee based on '
          'role, document type, and exception rules. This is a read-only '
          'preview and does not change any settings.',
          style: TextStyle(fontSize: 13.5, height: 1.45, color: muted),
        ),
      ],
    );
  }
}

class _PrecedencePanel extends StatelessWidget {
  const _PrecedencePanel();

  @override
  Widget build(BuildContext context) {
    final tone = DocuTrackerTokens.toneOf(context, DocuTrackerTokens.brand);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.brandSoftOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(
          color: DocuTrackerTokens.highlightPeachBorderOf(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: DocuTrackerTokens.textSecondaryOf(context),
                ),
                children: [
                  TextSpan(
                    text: 'Precedence rules (how the effective access is '
                        'computed): ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: DocuTrackerTokens.textPrimaryOf(context),
                    ),
                  ),
                  const TextSpan(
                    text:
                        'Employee exceptions override role permissions, and '
                        'document-type settings override both. The result '
                        'below shows the final, effective access for the '
                        'selected employee and document type.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedEmployeeSummary extends StatelessWidget {
  const _SelectedEmployeeSummary({
    required this.employee,
    required this.roleLabel,
    this.previewName,
    this.previewRole,
  });

  final EmployeeDirectoryEntry employee;
  final String Function(String roleId) roleLabel;
  final String? previewName;
  final String? previewRole;

  @override
  Widget build(BuildContext context) {
    final name = (previewName?.trim().isNotEmpty == true)
        ? previewName!.trim()
        : employee.fullName;
    final roleRaw = (previewRole?.trim().isNotEmpty == true)
        ? previewRole!.trim()
        : employee.roleId;
    final role = roleRaw == null || roleRaw.trim().isEmpty
        ? null
        : roleLabel(DocuTrackerRoles.normalize(roleRaw));
    final department = employee.departmentName?.trim();
    final position = employee.positionName?.trim();
    final subtitle = [
      if (department != null && department.isNotEmpty) department,
      if (position != null && position.isNotEmpty) position,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Row(
        children: [
          _EmployeeAvatar(name: name, large: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: DocuTrackerTokens.metaStyle(context)),
                ],
              ],
            ),
          ),
          if (department != null && department.isNotEmpty) ...[
            _SummaryDivider(),
            _SummaryFact(
              icon: Icons.apartment_outlined,
              label: 'Department',
              value: department,
            ),
          ],
          if (role != null) ...[
            _SummaryDivider(),
            _SummaryFact(
              icon: Icons.work_outline_rounded,
              label: 'Role',
              value: role,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: DocuTrackerTokens.borderSubtleOf(context),
    );
  }
}

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PermissionResultsSection extends StatelessWidget {
  const _PermissionResultsSection({
    required this.selected,
    required this.documentTypeLabel,
    required this.loading,
    required this.error,
    required this.preview,
    required this.hasSelection,
  });

  final EmployeeDirectoryEntry? selected;
  final String documentTypeLabel;
  final bool loading;
  final String? error;
  final DocuTrackerEffectiveAccessPreview? preview;
  final bool hasSelection;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.metaStyle(context);
    final name = selected?.fullName ?? preview?.userName ?? 'employee';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Permission results',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hasSelection
              ? 'Effective access for $name on $documentTypeLabel.'
              : 'Select an employee to preview effective access.',
          style: muted,
        ),
        const SizedBox(height: 14),
        if (!hasSelection)
          const SizedBox.shrink()
        else if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (error != null)
          Text(error!, style: const TextStyle(color: Color(0xFFB91C1C)))
        else if (preview == null || preview!.actions.isEmpty)
          Text('No access preview was returned.', style: muted)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final minCardWidth =
                  constraints.maxWidth < 600 ? 160.0 : 200.0;
              final width = constraints.maxWidth;
              final columns = width < minCardWidth
                  ? 1
                  : (width + gap) ~/ (minCardWidth + gap);
              final safeColumns = columns.clamp(1, width < 600 ? 2 : 5);
              final cardWidth = safeColumns == 1
                  ? width
                  : (width - gap * (safeColumns - 1)) / safeColumns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final action in preview!.actions)
                    SizedBox(
                      width: cardWidth,
                      child: _PermissionResultCard(action: action),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _PermissionResultCard extends StatelessWidget {
  const _PermissionResultCard({required this.action});

  final DocuTrackerEffectiveAccessAction action;

  @override
  Widget build(BuildContext context) {
    final label = _actionLabels[action.action] ?? action.action;
    final outcomeLabel = switch (action.outcome) {
      'allowed' => 'Allowed',
      'blocked' => 'Blocked',
      _ => 'Depends on document',
    };
    final outcomeColor = switch (action.outcome) {
      'allowed' => const Color(0xFF166534),
      'blocked' => const Color(0xFFB91C1C),
      _ => const Color(0xFFB45309),
    };
    final outcomeFill = switch (action.outcome) {
      'allowed' => const Color(0xFFDCFCE7),
      'blocked' => const Color(0xFFFEE2E2),
      _ => const Color(0xFFFEF3C7),
    };
    final outcomeIcon = switch (action.outcome) {
      'allowed' => Icons.check_circle_rounded,
      'blocked' => Icons.cancel_rounded,
      _ => Icons.info_rounded,
    };
    final source = switch (action.sourceKind) {
      'employee' => 'Employee exception',
      'role' =>
        'Role rule${action.matchedRoleId == null ? '' : ' (${action.matchedRoleId})'}',
      'administrator' => 'Administrator',
      _ => 'No matching rule',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.insetOf(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _actionIcons[action.action] ?? Icons.policy_outlined,
                  size: 18,
                  color: DocuTrackerTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: DocuTrackerTokens.tintOf(
                        context,
                        light: outcomeFill,
                        accent: outcomeColor,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          outcomeIcon,
                          size: 13,
                          color: DocuTrackerTokens.toneOf(
                            context,
                            outcomeColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            outcomeLabel,
                            key: ValueKey(
                              'effective-access-${action.action}',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: DocuTrackerTokens.toneOf(
                                context,
                                outcomeColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (action.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              action.summary,
              style: DocuTrackerTokens.metaStyle(
                context,
              ).copyWith(height: 1.4, fontSize: 12.5),
            ),
          ],
          for (final condition in action.conditions) ...[
            const SizedBox(height: 4),
            Text('• $condition', style: DocuTrackerTokens.metaStyle(context)),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: DocuTrackerTokens.insetOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: DocuTrackerTokens.textSecondaryOf(context),
                ),
                children: [
                  const TextSpan(
                    text: 'Source: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: source),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeAccessPicker extends StatefulWidget {
  const _EmployeeAccessPicker({
    required this.employees,
    required this.selectedUserId,
    required this.roleLabel,
    required this.onUserChanged,
  });

  final List<EmployeeDirectoryEntry> employees;
  final String? selectedUserId;
  final String Function(String roleId) roleLabel;
  final ValueChanged<String> onUserChanged;

  @override
  State<_EmployeeAccessPicker> createState() => _EmployeeAccessPickerState();
}

class _EmployeeAccessPickerState extends State<_EmployeeAccessPicker> {
  final MenuController _menu = MenuController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  EmployeeDirectoryEntry? get _selected {
    final id = widget.selectedUserId;
    if (id == null) return null;
    for (final entry in widget.employees) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  static const _maxVisible = 60;

  List<EmployeeDirectoryEntry> get _visible {
    final query = _search.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.employees
        : [
            for (final entry in widget.employees)
              if (_matches(entry, query)) entry,
          ];
    if (matches.length <= _maxVisible) return matches;
    return matches.take(_maxVisible).toList(growable: false);
  }

  bool get _resultsTruncated {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.employees.length > _maxVisible;
    var count = 0;
    for (final entry in widget.employees) {
      if (!_matches(entry, query)) continue;
      count++;
      if (count > _maxVisible) return true;
    }
    return false;
  }

  bool _matches(EmployeeDirectoryEntry entry, String query) {
    final haystack = [
      entry.fullName,
      if (entry.departmentName != null) entry.departmentName!,
      if (entry.positionName != null) entry.positionName!,
      if (entry.roleId != null) entry.roleId!,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  void _toggle() {
    if (_menu.isOpen) {
      _menu.close();
    } else {
      _search.clear();
      _menu.open();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen) _searchFocus.requestFocus();
      });
    }
    setState(() {});
  }

  void _choose(String userId) {
    _menu.close();
    setState(() {});
    widget.onUserChanged(userId);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('Employee', required: true),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final menuWidth = constraints.maxWidth.clamp(280.0, 640.0);
            return MenuAnchor(
              key: const ValueKey('effective-access-employee'),
              controller: _menu,
              alignmentOffset: const Offset(0, 6),
              crossAxisUnconstrained: false,
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(
                  DocuTrackerTokens.surfaceOf(context),
                ),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                elevation: const WidgetStatePropertyAll(10),
                maximumSize: WidgetStatePropertyAll(Size(menuWidth, 360)),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusMd,
                    ),
                    side: BorderSide(
                      color: DocuTrackerTokens.borderSubtleOf(context),
                    ),
                  ),
                ),
              ),
              builder: (context, controller, child) {
                return Material(
                  color: DocuTrackerTokens.surfaceOf(context),
                  borderRadius: BorderRadius.circular(
                    DocuTrackerTokens.radiusMd,
                  ),
                  child: InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusMd,
                    ),
                    child: InputDecorator(
                      isEmpty: selected == null,
                      decoration:
                          DocuTrackerTokens.warmSearchDecoration(
                            context,
                            'Search by name, department, or position...',
                          ).copyWith(
                            suffixIcon: Icon(
                              controller.isOpen
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: controller.isOpen
                                  ? DocuTrackerTokens.brand
                                  : muted,
                            ),
                          ),
                      child: selected == null
                          ? const SizedBox(height: 20)
                          : Text(
                              selected.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: DocuTrackerTokens.textPrimaryOf(
                                  context,
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              },
              menuChildren: [
                SizedBox(
                  width: menuWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: TextField(
                          key: const ValueKey(
                            'effective-access-employee-search',
                          ),
                          controller: _search,
                          focusNode: _searchFocus,
                          decoration: DocuTrackerTokens.warmSearchDecoration(
                            context,
                            'Search by name, department, or position...',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (widget.employees.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Text(
                            'No employees loaded.',
                            style: DocuTrackerTokens.metaStyle(context),
                          ),
                        )
                      else if (_visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Text(
                            'No matches.',
                            style: DocuTrackerTokens.metaStyle(context),
                          ),
                        )
                      else ...[
                        if (_resultsTruncated)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: Text(
                              'Showing $_maxVisible matches. Type more to '
                              'narrow the list.',
                              style: DocuTrackerTokens.metaStyle(context),
                            ),
                          ),
                        SizedBox(
                          height: 280,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: _visible.length,
                            itemBuilder: (context, index) {
                              final entry = _visible[index];
                              return _EmployeePickerRow(
                                entry: entry,
                                selected: entry.id == widget.selectedUserId,
                                roleLabel: widget.roleLabel,
                                onTap: () => _choose(entry.id),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EmployeePickerRow extends StatelessWidget {
  const _EmployeePickerRow({
    required this.entry,
    required this.selected,
    required this.roleLabel,
    required this.onTap,
  });

  final EmployeeDirectoryEntry entry;
  final bool selected;
  final String Function(String roleId) roleLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (entry.departmentName?.trim().isNotEmpty == true)
        entry.departmentName!.trim(),
      if (entry.positionName?.trim().isNotEmpty == true)
        entry.positionName!.trim(),
    ].join(' · ');
    final badge = entry.departmentName?.trim().isNotEmpty == true
        ? entry.departmentName!.trim()
        : (entry.roleId?.trim().isNotEmpty == true
              ? roleLabel(DocuTrackerRoles.normalize(entry.roleId))
              : null);

    return Material(
      color: selected
          ? DocuTrackerTokens.brandSoftOf(context)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              _EmployeeAvatar(name: entry.fullName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DocuTrackerTokens.textPrimaryOf(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DocuTrackerTokens.metaStyle(context),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 110),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DocuTrackerTokens.insetOf(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DocuTrackerTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: DocuTrackerTokens.brand,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeAvatar extends StatelessWidget {
  const _EmployeeAvatar({required this.name, this.large = false});

  final String name;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 44.0 : 36.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DocuTrackerTokens.brandSoftOf(context),
        shape: BoxShape.circle,
        border: Border.all(
          color: DocuTrackerTokens.highlightPeachBorderOf(context),
        ),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: large ? 14 : 12,
          fontWeight: FontWeight.w800,
          color: DocuTrackerTokens.toneOf(context, DocuTrackerTokens.brand),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final value = parts.first;
    return value.substring(0, value.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
