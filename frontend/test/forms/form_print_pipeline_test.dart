import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';
import 'package:hrms_plaridel/features/forms/presentation/admin/form_print_center.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/learning_application_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_need_analysis.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';

class _RecordingPrinting extends PrintingPlatform {
  Uint8List? lastBytes;
  String? lastName;
  PdfPageFormat? lastFormat;
  var layoutCalls = 0;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    layoutCalls++;
    lastName = name;
    lastFormat = format;
    lastBytes = await onLayout(format);
    return lastBytes != null && lastBytes!.isNotEmpty;
  }

  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Future<pw.Document> Function()> _catalogBuilders() => {
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
  'rsp|computation_of_points': () =>
      FormPdf.buildComputationOfPointsPdf(const ComputationOfPointsEntry()),
  'rsp|work_experience': () =>
      FormPdf.buildWorkExperienceSheetPdf(const WorkExperienceSheetEntry()),
  'rsp|turn_around_time': () =>
      FormPdf.buildTurnAroundTimePdf(const TurnAroundTimeEntry()),
  'rsp|ojt_work_immersion': () => FormPdf.buildOjtWorkImmersionEvaluationPdf(
    const OjtWorkImmersionEvaluation(ojtImmersion: 'Intern'),
  ),
  'ld|training_need_analysis': () =>
      FormPdf.buildTrainingNeedAnalysisPdf(const TrainingNeedAnalysisEntry()),
  'ld|action_brainstorming': () => FormPdf.buildActionBrainstormingCoachingPdf(
    const ActionBrainstormingEntry(),
  ),
  'ld|idp': () => FormPdf.buildIdpPdf(const IdpEntry()),
  'ld|learning_application_plan': () => FormPdf.buildLearningApplicationPlanPdf(
    const LearningApplicationPlanEntry(),
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPrinting = PrintingPlatform.instance;
  late _RecordingPrinting printing;

  setUp(() {
    printing = _RecordingPrinting();
    PrintingPlatform.instance = printing;
    SharedPreferences.setMockInitialValues({});
    FormPdf.debugLoadPrintTemplateMeta =
        ({required module, required formKey}) async => null;
  });

  tearDown(() {
    PrintingPlatform.instance = previousPrinting;
    FormPdf.debugLoadPrintTemplateMeta = null;
  });

  test('print pipeline opens layout for every FormPrintCatalog form', () async {
    final builders = _catalogBuilders();
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
      expect(prepared.bytes, isNotEmpty, reason: '${e.key} bytes');

      final opened = await FormPdf.layoutPreparedPdf(
        bytes: prepared.bytes,
        name: '${parts[1]}.pdf',
        format: prepared.format,
        dynamicLayout: false,
        forceCustomPrintPaper: true,
      );
      expect(opened, isTrue, reason: '${e.key} layout');
      expect(printing.lastBytes, isNotEmpty, reason: '${e.key} print bytes');
      expect(printing.lastName, '${parts[1]}.pdf', reason: e.key);
      expect(printing.lastFormat, isNotNull, reason: e.key);
    }
    expect(printing.layoutCalls, catalogKeys.length);
  });

  test(
    'FormPrintCenter exposes filename and format for every catalog form',
    () {
      for (final form in FormPrintCenter.systemForms) {
        final key = '${form.module}|${form.item.key}';
        expect(FormPrintCenter.filename(form), isNot('form.pdf'), reason: key);
        final format = FormPrintCenter.printFormat(form);
        expect(format.width, greaterThan(0), reason: key);
        expect(format.height, greaterThan(0), reason: key);
      }
    },
  );

  test('admin form sections wire Print Form to printModule/printFormKey', () {
    final expected = <String, List<String>>{
      'rsp|bi': [
        'lib/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart',
      ],
      'rsp|applicants_profile': [
        'lib/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart',
      ],
      'rsp|selection_lineup': [
        'lib/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart',
      ],
      'rsp|computation_of_points': [
        'lib/features/recruitment/presentation/admin/sections/computation_of_points_section.dart',
      ],
      'rsp|work_experience': [
        'lib/features/recruitment/presentation/admin/sections/work_experience_sheet_section.dart',
      ],
      'rsp|turn_around_time': [
        'lib/features/recruitment/presentation/admin/sections/turn_around_time_section.dart',
      ],
      'rsp|ojt_work_immersion': [
        'lib/features/recruitment/presentation/admin/sections/ojt_work_immersion_evaluation_section.dart',
      ],
      'ld|training_need_analysis': [
        'lib/features/learning_development/presentation/admin/sections/training_need_analysis_section.dart',
      ],
      'ld|action_brainstorming': [
        'lib/features/learning_development/presentation/admin/sections/action_brainstorming_section.dart',
      ],
      'ld|idp': [
        'lib/features/learning_development/presentation/admin/sections/idp_admin_section.dart',
      ],
      'ld|learning_application_plan': [
        'lib/features/learning_development/presentation/admin/sections/learning_application_plan_section.dart',
      ],
    };

    for (final e in expected.entries) {
      final parts = e.key.split('|');
      final module = parts[0];
      final formKey = parts[1];
      var wired = false;
      for (final path in e.value) {
        final source = File(path).readAsStringSync();
        final hasPrintCall =
            source.contains('FormPdf.printForm(') ||
            source.contains('FormPdf.printIdpPdf(');
        final hasModule = source.contains("printModule: '$module'");
        final hasKey =
            source.contains("printFormKey: '$formKey'") ||
            (formKey == 'idp' && source.contains('printIdpPdf'));
        if (hasPrintCall && hasModule && hasKey) {
          wired = true;
          break;
        }
      }
      expect(wired, isTrue, reason: e.key);
    }
  });
}
