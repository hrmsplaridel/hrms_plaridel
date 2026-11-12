import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_status_badge.dart';

enum RspApplicantDocCardStatus {
  notUploaded,
  uploaded,
  submitted,
  underReview,
  approved,
  rejected,
}

class RspApplicantDocumentUploadCard extends StatelessWidget {
  const RspApplicantDocumentUploadCard({
    super.key,
    required this.title,
    required this.status,
    this.fileName,
    this.rejectReason,
    this.onChoose,
    this.onRemove,
    this.onResubmit,
    this.resubmitEnabled = false,
    this.resubmitLabel = 'Resubmit file',
    this.busy = false,
    this.readOnly = false,
    this.compact = false,
  });

  final String title;
  final RspApplicantDocCardStatus status;
  final String? fileName;
  final String? rejectReason;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;

  /// Per-document submit after HR requested a revision for this file.
  final VoidCallback? onResubmit;
  final bool resubmitEnabled;
  final String resubmitLabel;
  final bool busy;
  final bool readOnly;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badge = _badge();
    final approved = status == RspApplicantDocCardStatus.approved;
    final rejected = status == RspApplicantDocCardStatus.rejected;
    final borderColor = rejected
        ? const Color(0xFFC62828).withValues(alpha: 0.4)
        : approved
            ? const Color(0xFF2E7D32).withValues(alpha: 0.28)
            : AppTheme.lightGray;
    final bg = approved
        ? const Color(0xFFF6FBF7)
        : rejected
            ? const Color(0xFFFFF8F8)
            : AppTheme.dashMutedSurfaceOf(context);
    final hasFile = fileName != null && fileName!.trim().isNotEmpty;
    final showResubmit = !readOnly && onResubmit != null;

    return Container(
      width: double.infinity,
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
          : const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: approved
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                      : rejected
                          ? const Color(0xFFC62828).withValues(alpha: 0.1)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  approved
                      ? Icons.description_rounded
                      : rejected
                          ? Icons.warning_amber_rounded
                          : Icons.upload_file_rounded,
                  size: 18,
                  color: approved
                      ? const Color(0xFF2E7D32)
                      : rejected
                          ? const Color(0xFFC62828)
                          : AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                    if (!readOnly) ...[
                      const SizedBox(height: 2),
                      Text(
                        rejected
                            ? 'Upload a new PDF for this document'
                            : 'PDF only',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: rejected
                              ? const Color(0xFFC62828)
                              : AppTheme.dashTextSecondaryOf(context),
                          fontWeight:
                              rejected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RspApplicantStatusBadge(kind: badge),
            ],
          ),
          if (hasFile) ...[
            SizedBox(height: compact ? 8 : 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    approved
                        ? Icons.check_circle_rounded
                        : Icons.picture_as_pdf_rounded,
                    size: 17,
                    color: approved
                        ? const Color(0xFF2E7D32)
                        : AppTheme.dashTextSecondaryOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (rejectReason != null && rejectReason!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFC62828).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                rejectReason!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (!readOnly && onChoose != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onChoose,
                    icon: Icon(
                      hasFile
                          ? Icons.swap_horiz_rounded
                          : Icons.upload_file_rounded,
                      size: 18,
                    ),
                    label: Text(
                      hasFile ? 'Choose another PDF' : 'Upload PDF',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: AppTheme.primaryNavy,
                      side: BorderSide(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                if (onRemove != null && hasFile) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: busy ? null : onRemove,
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ],
            ),
          ],
          if (showResubmit) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy || !resubmitEnabled ? null : onResubmit,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                busy ? 'Submitting…' : resubmitLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                backgroundColor: const Color(0xFFE85D04),
                disabledBackgroundColor:
                    const Color(0xFFE85D04).withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (!resubmitEnabled && !busy) ...[
              const SizedBox(height: 6),
              Text(
                hasFile
                    ? 'Finish uploading every rejected document above, then resubmit.'
                    : 'Upload a new PDF for this document first.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  RspApplicantBadgeKind _badge() {
    switch (status) {
      case RspApplicantDocCardStatus.notUploaded:
        return RspApplicantBadgeKind.needsAction;
      case RspApplicantDocCardStatus.uploaded:
        return RspApplicantBadgeKind.ready;
      case RspApplicantDocCardStatus.submitted:
        return RspApplicantBadgeKind.submitted;
      case RspApplicantDocCardStatus.underReview:
        return RspApplicantBadgeKind.underReview;
      case RspApplicantDocCardStatus.approved:
        return RspApplicantBadgeKind.approved;
      case RspApplicantDocCardStatus.rejected:
        return RspApplicantBadgeKind.rejected;
    }
  }
}
