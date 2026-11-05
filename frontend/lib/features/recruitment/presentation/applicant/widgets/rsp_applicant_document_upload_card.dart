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
                        'PDF only',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.dashTextSecondaryOf(context),
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
          if (fileName != null && fileName!.trim().isNotEmpty) ...[
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
            Text(
              rejectReason!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.red.shade800,
              ),
            ),
          ],
          if (!readOnly && onChoose != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: busy ? null : onChoose,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(
                      fileName == null || fileName!.isEmpty
                          ? 'Upload PDF'
                          : 'Replace',
                    ),
                  ),
                ),
                if (onRemove != null &&
                    fileName != null &&
                    fileName!.isNotEmpty) ...[
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
