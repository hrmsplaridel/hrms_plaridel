import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';

/// Relative widths for the request table columns. Header and data rows share
/// these flex values so the columns stay aligned.
const List<int> _columnFlex = <int>[30, 26, 10, 18, 16];

class EmployeeLeaveDesktopRequestsContent extends StatelessWidget {
  const EmployeeLeaveDesktopRequestsContent({
    super.key,
    required this.filters,
    required this.requests,
    required this.allRequests,
    required this.loading,
    required this.maxListHeight,
    required this.scrollController,
    required this.onOpenRequest,
  });

  final Widget filters;
  final List<LeaveRequest> requests;
  final List<LeaveRequest> allRequests;
  final bool loading;
  final double maxListHeight;
  final ScrollController scrollController;
  final ValueChanged<LeaveRequest> onOpenRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filters,
        const SizedBox(height: 16),
        _buildTableOrEmpty(context),
      ],
    );
  }

  Widget _buildTableOrEmpty(BuildContext context) {
    if (loading && allRequests.isEmpty) {
      return const _DesktopCenteredState(message: 'Loading leave requests...');
    }
    if (allRequests.isEmpty) {
      return const _DesktopCenteredState(
        message:
            'No leave requests yet. Start by filing your first leave request.',
      );
    }
    if (requests.isEmpty) {
      return const _DesktopCenteredState(
        message: 'No leave requests match the current filters.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LeaveTableHeader(),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: scrollController,
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: requests.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return _LeaveTableRow(
                    request: request,
                    onTap: () => onOpenRequest(request),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveTableHeader extends StatelessWidget {
  const _LeaveTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    return Container(
      color: AppTheme.dashMutedSurfaceOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: _columnFlex[0],
            child: Text('Leave Type', style: style),
          ),
          Expanded(
            flex: _columnFlex[1],
            child: Text('Date Range', style: style),
          ),
          Expanded(
            flex: _columnFlex[2],
            child: Text('Days', style: style),
          ),
          Expanded(
            flex: _columnFlex[3],
            child: Text('Submitted', style: style),
          ),
          Expanded(
            flex: _columnFlex[4],
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Status', style: style),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveTableRow extends StatelessWidget {
  const _LeaveTableRow({required this.request, required this.onTap});

  final LeaveRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryStyle = TextStyle(
      color: AppTheme.dashTextPrimaryOf(context),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final secondaryStyle = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context),
      fontSize: 13,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: _columnFlex[0],
                child: Text(
                  request.leaveTypeLabel,
                  style: primaryStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: _columnFlex[1],
                child: Text(
                  _formatRange(request),
                  style: secondaryStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: _columnFlex[2],
                child: Text(
                  request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
                  style: secondaryStyle,
                ),
              ),
              Expanded(
                flex: _columnFlex[3],
                child: Text(
                  request.dateFiled != null
                      ? _formatDate(request.dateFiled!)
                      : '—',
                  style: secondaryStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: _columnFlex[4],
                child: Align(
                  alignment: Alignment.centerRight,
                  child: LeaveStatusChip(status: request.status),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopCenteredState extends StatelessWidget {
  const _DesktopCenteredState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

String _formatRange(LeaveRequest request) {
  if (request.startDate == null || request.endDate == null) {
    return 'Date not set';
  }
  return '${_formatDate(request.startDate!)} – ${_formatDate(request.endDate!)}';
}

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
