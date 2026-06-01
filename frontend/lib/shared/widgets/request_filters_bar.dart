import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// One status tab in [RequestFiltersBar] (`value: null` = All).
class RequestFilterOption<T> {
  const RequestFilterOption({required this.label, this.value});

  final String label;
  final T? value;
}

/// Search + date range + horizontally scrollable status tabs on mobile;
/// classic wrapped toolbar on wider screens.
class RequestFiltersBar<T> extends StatelessWidget {
  const RequestFiltersBar({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onStatusChanged,
    required this.visibleCount,
    required this.totalCount,
    this.searchQuery = '',
    this.onSearchChanged,
    this.fromDate,
    this.toDate,
    this.onPickFromDate,
    this.onPickToDate,
    this.onClearFilters,
    this.showSearch = true,
    this.showDateRange = true,
    this.mobileBreakpoint = 600,
    this.formatDate,
  });

  final List<RequestFilterOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T?> onStatusChanged;
  final int visibleCount;
  final int totalCount;
  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final DateTime? fromDate;
  final DateTime? toDate;
  final VoidCallback? onPickFromDate;
  final VoidCallback? onPickToDate;
  final VoidCallback? onClearFilters;
  final bool showSearch;
  final bool showDateRange;
  final double mobileBreakpoint;
  final String Function(DateTime)? formatDate;

  static String defaultFormatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _format(DateTime value) => (formatDate ?? defaultFormatDate)(value);

  bool get _hasSearchRow => showSearch || showDateRange;

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.dashInputBorderOf(context);
    final activePill = AppTheme.primaryNavy;
    final inactiveText = AppTheme.dashTextSecondaryOf(context);
    final isMobile = MediaQuery.sizeOf(context).width < mobileBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasSearchRow)
          isMobile
              ? _buildMobileSearchRow(context, border: border)
              : _buildDesktopSearchRow(
                  context,
                  border: border,
                  activePill: activePill,
                  inactiveText: inactiveText,
                ),
        if (_hasSearchRow) const SizedBox(height: 10),
        isMobile
            ? _buildMobileStatusTabs(
                context,
                activePill: activePill,
                inactiveText: inactiveText,
              )
            : _buildDesktopStatusTabs(
                context,
                activePill: activePill,
                inactiveText: inactiveText,
              ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '$visibleCount of $totalCount',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isMobile && onClearFilters != null)
              TextButton(
                onPressed: onClearFilters,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileSearchRow(BuildContext context, {required Color border}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSearch) ...[
          Expanded(
            flex: showDateRange ? 3 : 1,
            child: SizedBox(
              height: 40,
              child: TextFormField(
                key: ValueKey(searchQuery),
                initialValue: searchQuery,
                onChanged: onSearchChanged,
                style: AppTheme.dashFieldTextStyle(
                  context,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _filterDecoration(
                  context,
                  hintText: 'Search',
                  borderColor: border,
                  suffixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (showSearch && showDateRange) const SizedBox(width: 8),
        if (showDateRange) ...[
          Expanded(
            flex: 2,
            child: _dateButton(
              context,
              label: fromDate == null ? 'From' : _format(fromDate!),
              onPressed: onPickFromDate!,
              borderColor: border,
              compact: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _dateButton(
              context,
              label: toDate == null ? 'To' : _format(toDate!),
              onPressed: onPickToDate!,
              borderColor: border,
              compact: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopSearchRow(
    BuildContext context, {
    required Color border,
    required Color activePill,
    required Color inactiveText,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showSearch)
          SizedBox(
            width: 240,
            height: 36,
            child: TextFormField(
              key: ValueKey(searchQuery),
              initialValue: searchQuery,
              onChanged: onSearchChanged,
              style: AppTheme.dashFieldTextStyle(
                context,
              ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: _filterDecoration(
                context,
                hintText: 'Search',
                borderColor: border,
                suffixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ),
          ),
        if (showDateRange) ...[
          _dateButton(
            context,
            label: fromDate == null ? 'From' : _format(fromDate!),
            onPressed: onPickFromDate!,
            borderColor: border,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '-',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          _dateButton(
            context,
            label: toDate == null ? 'To' : _format(toDate!),
            onPressed: onPickToDate!,
            borderColor: border,
          ),
        ],
        ..._statusChips(
          context,
          activePill: activePill,
          inactiveText: inactiveText,
        ),
        if (onClearFilters != null)
          TextButton(
            onPressed: onClearFilters,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear'),
          ),
      ],
    );
  }

  Widget _buildMobileStatusTabs(
    BuildContext context, {
    required Color activePill,
    required Color inactiveText,
  }) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: _statusChips(
          context,
          activePill: activePill,
          inactiveText: inactiveText,
          trailingPadding: true,
        ),
      ),
    );
  }

  Widget _buildDesktopStatusTabs(
    BuildContext context, {
    required Color activePill,
    required Color inactiveText,
  }) {
    if (_hasSearchRow) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _statusChips(
        context,
        activePill: activePill,
        inactiveText: inactiveText,
      ),
    );
  }

  List<Widget> _statusChips(
    BuildContext context, {
    required Color activePill,
    required Color inactiveText,
    bool trailingPadding = false,
  }) {
    final chips = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final option = options[i];
      final chip = _statusChip(
        context,
        label: option.label,
        selected: selectedValue == option.value,
        onTap: () => onStatusChanged(option.value),
        selectedColor: activePill,
        unselectedTextColor: inactiveText,
      );
      if (trailingPadding && i < options.length - 1) {
        chips.add(
          Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        );
      } else {
        chips.add(chip);
      }
    }
    return chips;
  }

  Widget _dateButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    required Color borderColor,
    bool compact = false,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.dashTextSecondaryOf(context),
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 8 : 10,
        ),
        textStyle: TextStyle(
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icon(
        Icons.calendar_today_rounded,
        size: compact ? 14 : 16,
        color: AppTheme.dashTextSecondaryOf(context),
      ),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    return SizedBox(
      height: compact ? 40 : 36,
      width: compact ? double.infinity : null,
      child: button,
    );
  }

  Widget _statusChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color selectedColor,
    required Color unselectedTextColor,
  }) {
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? selectedColor
              : AppTheme.dashMutedSurfaceOf(context),
          foregroundColor: selected ? Colors.white : unselectedTextColor,
          side: BorderSide(color: AppTheme.dashHairlineOf(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  InputDecoration _filterDecoration(
    BuildContext context, {
    required String hintText,
    required Color borderColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTheme.dashFieldHintStyle(
        context,
      ).copyWith(fontWeight: FontWeight.w600),
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: AppTheme.dashInputFillOf(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.2),
      ),
    );
  }
}

/// Single filter pill (shared by [RequestFiltersBar] and [HorizontalFilterChips]).
class FilterStatusChip extends StatelessWidget {
  const FilterStatusChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 36,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? AppTheme.primaryNavy
              : AppTheme.dashMutedSurfaceOf(context),
          foregroundColor: selected
              ? Colors.white
              : AppTheme.dashTextSecondaryOf(context),
          side: BorderSide(color: AppTheme.dashHairlineOf(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Horizontally scrollable row of filter chips (e.g. admin leave status on mobile).
class HorizontalFilterChips<T> extends StatelessWidget {
  const HorizontalFilterChips({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.height = 40,
  });

  final List<RequestFilterOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T?> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i < options.length - 1 ? 8 : 0),
              child: FilterStatusChip(
                label: options[i].label,
                selected: selectedValue == options[i].value,
                onTap: () => onSelected(options[i].value),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact outlined date picker for mobile filter bars.
class CompactFilterDateButton extends StatelessWidget {
  const CompactFilterDateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.borderColor,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? AppTheme.dashInputBorderOf(context);
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.dashTextSecondaryOf(context),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(
          Icons.calendar_today_rounded,
          size: 14,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
