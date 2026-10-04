import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/learning_application_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_need_analysis.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class _NoRasterPrinting extends PrintingPlatform {
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DocuTrackerSourceSignatureBundle _signatures(
  String table,
  List<String> slots, {
  String sourceModule = 'rsp',
}) {
  return DocuTrackerSourceSignatureBundle.fromJson(<String, dynamic>{
    'source_module': sourceModule,
    'source_table': table,
    'source_record_id': '11111111-1111-4111-8111-111111111111',
    'source_status': 'saved',
    'signatures': slots
        .map(
          (slot) => <String, dynamic>{
            'slot_key': slot,
            'label': slot,
            'assigned_signer_id': '22222222-2222-4222-8222-222222222222',
            'can_sign': true,
            'signature_asset_id': '33333333-3333-4333-8333-333333333333',
            'signature_image_base64': _onePixelPng,
            'mime_type': 'image/png',
            'signed_by': '22222222-2222-4222-8222-222222222222',
            'signer_name_snapshot': 'Verified Signer',
            'signed_at': '2026-09-16T01:00:00.000Z',
          },
        )
        .toList(growable: false),
  });
}

Future<void> _expectPdf(Future<pw.Document> documentFuture) async {
  final document = await documentFuture;
  final bytes = await document.save();
  expect(bytes.length, greaterThan(500));
  expect(ascii.decode(bytes.take(4).toList()), '%PDF');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all supported RSP forms generate PDFs with persisted signatures',
    () async {
      await _expectPdf(
        FormPdf.buildApplicantsProfilePdf(
          ApplicantsProfileEntry.fromJson(<String, dynamic>{
            'position_applied_for': 'Administrative Officer',
            'applicants': <dynamic>[],
            'prepared_by': 'Prepared Person',
            'checked_by': 'Checking Person',
          }),
          signatures: _signatures(ApplicantsProfileEntry.tableName, const [
            'prepared_by',
            'checked_by',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildSelectionLineupPdf(
          SelectionLineupEntry.fromJson(<String, dynamic>{
            'vacant_position': 'Administrative Officer',
            'applicants': <dynamic>[],
            'prepared_by_name': 'Prepared Person',
          }),
          signatures: _signatures(SelectionLineupEntry.tableName, const [
            'prepared_by',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildComputationOfPointsPdf(
          ComputationOfPointsEntry.fromJson(<String, dynamic>{
            'position': 'Administrative Officer',
            'candidates': <dynamic>[],
            'prepared_by_name': 'Prepared Person',
          }),
          signatures: _signatures(ComputationOfPointsEntry.tableName, const [
            'prepared_by',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildWorkExperienceSheetPdf(
          WorkExperienceSheetEntry.fromJson(<String, dynamic>{
            'position_applied_for': 'Administrative Officer',
            'applicant_name': 'Applicant Person',
          }),
          signatures: _signatures(WorkExperienceSheetEntry.tableName, const [
            'applicant',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildTurnAroundTimePdf(
          TurnAroundTimeEntry.fromJson(<String, dynamic>{
            'position': 'Administrative Officer',
            'applicants': <dynamic>[],
            'prepared_by_name': 'Prepared Person',
            'noted_by_name': 'Noting Person',
          }),
          signatures: _signatures(TurnAroundTimeEntry.tableName, const [
            'prepared_by',
            'noted_by',
          ]),
        ),
      );
    },
  );

  test('supported L&D forms generate PDFs with persisted signatures', () async {
    final previousPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoRasterPrinting();
    addTearDown(() => PrintingPlatform.instance = previousPrinting);

    await _expectPdf(
      FormPdf.buildIdpPdf(
        IdpEntry.fromJson(<String, dynamic>{
          'name': 'Employee Person',
          'position': 'Administrative Officer',
          'department': 'Human Resource Management',
          'development_plan_rows': <dynamic>[],
          'prepared_by': 'Prepared Person',
          'reviewed_by': 'Reviewing Person',
          'noted_by': 'Noting Person',
          'approved_by': 'Approving Person',
        }),
        signatures: _signatures(IdpEntry.tableName, const [
          'prepared_by',
          'reviewed_by',
          'noted_by',
          'approved_by',
        ], sourceModule: 'ld'),
      ),
    );

    await _expectPdf(
      FormPdf.buildActionBrainstormingCoachingPdf(
        ActionBrainstormingEntry.fromJson(<String, dynamic>{
          'department': 'Human Resource Management',
          'date': '2026-09-16',
          'rows': <dynamic>[],
          'certified_by': 'Department Head',
        }),
        signatures: _signatures(ActionBrainstormingEntry.tableName, const [
          'certified_by',
        ], sourceModule: 'ld'),
      ),
    );
  });

  test(
    'applicants profile uses one landscape page per ten applicants',
    () async {
      Future<int> pageCount(int count) async {
        final document = await FormPdf.buildApplicantsProfilePdf(
          ApplicantsProfileEntry(
            positionAppliedFor: 'Nurse I',
            minimumRequirements: 'Bachelor degree',
            dateOfPosting: '2026-09-01',
            closingDate: '2026-09-15',
            applicants: [
              for (var i = 0; i < count; i++)
                ApplicantsProfileApplicant(
                  name: 'Applicant $i',
                  course: 'BS Nursing',
                  address: 'Plaridel',
                  sex: 'F',
                  age: '24',
                  civilStatus: 'Single',
                ),
            ],
          ),
        );
        final bytes = await document.save();
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw.contains('935'), isTrue);
        expect(raw.contains('612'), isTrue);
        return RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
      }

      expect(await pageCount(0), 1);
      expect(await pageCount(1), 1);
      expect(await pageCount(5), 1);
      expect(await pageCount(10), 1);
      expect(await pageCount(11), 2);
      expect(await pageCount(17), 2);
      expect(await pageCount(20), 2);
    },
  );

  test(
    'action brainstorming uses one landscape page per fifteen rows',
    () async {
      Future<int> pageCount(int count) async {
        final document = await FormPdf.buildActionBrainstormingCoachingPdf(
          ActionBrainstormingEntry(
            department: 'Human Resource Management',
            date: 'September 16, 2026',
            rows: [
              for (var i = 0; i < count; i++)
                ActionBrainstormingRow(
                  name: 'Employee $i',
                  stopDoing: 'Stop $i',
                  doLessOf: 'Less $i',
                  keepDoing: 'Keep $i',
                  doMoreOf: 'More $i',
                  startDoing: 'Start $i',
                  goal: 'Goal $i',
                ),
            ],
          ),
        );
        final bytes = await document.save();
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw.contains('792'), isTrue);
        expect(raw.contains('612'), isTrue);
        return RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
      }

      expect(await pageCount(0), 1);
      expect(await pageCount(1), 1);
      expect(await pageCount(5), 1);
      expect(await pageCount(10), 1);
      expect(await pageCount(15), 1);
      expect(await pageCount(16), 2);
      expect(await pageCount(20), 2);
      expect(await pageCount(30), 2);
    },
  );

  test('training need analysis uses one landscape page per six rows', () async {
    Future<int> pageCount(int count) async {
      final document = await FormPdf.buildTrainingNeedAnalysisPdf(
        TrainingNeedAnalysisEntry(
          cyYear: '2025',
          department: 'Rural Health Unit',
          rows: [
            for (var i = 0; i < count; i++)
              TrainingNeedAnalysisRow(
                namePosition: 'Employee $i / Nurse',
                goal: 'Goal $i',
                behavior: 'Behavior $i',
                skillsKnowledge: 'Skills $i',
                needForTraining: 'Need $i',
                trainingRecommendations: 'Recommendation $i',
              ),
          ],
        ),
      );
      final bytes = await document.save();
      final raw = latin1.decode(bytes, allowInvalid: true);
      expect(raw.contains('792'), isTrue);
      expect(raw.contains('612'), isTrue);
      return RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
    }

    expect(await pageCount(0), 1);
    expect(await pageCount(1), 1);
    expect(await pageCount(3), 1);
    expect(await pageCount(6), 1);
    expect(await pageCount(7), 2);
    expect(await pageCount(10), 2);
    expect(await pageCount(12), 2);
    expect(await pageCount(13), 3);
  });

  test('learning application plan prints the official table', () async {
    Future<void> save(int count) async {
      final document = await FormPdf.buildLearningApplicationPlanPdf(
        LearningApplicationPlanEntry(
          memoReportTo: 'Municipal Mayor',
          from: 'HR Staff',
          subject: 'Subject Application Plan',
          entries: [
            for (var i = 0; i < count; i++)
              LearningApplicationPlanRow(
                learning: 'Learning $i',
                objectives: 'Objective $i',
                competencyGapsAddressed: 'Gap $i',
                reapImplementation: 'Coaching',
                timeline: 'Q1',
                personsInvolved: 'Staff',
                evidence: 'Report',
              ),
          ],
        ),
      );
      final bytes = await document.save();
      final raw = latin1.decode(bytes, allowInvalid: true);
      expect(bytes.length, greaterThan(500));
      expect(raw.contains('792'), isTrue);
      expect(raw.contains('612'), isTrue);
    }

    await save(0);
    await save(1);
    await save(3);
  });

  test('IDP prints as one 8.5 by 13 inch portrait page', () async {
    final previousPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoRasterPrinting();
    addTearDown(() => PrintingPlatform.instance = previousPrinting);

    final document = await FormPdf.buildIdpPdf(
      IdpEntry.fromJson(<String, dynamic>{
        'name': 'Employee Person',
        'position': 'Administrative Officer',
        'development_plan_rows': <dynamic>[],
      }),
    );
    final bytes = await document.save();
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length, 1);
    expect(raw.contains('612'), isTrue);
    expect(raw.contains('936'), isTrue);
    expect(FormPdf.idpLayoutPrintFormat.width, 8.5 * 72);
    expect(FormPdf.idpLayoutPrintFormat.height, 13 * 72);
  });

  test('BI form prints as three A4 pages', () async {
    final previousPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoRasterPrinting();
    addTearDown(() => PrintingPlatform.instance = previousPrinting);

    final document = await FormPdf.buildBiFormPdf(
      const BiFormEntry(
        applicantName: 'Jane Applicant',
        applicantDepartment: 'HR',
        applicantPosition: 'Staff',
        positionAppliedFor: 'Officer',
        respondentName: 'John Respondent',
        respondentPosition: 'Head',
        respondentRelationship: 'peer',
        rating1: 5,
        functionalAreas: ['Accounting', 'Program Management'],
        otherFunctionalArea: 'Liaison',
        performance3Years: 'Led the records project.',
      ),
    );
    final bytes = await document.save();
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length, 3);
    expect(raw.contains('595'), isTrue);
    expect(raw.contains('841'), isTrue);
  });

  test(
    'selection line-up prints the qualification table on landscape letter',
    () async {
      final previousPrinting = PrintingPlatform.instance;
      PrintingPlatform.instance = _NoRasterPrinting();
      addTearDown(() => PrintingPlatform.instance = previousPrinting);

      Future<int> pages(int count) async {
        final document = await FormPdf.buildSelectionLineupPdf(
          SelectionLineupEntry(
            date: 'September 18, 2025',
            nameOfAgencyOffice: 'Municipal Budget Office',
            vacantPosition: 'Supervising Administrative Officer',
            itemNo: '2',
            applicants: [
              for (var i = 0; i < count; i++)
                SelectionLineupApplicant(
                  name: 'Applicant $i',
                  education: 'Bachelor',
                  experience: 'Five years',
                  training: '40 hours',
                  eligibility: 'First level',
                ),
            ],
          ),
        );
        final bytes = await document.save();
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw.contains('792'), isTrue);
        expect(raw.contains('612'), isTrue);
        return RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
      }

      expect(await pages(0), 1);
      expect(await pages(1), 1);
      expect(await pages(5), 1);
      expect(await pages(6), 2);
    },
  );

  test(
    'computation of points prints five candidate rows on landscape letter',
    () async {
      final previousPrinting = PrintingPlatform.instance;
      PrintingPlatform.instance = _NoRasterPrinting();
      addTearDown(() => PrintingPlatform.instance = previousPrinting);

      Future<int> pages(int count) async {
        final document = await FormPdf.buildComputationOfPointsPdf(
          ComputationOfPointsEntry(
            date: 'September 18, 2025',
            positionLevel: 'Second Level Position',
            position: 'Administrative Officer',
            salaryGrade: '15',
            rate: '30000',
            office: 'Municipal Budget Office',
            minEducation: 'Bachelor degree',
            minTraining: '8 hours',
            minExperience: '1 year',
            minEligibility: 'Career Service',
            candidates: [
              for (var i = 0; i < count; i++)
                ComputationOfPointsCandidate(
                  name: 'Candidate $i',
                  position: 'Officer',
                  salaryGrade: '15',
                  rate: '30000',
                  education: '20',
                  eligibility: '15',
                  experience: '10',
                  training: '8',
                  performance: '8',
                  potential: '8',
                  workAttitude: '8',
                  total: '77',
                  rank: '${i + 1}',
                ),
            ],
            preparedByName: 'MARCELO B. CANARES',
          ),
        );
        final bytes = await document.save();
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw.contains('792'), isTrue);
        expect(raw.contains('612'), isTrue);
        expect(raw.contains('(088) 3448-200'), isFalse);
        expect(raw.contains('Asenso'), isFalse);
        return RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
      }

      expect(await pages(0), 1);
      expect(await pages(5), 1);
      expect(await pages(6), 2);
      expect(await pages(11), 3);
    },
  );

  test('work experience sheet prints as one landscape letter page', () async {
    final previousPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoRasterPrinting();
    addTearDown(() => PrintingPlatform.instance = previousPrinting);

    final document = await FormPdf.buildWorkExperienceSheetPdf(
      const WorkExperienceSheetEntry(
        positionAppliedFor: 'Administrative Officer',
        department: 'Budget Office',
        minEducation: 'Bachelor degree',
        minExperience: '1 year',
        minTraining: '8 hours',
        minEligibility: 'Career Service',
        jobDescriptionLastWork: 'Prepared payroll and budget reports.',
        applicantName: 'Juan Dela Cruz',
      ),
    );
    final bytes = await document.save();
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length, 1);
    expect(raw.contains('792'), isTrue);
    expect(raw.contains('612'), isTrue);
    expect(raw.contains('(088) 3448-200'), isFalse);
  });

  test('ojt evaluation prints as one F4 portrait page', () async {
    final previousPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoRasterPrinting();
    addTearDown(() => PrintingPlatform.instance = previousPrinting);

    final document = await FormPdf.buildOjtWorkImmersionEvaluationPdf(
      const OjtWorkImmersionEvaluation(
        ojtImmersion: 'Juan Dela Cruz',
        school: 'Misamis University',
        interviewDate: 'October 1, 2026',
        problemSolvingScore: 4,
        problemSolvingNotes: 'Decided quickly with the available facts.',
        communicationScore: 4,
        communicationNotes: 'Explained the update clearly.',
        teamworkScore: 5,
        teamworkNotes: 'Helped the team finish the task.',
        adaptabilityScore: 3,
        adaptabilityNotes: 'Adjusted when the deadline moved.',
        overallRecommendation: 'Recommended',
        keyStrengths: 'Clear communication',
        keyConcerns: 'Needs more examples',
        interviewer: 'MARCELO B. CANARES',
      ),
    );
    final bytes = await document.save();
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length, 1);
    expect(raw.contains('935'), isTrue);
    expect(raw.contains('612'), isTrue);
    expect(raw.contains('(088) 3448-200'), isFalse);
    expect(raw.contains('Asenso'), isFalse);
    final text = _pdfPlainText(bytes);
    expect(text, contains('information'));
    expect(text, contains('stakeholder'));
    expect(text, contains('Describe'));
    expect(text, contains('deadlines'));
    expect(document, isNotNull);
    expect(
      const OjtWorkImmersionEvaluation(
        problemSolvingScore: 4,
        communicationScore: 4,
        teamworkScore: 5,
        adaptabilityScore: 3,
      ).totalScore,
      16,
    );
  });

  test(
    'turn-around time prints five applicant rows on landscape letter',
    () async {
      final previousPrinting = PrintingPlatform.instance;
      PrintingPlatform.instance = _NoRasterPrinting();
      addTearDown(() => PrintingPlatform.instance = previousPrinting);

      Future<int> pages(int count) async {
        final document = await FormPdf.buildTurnAroundTimePdf(
          TurnAroundTimeEntry(
            position: 'Administrative Officer',
            office: 'Budget Office',
            noOfVacantPosition: '1',
            dateOfPublication: 'September 1, 2025',
            endSearch: 'September 15, 2025',
            qs: 'Bachelor degree',
            applicants: [
              for (var i = 0; i < count; i++)
                TurnAroundTimeApplicant(
                  name: 'Applicant $i',
                  dateInitialAssessment: '2025-09-02',
                  dateContractExam: '2025-09-03',
                  skillsTradeExamResult: 'Passed',
                  dateDeliberation: '2025-09-04',
                  dateJobOffer: '2025-09-05',
                  acceptanceDate: '2025-09-06',
                  dateAssumptionToDuty: '2025-09-07',
                  noOfDaysToFillUp: '20',
                  overallCostPerHire: '1500',
                ),
            ],
          ),
        );
        final bytes = await document.save();
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw.contains('792'), isTrue);
        expect(raw.contains('612'), isTrue);
        expect(raw.contains('(088) 3448-200'), isFalse);
        return RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
      }

      expect(await pages(0), 1);
      expect(await pages(3), 1);
      expect(await pages(5), 1);
      expect(await pages(6), 2);
      expect(await pages(11), 3);
    },
  );
}

String _pdfPlainText(List<int> bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final out = StringBuffer();
  final streams = RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream');
  for (final match in streams.allMatches(raw)) {
    final data = latin1.encode(match.group(1)!);
    try {
      out.write(latin1.decode(zlib.decode(data), allowInvalid: true));
    } catch (_) {
      out.write(latin1.decode(data, allowInvalid: true));
    }
  }
  return out.toString();
}
