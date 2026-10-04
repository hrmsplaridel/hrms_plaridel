import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';
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

/// One catalog form the printing center can open.
class FormSystemForm {
  const FormSystemForm({required this.module, required this.item});

  final String module;
  final FormPrintCatalogItem item;

  String get moduleLabel => module == 'ld' ? 'L&D' : 'RSP';

  String get pagesLabel {
    final count = item.pageCount;
    if (count == null) return 'Official form';
    return count == 1 ? '1 page' : '$count pages';
  }
}

/// A saved row the user can preview. [entry] is the existing model instance.
class FormPrintRecordRef {
  const FormPrintRecordRef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    required this.searchText,
    required this.entry,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime? updatedAt;
  final String searchText;
  final Object entry;
}

/// Adapts existing RSP and L&D repositories and PDF builders.
class FormPrintCenter {
  FormPrintCenter._();

  static List<FormSystemForm> get systemForms => [
    for (final item in FormPrintCatalog.rspForms)
      FormSystemForm(module: 'rsp', item: item),
    for (final item in FormPrintCatalog.ldForms)
      FormSystemForm(module: 'ld', item: item),
  ];

  static PdfPageFormat printFormat(FormSystemForm form) {
    switch ('${form.module}:${form.item.key}') {
      case 'rsp:bi':
        return FormPdf.biPrintPageFormat;
      case 'rsp:applicants_profile':
        return FormPdf.pageLongLandscape;
      case 'rsp:selection_lineup':
      case 'rsp:computation_of_points':
        return FormPdf.pageLetterLandscape;
      case 'rsp:turn_around_time':
        return FormPdf.pageLetterLandscape;
      case 'rsp:ojt_work_immersion':
        return FormPdf.pageLetter;
      case 'rsp:work_experience':
        return FormPdf.pageLetterLandscape;
      case 'ld:idp':
        return FormPdf.idpPrintPageFormat;
      case 'ld:training_need_analysis':
      case 'ld:action_brainstorming':
      case 'ld:learning_application_plan':
        return FormPdf.pageLetterLandscape;
      default:
        return FormPdf.pageLetter;
    }
  }

  static String filename(FormSystemForm form) {
    switch (form.item.key) {
      case 'bi':
        return 'BI_Form.pdf';
      case 'applicants_profile':
        return 'Applicants_Profile.pdf';
      case 'selection_lineup':
        return 'Selection_Lineup.pdf';
      case 'computation_of_points':
        return 'Computation_of_Points.pdf';
      case 'work_experience':
        return 'Work_Experience_Sheet.pdf';
      case 'turn_around_time':
        return 'Turn_Around_Time.pdf';
      case 'ojt_work_immersion':
        return 'OJT_Work_Immersion_Evaluation.pdf';
      case 'training_need_analysis':
        return 'Training_Need_Analysis.pdf';
      case 'action_brainstorming':
        return 'Action_Brainstorming_Coaching.pdf';
      case 'idp':
        return 'Individual_Development_Plan.pdf';
      case 'learning_application_plan':
        return 'Learning_Application_Plan.pdf';
      default:
        return 'form.pdf';
    }
  }

  static Future<List<FormPrintRecordRef>> listRecords(
    FormSystemForm form,
  ) async {
    switch ('${form.module}:${form.item.key}') {
      case 'rsp:bi':
        final rows = await BiFormRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.applicantName,
              subtitle: _join([e.positionAppliedFor, e.applicantPosition]),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.respondentName,
              entry: e,
            ),
        ];
      case 'rsp:applicants_profile':
        final rows = await ApplicantsProfileRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.positionAppliedFor,
              subtitle: _first(e.applicants.map((a) => a.name)),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.dateOfPosting,
              entry: e,
            ),
        ];
      case 'rsp:selection_lineup':
        final rows = await SelectionLineupRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.vacantPosition,
              subtitle: _first(e.applicants.map((a) => a.name)),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.date,
              entry: e,
            ),
        ];
      case 'rsp:computation_of_points':
        final rows = await ComputationOfPointsRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.position,
              subtitle: _first(e.candidates.map((c) => c.name)),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.office,
              entry: e,
            ),
        ];
      case 'rsp:work_experience':
        final rows = await WorkExperienceSheetRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.applicantName,
              subtitle: e.positionAppliedFor,
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.department,
              entry: e,
            ),
        ];
      case 'rsp:turn_around_time':
        final rows = await TurnAroundTimeRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.position,
              subtitle: _first(e.applicants.map((a) => a.name)),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.office,
              entry: e,
            ),
        ];
      case 'rsp:ojt_work_immersion':
        final rows = await OjtWorkImmersionEvaluationRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.ojtImmersion,
              subtitle: e.school,
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.interviewer,
              entry: e,
            ),
        ];
      case 'ld:training_need_analysis':
        final rows = await TrainingNeedAnalysisRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.department,
              subtitle: _first(e.rows.map((r) => r.namePosition)),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.cyYear,
              entry: e,
            ),
        ];
      case 'ld:action_brainstorming':
        final rows = await ActionBrainstormingRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.department,
              subtitle: _first(e.rows.map((r) => r.name)),
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.date,
              entry: e,
            ),
        ];
      case 'ld:idp':
        final rows = await IdpRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: e.name,
              subtitle: e.position,
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.department,
              entry: e,
            ),
        ];
      case 'ld:learning_application_plan':
        final rows = await LearningApplicationPlanRepo.instance.list();
        return [
          for (final e in rows)
            _ref(
              id: e.id,
              title: _join([e.title, e.subject]),
              subtitle: e.reportedBy,
              updatedAt: e.updatedAt ?? e.createdAt,
              extra: e.date,
              entry: e,
            ),
        ];
      default:
        return const [];
    }
  }

  static Future<pw.Document> buildDocument(
    BuildContext context,
    FormSystemForm form,
    FormPrintRecordRef record,
  ) async {
    switch ('${form.module}:${form.item.key}') {
      case 'rsp:bi':
        return FormPdf.buildBiFormPdf(record.entry as BiFormEntry);
      case 'rsp:applicants_profile':
        final entry = record.entry as ApplicantsProfileEntry;
        return FormPdf.buildApplicantsProfilePdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'rsp',
            table: ApplicantsProfileEntry.tableName,
            id: entry.id,
          ),
        );
      case 'rsp:selection_lineup':
        final entry = record.entry as SelectionLineupEntry;
        return FormPdf.buildSelectionLineupPdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'rsp',
            table: SelectionLineupEntry.tableName,
            id: entry.id,
          ),
        );
      case 'rsp:computation_of_points':
        final entry = record.entry as ComputationOfPointsEntry;
        return FormPdf.buildComputationOfPointsPdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'rsp',
            table: ComputationOfPointsEntry.tableName,
            id: entry.id,
          ),
        );
      case 'rsp:work_experience':
        final entry = record.entry as WorkExperienceSheetEntry;
        return FormPdf.buildWorkExperienceSheetPdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'rsp',
            table: WorkExperienceSheetEntry.tableName,
            id: entry.id,
          ),
        );
      case 'rsp:turn_around_time':
        final entry = record.entry as TurnAroundTimeEntry;
        return FormPdf.buildTurnAroundTimePdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'rsp',
            table: TurnAroundTimeEntry.tableName,
            id: entry.id,
          ),
        );
      case 'rsp:ojt_work_immersion':
        return FormPdf.buildOjtWorkImmersionEvaluationPdf(
          record.entry as OjtWorkImmersionEvaluation,
        );
      case 'ld:training_need_analysis':
        return FormPdf.buildTrainingNeedAnalysisPdf(
          record.entry as TrainingNeedAnalysisEntry,
        );
      case 'ld:action_brainstorming':
        final entry = record.entry as ActionBrainstormingEntry;
        return FormPdf.buildActionBrainstormingCoachingPdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'ld',
            table: ActionBrainstormingEntry.tableName,
            id: entry.id,
          ),
        );
      case 'ld:idp':
        final entry = record.entry as IdpEntry;
        return FormPdf.buildIdpPdf(
          entry,
          signatures: await _signatures(
            context,
            module: 'ld',
            table: IdpEntry.tableName,
            id: entry.id,
          ),
        );
      case 'ld:learning_application_plan':
        return FormPdf.buildLearningApplicationPlanPdf(
          record.entry as LearningApplicationPlanEntry,
        );
      default:
        throw StateError('Unknown form');
    }
  }

  static Future<DocuTrackerSourceSignatureBundle?> _signatures(
    BuildContext context, {
    required String module,
    required String table,
    required String? id,
  }) async {
    if (id == null || id.isEmpty) return null;
    final provider = context.read<DocuTrackerProvider>();
    final bundle = await provider.loadSourceSignatures(
      sourceModule: module,
      sourceTable: table,
      sourceRecordId: id,
    );
    if (bundle == null) {
      throw StateError(
        provider.sourceSignatureError ??
            'The form signatures could not be loaded.',
      );
    }
    return bundle;
  }

  static FormPrintRecordRef _ref({
    required String? id,
    required String? title,
    required String? subtitle,
    required DateTime? updatedAt,
    required String? extra,
    required Object entry,
  }) {
    final cleanTitle = _text(title);
    final cleanSubtitle = _text(subtitle);
    final recordId = id?.trim() ?? '';
    return FormPrintRecordRef(
      id: recordId,
      title: cleanTitle.isEmpty ? 'Saved record' : cleanTitle,
      subtitle: cleanSubtitle,
      updatedAt: updatedAt,
      searchText: [
        cleanTitle,
        cleanSubtitle,
        recordId,
        _text(extra),
      ].join(' ').toLowerCase(),
      entry: entry,
    );
  }

  static String _first(Iterable<String?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _join(List<String?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(String? value) => value?.trim() ?? '';
}

String formPrintUpdatedLabel(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Updated ${months[local.month - 1]} ${local.day}, ${local.year}';
}
