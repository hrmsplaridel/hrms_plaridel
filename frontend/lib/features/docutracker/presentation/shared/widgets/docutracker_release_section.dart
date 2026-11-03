import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_document_detail_ui.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

export 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_release_dialog.dart'
    show
        DocuTrackerReleaseDialog,
        DocuTrackerReleaseOptionsLoader,
        DocuTrackerReleaseSubmitter,
        docuTrackerFilterReleaseDepartments,
        docuTrackerReleaseInfoIrreversible,
        docuTrackerReleaseInfoViewOnly,
        docuTrackerReleaseNoDepartmentsFound,
        docuTrackerReleaseRemarksMaxLength,
        showDocuTrackerReleaseDialog;

/// Release stage of an approved document, shown apart from the workflow.
class DocuTrackerReleaseSection extends StatelessWidget {
  const DocuTrackerReleaseSection({
    super.key,
    required this.document,
    this.onRelease,
  });

  final DocuTrackerDocument document;

  /// Shown only when the backend allows the viewer to release now.
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    if (!document.releaseRequired) return const SizedBox.shrink();
    final released = document.isReleased;
    final muted = DocuTrackerTokens.textMutedOf(context);
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final department = document.releasedToDepartmentName?.trim();
    final releasedBy = docuTrackerReleasedByLine(document);
    final remarks = document.releaseRemarks?.trim();

    return DocuTrackerDetailSectionCard(
      key: const ValueKey('docutracker-release-section'),
      icon: released ? Icons.outbox_rounded : Icons.schedule_send_outlined,
      title: released ? 'Released' : 'Approved · Awaiting release',
      subtitle: released
          ? 'Distributed after final approval'
          : 'Final approval is complete; not yet distributed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (released) ...[
            Text(
              department == null || department.isEmpty
                  ? 'Released to department'
                  : 'Released to $department',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
            if (releasedBy != null) ...[
              const SizedBox(height: 4),
              Text(releasedBy, style: TextStyle(fontSize: 13, color: muted)),
            ],
            if (remarks != null && remarks.isNotEmpty) ...[
              const SizedBox(height: 12),
              DocuTrackerPeachDashedBox(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  remarks,
                  style: TextStyle(fontSize: 13, height: 1.4, color: primary),
                ),
              ),
            ],
          ] else ...[
            Text(
              'The receiving department cannot see this document until an '
              'authorized user releases it.',
              style: TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
            if (onRelease != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('docutracker-release-button'),
                onPressed: onRelease,
                icon: const Icon(Icons.outbox_rounded),
                label: const Text('Release Document'),
                style: DocuTrackerStyles.primaryBrandButtonStyle(context),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
