import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/open_attachment_io.dart'
    if (dart.library.html) 'package:hrms_plaridel/features/dtr/leave/utils/open_attachment_web.dart'
    as open_attachment;
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/history_timeline.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_status_chip.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_shared_widgets.dart';

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
            color: AppTheme.dashPanelOf(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Request details',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
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
                final revokeDisabledReason = approved && onRevoke != null
                    ? adminLeaveRevokeDisabledReason(req)
                    : null;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: _AdminLeaveRequestDetailsPanel(
                    request: req,
                    isDepartmentHead: isDepartmentHead,
                    reviewing: provider.reviewing,
                    onApprove: canReview ? () => onApprove(req) : null,
                    onReturn: canReview ? () => onReturn(req) : null,
                    onReject: canReview ? () => onReject(req) : null,
                    onRevoke:
                        approved &&
                            onRevoke != null &&
                            revokeDisabledReason == null
                        ? () => onRevoke!(req)
                        : null,
                    revokeDisabledReason: approved && onRevoke != null
                        ? revokeDisabledReason
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
    this.revokeDisabledReason,
    this.onPrint,
  });

  final LeaveRequest? request;
  final bool isDepartmentHead;
  final bool reviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReturn;
  final VoidCallback? onReject;
  final VoidCallback? onRevoke; // #15
  final String? revokeDisabledReason;
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
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      request!.leaveTypeLabel,
                      style: TextStyle(
                        color: AppTheme.dashIsDark(context)
                            ? AppTheme.primaryNavyLight
                            : AppTheme.primaryNavyDark,
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
    final rows = _buildDetailRows(request);

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

  List<({String label, String value})> _buildDetailRows(LeaveRequest request) {
    final rows = <({String label, String value})>[
      (
        label: 'Office/Department',
        value: _displayValue(request.officeDepartment),
      ),
      (label: 'Position Title', value: _displayValue(request.positionTitle)),
      (
        label: 'Salary',
        value: request.salary != null
            ? request.salary!.toStringAsFixed(2)
            : '—',
      ),
    ];

    void addRelevant({
      required String label,
      required String? value,
      required bool applies,
    }) {
      if (!applies && !_hasValue(value)) return;
      rows.add((label: label, value: _displayValue(value)));
    }

    void addRelevantEnum({
      required String label,
      required String? value,
      required bool applies,
    }) {
      if (!applies && !_hasValue(value)) return;
      rows.add((label: label, value: value ?? '—'));
    }

    void addRelevantDate({
      required String label,
      required DateTime? value,
      required bool applies,
    }) {
      if (!applies && value == null) return;
      rows.add((
        label: label,
        value: value != null ? formatAdminLeaveDate(value) : '—',
      ));
    }

    final leaveType = request.leaveType;

    addRelevant(
      label: 'Custom Leave Type',
      value: request.customLeaveTypeText,
      applies: leaveType == LeaveType.others,
    );
    addRelevantEnum(
      label: 'Maternity Classification',
      value: request.maternityDeliveryType?.displayName,
      applies: leaveType == LeaveType.maternityLeave,
    );
    addRelevantDate(
      label: 'Expected Delivery Date',
      value: request.expectedDeliveryDate,
      applies: leaveType == LeaveType.maternityLeave,
    );
    addRelevantDate(
      label: 'Child Delivery Date',
      value: request.childDeliveryDate,
      applies: leaveType == LeaveType.paternityLeave,
    );
    addRelevantDate(
      label: 'Accident Date',
      value: request.accidentDate,
      applies: leaveType == LeaveType.rehabilitationPrivilege,
    );
    addRelevantDate(
      label: 'Calamity Occurrence Date',
      value: request.calamityDate,
      applies: leaveType == LeaveType.specialEmergencyCalamityLeave,
    );
    addRelevantEnum(
      label: 'Adoption Eligibility',
      value: request.adoptionParentRole?.displayName,
      applies: leaveType == LeaveType.adoptionLeave,
    );
    addRelevantDate(
      label: 'PAPA / Adoption Placement Date',
      value: request.adoptionPlacementDate,
      applies: leaveType == LeaveType.adoptionLeave,
    );
    addRelevantEnum(
      label: 'VAWC Supporting Document',
      value: request.vawcSupportDocumentType?.displayName,
      applies: leaveType == LeaveType.tenDayVawcLeave,
    );
    addRelevant(
      label: 'VAWC Case Details',
      value: request.vawcCaseDetails,
      applies: leaveType == LeaveType.tenDayVawcLeave,
    );
    addRelevant(
      label: 'Solo Parent ID Number',
      value: request.soloParentIdNumber,
      applies: leaveType == LeaveType.soloParentLeave,
    );
    addRelevantDate(
      label: 'Solo Parent ID Expiry Date',
      value: request.soloParentIdExpiryDate,
      applies: leaveType == LeaveType.soloParentLeave,
    );
    addRelevantEnum(
      label: 'Location',
      value: request.locationOption?.displayName,
      applies:
          leaveType == LeaveType.vacationLeave ||
          leaveType == LeaveType.specialPrivilegeLeave,
    );
    addRelevant(
      label: 'Location Details',
      value: request.locationDetails,
      applies:
          leaveType == LeaveType.vacationLeave ||
          leaveType == LeaveType.specialPrivilegeLeave,
    );
    addRelevantEnum(
      label: 'Sick Leave Nature',
      value: request.sickLeaveNature?.displayName,
      applies: leaveType == LeaveType.sickLeave,
    );
    addRelevant(
      label: 'Sick Illness Details',
      value: request.sickIllnessDetails,
      applies: leaveType == LeaveType.sickLeave,
    );
    addRelevant(
      label: 'Women Illness Details',
      value: request.womenIllnessDetails,
      applies: leaveType == LeaveType.specialLeaveBenefitsForWomen,
    );
    addRelevantEnum(
      label: 'Study Purpose',
      value: request.studyPurpose?.displayName,
      applies: leaveType == LeaveType.studyLeave,
    );
    addRelevant(
      label: 'Study Purpose Details',
      value: request.studyPurposeDetails,
      applies: leaveType == LeaveType.studyLeave,
    );
    addRelevantEnum(
      label: 'Other Purpose',
      value: request.otherPurpose?.displayName,
      applies: leaveType == LeaveType.others,
    );
    addRelevant(
      label: 'Other Purpose Details',
      value: request.otherPurposeDetails,
      applies: leaveType == LeaveType.others,
    );

    return rows;
  }

  static bool _hasValue(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String _displayValue(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? '—' : trimmed;
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
                  onPressed: requestId != null && requestId!.isNotEmpty
                      ? () => _previewAttachment(context)
                      : null,
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
