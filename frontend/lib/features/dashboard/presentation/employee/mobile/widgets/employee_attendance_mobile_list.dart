import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/attendance_overview/attendance_overview_data.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_source_badge.dart';

typedef EmployeeAttendanceTimeFormatter =
    String Function(TimeRecord record, DateTime? dateTime, String segment);

class EmployeeAttendanceMobileList extends StatelessWidget {
  const EmployeeAttendanceMobileList({
    super.key,
    required this.records,
    required this.formatDate,
    required this.formatTime,
  });

  final List<TimeRecord> records;
  final String Function(DateTime date) formatDate;
  final EmployeeAttendanceTimeFormatter formatTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < records.length; i++) ...[
          EmployeeAttendanceMobileCard(
            dateLabel: formatDate(records[i].recordDate),
            amIn: formatTime(records[i], records[i].timeIn?.toLocal(), 'AM IN'),
            amOut: formatTime(
              records[i],
              records[i].breakOut?.toLocal(),
              'AM OUT',
            ),
            pmIn: formatTime(
              records[i],
              records[i].breakIn?.toLocal(),
              'PM IN',
            ),
            pmOut: formatTime(
              records[i],
              records[i].timeOut?.toLocal(),
              'PM OUT',
            ),
            late: formatLateMinutes(records[i]),
            undertime: formatUndertimeMinutes(records[i]),
            remark: getAttendanceRemark(records[i]),
            isHoliday:
                records[i].status == 'holiday' || records[i].holidayId != null,
            source: records[i].source,
          ),
          if (i != records.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class EmployeeAttendanceMobileCard extends StatelessWidget {
  const EmployeeAttendanceMobileCard({
    super.key,
    required this.dateLabel,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    required this.late,
    required this.undertime,
    required this.remark,
    required this.isHoliday,
    required this.source,
  });

  final String dateLabel;
  final String amIn;
  final String amOut;
  final String pmIn;
  final String pmOut;
  final String late;
  final String undertime;
  final String remark;
  final bool isHoliday;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AttendanceOverviewColors.present.withValues(
                    alpha: dark ? 0.24 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: AttendanceOverviewColors.present,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Daily time record',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AttendanceRemarksChip(
                    remark: remark,
                    isHoliday: isHoliday,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _EmployeeAttendanceTimeTile(
                      icon: Icons.login_rounded,
                      label: 'AM In',
                      value: amIn,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _EmployeeAttendanceTimeTile(
                      icon: Icons.logout_rounded,
                      label: 'AM Out',
                      value: amOut,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _EmployeeAttendanceTimeTile(
                      icon: Icons.login_rounded,
                      label: 'PM In',
                      value: pmIn,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _EmployeeAttendanceTimeTile(
                      icon: Icons.logout_rounded,
                      label: 'PM Out',
                      value: pmOut,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _EmployeeAttendanceMetaChip(
                icon: Icons.timer_outlined,
                label: 'Late',
                value: late,
              ),
              _EmployeeAttendanceMetaChip(
                icon: Icons.hourglass_bottom_rounded,
                label: 'Undertime',
                value: undertime,
              ),
              if ((source ?? '').trim().isNotEmpty)
                AttendanceSourceBadge(source: source, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmployeeAttendanceTimeTile extends StatelessWidget {
  const _EmployeeAttendanceTimeTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != '—';
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: hasValue
                ? AppTheme.primaryNavy
                : AppTheme.dashTextSecondaryOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasValue
                        ? AppTheme.dashTextPrimaryOf(context)
                        : AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeAttendanceMetaChip extends StatelessWidget {
  const _EmployeeAttendanceMetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.dashTextSecondaryOf(context)),
          const SizedBox(width: 5),
          Text(
            '$label: $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
