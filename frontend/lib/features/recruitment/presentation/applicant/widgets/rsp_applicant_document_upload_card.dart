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
  });

  final String title;
  final RspApplicantDocCardStatus status;
  final String? fileName;
  final String? rejectReason;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;
  final bool busy;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final badge = _badge();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == RspApplicantDocCardStatus.rejected
              ? const Color(0xFFC62828).withValues(alpha: 0.4)
              : AppTheme.lightGray,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              RspApplicantStatusBadge(kind: badge),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'PDF only',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          if (fileName != null && fileName!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  status == RspApplicantDocCardStatus.approved
                      ? Icons.check_circle_rounded
                      : Icons.insert_drive_file_outlined,
                  size: 18,
                  color: status == RspApplicantDocCardStatus.approved
                      ? const Color(0xFF2E7D32)
                      : AppTheme.dashTextSecondaryOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
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
