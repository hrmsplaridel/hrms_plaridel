import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_assignments.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_repository.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_bulk_export.dart';

class _Repository extends DtrReportRepository {
  final batches = <List<String>>[];
  final errors = <String, String>{};
  bool missingAssignment = false;
  @override
  Future<DtrBulkReportBatch> fetchBulkReportBatch(
    List<EmployeeOption> employees, {
    required int year,
    required int month,
  }) async {
    batches.add(employees.map((e) => e.id).toList());
    return DtrBulkReportBatch(
      employees: {
        for (final employee in employees)
          if (!errors.containsKey(employee.id))
            employee.id: DtrBulkEmployeeReport(
              recordsPage: const TimeRecordPage(
                items: [],
                total: 0,
                limit: 0,
                offset: 0,
              ),
              assignmentTimeline: missingAssignment
                  ? const []
                  : [
                      DtrReportAssignment(
                        effectiveFrom: DateTime(2026, 2),
                        officialHours: '08:00AM-05:00PM',
                        workHoursPerDay: 8,
                        workingDays: const [1, 2, 3, 4, 5],
                      ),
                    ],
            ),
      },
      errors: errors,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  List<EmployeeOption> employees(int count) => List.generate(
    count,
    (i) => EmployeeOption(id: '$i', fullName: 'Employee $i'),
  );
  DtrReportBulkExporter exporter(_Repository repository) =>
      DtrReportBulkExporter(
        repository: repository,
        year: 2026,
        month: 2,
        start: DateTime(2026, 2),
        end: DateTime(2026, 2, 28),
        signatories: DtrExportSignatories.empty,
      );

  test(
    'bulk batches 101 employees and rejects a partial report with the employee error',
    () async {
      final repository = _Repository()..errors['100'] = 'Missing policy';
      final progress = <int>[];
      await expectLater(
        exporter(repository).prepare(
          selected: employees(101),
          onProgress: (prepared, total) {
            expect(total, 101);
            progress.add(prepared);
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Employee 100: Missing policy'),
          ),
        ),
      );
      expect(repository.batches.map((b) => b.length), [100, 1]);
      expect(progress, [0, 100, 101]);
    },
  );

  test(
    'changing print paper reuses loaded reports and caches each document',
    () async {
      final repository = _Repository();
      final build = await exporter(repository).prepare(selected: employees(2));
      final a4 = build(PdfPageFormat.a4);
      expect(identical(a4, build(PdfPageFormat.a4)), isTrue);
      final legal = build(PdfPageFormat.legal);
      final documents = [await a4, await legal];
      for (final bytes in documents) {
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)),
          hasLength(2),
        );
      }
      expect(repository.batches, hasLength(1));
    },
  );

  test(
    'unverified assignments and undated inactive employees cannot be printed',
    () async {
      final repository = _Repository()..missingAssignment = true;
      await expectLater(
        exporter(repository).prepare(selected: employees(2)),
        throwsStateError,
      );
      final inactive = [
        const EmployeeOption(
          id: 'x',
          fullName: 'Inactive',
          employmentStatus: 'inactive',
        ),
        ...employees(1),
      ];
      repository.batches.clear();
      await expectLater(
        exporter(repository).prepare(selected: inactive),
        throwsStateError,
      );
      expect(repository.batches, isEmpty);
    },
  );
}
