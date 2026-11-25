import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_formatting.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

/// Employee summary beside the DTR table: totals, unit toggle, and the
/// preview / print / export actions (supplied by the reports page).
class DtrReportSummaryCard extends StatelessWidget {
  const DtrReportSummaryCard({
    super.key,
    required this.loading,
    required this.selectedName,
    required this.periodLabel,
    required this.workingDays,
    required this.absentCount,
    required this.totalLateMinutes,
    required this.totalUndertimeMinutes,
    required this.hideCounts,
    required this.showMinutesFormat,
    required this.onShowMinutesFormatChanged,
    required this.resolveEquivalentDay,
    required this.actionsEnabled,
    required this.onPreview,
    required this.onPrint,
    required this.onExportPdf,
    required this.onExportWord,
    required this.onExportExcel,
    this.fullWidth = false,
    this.isResponsive = false,
    this.dense = false,
  });

  final bool loading;
  final String selectedName;
  final String periodLabel;
  final int workingDays;
  final int absentCount;
  final int totalLateMinutes;
  final int totalUndertimeMinutes;

  /// Working days and absences show a dash while inactive-period attendance is unverified.
  final bool hideCounts;
  final bool showMinutesFormat;
  final ValueChanged<bool> onShowMinutesFormatChanged;

  /// Official equivalent day; null when it cannot be verified. Called only when not loading.
  final double? Function() resolveEquivalentDay;
  final bool actionsEnabled;
  final VoidCallback onPreview;
  final VoidCallback onPrint;
  final VoidCallback onExportPdf;
  final VoidCallback onExportWord;
  final VoidCallback onExportExcel;
  final bool fullWidth;
  final bool isResponsive;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        width: fullWidth ? double.infinity : 200,
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.dashSurfaceCard(context, radius: 12),
        child: const SingleChildScrollView(
          child: WorkforceRowsSkeleton(
            columns: [1, 1],
            rows: 4,
            cellHeight: 40,
            label: 'Loading report summary',
          ),
        ),
      );
    }
    final dark = AppTheme.dashIsDark(context);
    final compactPanel = dense || !fullWidth;
    final equivalentDay = resolveEquivalentDay();
    return Container(
      width: fullWidth ? null : 200,
      constraints: fullWidth
          ? const BoxConstraints(maxHeight: 600)
          : const BoxConstraints(maxWidth: 200),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compactPanel ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleAvatar(
              radius: compactPanel ? 24 : 32,
              backgroundColor: AppTheme.primaryNavy.withValues(
                alpha: dark ? 0.35 : 0.2,
              ),
              child: Icon(
                Icons.person_rounded,
                size: compactPanel ? 26 : 32,
                color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
              ),
            ),
            SizedBox(height: compactPanel ? 8 : 12),
            Text(
              selectedName,
              style: TextStyle(
                fontSize: compactPanel ? 14 : 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              textAlign: TextAlign.center,
              maxLines: compactPanel ? 2 : null,
              overflow: compactPanel ? TextOverflow.ellipsis : null,
            ),
            SizedBox(height: compactPanel ? 2 : 4),
            Text(
              periodLabel,
              style: TextStyle(
                fontSize: compactPanel ? 11 : 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: compactPanel ? 8 : 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Show time as:',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('Min')),
                            ButtonSegment(value: false, label: Text('Hrs')),
                          ],
                          selected: {showMinutesFormat},
                          onSelectionChanged: (selected) {
                            onShowMinutesFormatChanged(selected.first);
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStateProperty.all(
                              EdgeInsets.symmetric(
                                horizontal: compactPanel ? 8 : 12,
                                vertical: compactPanel ? 4 : 6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: compactPanel ? 10 : 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stats = [
                  _SummaryStat(
                    label: 'Working Days',
                    value: hideCounts ? '—' : '$workingDays',
                    compact: compactPanel,
                  ),
                  _SummaryStat(
                    label: 'Late',
                    value: formatDtrMinutesOrHours(
                      totalLateMinutes,
                      showMinutes: showMinutesFormat,
                    ),
                    hasBorder: true,
                    borderColor: totalLateMinutes > 0
                        ? Colors.red
                        : const Color(0xFF4CAF50),
                    compact: compactPanel,
                  ),
                  _SummaryStat(
                    label: 'Undertime',
                    value: formatDtrMinutesOrHours(
                      totalUndertimeMinutes,
                      showMinutes: showMinutesFormat,
                    ),
                    hasBorder: totalUndertimeMinutes > 0,
                    borderColor: Colors.orange,
                    compact: compactPanel,
                  ),
                  _SummaryStat(
                    label: 'Absent',
                    value: hideCounts ? '—' : '$absentCount',
                    hasBorder: absentCount > 0,
                    borderColor: Colors.orange,
                    compact: compactPanel,
                  ),
                ];
                if (compactPanel || isResponsive) {
                  final gap = compactPanel ? 8.0 : 12.0;
                  final columns = dense && constraints.maxWidth >= 330 ? 3 : 2;
                  final width = compactPanel
                      ? ((constraints.maxWidth - (gap * (columns - 1))) /
                                columns)
                            .clamp(72.0, 140.0)
                      : 140.0;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final stat in stats)
                        SizedBox(width: width, child: stat),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      stats[i],
                    ],
                  ],
                );
              },
            ),
            SizedBox(height: compactPanel ? 10 : 16),
            Text(
              'Equivalent Day: ${equivalentDay == null ? 'Unverified' : formatDtrEquivalentDay(equivalentDay)}',
              style: TextStyle(
                fontSize: compactPanel ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              textAlign: TextAlign.start,
            ),
            SizedBox(height: compactPanel ? 12 : 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: actionsEnabled ? onPreview : null,
                icon: const Icon(Icons.preview_rounded, size: 18),
                label: const Text('PREVIEW'),
              ),
            ),
            SizedBox(height: compactPanel ? 8 : 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: actionsEnabled ? onPrint : null,
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('PRINT CURRENT'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.white,
                  padding: EdgeInsets.symmetric(
                    vertical: compactPanel ? 10 : 12,
                    horizontal: compactPanel ? 10 : 16,
                  ),
                ),
              ),
            ),
            SizedBox(height: compactPanel ? 8 : 12),
            Text(
              'Generate DTR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
            SizedBox(height: compactPanel ? 6 : 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: actionsEnabled
                    ? () {
                        showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: AppTheme.dashPanelOf(context),
                          builder: (ctx) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Export DTR as',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.dashTextPrimaryOf(ctx),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      'PDF',
                                      style: TextStyle(
                                        color: AppTheme.dashTextPrimaryOf(ctx),
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      onExportPdf();
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.description,
                                      color: Colors.blue,
                                    ),
                                    title: Text(
                                      'Word (.doc)',
                                      style: TextStyle(
                                        color: AppTheme.dashTextPrimaryOf(ctx),
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      onExportWord();
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.table_chart,
                                      color: Colors.green,
                                    ),
                                    title: Text(
                                      'Excel (.xlsx)',
                                      style: TextStyle(
                                        color: AppTheme.dashTextPrimaryOf(ctx),
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      onExportExcel();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: dark
                      ? Colors.green.shade900.withValues(alpha: 0.4)
                      : const Color(0xFFE8F5E9),
                  foregroundColor: dark
                      ? Colors.green.shade300
                      : const Color(0xFF2E7D32),
                  side: BorderSide(
                    color: dark
                        ? Colors.green.shade700
                        : const Color(0xFF81C784),
                  ),
                ),
                child: const Text('GENERATE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    this.hasBorder = false,
    this.borderColor = Colors.grey,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool hasBorder;
  final Color borderColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 50 : 0),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(8),
        border: hasBorder ? Border.all(color: borderColor, width: 1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
