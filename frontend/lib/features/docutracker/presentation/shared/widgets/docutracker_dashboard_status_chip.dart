import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_status_theme.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';

/// Label printed on a dashboard document tile.
///
/// Approved documents use the release presentation
/// ([docuTrackerApprovedStateLabel]). The stored status stays `approved`.
/// Other statuses keep the existing uppercase workflow label.
String docuTrackerDashboardStatusLabel(DocuTrackerDocument document) {
  if (document.status == DocumentStatus.approved) {
    return docuTrackerApprovedStateLabel(document);
  }
  return docuTrackerStatusForDisplay(document).displayName.toUpperCase();
}

class DocuTrackerDashboardStatusChip extends StatelessWidget {
  const DocuTrackerDashboardStatusChip({
    super.key,
    required this.document,
    this.compact = false,
  });

  final DocuTrackerDocument document;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statusForUi = docuTrackerStatusForDisplay(document);
    final label = docuTrackerDashboardStatusLabel(document);
    final awaitingRelease = document.isAwaitingRelease;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DocuTrackerStatusTheme.chipBackground(statusForUi),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: compact && awaitingRelease ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: DocuTrackerStatusTheme.foreground(statusForUi),
          letterSpacing: awaitingRelease ? 0 : 0.3,
          height: 1.2,
        ),
      ),
    );
    if (!compact) return chip;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: awaitingRelease ? 132 : 100),
      child: chip,
    );
  }
}
