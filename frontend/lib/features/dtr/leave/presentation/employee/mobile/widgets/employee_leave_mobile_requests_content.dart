import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_card.dart';

class EmployeeLeaveMobileRequestsContent extends StatelessWidget {
  const EmployeeLeaveMobileRequestsContent({
    super.key,
    required this.filters,
    required this.requests,
    required this.allRequests,
    required this.loading,
    required this.useScrollableList,
    required this.maxListHeight,
    required this.openOnTap,
    required this.scrollController,
    required this.selectedRequestKey,
    required this.requestKey,
    required this.onOpenRequest,
    required this.onToggleSelection,
  });

  final Widget filters;
  final List<LeaveRequest> requests;
  final List<LeaveRequest> allRequests;
  final bool loading;
  final bool useScrollableList;
  final double maxListHeight;
  final bool openOnTap;
  final ScrollController scrollController;
  final String? selectedRequestKey;
  final String Function(LeaveRequest request) requestKey;
  final ValueChanged<LeaveRequest> onOpenRequest;
  final ValueChanged<LeaveRequest> onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final listOrEmpty = _buildListOrEmpty();
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [filters, const SizedBox(height: 12), listOrEmpty],
    );

    if (!useScrollableList || requests.isEmpty) {
      return body;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxListHeight),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          child: body,
        ),
      ),
    );
  }

  Widget _buildListOrEmpty() {
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

    final children = List.generate(requests.length, (index) {
      final request = requests[index];
      return Padding(
        padding: EdgeInsets.only(bottom: index == requests.length - 1 ? 0 : 12),
        child: _EmployeeLeaveMobileRequestItem(
          request: request,
          isSelected: !openOnTap && requestKey(request) == selectedRequestKey,
          onTap: () =>
              openOnTap ? onOpenRequest(request) : onToggleSelection(request),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _EmployeeLeaveMobileRequestItem extends StatelessWidget {
  const _EmployeeLeaveMobileRequestItem({
    required this.request,
    required this.isSelected,
    required this.onTap,
  });

  final LeaveRequest request;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LeaveCard(
      request: request,
      onTap: onTap,
      isSelected: isSelected,
      showActions: false,
      onViewDetails: () {},
      onViewHistory: () {},
      onCancel: null,
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
