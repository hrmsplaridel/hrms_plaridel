import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/input_rules.dart';

class _RefreshingController extends TextEditingController {
  void refreshOptions() => notifyListeners();
}

/// Text field that also opens a filterable option list.
///
/// Typing narrows the list. The arrow opens the full list. When [allowCustom]
/// is true, a value that is not in [options] is kept.
///
/// Keyboard: Arrow Down/Up moves the highlight; Enter selects it; Escape closes.
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
    this.inputFormatters,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final InputDecoration decoration;
  final bool enabled;
  final bool allowCustom;
  final TextStyle? style;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

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
  final ScrollController _optionsScrollController = ScrollController();
  final ValueNotifier<int> _highlightIndex = ValueNotifier<int>(-1);

  bool _showAll = false;
  String _showAllAnchor = '';
  List<String> _visibleOptions = const [];
  AutocompleteOnSelected<String>? _optionsOnSelected;

  static const double _optionRowExtent = 40;
  static const double _groupHeaderExtent = 28;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value ?? '';
    _focusNode.addListener(_handleFocus);
    _focusNode.onKeyEvent = _onKeyEvent;
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
    _focusNode.onKeyEvent = null;
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    _arrowFocusNode.dispose();
    _controller.dispose();
    _optionsScrollController.dispose();
    _highlightIndex.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (_focusNode.hasFocus || !mounted) return;
    _showAll = false;
    _highlightIndex.value = -1;
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

  void _syncVisibleOptions(List<String> list) {
    _visibleOptions = list;
    if (_highlightIndex.value >= list.length) {
      _highlightIndex.value = list.isEmpty ? -1 : list.length - 1;
    }
  }

  void _ensureOptionsOpen() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    final hasQuery = _controller.text.trim().isNotEmpty;
    if (!hasQuery && !_showAll) {
      _showAll = true;
      _showAllAnchor = _controller.text;
      _controller.refreshOptions();
    } else {
      _controller.refreshOptions();
    }
  }

  void _moveHighlight(int delta) {
    if (!widget.enabled) return;
    _ensureOptionsOpen();
    final list = _optionsFor(_controller.value).toList(growable: false);
    _visibleOptions = list;
    if (list.isEmpty) {
      _highlightIndex.value = -1;
      return;
    }
    final current = _highlightIndex.value;
    if (current < 0) {
      _highlightIndex.value = delta > 0 ? 0 : list.length - 1;
    } else {
      final next = (current + delta).clamp(0, list.length - 1);
      _highlightIndex.value = next;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollHighlightIntoView();
    });
  }

  double _offsetForIndex(int index) {
    var offset = 0.0;
    for (var i = 0; i <= index && i < _visibleOptions.length; i++) {
      final option = _visibleOptions[i];
      final group = widget.groupLabel?.call(option);
      final previous = i == 0
          ? null
          : widget.groupLabel?.call(_visibleOptions[i - 1]);
      final showGroup = group != null && group.isNotEmpty && group != previous;
      if (showGroup) offset += _groupHeaderExtent;
      if (i < index) offset += _optionRowExtent;
    }
    return offset;
  }

  void _scrollHighlightIntoView() {
    if (!_optionsScrollController.hasClients) return;
    final index = _highlightIndex.value;
    if (index < 0) return;
    final target = _offsetForIndex(index);
    final view = _optionsScrollController.position;
    final top = view.pixels;
    final bottom = top + view.viewportDimension;
    final rowBottom = target + _optionRowExtent;
    if (target < top) {
      _optionsScrollController.jumpTo(target.clamp(0.0, view.maxScrollExtent));
    } else if (rowBottom > bottom) {
      _optionsScrollController.jumpTo(
        (rowBottom - view.viewportDimension).clamp(0.0, view.maxScrollExtent),
      );
    }
  }

  bool _selectHighlighted() {
    final index = _highlightIndex.value;
    if (index < 0 || index >= _visibleOptions.length) return false;
    final option = _visibleOptions[index];
    final select = _optionsOnSelected;
    if (select != null) {
      select(option);
    } else {
      _controller.text = option;
      widget.onChanged(option);
    }
    _highlightIndex.value = -1;
    _showAll = false;
    _focusNode.unfocus();
    return true;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_selectHighlighted()) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      _highlightIndex.value = -1;
      _showAll = false;
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleMenu() {
    if (!widget.enabled) return;
    if (_focusNode.hasFocus && _showAll) {
      _focusNode.unfocus();
      return;
    }
    _showAll = true;
    _showAllAnchor = _controller.text;
    _highlightIndex.value = -1;
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
      onSelected: (option) {
        _highlightIndex.value = -1;
        _showAll = false;
        widget.onChanged(option);
      },
      optionsViewBuilder: (context, onSelected, options) {
        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final width = box != null && box.hasSize ? box.size.width : 280.0;
        final list = options.toList(growable: false);
        _optionsOnSelected = onSelected;
        _syncVisibleOptions(list);
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
              child: ValueListenableBuilder<int>(
                valueListenable: _highlightIndex,
                builder: (context, highlighted, _) {
                  return ListView.builder(
                    controller: _optionsScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: !scrollLongList,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final option = list[index];
                      final selectedValue = option == (widget.value ?? '');
                      final isHighlighted = index == highlighted;
                      final group = widget.groupLabel?.call(option);
                      final previous = index == 0
                          ? null
                          : widget.groupLabel?.call(list[index - 1]);
                      final showGroup =
                          group != null &&
                          group.isNotEmpty &&
                          group != previous;
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
                              color: isHighlighted
                                  ? AppTheme.primaryNavy.withValues(alpha: 0.16)
                                  : selectedValue
                                  ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Text(
                                option,
                                style: fieldStyle.copyWith(
                                  fontWeight: isHighlighted || selectedValue
                                      ? FontWeight.w700
                                      : fieldStyle.fontWeight,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
          inputFormatters: InputRules.merge(
            widget.inputFormatters,
            fallback: InputRules.plainTextFormatters(maxLength: 200),
          ),
          onSubmitted: (_) {
            if (_selectHighlighted()) return;
            onSubmitted();
          },
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
            _highlightIndex.value = -1;
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
