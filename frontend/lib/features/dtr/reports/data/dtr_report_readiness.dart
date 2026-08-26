enum DtrReportDataState { idle, loading, ready, failed, missing }

class DtrReportReadiness {
  const DtrReportReadiness({
    required this.employees,
    required this.records,
    required this.assignments,
    required this.policy,
    required this.signatories,
  });

  final DtrReportDataState employees;
  final DtrReportDataState records;
  final DtrReportDataState assignments;
  final DtrReportDataState policy;
  final DtrReportDataState signatories;

  bool get isLoading =>
      employees == DtrReportDataState.loading ||
      records == DtrReportDataState.loading ||
      assignments == DtrReportDataState.loading ||
      policy == DtrReportDataState.loading ||
      signatories == DtrReportDataState.loading;

  bool get canGenerateOfficialReport =>
      employees == DtrReportDataState.ready &&
      records == DtrReportDataState.ready &&
      assignments == DtrReportDataState.ready &&
      policy == DtrReportDataState.ready &&
      signatories == DtrReportDataState.ready;

  List<String> get blockingIssues {
    final issues = <String>[];
    _addIssue(
      issues,
      employees,
      failed: 'Employee directory could not be loaded.',
      missing: 'No employee is available for this report.',
    );
    _addIssue(
      issues,
      records,
      failed: 'Attendance records could not be loaded.',
      missing: 'Attendance records required for this report are unavailable.',
    );
    _addIssue(
      issues,
      assignments,
      failed: 'Historical assignment and shift data could not be loaded.',
      missing: 'No assignment and shift covers the selected report period.',
    );
    _addIssue(
      issues,
      policy,
      failed: 'Attendance policy data could not be verified.',
      missing:
          'Some scheduled dates have no verified attendance policy or deduction data.',
    );
    _addIssue(
      issues,
      signatories,
      failed: 'Report signatories could not be loaded.',
      missing: 'Required report signatories are not configured.',
    );
    return issues;
  }

  static void _addIssue(
    List<String> issues,
    DtrReportDataState state, {
    required String failed,
    required String missing,
  }) {
    if (state == DtrReportDataState.failed) issues.add(failed);
    if (state == DtrReportDataState.missing) issues.add(missing);
  }
}
