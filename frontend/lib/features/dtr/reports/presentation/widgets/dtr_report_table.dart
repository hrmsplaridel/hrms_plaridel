import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_formatting.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

/// Day-by-day DTR table (punches, late, undertime, remarks) for one employee.
class DtrReportTable extends StatelessWidget {
  const DtrReportTable({
    super.key,
    required this.end,
    required this.recordsByDate,
    required this.sortedDates,
    required this.showMinutesFormat,
    required this.shiftPunchMode,
    required this.reportLoading,
    required this.statsInclusiveEnd,
    required this.isScheduledWorkDay,
    required this.assignmentEffectiveFrom,
    this.compactColumns = false,
    this.availableWidth,
  });

  final DateTime end;
  final Map<DateTime, TimeRecord> recordsByDate;
  final List<DateTime> sortedDates;
  final bool compactColumns;
  final double? availableWidth;
  final bool showMinutesFormat;
  final String? shiftPunchMode;
  final bool reportLoading;
  final DateTime statsInclusiveEnd;
  final bool Function(DateTime date) isScheduledWorkDay;
  final DateTime? assignmentEffectiveFrom;

  @override
  Widget build(BuildContext context) {
    final availableWidth = this.availableWidth;
    final visibleRecords = sortedDates
        .map((date) => recordsByDate[date])
        .whereType<TimeRecord>()
        .toList();
    final singleSession = visibleRecords.isEmpty
        ? shiftPunchMode == 'single_session'
        : visibleRecords.every(
            (record) => record.shiftPunchMode == 'single_session',
          );
    final genericHeaders =
        singleSession ||
        visibleRecords.any(
          (record) =>
              record.shiftIsOvernight ||
              record.shiftPunchMode == 'single_session',
        );
    final colDate = compactColumns ? 80.0 : 90.0;
    final colTime = compactColumns ? 84.0 : 96.0;
    final colLate = compactColumns ? 48.0 : 58.0;
    final colUndertime = compactColumns ? 72.0 : 78.0;
    final minTableWidth = compactColumns
        ? (colDate +
              colTime * (singleSession ? 2 : 4) +
              colLate +
              colUndertime +
              100)
        : colDate +
              colTime * (singleSession ? 2 : 4) +
              colLate +
              colUndertime +
              140;
    final tableWidth = availableWidth != null
        ? availableWidth.clamp(minTableWidth, double.infinity)
        : minTableWidth;
    final dark = AppTheme.dashIsDark(context);
    final cellStyle = TextStyle(
      fontSize: 12,
      color: AppTheme.dashTextPrimaryOf(context),
    );
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: compactColumns ? 11 : 12,
      color: AppTheme.dashTextPrimaryOf(context),
    );
    final statsEnd = statsInclusiveEnd;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Container(
          decoration: AppTheme.dashSurfaceCard(context, radius: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.dashMutedSurfaceOf(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: colDate,
                      child: Text('Date', style: headerStyle),
                    ),
                    SizedBox(
                      width: colTime,
                      child: Text(
                        genericHeaders ? 'TIME IN' : 'AM IN',
                        style: headerStyle,
                      ),
                    ),
                    if (!singleSession)
                      SizedBox(
                        width: colTime,
                        child: Text(
                          genericHeaders ? 'BREAK OUT' : 'AM OUT',
                          style: headerStyle,
                        ),
                      ),
                    if (!singleSession)
                      SizedBox(
                        width: colTime,
                        child: Text(
                          genericHeaders ? 'BREAK IN' : 'PM IN',
                          style: headerStyle,
                        ),
                      ),
                    SizedBox(
                      width: colTime,
                      child: Text(
                        genericHeaders ? 'TIME OUT' : 'PM OUT',
                        style: headerStyle,
                      ),
                    ),
                    SizedBox(
                      width: colLate,
                      child: Text('Late', style: headerStyle),
                    ),
                    SizedBox(
                      width: colUndertime,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Undertime',
                          style: headerStyle,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    Expanded(child: Text('Remarks', style: headerStyle)),
                  ],
                ),
              ),
              Expanded(
                child: reportLoading
                    ? const SingleChildScrollView(
                        child: WorkforceRowsSkeleton(
                          columns: [2, 1, 1, 1, 1, 1, 1, 2],
                          rows: 8,
                          label: 'Loading attendance report',
                        ),
                      )
                    : sortedDates.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No DTR records for this period',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: sortedDates.length,
                        itemBuilder: (context, i) {
                          final dt = sortedDates[i];
                          final rec = recordsByDate[dt];
                          final isScheduled =
                              assignmentEffectiveFrom != null &&
                              isScheduledWorkDay(dt);
                          final isQuietPlaceholder =
                              rec == null &&
                              (!isScheduled || dt.isAfter(statsEnd));
                          final isMissingScheduledWorkDay =
                              rec == null && !isQuietPlaceholder;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: i % 2 == 0
                                  ? AppTheme.dashPanelOf(context)
                                  : AppTheme.dashMutedSurfaceOf(
                                      context,
                                    ).withValues(alpha: dark ? 0.65 : 1),
                              border: Border(
                                bottom: BorderSide(
                                  color: AppTheme.dashHairlineOf(
                                    context,
                                  ).withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: colDate,
                                  child: Text(
                                    formatDtrReportDate(dt),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : dtrCellDisplayForSegment(
                                            record: rec,
                                            timeValue:
                                                rec.timeIn ??
                                                (singleSession
                                                    ? rec.breakIn
                                                    : null),
                                            segment: 'AM IN',
                                          ),
                                    style: cellStyle,
                                  ),
                                ),
                                if (!singleSession)
                                  SizedBox(
                                    width: colTime,
                                    child: Text(
                                      rec == null
                                          ? '—'
                                          : dtrCellDisplayForSegment(
                                              record: rec,
                                              timeValue: rec.breakOut,
                                              segment: 'AM OUT',
                                            ),
                                      style: cellStyle,
                                    ),
                                  ),
                                if (!singleSession)
                                  SizedBox(
                                    width: colTime,
                                    child: Text(
                                      rec == null
                                          ? '—'
                                          : dtrCellDisplayForSegment(
                                              record: rec,
                                              timeValue: rec.breakIn,
                                              segment: 'PM IN',
                                            ),
                                      style: cellStyle,
                                    ),
                                  ),
                                SizedBox(
                                  width: colTime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : dtrCellDisplayForSegment(
                                            record: rec,
                                            timeValue:
                                                rec.timeOut ??
                                                (singleSession
                                                    ? rec.breakOut
                                                    : null),
                                            segment: 'PM OUT',
                                          ),
                                    style: cellStyle,
                                  ),
                                ),
                                SizedBox(
                                  width: colLate,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : formatDtrMinutes(rec.lateMinutes),
                                    style: cellStyle.copyWith(
                                      color: (rec?.lateMinutes ?? 0) > 0
                                          ? (dark
                                                ? Colors.red.shade300
                                                : Colors.red.shade700)
                                          : AppTheme.dashTextPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: colUndertime,
                                  child: Text(
                                    rec == null
                                        ? '—'
                                        : formatDtrMinutes(
                                            rec.undertimeMinutes,
                                          ),
                                    style: cellStyle.copyWith(
                                      color: (rec?.undertimeMinutes ?? 0) > 0
                                          ? (dark
                                                ? Colors.orange.shade300
                                                : Colors.orange.shade700)
                                          : AppTheme.dashTextPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Builder(
                                    builder: (rowCtx) {
                                      final remark = dtrReportRowRemark(
                                        record: rec,
                                        isQuietPlaceholder: isQuietPlaceholder,
                                        isMissingScheduledWorkDay:
                                            isMissingScheduledWorkDay,
                                      );
                                      final isHoliday =
                                          rec?.status == 'holiday' ||
                                          rec?.holidayId != null;
                                      return Text(
                                        remark,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorForRemarkText(
                                            rowCtx,
                                            remark,
                                            isHoliday: isHoliday,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
