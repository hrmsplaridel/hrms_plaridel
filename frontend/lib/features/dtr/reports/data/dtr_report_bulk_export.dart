import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'dtr_export.dart';
import 'dtr_report_assignments.dart';
import 'dtr_report_employee_status.dart';
import 'dtr_report_repository.dart';

/// Prepares a complete bulk report once, then reuses it for printer paper changes.
class DtrReportBulkExporter {
  const DtrReportBulkExporter({
    required this.repository,
    required this.year,
    required this.month,
    required this.start,
    required this.end,
    required this.signatories,
  });
  final DtrReportRepository repository;
  final int year, month;
  final DateTime start, end;
  final DtrExportSignatories signatories;

  DtrExportItem _buildDtrExportItem({
    required EmployeeOption employee,
    required TimeRecordPage recordsPage,
    required List<DtrReportAssignment> assignmentTimeline,
  }) {
    final records = recordsPage.items;
    final selectedAssignments = assignmentsOverlappingDtrRange(
      assignmentTimeline,
      this.start,
      this.end,
    );
    if (selectedAssignments.isEmpty ||
        !hasCompleteDtrAssignments(selectedAssignments)) {
      throw StateError(
        'No assignment and shift covers ${employee.fullName} for the selected month.',
      );
    }
    if (!hasVerifiedDtrPolicyCoverage(
      records: records,
      timeline: assignmentTimeline,
      year: year,
      month: month,
      startDay: this.start.day,
      endDay: this.end.day,
      reportableThrough: recordsPage.reportableThrough,
    )) {
      throw StateError(
        'Attendance policy data could not be verified for ${employee.fullName}.',
      );
    }
    final start = this.start;
    final end = this.end;
    final reportAssignments = assignmentsOverlappingDtrRange(
      assignmentTimeline,
      start,
      end,
    );
    final rawRecordsByDate = <DateTime, TimeRecord>{};
    for (final r in records) {
      rawRecordsByDate[DateTime(
            r.recordDate.year,
            r.recordDate.month,
            r.recordDate.day,
          )] =
          r;
    }
    final filteredRecords = filterDtrReportRecords(
      rawRecordsByDate,
      assignmentTimeline,
    );
    final rangedRecords = Map<DateTime, TimeRecord>.fromEntries(
      filteredRecords.entries.where(
        (e) => !e.key.isBefore(start) && !e.key.isAfter(end),
      ),
    );
    return DtrExportItem(
      employeeName: employee.fullName,
      recordsByDate: rangedRecords,
      department:
          dtrAssignmentHeaderValue(
            reportAssignments.map((a) => a.department),
            multipleLabel: 'Multiple departments (see notes)',
          ) ??
          employee.departmentName,
      position: dtrAssignmentHeaderValue(
        reportAssignments.map((a) => a.position),
        multipleLabel: 'Multiple positions (see notes)',
      ),
      officialHours: dtrAssignmentHeaderValue(
        reportAssignments.map((a) => a.officialHours),
        multipleLabel: 'Multiple schedules (see notes)',
      ),
      assignmentSegments: reportAssignments
          .map(
            (assignment) => DtrAssignmentSegment(
              effectiveFrom: assignment.effectiveFrom,
              effectiveTo: assignment.effectiveTo,
              department: assignment.department,
              position: assignment.position,
              officialHours: assignment.officialHours,
              scheduledWorkHoursPerDay: assignment.workHoursPerDay,
              punchMode: assignment.punchMode,
              overnight: assignment.overnight,
              shiftEndMinutes: assignment.shiftEndMinutes,
              workingDays: assignment.workingDays,
              scheduleOverrides: assignment.scheduleOverrides,
            ),
          )
          .toList(growable: false),
      reportableThrough: recordsPage.reportableThrough,
    );
  }

  Future<LayoutCallback> prepare({
    required List<EmployeeOption> selected,
    void Function(int prepared, int total)? onProgress,
  }) async {
    if (selected.length < 2) {
      throw StateError('Select at least two employees first.');
    }
    if (selected.any(
      (employee) => hasUndatedInactiveEmployment(
        employmentStatus: employee.employmentStatus,
      ),
    )) {
      throw StateError(
        'An employee has undated inactive employment. Record the last day of service before exporting.',
      );
    }
    const batchSize = 100;
    final items = <DtrExportItem>[];
    final failures = <String>[];
    onProgress?.call(0, selected.length);
    for (var offset = 0; offset < selected.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, selected.length).toInt();
      final batchEmployees = selected.sublist(offset, end);
      final batch = await repository.fetchBulkReportBatch(
        batchEmployees,
        year: year,
        month: month,
      );
      for (final employee in batchEmployees) {
        final employeeFailure = batch.errors[employee.id];
        final reportData = batch.employees[employee.id];
        if (employeeFailure != null || reportData == null) {
          failures.add(
            '${employee.fullName}: '
            '${employeeFailure ?? 'No report data was returned'}',
          );
          continue;
        }
        try {
          items.add(
            _buildDtrExportItem(
              employee: employee,
              recordsPage: reportData.recordsPage,
              assignmentTimeline: reportData.assignmentTimeline,
            ),
          );
        } catch (error) {
          failures.add('${employee.fullName}: $error');
        }
      }
      onProgress?.call(end, selected.length);
    }
    if (failures.isNotEmpty) {
      final visible = failures.take(5).join('; ');
      final remaining = failures.length - 5;
      throw StateError(
        'Could not prepare ${failures.length} selected DTR(s): $visible'
        '${remaining > 0 ? '; and $remaining more' : ''}',
      );
    }
    // Re-layout prepared data when the printer changes paper; do not re-fetch
    // employee reports for each native print-dialog callback.
    final documents = <PdfPageFormat, Future<Uint8List>>{};
    return (pageFormat) => documents.putIfAbsent(
      pageFormat,
      () => DtrExport.generateBulkPdf(
        items: items,
        year: year,
        month: month,
        start: start,
        end: end,
        reportTitle: 'Daily Time Record Report',
        signatories: signatories,
        pageFormat: pageFormat,
      ),
    );
  }
}
