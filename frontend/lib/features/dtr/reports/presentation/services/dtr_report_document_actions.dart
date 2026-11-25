import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:hrms_plaridel/core/widgets/pdf_preview_preparation.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import '../../data/dtr_export.dart';
import '../../data/dtr_report_period.dart';
import '../../data/dtr_share.dart';
import '../widgets/dtr_report_paper_size.dart';
import '../widgets/dtr_pdf_preview_panel.dart';

enum DtrReportExportFormat { pdf, word, excel }

/// Document actions for one verified report selection. Authorization/readiness
/// remain with the page; this object holds only the document's input data.
class DtrReportDocumentActions {
  const DtrReportDocumentActions({
    required this.year,
    required this.month,
    required this.signatories,
    this.department,
    this.position,
    this.officialHours,
    this.scheduledWorkHoursPerDay,
    this.punchMode,
    this.workingDays,
    this.assignmentEffectiveFrom,
    this.assignmentEffectiveTo,
    this.assignmentSegments = const [],
    this.reportableThrough,
  });
  final int year, month;
  final DtrExportSignatories signatories;
  final String? department, position, officialHours, punchMode;
  final double? scheduledWorkHoursPerDay;
  final List<int>? workingDays;
  final DateTime? assignmentEffectiveFrom,
      assignmentEffectiveTo,
      reportableThrough;
  final List<DtrAssignmentSegment> assignmentSegments;

  Future<void> generateDtr(
    BuildContext context,
    DtrReportExportFormat format, {
    required String selectedName,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
  }) async {
    final signatories = this.signatories;
    final baseName =
        'DTR_${selectedName.replaceAll(' ', '_')}_${dtrReportMonths[month - 1]}_$year';
    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generating DTR...')));
      switch (format) {
        case DtrReportExportFormat.pdf:
          final bytes = await DtrExport.generatePdf(
            employeeName: selectedName,
            year: year,
            month: month,
            start: start,
            end: end,
            recordsByDate: recordsByDate,
            department: department,
            position: position,
            officialHours: officialHours,
            scheduledWorkHoursPerDay: scheduledWorkHoursPerDay,
            punchMode: punchMode,
            workingDays: workingDays,
            assignmentEffectiveFrom: assignmentEffectiveFrom,
            assignmentEffectiveTo: assignmentEffectiveTo,
            assignmentSegments: assignmentSegments,
            reportableThrough: reportableThrough,
            signatories: signatories,
          );
          if (!context.mounted) return;
          await shareOrDownloadPdf(bytes, '$baseName.pdf');
          break;
        case DtrReportExportFormat.excel:
          final bytes = await DtrExport.generateExcel(
            employeeName: selectedName,
            year: year,
            month: month,
            start: start,
            end: end,
            recordsByDate: recordsByDate,
            department: department,
            position: position,
            officialHours: officialHours,
            scheduledWorkHoursPerDay: scheduledWorkHoursPerDay,
            punchMode: punchMode,
            workingDays: workingDays,
            assignmentEffectiveFrom: assignmentEffectiveFrom,
            assignmentEffectiveTo: assignmentEffectiveTo,
            assignmentSegments: assignmentSegments,
            reportableThrough: reportableThrough,
            signatories: signatories,
          );
          if (!context.mounted) return;
          await shareOrDownloadFile(
            bytes,
            '$baseName.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          break;
        case DtrReportExportFormat.word:
          final html = await DtrExport.generateWordHtml(
            employeeName: selectedName,
            year: year,
            month: month,
            start: start,
            end: end,
            recordsByDate: recordsByDate,
            department: department,
            position: position,
            officialHours: officialHours,
            scheduledWorkHoursPerDay: scheduledWorkHoursPerDay,
            punchMode: punchMode,
            workingDays: workingDays,
            assignmentEffectiveFrom: assignmentEffectiveFrom,
            assignmentEffectiveTo: assignmentEffectiveTo,
            assignmentSegments: assignmentSegments,
            reportableThrough: reportableThrough,
            signatories: signatories,
          );
          final bytes = Uint8List.fromList(utf8.encode(html));
          if (!context.mounted) return;
          await shareOrDownloadFile(
            bytes,
            '$baseName.doc',
            'application/msword',
          );
          break;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DTR exported as ${format.name.toUpperCase()}')),
      );
    } catch (e, st) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('DTR export error: $e\n$st');
    }
  }

  /// Print DTR report: open system print dialog when supported; otherwise share PDF.
  Future<void> previewDtrReport(
    BuildContext context, {
    required String selectedName,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? department,
    String? position,
  }) async {
    final signatories = this.signatories;
    final pageFormat = await chooseDtrReportPaperSize(context);
    if (pageFormat == null || !context.mounted) return;
    final baseName =
        'DTR_${selectedName.replaceAll(' ', '_')}_${dtrReportMonths[month - 1]}_$year.pdf';

    try {
      final documents = <PdfPageFormat, Future<Uint8List>>{};
      Future<Uint8List> buildPdf(PdfPageFormat outputFormat) =>
          documents.putIfAbsent(
            outputFormat,
            () => DtrExport.generatePdf(
              employeeName: selectedName,
              year: year,
              month: month,
              start: start,
              end: end,
              recordsByDate: recordsByDate,
              department: department ?? this.department,
              position: position ?? this.position,
              officialHours: officialHours,
              scheduledWorkHoursPerDay: scheduledWorkHoursPerDay,
              punchMode: punchMode,
              workingDays: workingDays,
              assignmentEffectiveFrom: assignmentEffectiveFrom,
              assignmentEffectiveTo: assignmentEffectiveTo,
              assignmentSegments: assignmentSegments,
              reportableThrough: reportableThrough,
              signatories: signatories,
              pageFormat: outputFormat,
            ),
          );
      final prepared = await preparePdfPreview(
        context: context,
        prepare: (_) => buildPdf(pageFormat),
      );
      if (prepared == null || !context.mounted) return;
      await openResponsiveRightSidePanel<void>(
        context: context,
        barrierLabel: 'Close DTR preview',
        breakpoint: 900,
        minWidth: 680,
        initialWidthFraction: 0.62,
        builder: (_) => DtrPdfPreviewPanel(
          buildPdf: buildPdf,
          pageFormat: pageFormat,
          filename: baseName,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to preview DTR: $error')));
    }
  }

  Future<void> printDtrReport(
    BuildContext context, {
    required String selectedName,
    required DateTime start,
    required DateTime end,
    required Map<DateTime, TimeRecord> recordsByDate,
    String? department,
    String? position,
  }) async {
    final signatories = this.signatories;
    final pageFormat = await chooseDtrReportPaperSize(context);
    if (pageFormat == null || !context.mounted) return;
    final baseName =
        'DTR_${selectedName.replaceAll(' ', '_')}_${dtrReportMonths[month - 1]}_$year';
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Preparing print...')));
    try {
      await Printing.layoutPdf(
        onLayout: (printFormat) => DtrExport.generatePdf(
          employeeName: selectedName,
          year: year,
          month: month,
          start: start,
          end: end,
          recordsByDate: recordsByDate,
          department: department ?? this.department,
          position: position ?? this.position,
          officialHours: officialHours,
          scheduledWorkHoursPerDay: scheduledWorkHoursPerDay,
          punchMode: punchMode,
          workingDays: workingDays,
          assignmentEffectiveFrom: assignmentEffectiveFrom,
          assignmentEffectiveTo: assignmentEffectiveTo,
          assignmentSegments: assignmentSegments,
          reportableThrough: reportableThrough,
          signatories: signatories,
          pageFormat: printFormat,
        ),
        name: baseName,
        format: pageFormat,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DTR sent to print')));
    } catch (e) {
      if (!context.mounted) return;
      try {
        final bytes = await DtrExport.generatePdf(
          employeeName: selectedName,
          year: year,
          month: month,
          start: start,
          end: end,
          recordsByDate: recordsByDate,
          reportTitle: 'Daily Time Record Report',
          department: department ?? this.department,
          position: position ?? this.position,
          officialHours: officialHours,
          scheduledWorkHoursPerDay: scheduledWorkHoursPerDay,
          punchMode: punchMode,
          workingDays: workingDays,
          assignmentEffectiveFrom: assignmentEffectiveFrom,
          assignmentEffectiveTo: assignmentEffectiveTo,
          assignmentSegments: assignmentSegments,
          reportableThrough: reportableThrough,
          signatories: signatories,
          pageFormat: pageFormat,
        );
        await shareOrDownloadPdf(bytes, '$baseName.pdf');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Print dialog not available. PDF shared — open it to print.',
            ),
          ),
        );
      } catch (e2) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e2'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
