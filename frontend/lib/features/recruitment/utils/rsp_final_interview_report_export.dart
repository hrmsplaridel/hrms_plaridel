import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_share.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';

/// One row for the Final interview (passed exam) report.
class RspFinalInterviewReportRow {
  const RspFinalInterviewReportRow({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.positionApplied,
    required this.examScorePercent,
    required this.pipelineStatus,
    required this.finalInterviewScheduled,
    required this.finalInterviewResult,
    required this.hrAccountSetup,
    required this.hired,
    required this.appliedAt,
  });

  final String fullName;
  final String email;
  final String phone;
  final String positionApplied;
  final String examScorePercent;
  final String pipelineStatus;
  final String finalInterviewScheduled;
  final String finalInterviewResult;
  final String hrAccountSetup;
  final String hired;
  final String appliedAt;

  static bool _isRegistered(RecruitmentApplication a) {
    return a.status == 'registered' ||
        (a.hiredUserId != null && a.hiredUserId!.trim().isNotEmpty);
  }

  /// Matches labels shown on [RspFinalInterviewScheduler] status badges.
  static String pipelineStatusLabel(RecruitmentApplication app) {
    final registered = _isRegistered(app);
    final scheduled = app.finalInterviewAt;
    final outcome = app.finalInterviewPassed;
    final hrDone = app.hrAccountSetupDone == true;

    if (registered) return 'Hired - Account linked';
    if (outcome == true && hrDone) return 'Final passed - Step 8 done';
    if (outcome == true) return 'Final interview passed - Pending account';
    if (outcome == false) return 'Final interview: Not passed';
    if (scheduled != null) return 'Final interview scheduled';
    return 'Waiting for final interview schedule';
  }

  static String _finalResultLabel(RecruitmentApplication app) {
    final o = app.finalInterviewPassed;
    if (o == true) return 'Passed';
    if (o == false) return 'Not passed';
    return 'Pending';
  }

  static String _formatDateTime(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  static RspFinalInterviewReportRow fromApplication({
    required RecruitmentApplication app,
    required RecruitmentExamResult exam,
  }) {
    return RspFinalInterviewReportRow(
      fullName: app.fullName.trim(),
      email: app.email.trim(),
      phone: (app.phone ?? '').trim(),
      positionApplied: (app.positionAppliedFor ?? '').trim(),
      examScorePercent: exam.scorePercent.toStringAsFixed(1),
      pipelineStatus: pipelineStatusLabel(app),
      finalInterviewScheduled: _formatDateTime(app.finalInterviewAt),
      finalInterviewResult: _finalResultLabel(app),
      hrAccountSetup: app.hrAccountSetupDone ? 'Yes' : 'No',
      hired: _isRegistered(app) ? 'Yes' : 'No',
      appliedAt: _formatDateTime(app.createdAt),
    );
  }
}

abstract final class RspFinalInterviewReportExport {
  RspFinalInterviewReportExport._();

  static String _csvEscape(String value) {
    final s = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (s.contains(',') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _fileStamp() {
    final n = DateTime.now().toLocal();
    return '${n.year}${_two(n.month)}${_two(n.day)}_${_two(n.hour)}${_two(n.minute)}';
  }

  static Uint8List buildCsvBytes({
    required List<RspFinalInterviewReportRow> rows,
    String? filterSummary,
  }) {
    const header = [
      'Full name',
      'Email',
      'Phone',
      'Position',
      'Exam score %',
      'Pipeline status',
      'Final interview scheduled',
      'Deliberation result',
      'HR account setup',
      'Hired',
      'Applied at',
    ];

    final lines = <String>[
      if (filterSummary != null && filterSummary.isNotEmpty) '# $filterSummary',
      '# Generated: ${DateTime.now().toLocal()}',
      '# Applicants (passed screening exam): ${rows.length}',
      header.map(_csvEscape).join(','),
      for (final r in rows)
        [
          r.fullName,
          r.email,
          r.phone,
          r.positionApplied,
          r.examScorePercent,
          r.pipelineStatus,
          r.finalInterviewScheduled,
          r.finalInterviewResult,
          r.hrAccountSetup,
          r.hired,
          r.appliedAt,
        ].map(_csvEscape).join(','),
    ];

    return Uint8List.fromList(utf8.encode('\uFEFF${lines.join('\n')}\n'));
  }

  static Future<pw.Document> buildPdf({
    required List<RspFinalInterviewReportRow> rows,
    String? filterSummary,
  }) async {
    await FormPdf.ensureLogoLoaded();
    final doc = pw.Document();
    final generated = DateTime.now().toLocal();
    final dateLabel =
        '${generated.year}-${_two(generated.month)}-${_two(generated.day)}';

    pw.Widget cell(String text, {bool header = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 7.5 : 7,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          maxLines: 3,
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          'Name',
          'Email',
          'Position',
          'Exam %',
          'Status',
          'Interview date',
          'Result',
          'Hired',
          'Applied',
        ].map((h) => cell(h, header: true)).toList(),
      ),
      for (final r in rows)
        pw.TableRow(
          children: [
            r.fullName,
            r.email,
            r.positionApplied,
            r.examScorePercent,
            r.pipelineStatus,
            r.finalInterviewScheduled,
            r.finalInterviewResult,
            r.hired,
            r.appliedAt,
          ].map(cell).toList(),
        ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: FormPdf.pageLetterLandscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'Final Interview Report (Passed Exam)',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Municipality of Plaridel - Human Resource Management',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generated: $dateLabel · ${rows.length} applicant(s)',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (filterSummary != null && filterSummary.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(filterSummary, style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.25, color: PdfColors.grey600),
            columnWidths: {
              for (var i = 0; i < 9; i++) i: const pw.FlexColumnWidth(1),
            },
            children: tableRows,
          ),
        ],
      ),
    );

    return doc;
  }

  static Future<void> shareCsv({
    required List<RspFinalInterviewReportRow> rows,
    String? filterSummary,
  }) async {
    final bytes = buildCsvBytes(rows: rows, filterSummary: filterSummary);
    await shareOrDownloadFile(
      bytes,
      'rsp_final_interview_report_${_fileStamp()}.csv',
      'text/csv',
    );
  }

  static Future<void> sharePdf({
    required List<RspFinalInterviewReportRow> rows,
    String? filterSummary,
  }) async {
    final doc = await buildPdf(rows: rows, filterSummary: filterSummary);
    final bytes = await doc.save();
    await shareOrDownloadFile(
      bytes,
      'rsp_final_interview_report_${_fileStamp()}.pdf',
      'application/pdf',
    );
  }

  static Future<void> printPdf({
    required BuildContext context,
    required List<RspFinalInterviewReportRow> rows,
    String? filterSummary,
  }) async {
    await FormPdf.printForm(
      context: context,
      buildDocument: () => buildPdf(rows: rows, filterSummary: filterSummary),
      filename: 'rsp_final_interview_report.pdf',
      format: FormPdf.pageLetterLandscape,
    );
  }
}
