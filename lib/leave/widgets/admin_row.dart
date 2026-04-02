import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'leave_status_chip.dart';

class AdminRow extends StatelessWidget {
  const AdminRow({
    super.key,
    required this.request,
    required this.onView,
    this.onApprove,
    this.onReject,
    this.highlighted = false,
    this.statusLabel,
  });

  final LeaveRequest request;
  final VoidCallback onView;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final rowBg = highlighted
        ? AppTheme.primaryNavy.withOpacity(0.05)
        : AppTheme.white;
    return Material(
      color: rowBg,
      child: InkWell(
        onTap: onView,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              _fixedCell(
                _kColEmployee,
                _cell(request.employeeName ?? 'Unknown'),
              ),
              _fixedCell(
                _kColDepartment,
                _cell(request.officeDepartment ?? '—'),
              ),
              _fixedCell(_kColLeaveType, _cell(request.leaveType.displayName)),
              _fixedCell(_kColDateRange, _cell(_rangeText(request))),
              _fixedCell(
                _kColDays,
                _cell(request.workingDaysApplied?.toStringAsFixed(1) ?? '—'),
              ),
              _fixedCell(
                _kColStatus,
                Align(
                  alignment: Alignment.centerLeft,
                  child: LeaveStatusChip(
                    status: request.status,
                    label: statusLabel,
                  ),
                ),
              ),
              _fixedCell(
                _kColSubmitted,
                _cell(
                  request.dateFiled != null
                      ? _formatDate(request.dateFiled!)
                      : '—',
                ),
              ),
              _fixedCell(_kColActions, _actions()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        if (onApprove != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton.tonal(
              onPressed: onApprove,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Approve'),
            ),
          ),
        if (onReject != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedButton(
              onPressed: onReject,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Reject'),
            ),
          ),
        OutlinedButton(
          onPressed: onView,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('View'),
        ),
      ],
    );
  }

  Widget _fixedCell(double width, Widget child) {
    return SizedBox(width: width, child: child);
  }

  Widget _cell(String text) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
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
    TextStyle style = TextStyle(
      color: AppTheme.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text) => Text(text, style: style);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        border: Border(
          bottom: BorderSide(color: Colors.black.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: _kColEmployee, child: cell('Employee Name')),
          SizedBox(width: _kColDepartment, child: cell('Department')),
          SizedBox(width: _kColLeaveType, child: cell('Leave Type')),
          SizedBox(width: _kColDateRange, child: cell('Date Range')),
          SizedBox(width: _kColDays, child: cell('Days')),
          SizedBox(width: _kColStatus, child: cell('Status')),
          SizedBox(width: _kColSubmitted, child: cell('Submitted')),
          SizedBox(width: _kColActions, child: cell('Actions')),
        ],
      ),
    );
  }
}

const double _kColEmployee = 170;
const double _kColDepartment = 140;
const double _kColLeaveType = 130;
const double _kColDateRange = 170;
const double _kColDays = 70;
const double _kColStatus = 150;
const double _kColSubmitted = 120;
const double _kColActions = 220;
const double kAdminTableMinWidth =
    _kColEmployee +
    _kColDepartment +
    _kColLeaveType +
    _kColDateRange +
    _kColDays +
    _kColStatus +
    _kColSubmitted +
    _kColActions;

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
