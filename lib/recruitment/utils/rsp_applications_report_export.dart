import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/recruitment_application.dart';
import '../../data/rsp_screening_scores.dart';
import '../../dtr/dtr_share.dart';
import '../../utils/form_pdf.dart';

/// One applicant row for CSV / PDF export (Applications & Exam Results).
class RspApplicationsReportRow {
  const RspApplicationsReportRow({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.suffix,
    required this.gender,
    required this.email,
    required this.phone,
    required this.positionApplied,
    required this.status,
    required this.examOutcome,
    required this.examScorePercent,
    required this.generalPercent,
    required this.mathPercent,
    required this.generalInfoPercent,
    required this.beiPercent,
    required this.appliedAt,
    required this.applicationLetter,
    required this.resume,
    required this.tor,
    required this.eligibilityTrainings,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String suffix;
  final String gender;
  final String email;
  final String phone;
  final String positionApplied;
  final String status;
  final String examOutcome;
  final String examScorePercent;
  final String generalPercent;
  final String mathPercent;
  final String generalInfoPercent;
  final String beiPercent;
  final String appliedAt;
  final String applicationLetter;
  final String resume;
  final String tor;
  final String eligibilityTrainings;

  static RspApplicationsReportRow fromApplication({
    required RecruitmentApplication app,
    RecruitmentExamResult? exam,
  }) {
    final full = app.fullName.trim();
    final parts = full.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final fallbackFirst = parts.isNotEmpty ? parts.first : '';
    final fallbackLast = parts.length >= 2 ? parts.last : '';

    final first = (app.firstName ?? '').trim().isNotEmpty
        ? app.firstName!.trim()
        : fallbackFirst;
    final middle = (app.middleName ?? '').trim();
    final last = (app.lastName ?? '').trim().isNotEmpty
        ? app.lastName!.trim()
        : fallbackLast;

    Map<String, dynamic>? answers;
    if (exam?.answersJson != null) {
      answers = exam!.answersJson;
    }

    double? sectionPct(String key) {
      final section = _subsection(answers, key);
      if (section == null) return null;
      return RspScreeningScores.mcqSectionPercent(section);
    }

    double? beiPct() {
      final bei = _subsection(answers, 'bei');
      if (bei == null) return null;
      return RspScreeningScores.beiSectionPercent(bei);
    }

    String pctOrBlank(double? v) =>
        v == null ? '' : v.toStringAsFixed(1);

    String applied = '';
    if (app.createdAt != null) {
      final d = app.createdAt!.toLocal();
      applied =
          '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
    }

    return RspApplicationsReportRow(
      firstName: first,
      middleName: middle,
      lastName: last,
      suffix: (app.suffix ?? '').trim(),
      gender: (app.sex ?? '').trim(),
      email: app.email.trim(),
      phone: (app.phone ?? '').trim(),
      positionApplied: (app.positionAppliedFor ?? '').trim(),
      status: RspApplicationsReportExport.statusDisplayLabel(app.status),
      examOutcome: exam == null
          ? 'No exam'
          : (exam.passed ? 'Passed' : 'Failed'),
      examScorePercent:
          exam == null ? '' : exam.scorePercent.toStringAsFixed(1),
      generalPercent: pctOrBlank(sectionPct('general')),
      mathPercent: pctOrBlank(sectionPct('math')),
      generalInfoPercent: pctOrBlank(sectionPct('general_info')),
      beiPercent: pctOrBlank(beiPct()),
      appliedAt: applied,
      applicationLetter: _docLabel(app, RspApplicationDocKind.applicationLetter),
      resume: _docLabel(app, RspApplicationDocKind.resume),
      tor: _docLabel(app, RspApplicationDocKind.tor),
      eligibilityTrainings:
          _docLabel(app, RspApplicationDocKind.eligibilityTrainings),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static Map<String, dynamic>? _subsection(
    Map<String, dynamic>? answers,
    String key,
  ) {
    if (answers == null) return null;
    final v = answers[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static String _docLabel(RecruitmentApplication app, RspApplicationDocKind kind) {
    final path = app.docPath(kind);
    if (path == null || path.trim().isEmpty) return 'No';
    final name = app.docDisplayName(kind);
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return 'Yes';
  }
}

abstract final class RspApplicationsReportExport {
  RspApplicationsReportExport._();

  /// Human-readable application status for reports (CSV, PDF, preview).
  static String statusDisplayLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'registered':
        return 'Hired';
      case 'passed':
        return 'Exam Passed';
      case 'failed':
        return 'Exam Not Passed';
      case 'document_approved':
        return 'Documents Approved';
      case 'document_declined':
        return 'Documents Declined';
      case 'exam_taken':
        return 'Exam Submitted';
      case 'submitted':
        return 'Application Submitted';
      default:
        final s = raw.trim();
        if (s.isEmpty) return '-';
        if (s.contains('_')) {
          return s
              .split('_')
              .where((p) => p.isNotEmpty)
              .map(
                (p) => '${p[0].toUpperCase()}${p.length > 1 ? p.substring(1) : ''}',
              )
              .join(' ');
        }
        return s;
    }
  }

  static String _csvEscape(String value) {
    final s = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static Uint8List buildCsvBytes({
    required List<RspApplicationsReportRow> rows,
    String? filterSummary,
  }) {
    final header = [
      'First name',
      'Middle name',
      'Last name',
      'Suffix',
      'Gender',
      'Email',
      'Phone',
      'Position applied',
      'Status',
      'Exam outcome',
      'Exam score %',
      'General %',
      'Math %',
      'General info %',
      'BEI %',
      'Applied at',
      'Application letter',
      'Resume',
      'TOR',
      'Eligibility / trainings',
    ];

    final lines = <String>[
      if (filterSummary != null && filterSummary.isNotEmpty)
        '# $filterSummary',
      '# Generated: ${DateTime.now().toLocal()}',
      '# Applicants: ${rows.length}',
      header.map(_csvEscape).join(','),
      for (final r in rows)
        [
          r.firstName,
          r.middleName,
          r.lastName,
          r.suffix,
          r.gender,
          r.email,
          r.phone,
          r.positionApplied,
          r.status,
          r.examOutcome,
          r.examScorePercent,
          r.generalPercent,
          r.mathPercent,
          r.generalInfoPercent,
          r.beiPercent,
          r.appliedAt,
          r.applicationLetter,
          r.resume,
          r.tor,
          r.eligibilityTrainings,
        ].map(_csvEscape).join(','),
    ];

    return Uint8List.fromList(utf8.encode('\uFEFF${lines.join('\n')}\n'));
  }

  static Future<pw.Document> buildPdf({
    required List<RspApplicationsReportRow> rows,
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
            fontSize: header ? 7 : 6.5,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          maxLines: 2,
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          'First',
          'Last',
          'Email',
          'Phone',
          'Position',
          'Status',
          'Exam',
          'Score',
          'Gen%',
          'Math%',
          'Info%',
          'BEI%',
          'Applied',
        ].map((h) => cell(h, header: true)).toList(),
      ),
      for (final r in rows)
        pw.TableRow(
          children: [
            r.firstName,
            r.lastName,
            r.email,
            r.phone,
            r.positionApplied,
            r.status,
            r.examOutcome,
            r.examScorePercent,
            r.generalPercent,
            r.mathPercent,
            r.generalInfoPercent,
            r.beiPercent,
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
            'Applications & Exam Results Report',
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
            pw.Text(
              filterSummary,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.25, color: PdfColors.grey600),
            columnWidths: {
              for (var i = 0; i < 13; i++) i: const pw.FlexColumnWidth(1),
            },
            children: tableRows,
          ),
        ],
      ),
    );

    return doc;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _fileStamp() {
    final n = DateTime.now().toLocal();
    return '${n.year}${_two(n.month)}${_two(n.day)}_${_two(n.hour)}${_two(n.minute)}';
  }

  static Future<void> shareCsv({
    required List<RspApplicationsReportRow> rows,
    String? filterSummary,
  }) async {
    final bytes = buildCsvBytes(rows: rows, filterSummary: filterSummary);
    await shareOrDownloadFile(
      bytes,
      'rsp_applications_report_${_fileStamp()}.csv',
      'text/csv',
    );
  }

  static Future<void> sharePdf({
    required List<RspApplicationsReportRow> rows,
    String? filterSummary,
  }) async {
    final doc = await buildPdf(rows: rows, filterSummary: filterSummary);
    final bytes = await doc.save();
    await shareOrDownloadFile(
      bytes,
      'rsp_applications_report_${_fileStamp()}.pdf',
      'application/pdf',
    );
  }

  static Future<void> printPdf({
    required BuildContext context,
    required List<RspApplicationsReportRow> rows,
    String? filterSummary,
  }) async {
    await FormPdf.printForm(
      context: context,
      buildDocument: () => buildPdf(rows: rows, filterSummary: filterSummary),
      filename: 'rsp_applications_report.pdf',
      format: FormPdf.pageLetterLandscape,
    );
  }
}
