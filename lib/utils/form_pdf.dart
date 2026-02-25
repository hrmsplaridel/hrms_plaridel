import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Use project data models (same package)
import '../data/applicants_profile.dart';
import '../data/bi_form.dart';
import '../data/comparative_assessment.dart';
import '../data/individual_development_plan.dart';
import '../data/performance_evaluation_form.dart';
import '../data/promotion_certification.dart';
import '../data/action_brainstorming_coaching.dart';
import '../data/selection_lineup.dart';
import '../data/training_need_analysis.dart';
import '../data/turn_around_time.dart';

/// Builds PDF documents from RSP form entries and supports print / share.
/// Paper sizes match sample files: Letter.pdf (8.5"×11"), Long Letter.pdf (8.5"×14"), A4 Letter.pdf.
class FormPdf {
  FormPdf._();

  /// Letter size: 8.5" × 11" (e.g. Letter.pdf)
  static final PdfPageFormat pageLetter =
      PdfPageFormat(612, 792, marginAll: 36);

  /// Long bond: 8.5" × 14" (e.g. Long Letter.pdf)
  static final PdfPageFormat pageLong =
      PdfPageFormat(612, 1008, marginAll: 36);

  /// A4: 210 × 297 mm (e.g. A4 Letter.pdf)
  static final PdfPageFormat pageA4 = PdfPageFormat.a4;

  static String _s(String? v) => v?.trim() ?? '—';

  static Future<void> printDocument(
    pw.Document doc, {
    String name = 'form.pdf',
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: name,
    );
  }

  static Future<void> sharePdf(
    pw.Document doc, {
    String name = 'form.pdf',
  }) async {
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  /// Design layout: wraps body with standard header and footer (matches sample Letter/Long/A4).
  static pw.Widget _formLayout(
    String formTitle,
    pw.Widget body, {
    bool useBoardHeader = false,
    String? officeName,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        useBoardHeader
            ? _pdfHeaderBoard(formTitle, officeName: officeName)
            : _pdfHeader(formTitle),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: body,
          ),
        ),
        _pdfFooter(),
      ],
    );
  }

  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );

  static pw.Document buildBiFormPdf(BiFormEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'BACKGROUND INVESTIGATION (BI FORM)',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'APPLICANT UNDER BI:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      _row('Name:', e.applicantName),
                      _row('Department:', _s(e.applicantDepartment)),
                      _row('Position:', _s(e.applicantPosition)),
                      _row(
                        'Position Applied for in LGU-Plaridel:',
                        _s(e.positionAppliedFor),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'RESPONDENTS:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      _row('Name:', e.respondentName),
                      _row('Position:', _s(e.respondentPosition)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Work relationship: ${e.respondentRelationship}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
              pw.SizedBox(height: 16),
              pw.Text(
                'I. ON COMPETENCIES',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Core and Organizational Competencies:',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Using the following rating guide please check (/) the appropriate box opposite each behavioral Indicator:',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.5),
                  1: pw.FlexColumnWidth(4),
                  2: pw.FlexColumnWidth(0.35),
                  3: pw.FlexColumnWidth(0.35),
                  4: pw.FlexColumnWidth(0.35),
                  5: pw.FlexColumnWidth(0.35),
                  6: pw.FlexColumnWidth(0.35),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children:
                        ['AREA', 'CORE DISCRIPTION', '5', '4', '3', '2', '1']
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  h,
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...List.generate(9, (i) {
                    final r = [
                      e.rating1,
                      e.rating2,
                      e.rating3,
                      e.rating4,
                      e.rating5,
                      e.rating6,
                      e.rating7,
                      e.rating8,
                      e.rating9,
                    ][i];
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            '${i + 1}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            BiFormEntry.competencyDescriptions[i],
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 5 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 4 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 3 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 2 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Center(
                            child: pw.Text(
                              r == 1 ? '/' : '',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static final PdfColor _letterheadNavy = PdfColor.fromInt(0xFF1A237E);
  static final PdfColor _letterheadOrange = PdfColor.fromInt(0xFFE85D04);

  static pw.Widget _pdfHeader(String formTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 52,
              height: 52,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: _letterheadNavy, width: 1.5),
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'Republic of the Philippines',
                  style: pw.TextStyle(fontSize: 9, color: _letterheadNavy),
                ),
                pw.Text(
                  'PROVINCE OF MISAMIS OCCIDENTAL',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _letterheadNavy,
                  ),
                ),
                pw.Text(
                  'MUNICIPALITY OF PLARIDEL',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _letterheadNavy,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Container(
                  width: 180,
                  height: 2,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _letterheadOrange,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          formTitle,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadOrange,
          ),
        ),
        pw.SizedBox(height: 14),
      ],
    );
  }

  static pw.Widget _pdfFooter() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  _pdfFooterIcon(),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    '(088) 3448-200',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(width: 12),
                  _pdfFooterIcon(),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    '(088) 3448-358',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  _pdfFooterIcon(),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    'plaridel_misocc@yahoo.com',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'Asenso',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  fontWeight: pw.FontWeight.bold,
                  color: _letterheadNavy,
                ),
              ),
              pw.Text(
                'PLARIDEL',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _letterheadOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooterIcon() {
    return pw.Container(
      width: 14,
      height: 14,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: _letterheadNavy,
      ),
    );
  }

  static pw.Document buildPerformanceEvaluationPdf(
    PerformanceEvaluationEntry e,
  ) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'Performance / Functional Evaluation',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
              'A. Functional Areas:',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Please check (/) the boxes opposite the functional area where the applicant can perform effectively.',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              e.functionalAreas.isEmpty ? '—' : e.functionalAreas.join(', '),
              style: const pw.TextStyle(fontSize: 9),
            ),
            _row('Other (Please specify)', _s(e.otherFunctionalArea)),
            pw.SizedBox(height: 12),
            pw.Text(
              'I. On performance and other relevant information.',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Work performance in the last 3 years, accomplishments, recognition, contributions:',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              _s(e.performance3Years),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Challenges/difficulties and how the applicant coped:',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              _s(e.challengesCoping),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Compliance with rules; attendance at flag ceremonies, retreats, office programs:',
              style: const pw.TextStyle(fontSize: 8),
            ),
              pw.Text(
                _s(e.complianceAttendance),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static pw.Document buildIdpPdf(IdpEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageA4,
        build: (ctx) => [
          _pdfHeader('INDIVIDUAL DEVELOPMENT PLAN'),
          pw.Text(
            'LOCAL GOVERNMENT UNIT OF PLARIDEL',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          _section('Personal & position'),
          _row('Name', _s(e.name)),
          _row('Position', _s(e.position)),
          _row('Category', _s(e.category)),
          _row('Division', _s(e.division)),
          _row('Department', _s(e.department)),
          _section('Qualifications'),
          _row('Education', _s(e.education)),
          _row('Experience', _s(e.experience)),
          _row('Training', _s(e.training)),
          _row('Eligibility', _s(e.eligibility)),
          _section('Target positions'),
          _row('1', _s(e.targetPosition1)),
          _row('2', _s(e.targetPosition2)),
          _section('Performance'),
          _row('Avg rating', _s(e.avgRating)),
          _row('Performance rating', _s(e.performanceRating)),
          _section('Competence'),
          _row('Competency', _s(e.competencyDescription)),
          _row('Rating', _s(e.competenceRating)),
          _section('Succession priority'),
          _row('Score', _s(e.successionPriorityScore)),
          _row('Rating', _s(e.successionPriorityRating)),
          _section('Development plan'),
          if (e.developmentPlanRows.isEmpty)
            pw.Text('—', style: const pw.TextStyle(fontSize: 10))
          else
            ...e.developmentPlanRows.map(
              (r) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  'Objectives: ${_s(r.objectives)}\nL&D: ${_s(r.ldProgram)}\nRequirements: ${_s(r.requirements)}\nTime frame: ${_s(r.timeFrame)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ),
          _section('Signatures'),
          _row('Prepared by', _s(e.preparedBy)),
          _row('Reviewed by', _s(e.reviewedBy)),
          _row('Noted by', _s(e.notedBy)),
          _row('Approved by', _s(e.approvedBy)),
          pw.SizedBox(height: 16),
          _pdfFooter(),
        ],
      ),
    );
    return doc;
  }

  static pw.Document buildApplicantsProfilePdf(ApplicantsProfileEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLong,
        build: (ctx) => _formLayout(
          'APPLICANTS PROFILE',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row('Position Applied for:', _s(e.positionAppliedFor)),
            _row('Minimum Requirements:', _s(e.minimumRequirements)),
            _row('Date of Posting:', _s(e.dateOfPosting)),
            _row('Closing Date:', _s(e.closingDate)),
            pw.SizedBox(height: 12),
            if (e.applicants.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(0.4),
                  4: const pw.FlexColumnWidth(0.4),
                  5: const pw.FlexColumnWidth(0.8),
                  6: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'NAME',
                              'COURSE',
                              'ADDRESS',
                              'SEX',
                              'AGE',
                              'CIVIL STATUS',
                              'REMARK (DISABILITY)',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 8),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.applicants.map(
                    (a) => pw.TableRow(
                      children:
                          [
                                _s(a.name),
                                _s(a.course),
                                _s(a.address),
                                _s(a.sex),
                                _s(a.age),
                                _s(a.civilStatus),
                                _s(a.remarkDisability),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 8),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _row('Prepared by:', _s(e.preparedBy)),
              _row('Checked by:', _s(e.checkedBy)),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static pw.Widget _pdfHeaderBoard(String formTitle, {String? officeName}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Republic of the Philippines',
          style: pw.TextStyle(fontSize: 9, color: _letterheadNavy),
        ),
        pw.Text(
          'PROVINCE OF MISAMIS OCCIDENTAL',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadNavy,
          ),
        ),
        pw.Text(
          'MUNICIPALITY OF PLARIDEL',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadNavy,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          width: 160,
          height: 1.5,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'HUMAN RESOURCE MERIT PROMOTION AND SELECTION BOARD',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadOrange,
          ),
        ),
        if (officeName != null && officeName.isNotEmpty)
          pw.Text(
            officeName,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        pw.SizedBox(height: 8),
        pw.Text(
          formTitle,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _letterheadOrange,
          ),
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  static pw.Document buildComparativeAssessmentPdf(
    ComparativeAssessmentEntry e,
  ) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLong,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeaderBoard(
              'COMPARATIVE ASSESSMENT OF CANDIDATES FOR PROMOTION',
            ),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'POSITION TO BE FILLED:',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
            pw.Text(
              _s(e.positionToBeFilled),
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'MINIMUM REQUIREMENTS:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            _row('EDUCATION :', _s(e.minReqEducation)),
            _row('EXPERIENCE :', _s(e.minReqExperience)),
            _row('ELIGIBILITY :', _s(e.minReqEligibility)),
            _row('TRAINING :', _s(e.minReqTraining)),
            pw.SizedBox(height: 10),
            if (e.candidates.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(0.8),
                  3: const pw.FlexColumnWidth(0.5),
                  4: const pw.FlexColumnWidth(0.8),
                  5: const pw.FlexColumnWidth(0.6),
                  6: const pw.FlexColumnWidth(0.5),
                  7: const pw.FlexColumnWidth(0.8),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'CANDIDATES',
                              'Present Position/Salary Grade/Monthly Salary',
                              'EDUCATION',
                              'No. of hrs. Related Training',
                              'Related Experienced',
                              'Eligibility',
                              'Performance Rating',
                              'REMARKS',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(3),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.candidates.map(
                    (c) => pw.TableRow(
                      children:
                          [
                                _s(c.candidateName),
                                _s(c.presentPositionSalary),
                                _s(c.education),
                                _s(c.trainingHrs),
                                _s(c.relatedExperience),
                                _s(c.eligibility),
                                _s(c.performanceRating),
                                _s(c.remarks),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
          _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  static pw.Document buildPromotionCertificationPdf(
    PromotionCertificationEntry e,
  ) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'Promotion Certification / Screening',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row('Position for promotion:', _s(e.positionForPromotion)),
            pw.SizedBox(height: 10),
            if (e.candidates.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: ['Name', '1', '2', '3', '4', '5']
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              h,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  ...e.candidates.map(
                    (c) => pw.TableRow(
                      children:
                          [
                                _s(c.name),
                                _s(c.col1),
                                _s(c.col2),
                                _s(c.col3),
                                _s(c.col4),
                                _s(c.col5),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 8),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            pw.Text(
              'We hereby certify that the above candidate(s) have been screened and found to be qualified for promotion to the above position.',
              style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Done this ${_s(e.dateDay)} day of ${_s(e.dateMonth)}, ${_s(e.dateYear)}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              _s(e.signatoryName),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _s(e.signatoryTitle),
              style: const pw.TextStyle(fontSize: 9),
            ),
              pw.Text('Secretariat', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static pw.Document buildSelectionLineupPdf(SelectionLineupEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => _formLayout(
          'SELECTION LINE-UP',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Date: ${_s(e.date)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            _row('Name of Agency/Office:', _s(e.nameOfAgencyOffice)),
            _row('Vacant Position:', _s(e.vacantPosition)),
            _row('Item No.:', _s(e.itemNo)),
            pw.SizedBox(height: 10),
            if (e.applicants.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'NAME OF APPLICANTS',
                              'EDUCATION',
                              'EXPERIENCE',
                              'TRAINING',
                              'ELIGIBILITY',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(3),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.applicants.map(
                    (a) => pw.TableRow(
                      children:
                          [
                                _s(a.name),
                                _s(a.education),
                                _s(a.experience),
                                _s(a.training),
                                _s(a.eligibility),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Prepared by:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _s(e.preparedByName),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
              pw.Text(
                _s(e.preparedByTitle),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }

  static pw.Document buildTurnAroundTimePdf(TurnAroundTimeEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLong,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeaderBoard(
              'TURN-AROUND TIME',
              officeName: 'MGO-Plaridel, Misamis Occidental',
            ),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _row('Position:', _s(e.position)),
            _row('Office:', _s(e.office)),
            _row('No. of Vacant Position:', _s(e.noOfVacantPosition)),
            _row('Date of Publication:', _s(e.dateOfPublication)),
            _row('End Search:', _s(e.endSearch)),
            _row('Q.S.:', _s(e.qs)),
            pw.SizedBox(height: 10),
            if (e.applicants.isEmpty)
              pw.Text('—', style: const pw.TextStyle(fontSize: 10))
            else
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(0.6),
                  2: const pw.FlexColumnWidth(0.6),
                  3: const pw.FlexColumnWidth(0.6),
                  4: const pw.FlexColumnWidth(0.5),
                  5: const pw.FlexColumnWidth(0.5),
                  6: const pw.FlexColumnWidth(0.6),
                  7: const pw.FlexColumnWidth(0.6),
                  8: const pw.FlexColumnWidth(0.5),
                  9: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children:
                        [
                              'Name of Applicant',
                              'Date of Initial Assesment',
                              'Date of Contract for trade and written exam',
                              'Skills Trade/ Exam Result',
                              'Date of Deliberation',
                              'Date of Job Offer',
                              'Acceptance date of Job Offer',
                              'Date of Assumption to Duty',
                              'No. of Days to Fill-Up Position',
                              'Overall Cost per hire',
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(2),
                                child: pw.Text(
                                  h,
                                  style: const pw.TextStyle(fontSize: 6),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ...e.applicants.map(
                    (a) => pw.TableRow(
                      children:
                          [
                                _s(a.name),
                                _s(a.dateInitialAssessment),
                                _s(a.dateContractExam),
                                _s(a.skillsTradeExamResult),
                                _s(a.dateDeliberation),
                                _s(a.dateJobOffer),
                                _s(a.acceptanceDate),
                                _s(a.dateAssumptionToDuty),
                                _s(a.noOfDaysToFillUp),
                                _s(a.overallCostPerHire),
                              ]
                              .map(
                                (v) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(2),
                                  child: pw.Text(
                                    v,
                                    style: const pw.TextStyle(fontSize: 6),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Prepared by:',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        _s(e.preparedByName),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _s(e.preparedByTitle),
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Noted by:',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        _s(e.notedByName),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _s(e.notedByTitle),
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
                  ],
                ),
              ),
            ),
            _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  /// Training Need Analysis and Consolidated Report (L&D) — header with CY and Department, then 6-column table.
  static pw.Document buildTrainingNeedAnalysisPdf(TrainingNeedAnalysisEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeader('TRAINING NEED ANALYSIS'),
            pw.Text(
              'AND CONSOLIDATED REPORT',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('FOR CY ${_s(e.cyYear)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('DEPARTMENT: ${_s(e.department)}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 14),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: e.rows.isEmpty
                    ? pw.Text('—', style: const pw.TextStyle(fontSize: 10))
                    : pw.Table(
                        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.2),
                          1: pw.FlexColumnWidth(1),
                          2: pw.FlexColumnWidth(1),
                          3: pw.FlexColumnWidth(1),
                          4: pw.FlexColumnWidth(1),
                          5: pw.FlexColumnWidth(1.2),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            children: [
                              'NAME/POSITION',
                              'GOAL',
                              'BEHAVIOR',
                              'SKILLS/KNOWLEDGE',
                              'NEED FOR TRAINING',
                              'TRAINING RECOMMENDATIONS',
                            ]
                                .map(
                                  (h) => pw.Padding(
                                    padding: const pw.EdgeInsets.all(4),
                                    child: pw.Text(
                                      h,
                                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          ...e.rows.map(
                            (r) => pw.TableRow(
                              children: [
                                _s(r.namePosition),
                                _s(r.goal),
                                _s(r.behavior),
                                _s(r.skillsKnowledge),
                                _s(r.needForTraining),
                                _s(r.trainingRecommendations),
                              ]
                                  .map(
                                    (v) => pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(v, style: const pw.TextStyle(fontSize: 8)),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }

  /// Action Brainstorming and Coaching Worksheet (L&D) — DEPARTMENT, DATE, instruction, 7-column table, Certified by / Date.
  static pw.Document buildActionBrainstormingCoachingPdf(ActionBrainstormingEntry e) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageLetter,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _pdfHeader('ACTION BRAINSTORMING AND COACHING WORKSHEET'),
            _row('DEPARTMENT:', _s(e.department)),
            _row('DATE:', _s(e.date)),
            pw.SizedBox(height: 8),
            pw.Text(
              'Instruction: Use the worksheet to brainstorm/coach staff of the new ideas to move the department closer to department goal.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: e.rows.isEmpty
                    ? pw.Text('—', style: const pw.TextStyle(fontSize: 10))
                    : pw.Table(
                        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(0.4),
                          1: pw.FlexColumnWidth(1),
                          2: pw.FlexColumnWidth(1),
                          3: pw.FlexColumnWidth(1),
                          4: pw.FlexColumnWidth(1),
                          5: pw.FlexColumnWidth(1),
                          6: pw.FlexColumnWidth(1),
                          7: pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            children: [
                              '#',
                              'NAME',
                              'STOP DOING',
                              'DO LESS OF',
                              'KEEP DOING',
                              'DO MORE OF',
                              'START DOING',
                              'GOAL',
                            ]
                                .map(
                                  (h) => pw.Padding(
                                    padding: const pw.EdgeInsets.all(3),
                                    child: pw.Text(
                                      h,
                                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          ...e.rows.asMap().entries.map(
                                (entry) {
                                  final i = entry.key + 1;
                                  final r = entry.value;
                                  return pw.TableRow(
                                    children: [
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.all(3),
                                        child: pw.Text('$i', style: const pw.TextStyle(fontSize: 8)),
                                      ),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.name), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.stopDoing), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.doLessOf), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.keepDoing), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.doMoreOf), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.startDoing), style: const pw.TextStyle(fontSize: 7))),
                                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_s(r.goal), style: const pw.TextStyle(fontSize: 7))),
                                    ],
                                  );
                                },
                              ),
                        ],
                      ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Certified by:', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(_s(e.certifiedBy), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Department Head', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Date:', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(_s(e.certificationDate), style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            _pdfFooter(),
          ],
        ),
      ),
    );
    return doc;
  }
}
