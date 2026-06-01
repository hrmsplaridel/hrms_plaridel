import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'leave_status_chip.dart';

class AdminRow extends StatelessWidget {
  const AdminRow({
    super.key,
    required this.request,
    required this.onView,
    this.highlighted = false,
    this.statusLabel,
  });

  final LeaveRequest request;
  final VoidCallback onView;
  final bool highlighted;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final rowBg = highlighted
        ? (dark
              ? AppTheme.primaryNavy.withValues(alpha: 0.28)
              : AppTheme.primaryNavy.withValues(alpha: 0.05))
        : Colors.transparent;
    return Material(
      color: rowBg,
      child: InkWell(
        onTap: onView,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
            ),
          ),
          child: Row(
            children: [
              _flexCell(
                _kFlexEmployee,
                _cell(context, request.employeeName ?? 'Unknown'),
              ),
              _flexCell(
                _kFlexDepartment,
                _cell(context, request.officeDepartment ?? '—'),
              ),
              _flexCell(
                _kFlexLeaveType,
                _cell(context, request.leaveTypeLabel),
              ),
              _flexCell(_kFlexDateRange, _cell(context, _rangeText(request))),
              _flexCell(
                _kFlexDays,
                _cell(
                  context,
                  request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
                ),
              ),
              _flexCell(
                _kFlexStatus,
                Align(
                  alignment: Alignment.centerLeft,
                  child: LeaveStatusChip(
                    status: request.status,
                    label: statusLabel,
                  ),
                ),
              ),
              _flexCell(
                _kFlexSubmitted,
                _cell(
                  context,
                  request.dateFiled != null
                      ? _formatDate(request.dateFiled!)
                      : '—',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flexCell(int flex, Widget child) {
    return Expanded(flex: flex, child: child);
  }

  Widget _cell(BuildContext context, String text) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppTheme.dashTextPrimaryOf(context),
        fontSize: 12,
      ),
    );
  }

  String _rangeText(LeaveRequest request) {
    if (request.startDate == null || request.endDate == null) return '—';
    return '${_formatDate(request.startDate!)} – ${_formatDate(request.endDate!)}';
  }
}

class AdminTableHeader extends StatelessWidget {
  const AdminTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text) => Text(text, style: style);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: _kFlexEmployee, child: cell('Employee Name')),
          Expanded(flex: _kFlexDepartment, child: cell('Department')),
          Expanded(flex: _kFlexLeaveType, child: cell('Leave Type')),
          Expanded(flex: _kFlexDateRange, child: cell('Date Range')),
          Expanded(flex: _kFlexDays, child: cell('Days')),
          Expanded(flex: _kFlexStatus, child: cell('Status')),
          Expanded(flex: _kFlexSubmitted, child: cell('Submitted')),
        ],
      ),
    );
  }
}

/// Target column proportions (flex). Same totals as legacy fixed widths (~1170).
const int _kFlexEmployee = 170;
const int _kFlexDepartment = 140;
const int _kFlexLeaveType = 130;
const int _kFlexDateRange = 170;
const int _kFlexDays = 70;
const int _kFlexStatus = 150;
const int _kFlexSubmitted = 120;

/// Horizontal scroll minimum; equals sum of flex weights.
const double kAdminTableMinWidth =
    1.0 *
    (_kFlexEmployee +
        _kFlexDepartment +
        _kFlexLeaveType +
        _kFlexDateRange +
        _kFlexDays +
        _kFlexStatus +
        _kFlexSubmitted);

String _formatDate(DateTime value) {
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
