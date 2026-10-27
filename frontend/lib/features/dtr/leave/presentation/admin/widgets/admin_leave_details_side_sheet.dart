import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_workflow_history.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/open_attachment_io.dart'
    if (dart.library.html) 'package:hrms_plaridel/features/dtr/leave/utils/open_attachment_web.dart'
    as open_attachment;
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/history_timeline.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_shared_widgets.dart';

import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_request_information.dart';

/// Leave review details shown over the queue (matches [openResponsiveLeaveFormHost] behavior).
class AdminLeaveDetailsSideSheet extends StatelessWidget {
  const AdminLeaveDetailsSideSheet({
    super.key,
    required this.initial,
    required this.isDepartmentHead,
    this.canReviewPending = true,
    this.currentReviewerId,
    required this.onApprove,
    required this.onReturn,
    required this.onReject,
    this.onPreview,
    required this.onPrint,
    this.onRevoke,
  });

  final LeaveRequest initial;
  final bool isDepartmentHead;
  final bool canReviewPending;
  final String? currentReviewerId;
  final Future<void> Function(LeaveRequest) onApprove;
  final Future<void> Function(LeaveRequest) onReturn;
  final Future<void> Function(LeaveRequest) onReject;
  final Future<void> Function(LeaveRequest)? onPreview;
  final Future<void> Function(LeaveRequest)? onRevoke;
  final Future<void> Function(LeaveRequest) onPrint;

  @override
  Widget build(BuildContext context) {
    return AdminLeaveDetailsFrame(
      child: Consumer<LeaveProvider>(
        builder: (context, provider, _) {
          var req = initial;
          final id = initial.id;
          if (id != null && id.isNotEmpty) {
            final hit =
                (isDepartmentHead
                        ? provider.departmentHeadRequests
                        : provider.requests)
                    .where((r) => r.id == id)
                    .toList();
            if (hit.isNotEmpty) req = hit.first;
          }
          final isOwnRequest =
              currentReviewerId != null && currentReviewerId == req.userId;
          final sharedWorkflow = (req.workflowSnapshot?['steps'] as List? ?? [])
              .any((step) => step is Map);
          final canReview =
              !isOwnRequest &&
              !sharedWorkflow &&
              (isDepartmentHead
                  ? canReviewPending &&
                        req.status == LeaveRequestStatus.pendingDepartmentHead
                  : canReviewPending && req.status.isPending);
          final approved = req.status == LeaveRequestStatus.approved;
          final canRevoke =
              approved &&
              !req.isPaperRecord &&
              !isOwnRequest &&
              onRevoke != null &&
              (!sharedWorkflow || req.canRevokeApproval == true);
          final revokeDisabledReason = canRevoke
              ? adminLeaveRevokeDisabledReason(req)
              : null;
          return AdminLeaveRequestDetailsPanel(
            request: req,
            isDepartmentHead: isDepartmentHead,
            reviewing: provider.reviewing,
            onApprove: canReview ? () => onApprove(req) : null,
            onReturn: canReview ? () => onReturn(req) : null,
            onReject: canReview ? () => onReject(req) : null,
            onPreview: onPreview == null ? null : () => onPreview!(req),
            onRevoke: canRevoke && revokeDisabledReason == null
                ? () => onRevoke!(req)
                : null,
            revokeDisabledReason: canRevoke ? revokeDisabledReason : null,
            onPrint: () => onPrint(req),
          );
        },
      ),
    );
  }
}

/// The existing leave details header and body host, shared by every route.
class AdminLeaveDetailsFrame extends StatelessWidget {
  const AdminLeaveDetailsFrame({
    super.key,
    required this.child,
    this.canClose = true,
  });

  final Widget child;
  final bool canClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            color: AppTheme.dashPanelOf(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Request Details',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: canClose
                        ? () => Navigator.of(context).pop()
                        : null,
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AdminLeaveRequestDetailsPanel extends StatelessWidget {
  const AdminLeaveRequestDetailsPanel({
    super.key,
    required this.request,
    required this.isDepartmentHead,
    required this.reviewing,
    this.onApprove,
    this.onReturn,
    this.onReject,
    this.onRevoke, // #15
    this.onPreview,
    this.revokeDisabledReason,
    this.onPrint,
    this.historyEvents,
    this.reviewFields,
    this.approvalEnabled = true,
    this.statusLabel,
    this.onOpenAttachment,
  });

  final LeaveRequest? request;
  final bool isDepartmentHead;
  final bool reviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReturn;
  final VoidCallback? onReject;
  final VoidCallback? onRevoke; // #15
  final VoidCallback? onPreview;
  final String? revokeDisabledReason;
  final VoidCallback? onPrint;
  final List<LeaveHistoryEvent>? historyEvents;
  final Widget? reviewFields;
  final bool approvalEnabled;
  final String? statusLabel;
  final VoidCallback? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    if (request == null) {
      return const AdminLeaveSectionCard(
        title: 'Request Details',
        subtitle: 'Select a request from the queue to review it.',
        child: AdminLeaveCenteredState(message: 'No request selected.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('leave-request-details-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    LeaveStatusChip(
                      status: request!.status,
                      label:
                          statusLabel ??
                          adminLeaveStatusLabel(
                            request!.status,
                            paperRecorded:request!.isPaperRecord,
                            finalReviewRoute: request!.finalReviewRoute,
                            isDepartmentHead: isDepartmentHead,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                const SizedBox(height: 20),
                LeaveRequestInformation(request: request!),
                if ((request!.attachmentName ?? '').trim().isNotEmpty) ...[
                  _AdminLeaveAttachmentTile(
                    requestId: request!.id,
                    attachmentName: request!.attachmentName,
                    hasAttachment: true,
                    onOpen: onOpenAttachment,
                  ),
                  const SizedBox(height: 16),
                ],
                AdminLeaveSubsectionTitle(title: 'Approval History'),
                const SizedBox(height: 8),
                HistoryTimeline(
                  events: historyEvents ?? _buildHistoryEvents(request!),
                ),
                const SizedBox(height: 10),
                if (reviewFields != null) ...[
                  reviewFields!,
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
        _buildActionsFooter(context),
      ],
    );
  }

  Widget _buildActionsFooter(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('leave-request-actions-footer'),
      decoration: BoxDecoration(
        color: AppTheme.dashIsDark(context)
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.offWhite,
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (revokeDisabledReason != null) ...[
                Text(
                  revokeDisabledReason!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (onApprove != null)
                    FilledButton.icon(
                      onPressed: reviewing || !approvalEnabled
                          ? null
                          : onApprove,
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
                  if (onPreview != null)
                    OutlinedButton.icon(
                      onPressed: reviewing ? null : onPreview,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview Form'),
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
        ),
      ),
    );
  }

  List<LeaveHistoryEvent> _buildHistoryEvents(LeaveRequest request) {
    if ((request.workflowSnapshot?['steps'] as List? ?? []).any(
      (step) => step is Map,
    )) {
      return leaveWorkflowHistory(request);
    }
    final reviewer = (request.reviewerName ?? '').trim().isNotEmpty
        ? request.reviewerName!.trim()
        : 'HR/Admin';
    final departmentHeadReviewer =
        (request.departmentHeadReviewerName ?? '').trim().isNotEmpty
        ? request.departmentHeadReviewerName!.trim()
        : 'Department Reviewer';
    final departmentHeadReviewedAt = request.departmentHeadReviewedAt;
    final departmentHeadRemarks =
        (request.departmentHeadRemarks ?? '').trim().isNotEmpty
        ? request.departmentHeadRemarks
        : null;
    if(request.isPaperRecord) {
      final paper=request.paperApprovalRecord!;
      return [LeaveHistoryEvent(label:'Approved paper leave recorded',
        dateTime:DateTime.tryParse(paper['encoded_at']?.toString() ?? ''),actor:paper['encoded_by_name']?.toString() ?? 'HR encoder',
        remarks:'Original paper approval: ${paper['approval_date']} by ${paper['final_approver']?['name'] ?? ''}',completed:true)];
    }
    final submittedAt = request.dateFiled ?? request.createdAt;
    final reviewedAt = request.reviewedAt;
    final status = request.status;
    final finalStage = request.finalReviewRoute == 'mayor'
        ? 'Department'
        : 'HR';
    final departmentHeadAction = request.departmentHeadAction;

    final deptHeadApprovedStage =
        departmentHeadAction == 'department_head_approved';

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
          label: 'Approved by Department Reviewer',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          remarks: departmentHeadRemarks,
          completed: true,
        ),
      if (deptHeadApprovedStage && request.finalReviewRoute != 'mayor')
        LeaveHistoryEvent(
          label: 'Forwarded to HR',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          completed: true,
        ),
      if (deptHeadRejected)
        LeaveHistoryEvent(
          label: 'Rejected by Department Reviewer',
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
          label: 'Returned by Department Reviewer',
          dateTime: departmentHeadReviewedAt,
          actor: departmentHeadReviewer,
          remarks: departmentHeadRemarks,
          completed: true,
        ),
      if (status == LeaveRequestStatus.pendingHr ||
          status == LeaveRequestStatus.pendingMayor)
        LeaveHistoryEvent(
          label: '$finalStage Final Review',
          dateTime: null,
          actor: finalStage,
          completed: false,
        ),
      if (hrApproved &&
          (!deptHeadApprovedStage || request.finalReviewRoute != 'mayor'))
        LeaveHistoryEvent(
          label: 'Approved by $finalStage',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks: request.hrRemarks,
          completed: true,
        ),
      if (hrReturned)
        LeaveHistoryEvent(
          label: 'Returned by $finalStage',
          dateTime: reviewedAt,
          actor: reviewer,
          remarks: request.hrRemarks,
          completed: true,
        ),
      if (hrRejected)
        LeaveHistoryEvent(
          label: 'Rejected by $finalStage',
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

class _AdminLeaveAttachmentTile extends StatelessWidget {
  const _AdminLeaveAttachmentTile({
    required this.requestId,
    required this.attachmentName,
    required this.hasAttachment,
    this.onOpen,
  });

  final String? requestId;
  final String? attachmentName;
  final bool hasAttachment;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachment',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (!hasAttachment)
            Text(
              'No attachment linked yet',
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 14,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    attachmentName!,
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      onOpen ??
                      (requestId != null && requestId!.isNotEmpty
                          ? () => _previewAttachment(context)
                          : null),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Preview'),
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

  Future<void> _previewAttachment(BuildContext context) async {
    if (requestId == null || requestId!.isEmpty) return;

    final provider = context.read<LeaveProvider>();
    final snackbar = ScaffoldMessenger.of(context);

    try {
      snackbar.showSnackBar(
        const SnackBar(content: Text('Loading attachment preview...')),
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
      final name = attachmentName ?? 'attachment';
      await showDialog<void>(
        context: context,
        builder: (_) => _AdminAttachmentPreviewDialog(
          bytes: Uint8List.fromList(bytes),
          filename: name,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        snackbar.showSnackBar(
          SnackBar(content: Text('Could not open attachment: $e')),
        );
      }
    }
  }
}

class _AdminAttachmentPreviewDialog extends StatelessWidget {
  const _AdminAttachmentPreviewDialog({
    required this.bytes,
    required this.filename,
  });

  final Uint8List bytes;
  final String filename;

  bool get _isPdf => filename.toLowerCase().endsWith('.pdf');

  bool get _isImage {
    final lower = filename.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width.clamp(320, 1100).toDouble(),
        height: size.height.clamp(420, 820).toDouble(),
        child: Column(
          children: [
            Material(
              color: AppTheme.dashPanelOf(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          open_attachment.openAttachmentBytes(bytes, filename),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open externally'),
                    ),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildPreview(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (_isPdf) {
      return PdfPreview(
        build: (_) async => bytes,
        pdfFileName: filename,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      );
    }
    if (_isImage) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.04),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _AttachmentPreviewMessage(
                message: 'This image could not be displayed.',
              ),
            ),
          ),
        ),
      );
    }
    return const _AttachmentPreviewMessage(
      message:
          'Preview is unavailable for this file type. Use Open externally.',
    );
  }
}

class _AttachmentPreviewMessage extends StatelessWidget {
  const _AttachmentPreviewMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
        ),
      ),
    );
  }
}
