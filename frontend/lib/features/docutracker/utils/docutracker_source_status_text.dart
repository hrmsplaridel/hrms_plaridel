import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_applications_report_export.dart';

/// Read-only status wording for records owned by other HRMS modules.
class DocuTrackerSourceStatusText {
  const DocuTrackerSourceStatusText({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

/// Display name of an RSP / L&D source module, or null for other modules.
String? docuTrackerSourceModuleLabel(String? sourceModule) =>
    switch (sourceModule?.trim().toLowerCase()) {
      'rsp' => 'RSP',
      'ld' => 'L&D',
      _ => null,
    };

DocuTrackerSourceStatusText docuTrackerLinkedSourceStatusText({
  required String sourceModule,
  required String status,
}) {
  final raw = status.trim().toLowerCase();
  if (sourceModule == 'ld') return _trainingReportStatusText(raw);
  if (sourceModule == 'rsp') return _recruitmentStatusText(raw);
  return DocuTrackerSourceStatusText(
    label: _humanize(raw),
    description: 'Status is managed by the source module.',
  );
}

/// Badge wording for an L&D source row. Its DocuTracker status is coarser than
/// the L&D lifecycle (a reviewed report maps to approved), so the badge uses
/// the module's own label instead.
String? docuTrackerSourceBadgeLabel(DocuTrackerDocument document) {
  if (!document.sourceOnly) return null;
  if (document.sourceModule?.trim().toLowerCase() != 'ld') return null;
  final raw = document.sourceStatus?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return null;
  return _trainingReportStatusText(raw).label;
}

/// Whether [document] is an L&D report that L&D marked seen/reviewed: complete
/// in DocuTracker, but never approved, so it stays out of approval counts.
bool docuTrackerIsReviewedSourceCompletion(DocuTrackerDocument document) {
  if (!document.sourceOnly) return false;
  if (document.sourceModule?.trim().toLowerCase() != 'ld') return false;
  final raw = document.sourceStatus?.trim().toLowerCase() ?? '';
  return raw == 'seen' || raw == 'reviewed';
}

DocuTrackerSourceStatusText _trainingReportStatusText(String raw) {
  final description = switch (raw) {
    'submitted' => 'The report was submitted and is waiting for L&D review.',
    'seen' || 'reviewed' =>
      'An L&D administrator reviewed this report. No further '
          'action is needed.',
    'approved' => 'The report was approved by L&D.',
    'needs_revision' ||
    'needs-revision' => 'L&D asked the employee to revise this report.',
    _ => 'Status is managed by the L&D module.',
  };
  return DocuTrackerSourceStatusText(
    label: raw == 'seen' ? 'Reviewed' : _humanize(raw),
    description: description,
  );
}

DocuTrackerSourceStatusText _recruitmentStatusText(String raw) {
  final description = switch (raw) {
    'submitted' =>
      'The application is waiting for HR to review the submitted documents.',
    'document_approved' =>
      'HR approved the documents. The applicant may take the screening exam.',
    'document_declined' =>
      'HR did not approve the documents. The applicant must replace them '
          'and resubmit.',
    'exam_taken' =>
      'The applicant submitted the screening exam and is waiting for the '
          'result.',
    'passed' => 'The applicant passed the screening exam.',
    'failed' =>
      'The applicant did not pass the screening exam and cannot continue '
          'this application.',
    'registered' =>
      'The applicant was hired and an employee account was set up.',
    _ => 'Status is managed by the RSP module.',
  };
  return DocuTrackerSourceStatusText(
    label: RspApplicationsReportExport.statusDisplayLabel(raw),
    description: description,
  );
}

String _humanize(String raw) {
  final normalized = raw.replaceAll(RegExp(r'[_-]'), ' ').trim();
  if (normalized.isEmpty) return 'Not provided';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}
