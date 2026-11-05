import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

enum _CreateWorkflowMode { existingType, newType }

/// Modal for choosing an existing document type or naming a new one.
///
/// Does not create types or write workflows. The caller opens the workflow
/// editor; publishing remains the authorized save path.
Future<DocumentType?> showDocuTrackerCreateWorkflowDialog({
  required BuildContext context,
  required List<DocumentType> documentTypes,
  required Map<String, int> workflowUsageByType,
  Map<String, int> latestVersionByType = const {},
}) {
  return showDialog<DocumentType>(
    context: context,
    barrierDismissible: true,
    builder: (context) => DocuTrackerCreateWorkflowDialog(
      documentTypes: documentTypes,
      workflowUsageByType: workflowUsageByType,
      latestVersionByType: latestVersionByType,
    ),
  );
}

class DocuTrackerCreateWorkflowDialog extends StatefulWidget {
  const DocuTrackerCreateWorkflowDialog({
    super.key,
    required this.documentTypes,
    required this.workflowUsageByType,
    this.latestVersionByType = const {},
  });

  final List<DocumentType> documentTypes;
  final Map<String, int> workflowUsageByType;
  final Map<String, int> latestVersionByType;

  @override
  State<DocuTrackerCreateWorkflowDialog> createState() =>
      _DocuTrackerCreateWorkflowDialogState();
}

class _DocuTrackerCreateWorkflowDialogState
    extends State<DocuTrackerCreateWorkflowDialog> {
  final _searchController = TextEditingController();
  final _newTypeController = TextEditingController();
  _CreateWorkflowMode _mode = _CreateWorkflowMode.existingType;
  DocumentType? _selected;
  String _search = '';
  String? _newTypeError;

  @override
  void initState() {
    super.initState();
    _selected = widget.documentTypes.isEmpty
        ? null
        : widget.documentTypes.first;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newTypeController.dispose();
    super.dispose();
  }

  List<DocumentType> get _filtered {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return widget.documentTypes;
    return [
      for (final type in widget.documentTypes)
        if (type.displayName.toLowerCase().contains(query) ||
            type.value.toLowerCase().contains(query))
          type,
    ];
  }

  DocumentType? get _parsedNewType {
    final raw = _newTypeController.text.trim();
    if (raw.isEmpty) return null;
    try {
      return DocumentType.fromDisplayName(raw);
    } on ArgumentError {
      return null;
    }
  }

  void _setMode(_CreateWorkflowMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _newTypeError = null;
      if (mode == _CreateWorkflowMode.existingType) {
        _newTypeController.clear();
        _selected ??= widget.documentTypes.isEmpty
            ? null
            : widget.documentTypes.first;
      } else {
        _selected = null;
        _searchController.clear();
        _search = '';
      }
    });
  }

  void _validateNewTypeField() {
    final raw = _newTypeController.text.trim();
    if (raw.isEmpty) {
      _newTypeError = null;
      return;
    }
    try {
      final type = DocumentType.fromDisplayName(raw);
      if (widget.documentTypes.contains(type)) {
        _newTypeError =
            '“${type.displayName}” already exists. Choose Use an existing '
            'document type instead.';
      } else {
        _newTypeError = null;
      }
    } on ArgumentError catch (error) {
      _newTypeError = error.message?.toString() ?? 'Invalid document type name.';
    }
  }

  bool get _canContinue {
    if (_mode == _CreateWorkflowMode.existingType) {
      return _selected != null;
    }
    final type = _parsedNewType;
    return type != null &&
        !widget.documentTypes.contains(type) &&
        _newTypeError == null;
  }

  void _continue() {
    if (_mode == _CreateWorkflowMode.newType) {
      _validateNewTypeField();
      final type = _parsedNewType;
      if (type == null || widget.documentTypes.contains(type)) {
        setState(() {});
        return;
      }
      Navigator.pop(context, type);
      return;
    }
    final selected = _selected;
    if (selected != null) Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final secondary = DocuTrackerTokens.textSecondaryOf(context);
    final selectedUsage = _selected == null
        ? 0
        : (widget.workflowUsageByType[_selected!.value] ?? 0);
    final selectedVersion = _selected == null
        ? null
        : widget.latestVersionByType[_selected!.value];

    return Dialog(
      backgroundColor: DocuTrackerTokens.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: DocuTrackerTokens.brandSoftOf(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_tree_outlined,
                      color: DocuTrackerTokens.toneOf(
                        context,
                        DocuTrackerTokens.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create workflow',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose which document type this approval workflow '
                          'will apply to.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ModeOption(
                selected: _mode == _CreateWorkflowMode.existingType,
                title: 'Use an existing document type',
                subtitle: 'Pick a type that already exists in DocuTracker.',
                onTap: () => _setMode(_CreateWorkflowMode.existingType),
              ),
              const SizedBox(height: 8),
              _ModeOption(
                selected: _mode == _CreateWorkflowMode.newType,
                title: 'Create a new document type',
                subtitle:
                    'Name a type now. It becomes available after you publish '
                    'the workflow.',
                onTap: () => _setMode(_CreateWorkflowMode.newType),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: _mode == _CreateWorkflowMode.existingType
                      ? _ExistingTypePanel(
                          searchController: _searchController,
                          search: _search,
                          filtered: _filtered,
                          selected: _selected,
                          workflowUsageByType: widget.workflowUsageByType,
                          onSearchChanged: (value) {
                            setState(() => _search = value);
                          },
                          onSelect: (type) {
                            setState(() => _selected = type);
                          },
                        )
                      : _NewTypePanel(
                          controller: _newTypeController,
                          error: _newTypeError,
                          onChanged: (_) {
                            setState(_validateNewTypeField);
                          },
                          onSubmitted: (_) {
                            if (_canContinue) _continue();
                          },
                        ),
                ),
              ),
              if (_mode == _CreateWorkflowMode.existingType &&
                  _selected != null &&
                  selectedUsage > 0) ...[
                const SizedBox(height: 10),
                _InfoBanner(
                  text: selectedVersion == null
                      ? '“${_selected!.displayName}” already has a workflow. '
                            'Continuing opens workflow setup. Publishing saves '
                            'a new version; it does not create a second '
                            'independent workflow for this type.'
                      : '“${_selected!.displayName}” already has a workflow '
                            '(latest version $selectedVersion). Continuing '
                            'opens workflow setup. Publishing saves a new '
                            'version; it does not create a second independent '
                            'workflow for this type.',
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: secondary),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('create-workflow-continue'),
                    onPressed: _canContinue ? _continue : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: DocuTrackerTokens.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Continue to workflow setup'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Material(
      color: selected
          ? DocuTrackerTokens.brandSoftOf(context)
          : DocuTrackerTokens.insetOf(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            border: Border.all(
              color: selected
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderSubtleOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? DocuTrackerTokens.brand
                    : DocuTrackerTokens.textMutedOf(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingTypePanel extends StatelessWidget {
  const _ExistingTypePanel({
    required this.searchController,
    required this.search,
    required this.filtered,
    required this.selected,
    required this.workflowUsageByType,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final TextEditingController searchController;
  final String search;
  final List<DocumentType> filtered;
  final DocumentType? selected;
  final Map<String, int> workflowUsageByType;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<DocumentType> onSelect;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Existing document type',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: DocuTrackerTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('create-workflow-search'),
          controller: searchController,
          decoration: DocuTrackerTokens.warmSearchDecoration(
            context,
            'Search by name or type key',
          ),
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DocuTrackerTokens.insetOf(context),
              borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
              border: Border.all(
                color: DocuTrackerTokens.borderSubtleOf(context),
              ),
            ),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      search.trim().isEmpty
                          ? 'No document types are available.'
                          : 'No matching document types.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : RadioGroup<DocumentType>(
                    groupValue: selected,
                    onChanged: (value) {
                      if (value != null) onSelect(value);
                    },
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final type = filtered[index];
                        return _DocumentTypeChoiceTile(
                          key: ValueKey(
                            'create-workflow-type-${type.value}',
                          ),
                          type: type,
                          selected: type == selected,
                          usageCount: workflowUsageByType[type.value] ?? 0,
                          onTap: () => onSelect(type),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _NewTypePanel extends StatelessWidget {
  const _NewTypePanel({
    required this.controller,
    required this.error,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String? error;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'New document type name',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: DocuTrackerTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('create-workflow-new-type'),
          controller: controller,
          autofocus: true,
          decoration: DocuTrackerTokens.warmSearchDecoration(
            context,
            'Example: Travel Order',
          ).copyWith(
            prefixIcon: Icon(
              Icons.drive_file_rename_outline_rounded,
              color: muted.withValues(alpha: 0.85),
            ),
            errorText: error,
          ),
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: 8),
        Text(
          'The type is not created yet. It becomes available for future '
          'documents after you publish the workflow.',
          style: TextStyle(fontSize: 12, height: 1.35, color: muted),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tone = DocuTrackerTokens.toneOf(context, DocuTrackerTokens.brand);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
          Icon(Icons.info_outline_rounded, size: 18, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: DocuTrackerTokens.textSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTypeChoiceTile extends StatelessWidget {
  const _DocumentTypeChoiceTile({
    super.key,
    required this.type,
    required this.selected,
    required this.usageCount,
    required this.onTap,
  });

  final DocumentType type;
  final bool selected;
  final int usageCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    final border = selected
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.borderSubtleOf(context);

    return Material(
      color: selected
          ? DocuTrackerTokens.brandSoftOf(context)
          : DocuTrackerTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Radio<DocumentType>(
                value: type,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Type key: ${type.value}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              if (usageCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DocuTrackerTokens.insetOf(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    usageCount == 1
                        ? 'Has workflow'
                        : '$usageCount versions',
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
            ],
          ),
        ),
      ),
    );
  }
}
