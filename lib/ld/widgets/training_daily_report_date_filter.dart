import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Calendar-day helpers for training daily report date browsing.
class TrainingDailyReportDateUtils {
  TrainingDailyReportDateUtils._();

  static DateTime toLocalDate(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String formatDisplay(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// `YYYY-MM-DD` for API query params.
  static String formatQuery(DateTime d) => formatDisplay(d);

  static Future<DateTime?> pick({
    required BuildContext context,
    DateTime? current,
    List<DateTime> knownReportDays = const [],
    String helpText = 'Browse reports by date',
  }) async {
    final now = DateTime.now();
    final today = toLocalDate(now);
    final oneYearAgo = DateTime(today.year - 1, today.month, today.day);
    final DateTime firstDate;
    if (knownReportDays.isEmpty) {
      firstDate = oneYearAgo;
    } else {
      final oldest = knownReportDays.last;
      firstDate =
          oldest.isBefore(oneYearAgo) ? oldest : oneYearAgo;
    }
    var initial = current ?? (knownReportDays.isNotEmpty ? knownReportDays.first : today);
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(today)) initial = today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today,
      helpText: helpText,
      cancelText: 'Cancel',
      confirmText: 'Select',
    );
    if (picked == null) return null;
    return toLocalDate(picked);
  }
}

/// Date pill + prev/next + optional day chips for training report lists.
class TrainingDailyReportDateFilterBar extends StatelessWidget {
  const TrainingDailyReportDateFilterBar({
    super.key,
    required this.filterByDate,
    required this.datesWithReports,
    required this.onDateChanged,
    this.allowShowAll = true,
    this.countForDay,
  });

  final DateTime? filterByDate;
  final List<DateTime> datesWithReports;
  final ValueChanged<DateTime?> onDateChanged;
  final bool allowShowAll;
  final int Function(DateTime day)? countForDay;

  static const Color _accent = Color(0xFFF0671A);

  Future<void> _pick(BuildContext context) async {
    final picked = await TrainingDailyReportDateUtils.pick(
      context: context,
      current: filterByDate,
      knownReportDays: datesWithReports,
    );
    if (picked != null) onDateChanged(picked);
  }

  void _shift(int delta) {
    final today = TrainingDailyReportDateUtils.toLocalDate(DateTime.now());
    final base = filterByDate ?? today;
    final next = base.add(Duration(days: delta));
    if (next.isAfter(today)) return;
    onDateChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final filtering = filterByDate != null;
    final pillLabel = filtering
        ? TrainingDailyReportDateUtils.formatDisplay(filterByDate!)
        : 'All dates';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: AppTheme.primaryNavy.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Browse by date',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (allowShowAll && filtering)
                TextButton(
                  onPressed: () => onDateChanged(null),
                  child: const Text('Show all'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the date to open the calendar, or use the arrows to move day by day.',
            style: TextStyle(
              color: secondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: Semantics(
                    button: true,
                    label: 'Selected date $pillLabel. Tap to open calendar.',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _pick(context),
                          borderRadius: BorderRadius.circular(20),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: AppTheme.dashPanelOf(context),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.55),
                                width: 1.2,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 18,
                                  color: _accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  pillLabel,
                                  style: const TextStyle(
                                    color: _accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 22,
                                  color: _accent.withValues(alpha: 0.9),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Next day',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
          if (datesWithReports.length > 1) ...[
            const SizedBox(height: 14),
            Text(
              'Days with reports',
              style: TextStyle(
                color: secondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.55,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: datesWithReports.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = datesWithReports[index];
                  final selected = filtering && filterByDate == day;
                  final count = countForDay?.call(day);
                  final chipLabel = count != null
                      ? '${TrainingDailyReportDateUtils.formatDisplay(day)} ($count)'
                      : TrainingDailyReportDateUtils.formatDisplay(day);
                  return InputChip(
                    label: Text(
                      chipLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? _accent : primary,
                      ),
                    ),
                    avatar: Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: selected
                          ? _accent
                          : AppTheme.primaryNavy.withValues(alpha: 0.7),
                    ),
                    onPressed: () => onDateChanged(day),
                    backgroundColor: selected
                        ? _accent.withValues(alpha: 0.12)
                        : AppTheme.dashMutedSurfaceOf(context),
                    side: BorderSide(
                      color: selected
                          ? _accent.withValues(alpha: 0.55)
                          : AppTheme.dashHairlineOf(context),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
