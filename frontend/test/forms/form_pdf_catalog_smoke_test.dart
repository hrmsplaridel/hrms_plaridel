import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/comparative_assessment.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/learning_application_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/learning_development/models/performance_evaluation_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/promotion_certification.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_need_analysis.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPrinting = PrintingPlatform.instance;
  setUp(() {
    PrintingPlatform.instance = _NoRasterPrinting();
    SharedPreferences.setMockInitialValues({});
    FormPdf.debugLoadPrintTemplateMeta =
        ({required module, required formKey}) async => null;
  });
  tearDown(() {
    PrintingPlatform.instance = previousPrinting;
    FormPdf.debugLoadPrintTemplateMeta = null;
  });

  test(
    'FormPrintCatalog keys all have PDF builders that produce bytes',
    () async {
      final builders = <String, Future<pw.Document> Function()>{
        'rsp|bi': () => FormPdf.buildBiFormPdf(
          const BiFormEntry(
            applicantName: 'Applicant',
            respondentName: 'Respondent',
            respondentRelationship: 'Colleague',
          ),
        ),
        'rsp|applicants_profile': () => FormPdf.buildApplicantsProfilePdf(
          ApplicantsProfileEntry(
            positionAppliedFor: 'Clerk',
            applicants: const [ApplicantsProfileApplicant(name: 'A')],
          ),
        ),
        'rsp|selection_lineup': () =>
            FormPdf.buildSelectionLineupPdf(const SelectionLineupEntry()),
        'rsp|computation_of_points': () => FormPdf.buildComputationOfPointsPdf(
          const ComputationOfPointsEntry(),
        ),
        'rsp|work_experience': () => FormPdf.buildWorkExperienceSheetPdf(
          const WorkExperienceSheetEntry(),
        ),
        'rsp|turn_around_time': () =>
            FormPdf.buildTurnAroundTimePdf(const TurnAroundTimeEntry()),
        'rsp|ojt_work_immersion': () =>
            FormPdf.buildOjtWorkImmersionEvaluationPdf(
              const OjtWorkImmersionEvaluation(ojtImmersion: 'Intern'),
            ),
        'ld|training_need_analysis': () => FormPdf.buildTrainingNeedAnalysisPdf(
          const TrainingNeedAnalysisEntry(),
        ),
        'ld|action_brainstorming': () =>
            FormPdf.buildActionBrainstormingCoachingPdf(
              const ActionBrainstormingEntry(),
            ),
        'ld|idp': () => FormPdf.buildIdpPdf(const IdpEntry()),
        'ld|learning_application_plan': () =>
            FormPdf.buildLearningApplicationPlanPdf(
              const LearningApplicationPlanEntry(),
            ),
      };

      final catalogKeys = <String>{
        for (final f in FormPrintCatalog.rspForms) 'rsp|${f.key}',
        for (final f in FormPrintCatalog.ldForms) 'ld|${f.key}',
      };
      expect(builders.keys.toSet(), catalogKeys);

      for (final e in builders.entries) {
        final parts = e.key.split('|');
        final prepared = await FormPdf.captureFormPdf(
          buildDocument: e.value,
          printModule: parts[0],
          printFormKey: parts[1],
        );
        expect(prepared.bytes, isNotEmpty, reason: e.key);
        expect(prepared.bindError, isNull, reason: e.key);
      }
    },
  );

  test(
    'non-catalog forms build and clear leftover print background state',
    () async {
      final nonCatalog = <String, Future<pw.Document> Function()>{
        'performance': () => FormPdf.buildPerformanceEvaluationPdf(
          const PerformanceEvaluationEntry(),
        ),
        'comparative': () => FormPdf.buildComparativeAssessmentPdf(
          const ComparativeAssessmentEntry(),
        ),
        'promotion': () => FormPdf.buildPromotionCertificationPdf(
          const PromotionCertificationEntry(),
        ),
        'training_daily': () => FormPdf.buildTrainingDailyReportPdf(
          TrainingDailyReport(
            id: '1',
            employeeId: 'e1',
            employeeName: 'Employee',
            title: 'Day 1',
            description: 'Notes',
            submittedAt: DateTime.utc(2026, 1, 1),
            status: 'submitted',
          ),
        ),
      };

      for (final e in nonCatalog.entries) {
        final doc = await e.value();
        final bytes = await doc.save();
        expect(bytes, isNotEmpty, reason: e.key);
      }

      final source = File('lib/core/utils/form_pdf.dart').readAsStringSync();
      for (final name in [
        'buildPerformanceEvaluationPdf',
        'buildComparativeAssessmentPdf',
        'buildPromotionCertificationPdf',
        'buildTrainingDailyReportPdf',
      ]) {
        final start = source.indexOf('static Future<pw.Document> $name');
        expect(start, greaterThan(0), reason: name);
        final next = source.indexOf('static Future<pw.Document>', start + 1);
        final body = source.substring(
          start,
          next > start ? next : source.length,
        );
        expect(body.contains('_activeCustomBg = null'), isTrue, reason: name);
        expect(body.contains('_lockedPrintBg = null'), isTrue, reason: name);
      }
    },
  );

  test('form_pdf does not load bundled letterhead PDF assets', () {
    final source = File('lib/core/utils/form_pdf.dart').readAsStringSync();
    expect(source.contains("assets/forms/a4_letter.pdf"), isFalse);
    expect(source.contains("assets/forms/long_letter.pdf"), isFalse);
    expect(source.contains('ensureA4LetterTemplateLoaded'), isFalse);
    expect(source.contains('_loadIdpTemplateBackground'), isFalse);
    expect(source.contains('_a4LetterBackground'), isFalse);
    expect(source.contains('_idpMayorLetterBackground'), isFalse);
  });
}
