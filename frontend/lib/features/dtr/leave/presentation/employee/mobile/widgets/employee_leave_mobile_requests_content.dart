import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';

class EmployeeLeaveMobileRequestsContent extends StatelessWidget {
  const EmployeeLeaveMobileRequestsContent({
    super.key,
    required this.filters,
    required this.requests,
    required this.allRequests,
    required this.loading,
    required this.useScrollableList,
    required this.maxListHeight,
    required this.scrollController,
    required this.onOpenRequest,
  });

  final Widget filters;
  final List<LeaveRequest> requests;
  final List<LeaveRequest> allRequests;
  final bool loading;
  final bool useScrollableList;
  final double maxListHeight;
  final ScrollController scrollController;
  final ValueChanged<LeaveRequest> onOpenRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filters,
        const SizedBox(height: 12),
        _buildListArea(),
      ],
    );
  }

  Widget _buildListArea() {
    if (loading && allRequests.isEmpty) {
      return const _MobileCenteredState(message: 'Loading leave requests...');
    }
    if (allRequests.isEmpty) {
      return const _MobileCenteredState(
        message:
            'No leave requests yet. Start by filing your first leave request.',
      );
    }
    if (requests.isEmpty) {
      return const _MobileCenteredState(
        message: 'No leave requests match the current filters.',
      );
    }

    final list = ListView.separated(
      controller: scrollController,
      shrinkWrap: true,
      physics: useScrollableList
          ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
          : const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = requests[index];
        return _MobileLeaveRequestCard(
          request: request,
          onTap: () => onOpenRequest(request),
        );
      },
    );

    if (!useScrollableList) {
      return list;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxListHeight),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        child: list,
      ),
    );
  }
}

class _MobileLeaveRequestCard extends StatelessWidget {
  const _MobileLeaveRequestCard({required this.request, required this.onTap});

  final LeaveRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      request.leaveTypeLabel,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  LeaveStatusChip(status: request.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatRange(request),
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Days: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
                    ),
                    const TextSpan(text: '    •    '),
                    const TextSpan(
                      text: 'Submitted: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: request.dateFiled != null
                          ? _formatDate(request.dateFiled!)
                          : '—',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileCenteredState extends StatelessWidget {
  const _MobileCenteredState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
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
