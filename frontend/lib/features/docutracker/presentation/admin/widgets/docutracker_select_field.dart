import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// One choice in [DocuTrackerSelectField].
class DocuTrackerSelectOption<T> {
  const DocuTrackerSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.fieldLabel,
  });

  final T value;
  final String label;
  final String? subtitle;

  /// Closed-field text. Defaults to [label].
  final String? fieldLabel;

  String get closedLabel => fieldLabel ?? label;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final haystack = [
      label,
      if (subtitle != null) subtitle!,
      if (fieldLabel != null) fieldLabel!,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}

/// System Access menu with a clear selected row and room to tap.
///
/// Long lists can be searched. The closed field stays a single line.
class DocuTrackerSelectField<T> extends StatefulWidget {
  const DocuTrackerSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.searchable = false,
    this.searchHint = 'Search',
    this.externalLabel = false,
  });

  final String label;
  final T value;
  final List<DocuTrackerSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final bool searchable;
  final String searchHint;

  /// When true, [label] is not shown inside the field (caller renders it above).
  final bool externalLabel;

  @override
  State<DocuTrackerSelectField<T>> createState() =>
      _DocuTrackerSelectFieldState<T>();
}

class _DocuTrackerSelectFieldState<T> extends State<DocuTrackerSelectField<T>> {
  final MenuController _menu = MenuController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  DocuTrackerSelectOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  List<DocuTrackerSelectOption<T>> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final option in widget.options)
        if (option.matches(query)) option,
    ];
  }

  void _toggle() {
    if (widget.onChanged == null) return;
    if (_menu.isOpen) {
      _menu.close();
    } else {
      _search.clear();
      _menu.open();
      if (widget.searchable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _menu.isOpen) _searchFocus.requestFocus();
        });
      }
    }
    setState(() {});
  }

  void _choose(T value) {
    _menu.close();
    setState(() {});
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final enabled = widget.onChanged != null;
    final muted = DocuTrackerTokens.textMutedOf(context);
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      crossAxisUnconstrained: false,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          DocuTrackerTokens.surfaceOf(context),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        maximumSize: const WidgetStatePropertyAll(Size(560, 360)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: DocuTrackerTokens.borderSubtleOf(context)),
          ),
        ),
      ),
      builder: (context, controller, child) {
        return InkWell(
          onTap: enabled ? _toggle : null,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            isEmpty: selected == null,
            decoration:
                (widget.externalLabel
                        ? DocuTrackerTokens.warmSearchDecoration(
                            context,
                            selected?.closedLabel ?? widget.searchHint,
                          )
                        : DocuTrackerStyles.dropdownDecoration(
                            context,
                            widget.label,
                          ))
                    .copyWith(
                      enabled: enabled,
                      // Keep the closed field height aligned with search inputs
                      // when the label is rendered outside the field.
                      prefixIcon: widget.externalLabel
                          ? const SizedBox(width: 12)
                          : null,
                      prefixIconConstraints: widget.externalLabel
                          ? const BoxConstraints(minWidth: 12, minHeight: 0)
                          : null,
                      hintText: widget.externalLabel
                          ? null
                          : widget.label.isEmpty
                          ? null
                          : widget.label,
                      suffixIcon: Icon(
                        controller.isOpen
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: controller.isOpen
                            ? DocuTrackerTokens.brand
                            : muted,
                      ),
                    ),
            child: Text(
              selected?.closedLabel ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? DocuTrackerTokens.textPrimaryOf(context)
                    : muted,
              ),
            ),
          ),
        );
      },
      menuChildren: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: TextField(
              key: const ValueKey('docutracker-select-search'),
              controller: _search,
              focusNode: _searchFocus,
              decoration: DocuTrackerTokens.warmSearchDecoration(
                context,
                widget.searchHint,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (_visible.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'No matches.',
              style: DocuTrackerTokens.metaStyle(context),
            ),
          ),
        for (final option in _visible)
          MenuItemButton(
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(
                Size(48, option.subtitle == null ? 48 : 58),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              backgroundColor: WidgetStatePropertyAll(
                option.value == widget.value
                    ? DocuTrackerTokens.brand.withValues(alpha: 0.08)
                    : Colors.transparent,
              ),
            ),
            leadingIcon: Icon(
              Icons.check_rounded,
              size: 18,
              color: option.value == widget.value
                  ? DocuTrackerTokens.brand
                  : Colors.transparent,
            ),
            onPressed: enabled ? () => _choose(option.value) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
                if (option.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DocuTrackerTokens.metaStyle(context),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
