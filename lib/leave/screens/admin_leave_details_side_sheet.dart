import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../leave_provider.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import '../utils/open_attachment_io.dart'
    if (dart.library.html) '../utils/open_attachment_web.dart'
    as open_attachment;
import '../widgets/history_timeline.dart';
import '../widgets/leave_status_chip.dart';
import 'admin_leave_screen_utils.dart';
import 'admin_leave_shared_widgets.dart';

/// Leave review details shown over the queue (matches [openResponsiveLeaveFormHost] behavior).
class AdminLeaveDetailsSideSheet extends StatelessWidget {
  const AdminLeaveDetailsSideSheet({
    super.key,
    required this.initial,
    required this.isDepartmentHead,
    required this.onApprove,
    required this.onReturn,
    required this.onReject,
    required this.onPrint,
    this.onRevoke,
  });

  final LeaveRequest initial;
  final bool isDepartmentHead;
  final Future<void> Function(LeaveRequest) onApprove;
  final Future<void> Function(LeaveRequest) onReturn;
  final Future<void> Function(LeaveRequest) onReject;
  final Future<void> Function(LeaveRequest)? onRevoke;
  final Future<void> Function(LeaveRequest) onPrint;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            color: AppTheme.offWhite,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Request details',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<LeaveProvider>(
              builder: (context, provider, _) {
                var req = initial;
                final id = initial.id;
                if (id != null && id.isNotEmpty) {
                  final hit = provider.requests
                      .where((r) => r.id == id)
                      .toList();
                  if (hit.isNotEmpty) req = hit.first;
                }
                final canReview = isDepartmentHead
                    ? req.status == LeaveRequestStatus.pendingDepartmentHead
                    : req.status.isPending;
                final approved = req.status == LeaveRequestStatus.approved;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: _AdminLeaveRequestDetailsPanel(
                    request: req,
                    isDepartmentHead: isDepartmentHead,
                    reviewing: provider.reviewing,
                    onApprove: canReview ? () => onApprove(req) : null,
                    onReturn: canReview ? () => onReturn(req) : null,
                    onReject: canReview ? () => onReject(req) : null,
                    onRevoke: approved && onRevoke != null
                        ? () => onRevoke!(req)
                        : null,
                    onPrint: () => onPrint(req),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLeaveRequestDetailsPanel extends StatelessWidget {
  const _AdminLeaveRequestDetailsPanel({
    required this.request,
    required this.isDepartmentHead,
    required this.reviewing,
    this.onApprove,
    this.onReturn,
    this.onReject,
    this.onRevoke, // #15
    this.onPrint,
  });

  final LeaveRequest? request;
  final bool isDepartmentHead;
  final bool reviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReturn;
  final VoidCallback? onReject;
  final VoidCallback? onRevoke; // #15
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    if (request == null) {
      return const AdminLeaveSectionCard(
        title: 'Request Details',
        subtitle: 'Select a request from the queue to review it.',
        child: AdminLeaveCenteredState(message: 'No request selected.'),
      );
    }

    return AdminLeaveSectionCard(
      title: 'Request Details',
      subtitle: 'Review the employee application before taking action.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request!.employeeName ?? 'Unknown employee',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      request!.leaveTypeLabel,
                      style: TextStyle(
                        color: AppTheme.primaryNavyDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              LeaveStatusChip(
                status: request!.status,
                label: adminLeaveStatusLabel(
                  request!.status,
                  isDepartmentHead: isDepartmentHead,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AdminLeaveDetailPill(
                label: 'Date Filed',
                value: request!.dateFiled != null
                    ? formatAdminLeaveDate(request!.dateFiled!)
                    : '—',
              ),
              AdminLeaveDetailPill(
                label: 'Inclusive Dates',
                value: _formatRange(request!),
              ),
              AdminLeaveDetailPill(
                label: 'Working Days',
                value: request!.workingDaysApplied?.toStringAsFixed(1) ?? '—',
              ),
              AdminLeaveDetailPill(
                label: 'Commutation',
                value: request!.commutation.displayName,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AdminLeaveDetailGrid(request: request!),
          const SizedBox(height: 20),
          if ((request!.reason ?? '').trim().isNotEmpty) ...[
            AdminLeaveSubsectionTitle(title: 'Reason / Details'),
            AdminLeaveBodyCard(content: request!.reason!.trim()),
            const SizedBox(height: 16),
          ],
          AdminLeaveSubsectionTitle(title: 'Approval History'),
          const SizedBox(height: 8),
          HistoryTimeline(events: _buildHistoryEvents(request!)),
          const SizedBox(height: 10),
          AdminLeaveSubsectionTitle(title: 'Review Actions'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (onApprove != null)
                FilledButton.icon(
                  onPressed: reviewing ? null : onApprove,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Approve'),
                ),
              if (onReturn != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onReturn,
                  icon: const Icon(Icons.reply_rounded),
                  label: const Text('Return'),
                ),
              if (onReject != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onReject,
                  icon: const Icon(Icons.cancel_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  label: const Text('Reject'),
                ),
              // #15: Revoke — shown only when status is approved.
              if (onRevoke != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onRevoke,
                  icon: const Icon(Icons.undo_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                  label: const Text('Revoke Approval'),
                ),
              if (onPrint != null)
                OutlinedButton.icon(
                  onPressed: reviewing ? null : onPrint,
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Print Form'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRange(LeaveRequest request) {
    if (request.startDate == null || request.endDate == null) return '—';
    return '${formatAdminLeaveDate(request.startDate!)} to ${formatAdminLeaveDate(request.endDate!)}';
  }

  List<LeaveHistoryEvent> _buildHistoryEvents(LeaveRequest request) {
    final reviewer = (request.reviewerName ?? '').trim().isNotEmpty
        ? request.reviewerName!.trim()
        : 'Approver';
    final departmentHeadReviewer =
        (request.departmentHeadReviewerName ?? '').trim().isNotEmpty
        ? request.departmentHeadReviewerName!.trim()
        : (request.departmentHeadReviewerId != null
              ? 'Department Head'
              : reviewer);
    final departmentHeadReviewedAt =
        request.departmentHeadReviewedAt ??
        (request.status == LeaveRequestStatus.pendingHr ||
                request.status == LeaveRequestStatus.approved ||
                request.status == LeaveRequestStatus.rejected ||
                request.status == LeaveRequestStatus.rejectedByHr ||
                request.status == LeaveRequestStatus.rejectedByDepartmentHead
            ? request.reviewedAt
            : null);
    final departmentHeadRemarks =
        (request.departmentHeadRemarks ?? '').trim().isNotEmpty
        ? request.departmentHeadRemarks
        : null;
    final submittedAt = request.dateFiled ?? request.createdAt;
    final reviewedAt = request.reviewedAt;
    final status = request.status;
    final departmentHeadAction = request.departmentHeadAction;

    final deptHeadApprovedStage =
        departmentHeadAction == 'department_head_approved' ||
        status == LeaveRequestStatus.pendingHr ||
        status == LeaveRequestStatus.approved ||
        status == LeaveRequestStatus.rejected ||
        status == LeaveRequestStatus.rejectedByHr;

    final deptHeadRejected =
        departmentHeadAction == 'department_head_rejected' ||
        status == LeaveRequestStatus.rejectedByDepartmentHead;
    final deptHeadReturned =
        departmentHeadAction == 'department_head_returned' &&
        status == LeaveRequestStatus.returned;
    final hrApproved = status == LeaveRequestStatus.approved;
    final hrRejected =
        status == LeaveRequestStatus.rejected ||
        status == LeaveRequestStatus.rejectedByHr;
    final hrReturned =
        status == LeaveRequestStatus.returned && !deptHeadReturned;

    return [
      LeaveHistoryEvent(
        label: 'Submitted',
        dateTime: submittedAt,
        actor: request.employeeName ?? 'Employee',
        remarks: request.reason,
      ),
      if (deptHeadApprovedStage)
        LeaveHistoryEvent(
          label: 'Approved by Department Head',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          remarks: departmentHeadRemarks,
          completed: true,
        ),
      if (deptHeadApprovedStage)
        LeaveHistoryEvent(
          label: 'Forwarded to HR',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          completed: true,
        ),
      if (deptHeadRejected)
        LeaveHistoryEvent(
          label: 'Rejected by Department Head',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          remarks:
              (departmentHeadRemarks ??
                          request.disapprovalReason ??
                          request.hrRemarks)
                      ?.trim()
                      .isNotEmpty ==
                  true
              ? (departmentHeadRemarks ??
                    request.disapprovalReason ??
                    request.hrRemarks)
              : null,
          completed: true,
        ),
      if (deptHeadReturned)
        LeaveHistoryEvent(
          label: 'Returned by Department Head',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          remarks: departmentHeadRemarks,
          completed: true,
        ),
      if (status == LeaveRequestStatus.pendingHr)
        LeaveHistoryEvent(
          label: 'HR Final Review',
          dateTime: null,
          actor: 'HR',
          completed: false,
        ),
      if (hrApproved)
        LeaveHistoryEvent(
          label: 'Approved by HR',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks: request.hrRemarks,
          completed: true,
        ),
      if (hrReturned)
        LeaveHistoryEvent(
          label: 'Returned by HR',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks: request.hrRemarks,
          completed: true,
        ),
      if (hrRejected)
        LeaveHistoryEvent(
          label: 'Rejected by HR',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks:
              (request.disapprovalReason ?? request.hrRemarks)
                      ?.trim()
                      .isNotEmpty ==
                  true
              ? (request.disapprovalReason ?? request.hrRemarks)
              : null,
          completed: true,
        ),
    ];
  }
}

class _AdminLeaveDetailGrid extends StatelessWidget {
  const _AdminLeaveDetailGrid({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Office/Department', value: request.officeDepartment ?? '—'),
      (label: 'Position Title', value: request.positionTitle ?? '—'),
      (
        label: 'Salary',
        value: request.salary != null
            ? request.salary!.toStringAsFixed(2)
            : '—',
      ),
      (label: 'Custom Leave Type', value: request.customLeaveTypeText ?? '—'),
      (label: 'Location', value: request.locationOption?.displayName ?? '—'),
      (label: 'Location Details', value: request.locationDetails ?? '—'),
      (
        label: 'Sick Leave Nature',
        value: request.sickLeaveNature?.displayName ?? '—',
      ),
      (label: 'Sick Illness Details', value: request.sickIllnessDetails ?? '—'),
      (
        label: 'Women Illness Details',
        value: request.womenIllnessDetails ?? '—',
      ),
      (label: 'Study Purpose', value: request.studyPurpose?.displayName ?? '—'),
      (
        label: 'Study Purpose Details',
        value: request.studyPurposeDetails ?? '—',
      ),
      (label: 'Other Purpose', value: request.otherPurpose?.displayName ?? '—'),
      (
        label: 'Other Purpose Details',
        value: request.otherPurposeDetails ?? '—',
      ),
    ];

    final attachmentName = request.attachmentName?.trim();
    final hasAttachment = attachmentName != null && attachmentName.isNotEmpty;
    final requestId = request.id;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ...rows
            .where((r) => r.label != 'Attachment')
            .map(
              (item) => SizedBox(
                width: 260,
                child: AdminLeaveInfoTile(label: item.label, value: item.value),
              ),
            ),
        SizedBox(
          width: 260,
          child: _AdminLeaveAttachmentTile(
            requestId: requestId,
            attachmentName: attachmentName,
            hasAttachment: hasAttachment,
          ),
        ),
      ],
    );
  }
}

class _AdminLeaveAttachmentTile extends StatelessWidget {
  const _AdminLeaveAttachmentTile({
    required this.requestId,
    required this.attachmentName,
    required this.hasAttachment,
  });

  final String? requestId;
  final String? attachmentName;
  final bool hasAttachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachment',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (!hasAttachment)
            Text(
              'No attachment linked yet',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    attachmentName!,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: requestId != null && requestId!.isNotEmpty
                      ? () => _openOrDownloadAttachment(context)
                      : null,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('View'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openOrDownloadAttachment(BuildContext context) async {
    if (requestId == null || requestId!.isEmpty) return;

    final provider = context.read<LeaveProvider>();
    final snackbar = ScaffoldMessenger.of(context);

    try {
      snackbar.showSnackBar(
        const SnackBar(content: Text('Downloading attachment...')),
      );
      final bytes = await provider.getAttachmentBytes(requestId!);
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        snackbar.showSnackBar(
          const SnackBar(content: Text('Attachment could not be loaded.')),
        );
        return;
      }

      snackbar.clearSnackBars();
      snackbar.showSnackBar(
        const SnackBar(content: Text('Opening attachment...')),
      );

      final name = attachmentName ?? 'attachment';
      await open_attachment.openAttachmentBytes(bytes, name);
      if (context.mounted) {
        snackbar.showSnackBar(
          const SnackBar(content: Text('Attachment opened.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        snackbar.showSnackBar(
          SnackBar(content: Text('Could not open attachment: $e')),
        );
      }
    }
  }
}
