import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Scheduling-only presentation helpers (ADMIN → RSP → SCHEDULING).
///
/// Keeps the modern, compact card design consistent between the
/// Deliberation and Orientation schedulers without touching any other
/// RSP screen or shared app-wide widget.
class RspSchedulingUi {
  RspSchedulingUi._();

  static const double cardRadius = 16;
  static const double inputRadius = 11;
  static const double controlHeight = 44;

  static const List<String> _fullMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static Color accentOf(BuildContext context) => AppTheme.dashIsDark(context)
      ? AppTheme.primaryNavyLight
      : AppTheme.primaryNavy;

  /// Compact card container. [highlighted] draws a subtle orange accent
  /// border for the active/expanded card instead of a loud top bar.
  static BoxDecoration cardDecoration(
    BuildContext context, {
    bool highlighted = false,
  }) {
    final base = AppTheme.dashSurfaceCard(context, radius: cardRadius);
    if (!highlighted) return base;
    return base.copyWith(
      border: Border.all(
        color: accentOf(context).withValues(alpha: 0.45),
        width: 1.3,
      ),
    );
  }

  /// Single-line, ellipsized text for compact dropdown items — guards
  /// against horizontal overflow when a position name or label is long.
  static Widget ddText(String text) {
    return Text(text, overflow: TextOverflow.ellipsis, maxLines: 1, softWrap: false);
  }

  static InputDecoration filterDecoration(
    BuildContext context, {
    String? label,
    Widget? prefixIcon,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      labelText: label,
      prefixIcon: prefixIcon,
      radius: inputRadius,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  static Widget initialsAvatar(
    BuildContext context,
    String name, {
    double size = 42,
  }) {
    final parts = name.trim().split(RegExp(r'\s+'));
    var initials = '';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials += parts.first[0].toUpperCase();
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      initials += parts.last[0].toUpperCase();
    }
    if (initials.isEmpty) initials = '?';
    final ac = accentOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ac.withValues(alpha: 0.18), ac.withValues(alpha: 0.09)],
        ),
        border: Border.all(color: ac.withValues(alpha: 0.24)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'NotoSans',
          color: ac,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }

  /// Small pill badge used for scheduling status.
  static Widget statusBadge({
    required String label,
    required IconData icon,
    required Color fg,
    required Color bg,
    required Color border,
    double fontSize = 11.5,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'NotoSans',
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  /// Modern segmented navigation, e.g. [ Deliberation ] [ Orientation ].
  static Widget segmentedTabs<T>({
    required BuildContext context,
    required List<({T value, String label, IconData icon})> segments,
    required T selected,
    required ValueChanged<T> onChanged,
  }) {
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final ac = accentOf(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.circular(inputRadius + 3),
        border: Border.all(color: hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.map((s) {
          final active = s.value == selected;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? ac : Colors.transparent,
              borderRadius: BorderRadius.circular(inputRadius),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: ac.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(s.value),
                borderRadius: BorderRadius.circular(inputRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        s.icon,
                        size: 17,
                        color: active
                            ? Colors.white
                            : AppTheme.dashTextSecondaryOf(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.label,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: active
                              ? Colors.white
                              : AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// "Sort by" dropdown — Latest First (default) / Oldest First.
  static Widget sortDropdown({
    required BuildContext context,
    required bool latestFirst,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    double width = 178,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<bool>(
        initialValue: latestFirst,
        isExpanded: true,
        decoration: filterDecoration(
          context,
          label: 'Sort by',
          prefixIcon: const Icon(Icons.sort_rounded, size: 18),
        ),
        items: [
          DropdownMenuItem(value: true, child: ddText('Latest First')),
          DropdownMenuItem(value: false, child: ddText('Oldest First')),
        ],
        onChanged: enabled ? (v) => onChanged(v ?? true) : null,
      ),
    );
  }

  static Widget emptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    VoidCallback? onClearFilters,
  }) {
    return Container(
      width: double.infinity,
      decoration: cardDecoration(context),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentOf(context).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 28,
              color: accentOf(context).withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'NotoSans',
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'NotoSans',
              fontSize: 13,
              height: 1.5,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          if (onClearFilters != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Clear Filters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentOf(context),
                side: BorderSide(color: accentOf(context).withValues(alpha: 0.4)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// e.g. "September 13, 2026" — full month name, no weekday.
  static String formatLongDate(DateTime dt) {
    final d = dt.toLocal();
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Two-line compact date/time block, e.g. "September 13, 2026" / "8:26 PM".
  static Widget dateTimeBlock(
    BuildContext context,
    DateTime dt, {
    Color? color,
    double dateSize = 13.5,
    double timeSize = 12,
  }) {
    final local = dt.toLocal();
    final t = TimeOfDay.fromDateTime(local);
    final fg = color ?? accentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatLongDate(local),
          style: TextStyle(
            fontFamily: 'NotoSans',
            fontWeight: FontWeight.w700,
            fontSize: dateSize,
            color: fg,
            height: 1.25,
          ),
        ),
        Text(
          t.format(context),
          style: TextStyle(
            fontFamily: 'NotoSans',
            fontWeight: FontWeight.w600,
            fontSize: timeSize,
            color: AppTheme.dashTextSecondaryOf(context),
            height: 1.2,
          ),
        ),
      ],
    );
  }

  /// Responsive breakpoint helper for the two-column expanded layout.
  static bool isDesktopWidth(double width) => width >= 720;
}
