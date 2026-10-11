import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

class _RefreshingController extends TextEditingController {
  void refreshOptions() => notifyListeners();
}

/// Text field that also opens a filterable option list.
///
/// Typing narrows the list. The arrow opens the full list. When [allowCustom]
/// is true, a value that is not in [options] is kept.
class SearchableDropdownField extends StatefulWidget {
  const SearchableDropdownField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.decoration,
    this.enabled = true,
    this.allowCustom = false,
    this.style,
    this.textCapitalization = TextCapitalization.none,
    this.searchText,
    this.groupLabel,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final InputDecoration decoration;
  final bool enabled;
  final bool allowCustom;
  final TextStyle? style;
  final TextCapitalization textCapitalization;

  /// Extra words used only for matching, such as "BS" for a bachelor's degree.
  final String Function(String option)? searchText;

  /// Optional section title for an option. Headers follow the option order.
  final String? Function(String option)? groupLabel;

  @override
  State<SearchableDropdownField> createState() =>
      _SearchableDropdownFieldState();
}

class _SearchableDropdownFieldState extends State<SearchableDropdownField> {
  final _RefreshingController _controller = _RefreshingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _arrowFocusNode = FocusNode(
    debugLabel: 'searchable-dropdown-arrow',
    skipTraversal: true,
    canRequestFocus: false,
  );
  final GlobalKey _fieldKey = GlobalKey();
  bool _showAll = false;
  String _showAllAnchor = '';

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value ?? '';
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant SearchableDropdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value ?? '';
    if (!_focusNode.hasFocus && next != _controller.text) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    _arrowFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (_focusNode.hasFocus || !mounted) return;
    _showAll = false;
    _commit();
  }

  void _commit() {
    if (widget.allowCustom) {
      final trimmed = _controller.text.trim();
      if (_controller.text != trimmed) {
        _controller.value = TextEditingValue(
          text: trimmed,
          selection: TextSelection.collapsed(offset: trimmed.length),
        );
      }
      final next = trimmed.isEmpty ? null : trimmed;
      if ((widget.value ?? '') != (next ?? '')) widget.onChanged(next);
      return;
    }

    final typed = _controller.text.trim();
    if (typed.isEmpty) {
      if ((widget.value ?? '').isNotEmpty) widget.onChanged(null);
      if (_controller.text.isNotEmpty) _controller.clear();
      return;
    }

    String? match;
    for (final option in widget.options) {
      if (option.toLowerCase() == typed.toLowerCase()) {
        match = option;
        break;
      }
    }
    if (match != null) {
      if (_controller.text != match) _controller.text = match;
      if (match != widget.value) widget.onChanged(match);
      return;
    }

    final restore = widget.value ?? '';
    if (_controller.text != restore) _controller.text = restore;
  }

  bool _matches(String option, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = (widget.searchText?.call(option) ?? option).toLowerCase();
    if (q.length <= 2) {
      return RegExp('\\b${RegExp.escape(q)}\\b').hasMatch(hay);
    }
    if (hay.contains(q)) return true;
    final tokens = q.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    if (tokens.length < 2) return false;
    return tokens.every((token) {
      if (token.length <= 2) {
        return RegExp('\\b${RegExp.escape(token)}\\b').hasMatch(hay);
      }
      return hay.contains(token);
    });
  }

  Iterable<String> _optionsFor(TextEditingValue value) {
    if (!widget.enabled || widget.options.isEmpty) {
      return const Iterable<String>.empty();
    }
    if (_showAll && value.text != _showAllAnchor) {
      _showAll = false;
    }
    if (_showAll || value.text.trim().isEmpty) return widget.options;
    return widget.options.where((option) => _matches(option, value.text));
  }

  void _toggleMenu() {
    if (!widget.enabled) return;
    if (_focusNode.hasFocus && _showAll) {
      _focusNode.unfocus();
      return;
    }
    _showAll = true;
    _showAllAnchor = _controller.text;
    if (_focusNode.hasFocus) {
      _controller.refreshOptions();
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldStyle = widget.style ?? AppTheme.dashFieldTextStyle(context);
    return Autocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option,
      optionsBuilder: _optionsFor,
      onSelected: (option) => widget.onChanged(option),
      optionsViewBuilder: (context, onSelected, options) {
        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final width = box != null && box.hasSize ? box.size.width : 280.0;
        final list = options.toList(growable: false);
        final scrollLongList = list.length > 6;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppTheme.dashPanelOf(context),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 280,
                minWidth: width,
                maxWidth: width,
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: !scrollLongList,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final option = list[index];
                  final selected = option == _controller.text;
                  final group = widget.groupLabel?.call(option);
                  final previous = index == 0
                      ? null
                      : widget.groupLabel?.call(list[index - 1]);
                  final showGroup =
                      group != null && group.isNotEmpty && group != previous;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showGroup)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: Text(
                            group,
                            style: fieldStyle.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: AppTheme.primaryNavy.withValues(
                                alpha: 0.72,
                              ),
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          color: selected
                              ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(option, style: fieldStyle),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          key: _fieldKey,
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          style: fieldStyle,
          textCapitalization: widget.textCapitalization,
          autocorrect: false,
          onSubmitted: (_) => onSubmitted(),
          decoration: widget.decoration.copyWith(
            suffixIcon: IconButton(
              tooltip: 'Show list',
              focusNode: _arrowFocusNode,
              onPressed: widget.enabled ? _toggleMenu : null,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: widget.enabled
                    ? AppTheme.dashTextSecondaryOf(context)
                    : AppTheme.dashTextSecondaryOf(
                        context,
                      ).withValues(alpha: 0.45),
              ),
            ),
          ),
          onChanged: (text) {
            if (!widget.allowCustom) {
              if (text.trim().isEmpty && (widget.value ?? '').isNotEmpty) {
                widget.onChanged(null);
              }
              return;
            }
            final next = text.isEmpty ? null : text;
            if ((widget.value ?? '') != (next ?? '')) widget.onChanged(next);
          },
        );
      },
    );
  }
}
