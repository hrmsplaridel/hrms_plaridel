import 'package:flutter/material.dart';

import '../data/action_brainstorming_coaching.dart';
import '../data/applicants_profile.dart';
import '../data/bi_form.dart';
import '../data/comparative_assessment.dart';
import '../data/individual_development_plan.dart';
import '../data/performance_evaluation_form.dart';
import '../data/promotion_certification.dart';
import '../data/selection_lineup.dart';
import '../data/training_need_analysis.dart';
import '../data/turn_around_time.dart';
import 'read_only_saved_entry_dialog.dart';

/// Builds scroll sections for “View” on saved RSP / L&D forms.
class RspLdSavedEntryPreview {
  RspLdSavedEntryPreview._();

  static List<Widget> biForm(BiFormEntry e) {
    final ratings = [
      e.rating1,
      e.rating2,
      e.rating3,
      e.rating4,
      e.rating5,
      e.rating6,
      e.rating7,
      e.rating8,
      e.rating9,
    ];
    return [
      ...roField('Applicant name', e.applicantName),
      ...roField('Applicant department', e.applicantDepartment),
      ...roField('Applicant position', e.applicantPosition),
      ...roField('Position applied for', e.positionAppliedFor),
      ...roField('Respondent name', e.respondentName),
      ...roField('Respondent position', e.respondentPosition),
      ...roField('Relationship', e.respondentRelationship),
      roSectionTitle('Competency ratings (1–5)'),
      ...List.generate(9, (i) {
        final r = ratings[i];
        final desc = BiFormEntry.competencyDescriptions[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Area ${i + 1}: ${r?.toString() ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, height: 1.35, color: Colors.black54)),
            ],
          ),
        );
      }),
      if (e.createdAt != null) ...roField('Created', e.createdAt!.toLocal().toString()),
      if (e.updatedAt != null) ...roField('Last updated', e.updatedAt!.toLocal().toString()),
    ];
  }

  static List<Widget> performanceEvaluation(PerformanceEvaluationEntry e) {
    return [
      ...roField('Applicant name', e.applicantName),
      ...roField(
        'Functional areas',
        e.functionalAreas.isEmpty ? null : e.functionalAreas.join(', '),
      ),
      ...roField('Other functional area', e.otherFunctionalArea),
      ...roField('Performance (3 years)', e.performance3Years),
      ...roField('Challenges / coping', e.challengesCoping),
      ...roField('Compliance / attendance', e.complianceAttendance),
      if (e.createdAt != null) ...roField('Created', e.createdAt!.toLocal().toString()),
      if (e.updatedAt != null) ...roField('Last updated', e.updatedAt!.toLocal().toString()),
    ];
  }

  static List<Widget> idp(IdpEntry e) {
    final out = <Widget>[
      ...roField('Name', e.name),
      ...roField('Position', e.position),
      ...roField('Category', e.category),
      ...roField('Division', e.division),
      ...roField('Department', e.department),
      ...roField('Education', e.education),
      ...roField('Experience', e.experience),
      ...roField('Training', e.training),
      ...roField('Eligibility', e.eligibility),
      ...roField('Target position 1', e.targetPosition1),
      ...roField('Target position 2', e.targetPosition2),
      ...roField('Average rating', e.avgRating),
      ...roField('OPCR', e.opcr),
      ...roField('IPCR', e.ipcr),
      ...roField('Performance rating', e.performanceRating),
      ...roField('Competency description', e.competencyDescription),
      ...roField('Competence rating', e.competenceRating),
      ...roField('Succession priority score', e.successionPriorityScore),
      ...roField('Succession priority rating', e.successionPriorityRating),
      ...roField('Prepared by', e.preparedBy),
      ...roField('Reviewed by', e.reviewedBy),
      ...roField('Noted by', e.notedBy),
      ...roField('Approved by', e.approvedBy),
    ];
    if (e.developmentPlanRows.isNotEmpty) {
      out.add(roSectionTitle('Development plan rows'));
      for (var i = 0; i < e.developmentPlanRows.length; i++) {
        final r = e.developmentPlanRows[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Row ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ...roField('Objectives', r.objectives),
                ...roField('L&D program', r.ldProgram),
                ...roField('Requirements', r.requirements),
                ...roField('Time frame', r.timeFrame),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> applicantsProfile(ApplicantsProfileEntry e) {
    final out = <Widget>[
      ...roField('Position applied for', e.positionAppliedFor),
      ...roField('Minimum requirements', e.minimumRequirements),
      ...roField('Date of posting', e.dateOfPosting),
      ...roField('Closing date', e.closingDate),
      ...roField('Prepared by', e.preparedBy),
      ...roField('Checked by', e.checkedBy),
    ];
    if (e.applicants.isNotEmpty) {
      out.add(roSectionTitle('Applicants'));
      for (var i = 0; i < e.applicants.length; i++) {
        final a = e.applicants[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Applicant ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name', a.name),
                ...roField('Course', a.course),
                ...roField('Address', a.address),
                ...roField('Sex', a.sex),
                ...roField('Age', a.age),
                ...roField('Civil status', a.civilStatus),
                ...roField('Remark (disability)', a.remarkDisability),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> comparativeAssessment(ComparativeAssessmentEntry e) {
    final out = <Widget>[
      ...roField('Position to be filled', e.positionToBeFilled),
      ...roField('Min req. — education', e.minReqEducation),
      ...roField('Min req. — experience', e.minReqExperience),
      ...roField('Min req. — eligibility', e.minReqEligibility),
      ...roField('Min req. — training', e.minReqTraining),
    ];
    if (e.candidates.isNotEmpty) {
      out.add(roSectionTitle('Candidates'));
      for (var i = 0; i < e.candidates.length; i++) {
        final c = e.candidates[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Candidate ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name', c.candidateName),
                ...roField('Present position / salary', c.presentPositionSalary),
                ...roField('Education', c.education),
                ...roField('Training (hrs)', c.trainingHrs),
                ...roField('Related experience', c.relatedExperience),
                ...roField('Eligibility', c.eligibility),
                ...roField('Performance rating', c.performanceRating),
                ...roField('Remarks', c.remarks),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> promotionCertification(PromotionCertificationEntry e) {
    final out = <Widget>[
      ...roField('Position for promotion', e.positionForPromotion),
      ...roField('Date (day / month / year)', '${roDash(e.dateDay)} / ${roDash(e.dateMonth)} / ${roDash(e.dateYear)}'),
      ...roField('Signatory name', e.signatoryName),
      ...roField('Signatory title', e.signatoryTitle),
    ];
    if (e.candidates.isNotEmpty) {
      out.add(roSectionTitle('Candidates'));
      for (var i = 0; i < e.candidates.length; i++) {
        final c = e.candidates[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Row ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name', c.name),
                ...roField('Column 1', c.col1),
                ...roField('Column 2', c.col2),
                ...roField('Column 3', c.col3),
                ...roField('Column 4', c.col4),
                ...roField('Column 5', c.col5),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> selectionLineup(SelectionLineupEntry e) {
    final out = <Widget>[
      ...roField('Date', e.date),
      ...roField('Agency / office', e.nameOfAgencyOffice),
      ...roField('Vacant position', e.vacantPosition),
      ...roField('Item no.', e.itemNo),
      ...roField('Prepared by (name)', e.preparedByName),
      ...roField('Prepared by (title)', e.preparedByTitle),
    ];
    if (e.applicants.isNotEmpty) {
      out.add(roSectionTitle('Applicants'));
      for (var i = 0; i < e.applicants.length; i++) {
        final a = e.applicants[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Applicant ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name', a.name),
                ...roField('Education', a.education),
                ...roField('Experience', a.experience),
                ...roField('Training', a.training),
                ...roField('Eligibility', a.eligibility),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> turnAroundTime(TurnAroundTimeEntry e) {
    final out = <Widget>[
      ...roField('Position', e.position),
      ...roField('Office', e.office),
      ...roField('No. of vacant positions', e.noOfVacantPosition),
      ...roField('Date of publication', e.dateOfPublication),
      ...roField('End of search', e.endSearch),
      ...roField('QS', e.qs),
      ...roField('Prepared by (name)', e.preparedByName),
      ...roField('Prepared by (title)', e.preparedByTitle),
      ...roField('Noted by (name)', e.notedByName),
      ...roField('Noted by (title)', e.notedByTitle),
    ];
    if (e.applicants.isNotEmpty) {
      out.add(roSectionTitle('Applicants'));
      for (var i = 0; i < e.applicants.length; i++) {
        final a = e.applicants[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Applicant ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name', a.name),
                ...roField('Date initial assessment', a.dateInitialAssessment),
                ...roField('Date contract exam', a.dateContractExam),
                ...roField('Skills / trade exam result', a.skillsTradeExamResult),
                ...roField('Date deliberation', a.dateDeliberation),
                ...roField('Date job offer', a.dateJobOffer),
                ...roField('Acceptance date', a.acceptanceDate),
                ...roField('Date assumption to duty', a.dateAssumptionToDuty),
                ...roField('No. of days to fill up', a.noOfDaysToFillUp),
                ...roField('Overall cost per hire', a.overallCostPerHire),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> trainingNeedAnalysis(TrainingNeedAnalysisEntry e) {
    final out = <Widget>[
      ...roField('CY / Year', e.cyYear),
      ...roField('Department', e.department),
    ];
    if (e.rows.isNotEmpty) {
      out.add(roSectionTitle('Table rows'));
      for (var i = 0; i < e.rows.length; i++) {
        final r = e.rows[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Row ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name / position', r.namePosition),
                ...roField('Goal', r.goal),
                ...roField('Behavior', r.behavior),
                ...roField('Skills / knowledge', r.skillsKnowledge),
                ...roField('Need for training', r.needForTraining),
                ...roField('Training recommendations', r.trainingRecommendations),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

  static List<Widget> actionBrainstorming(ActionBrainstormingEntry e) {
    final out = <Widget>[
      ...roField('Department', e.department),
      ...roField('Date', e.date),
      ...roField('Certified by', e.certifiedBy),
      ...roField('Certification date', e.certificationDate),
    ];
    if (e.rows.isNotEmpty) {
      out.add(roSectionTitle('Worksheet rows'));
      for (var i = 0; i < e.rows.length; i++) {
        final r = e.rows[i];
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Row ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...roField('Name', r.name),
                ...roField('Stop doing', r.stopDoing),
                ...roField('Do less of', r.doLessOf),
                ...roField('Keep doing', r.keepDoing),
                ...roField('Do more of', r.doMoreOf),
                ...roField('Start doing', r.startDoing),
                ...roField('Goal', r.goal),
              ],
            ),
          ),
        );
      }
    }
    if (e.createdAt != null) out.addAll(roField('Created', e.createdAt!.toLocal().toString()));
    if (e.updatedAt != null) out.addAll(roField('Last updated', e.updatedAt!.toLocal().toString()));
    return out;
  }

}
