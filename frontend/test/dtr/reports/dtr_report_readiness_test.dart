import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_readiness.dart';

void main() {
  test('official reports require every authoritative source', () {
    const readiness = DtrReportReadiness(
      employees: DtrReportDataState.ready,
      records: DtrReportDataState.ready,
      assignments: DtrReportDataState.ready,
      policy: DtrReportDataState.ready,
      signatories: DtrReportDataState.ready,
    );

    expect(readiness.canGenerateOfficialReport, isTrue);
    expect(readiness.blockingIssues, isEmpty);
  });

  test('failed and missing sources identify why export is blocked', () {
    const readiness = DtrReportReadiness(
      employees: DtrReportDataState.ready,
      records: DtrReportDataState.ready,
      assignments: DtrReportDataState.failed,
      policy: DtrReportDataState.missing,
      signatories: DtrReportDataState.ready,
    );

    expect(readiness.canGenerateOfficialReport, isFalse);
    expect(
      readiness.blockingIssues,
      contains('Historical assignment and shift data could not be loaded.'),
    );
    expect(
      readiness.blockingIssues,
      contains(
        'Some scheduled dates have no verified attendance policy or deduction data.',
      ),
    );
  });

  test('unconfigured signatories block an otherwise ready report', () {
    const readiness = DtrReportReadiness(
      employees: DtrReportDataState.ready,
      records: DtrReportDataState.ready,
      assignments: DtrReportDataState.ready,
      policy: DtrReportDataState.ready,
      signatories: DtrReportDataState.missing,
    );

    expect(readiness.canGenerateOfficialReport, isFalse);
    expect(
      readiness.blockingIssues,
      contains('Required report signatories are not configured.'),
    );
  });
}
