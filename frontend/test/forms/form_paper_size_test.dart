import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/forms/data/form_paper_preference.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/learning_development/models/learning_application_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
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
  setUp(() => PrintingPlatform.instance = _NoRasterPrinting());
  tearDown(() => PrintingPlatform.instance = previousPrinting);

  ApplicantsProfileEntry entry() => ApplicantsProfileEntry(
    positionAppliedFor: 'Clerk',
    applicants: [
      for (var i = 0; i < 12; i++)
        ApplicantsProfileApplicant(name: 'Applicant $i', course: 'BSIT'),
    ],
  );

  test('Applicants Profile is rebuilt for the chosen paper size', () async {
    SharedPreferences.setMockInitialValues({});
    final expected = <String, List<double>>{
      'f4_landscape': [330 * 72 / 25.4, 216 * 72 / 25.4],
      'f4': [216 * 72 / 25.4, 330 * 72 / 25.4],
      'legal_landscape': [356 * 72 / 25.4, 216 * 72 / 25.4],
      'a4_landscape': [297 * 72 / 25.4, 210 * 72 / 25.4],
      'letter_landscape': [279 * 72 / 25.4, 216 * 72 / 25.4],
    };
    for (final e in expected.entries) {
      final prepared = await FormPdf.captureFormPdf(
        buildDocument: () => FormPdf.buildApplicantsProfilePdf(entry()),
        format: FormPdf.pageLongLandscape,
        printModule: 'rsp',
        printFormKey: 'applicants_profile',
        paperSizeId: e.key,
      );
      expect(prepared.format.width, closeTo(e.value[0], 1), reason: e.key);
      expect(prepared.format.height, closeTo(e.value[1], 1), reason: e.key);
      expect(prepared.bytes, isNotEmpty);
    }
  });

  test('other forms scale onto Long, Short and A4 without errors', () async {
    SharedPreferences.setMockInitialValues({});
    final builders = <String, Future<pw.Document> Function()>{
      'rsp|selection_lineup': () =>
          FormPdf.buildSelectionLineupPdf(const SelectionLineupEntry()),
      'rsp|computation_of_points': () =>
          FormPdf.buildComputationOfPointsPdf(const ComputationOfPointsEntry()),
      'rsp|work_experience': () =>
          FormPdf.buildWorkExperienceSheetPdf(const WorkExperienceSheetEntry()),
      'rsp|turn_around_time': () =>
          FormPdf.buildTurnAroundTimePdf(const TurnAroundTimeEntry()),
      'ld|training_need_analysis': () => FormPdf.buildTrainingNeedAnalysisPdf(
        const TrainingNeedAnalysisEntry(),
      ),
      'ld|idp': () => FormPdf.buildIdpPdf(const IdpEntry()),
      'ld|learning_application_plan': () =>
          FormPdf.buildLearningApplicationPlanPdf(
            const LearningApplicationPlanEntry(),
          ),
    };
    const sizes = {
      'a4': [595.28, 841.89],
      'letter': [612.0, 792.0],
      'long_13': [612.0, 936.0],
    };
    for (final b in builders.entries) {
      final parts = b.key.split('|');
      for (final s in sizes.entries) {
        final prepared = await FormPdf.captureFormPdf(
          buildDocument: b.value,
          printModule: parts[0],
          printFormKey: parts[1],
          paperSizeId: s.key,
        );
        final w = prepared.format.width < prepared.format.height
            ? prepared.format.width
            : prepared.format.height;
        final h = prepared.format.width < prepared.format.height
            ? prepared.format.height
            : prepared.format.width;
        expect(w, closeTo(s.value[0], 1), reason: '${b.key} ${s.key}');
        expect(h, closeTo(s.value[1], 1), reason: '${b.key} ${s.key}');
      }
    }
  });

  test('OJT evaluation uses F4 portrait and scales other papers', () async {
    SharedPreferences.setMockInitialValues({});
    Future<pw.Document> build() => FormPdf.buildOjtWorkImmersionEvaluationPdf(
      const OjtWorkImmersionEvaluation(ojtImmersion: 'Intern'),
    );
    final expected = <String, List<double>>{
      'f4': [216 * 72 / 25.4, 330 * 72 / 25.4],
      'a4': [210 * 72 / 25.4, 297 * 72 / 25.4],
      'letter': [216 * 72 / 25.4, 279 * 72 / 25.4],
      'legal': [216 * 72 / 25.4, 356 * 72 / 25.4],
    };
    for (final e in expected.entries) {
      final prepared = await FormPdf.captureFormPdf(
        buildDocument: build,
        printModule: 'rsp',
        printFormKey: 'ojt_work_immersion',
        paperSizeId: e.key,
      );
      expect(prepared.format.width, closeTo(e.value[0], 1), reason: e.key);
      expect(prepared.format.height, closeTo(e.value[1], 1), reason: e.key);
      expect(prepared.paperSizeId, e.key);
      final raw = String.fromCharCodes(prepared.bytes);
      expect(
        RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length,
        1,
        reason: e.key,
      );
    }
  });

  test('saved paper preference is used when none is passed', () async {
    SharedPreferences.setMockInitialValues({});
    await FormPaperPreference.save('rsp', 'applicants_profile', 'a4');
    final prepared = await FormPdf.captureFormPdf(
      buildDocument: () => FormPdf.buildApplicantsProfilePdf(entry()),
      format: FormPdf.pageLongLandscape,
      printModule: 'rsp',
      printFormKey: 'applicants_profile',
    );
    expect(prepared.format.width, closeTo(595.28, 1));
    expect(prepared.format.height, closeTo(841.89, 1));
    expect(prepared.paperSizeId, 'a4');
  });
}
