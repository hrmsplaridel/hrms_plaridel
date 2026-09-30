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

DocuTrackerSourceStatusText _trainingReportStatusText(String raw) {
  final description = switch (raw) {
    'submitted' => 'The report was submitted and is waiting for L&D review.',
    'seen' => 'An L&D administrator has opened this report.',
    'reviewed' => 'An L&D administrator has reviewed this report.',
    'approved' => 'The report was approved by L&D.',
    'needs_revision' ||
    'needs-revision' => 'L&D asked the employee to revise this report.',
    _ => 'Status is managed by the L&D module.',
  };
  return DocuTrackerSourceStatusText(
    label: _humanize(raw),
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
