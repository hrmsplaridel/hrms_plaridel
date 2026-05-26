import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';
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

  static List<Widget> _timestamps(DateTime? created, DateTime? updated) {
    final out = <Widget>[];
    if (created != null) {
      out.addAll(roField('Created', created.toLocal().toString()));
    }
    if (updated != null) {
      out.addAll(roField('Last updated', updated.toLocal().toString()));
    }
    return out;
  }

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
      roFieldsGroup(
        title: 'Applicant & respondent',
        children: [
          ...roField('Applicant name', e.applicantName),
          ...roField('Applicant department', e.applicantDepartment),
          ...roField('Applicant position', e.applicantPosition),
          ...roField('Position applied for', e.positionAppliedFor),
          ...roField('Respondent name', e.respondentName),
          ...roField('Respondent position', e.respondentPosition),
          ...roField('Relationship', e.respondentRelationship),
        ],
      ),
      roFieldsGroup(
        title: 'Competency ratings (1–5)',
        children: List.generate(9, (i) {
          final r = ratings[i];
          final desc = BiFormEntry.competencyDescriptions[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: roFieldCard(
              'Area ${i + 1}: ${r?.toString() ?? '—'}',
              desc,
            ),
          );
        }),
      ),
      ..._timestamps(e.createdAt, e.updatedAt),
    ];
  }

  static List<Widget> performanceEvaluation(PerformanceEvaluationEntry e) {
    return [
      roFieldsGroup(
        title: 'Evaluation summary',
        children: [
          ...roField('Applicant name', e.applicantName),
          ...roField(
            'Functional areas',
            e.functionalAreas.isEmpty ? null : e.functionalAreas.join(', '),
          ),
          ...roField('Other functional area', e.otherFunctionalArea),
          ...roField('Performance (3 years)', e.performance3Years),
          ...roField('Challenges / coping', e.challengesCoping),
          ...roField('Compliance / attendance', e.complianceAttendance),
        ],
      ),
      ..._timestamps(e.createdAt, e.updatedAt),
    ];
  }

  static List<Widget> idp(IdpEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Employee profile',
        children: [
          ...roField('Name', e.name),
          ...roField('Position', e.position),
          ...roField('Category', e.category),
          ...roField('Division', e.division),
          ...roField('Department', e.department),
          ...roField('Education', e.education),
          ...roField('Experience', e.experience),
          ...roField('Training', e.training),
          ...roField('Eligibility', e.eligibility),
        ],
      ),
      roFieldsGroup(
        title: 'Targets & ratings',
        children: [
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
        ],
      ),
      roFieldsGroup(
        title: 'Signatories',
        children: [
          ...roField('Prepared by', e.preparedBy),
          ...roField('Reviewed by', e.reviewedBy),
          ...roField('Noted by', e.notedBy),
          ...roField('Approved by', e.approvedBy),
        ],
      ),
    ];
    if (e.developmentPlanRows.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Development plan rows',
          children: [
            for (var i = 0; i < e.developmentPlanRows.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Row ${i + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppTheme.letterheadNavy,
                  ),
                ),
              ),
              ...roField('Objectives', e.developmentPlanRows[i].objectives),
              ...roField('L&D program', e.developmentPlanRows[i].ldProgram),
              ...roField('Requirements', e.developmentPlanRows[i].requirements),
              ...roField('Time frame', e.developmentPlanRows[i].timeFrame),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> applicantsProfile(ApplicantsProfileEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Posting details',
        children: [
          ...roField('Position applied for', e.positionAppliedFor),
          ...roField('Minimum requirements', e.minimumRequirements),
          ...roField('Date of posting', e.dateOfPosting),
          ...roField('Closing date', e.closingDate),
          ...roField('Prepared by', e.preparedBy),
          ...roField('Checked by', e.checkedBy),
        ],
      ),
    ];
    if (e.applicants.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Applicants',
          children: [
            for (var i = 0; i < e.applicants.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Applicant ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name', e.applicants[i].name),
              ...roField('Course', e.applicants[i].course),
              ...roField('Address', e.applicants[i].address),
              ...roField('Sex', e.applicants[i].sex),
              ...roField('Age', e.applicants[i].age),
              ...roField('Civil status', e.applicants[i].civilStatus),
              ...roField('Remark (disability)', e.applicants[i].remarkDisability),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> comparativeAssessment(ComparativeAssessmentEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Position & minimum requirements',
        children: [
          ...roField('Position to be filled', e.positionToBeFilled),
          ...roField('Min req. — education', e.minReqEducation),
          ...roField('Min req. — experience', e.minReqExperience),
          ...roField('Min req. — eligibility', e.minReqEligibility),
          ...roField('Min req. — training', e.minReqTraining),
        ],
      ),
    ];
    if (e.candidates.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Candidates',
          children: [
            for (var i = 0; i < e.candidates.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Candidate ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name', e.candidates[i].candidateName),
              ...roField(
                'Present position / salary',
                e.candidates[i].presentPositionSalary,
              ),
              ...roField('Education', e.candidates[i].education),
              ...roField('Training (hrs)', e.candidates[i].trainingHrs),
              ...roField('Related experience', e.candidates[i].relatedExperience),
              ...roField('Eligibility', e.candidates[i].eligibility),
              ...roField('Performance rating', e.candidates[i].performanceRating),
              ...roField('Remarks', e.candidates[i].remarks),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> promotionCertification(PromotionCertificationEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Certification',
        children: [
          ...roField('Position for promotion', e.positionForPromotion),
          ...roField(
            'Date (day / month / year)',
            '${roDash(e.dateDay)} / ${roDash(e.dateMonth)} / ${roDash(e.dateYear)}',
          ),
          ...roField('Signatory name', e.signatoryName),
          ...roField('Signatory title', e.signatoryTitle),
        ],
      ),
    ];
    if (e.candidates.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Candidates',
          children: [
            for (var i = 0; i < e.candidates.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Row ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name', e.candidates[i].name),
              ...roField('Column 1', e.candidates[i].col1),
              ...roField('Column 2', e.candidates[i].col2),
              ...roField('Column 3', e.candidates[i].col3),
              ...roField('Column 4', e.candidates[i].col4),
              ...roField('Column 5', e.candidates[i].col5),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> selectionLineup(SelectionLineupEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Line-up details',
        children: [
          ...roField('Date', e.date),
          ...roField('Agency / office', e.nameOfAgencyOffice),
          ...roField('Vacant position', e.vacantPosition),
          ...roField('Item no.', e.itemNo),
          ...roField('Prepared by (name)', e.preparedByName),
          ...roField('Prepared by (title)', e.preparedByTitle),
        ],
      ),
    ];
    if (e.applicants.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Applicants',
          children: [
            for (var i = 0; i < e.applicants.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Applicant ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name', e.applicants[i].name),
              ...roField('Education', e.applicants[i].education),
              ...roField('Experience', e.applicants[i].experience),
              ...roField('Training', e.applicants[i].training),
              ...roField('Eligibility', e.applicants[i].eligibility),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> turnAroundTime(TurnAroundTimeEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Position & timeline',
        children: [
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
        ],
      ),
    ];
    if (e.applicants.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Applicants',
          children: [
            for (var i = 0; i < e.applicants.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Applicant ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name', e.applicants[i].name),
              ...roField(
                'Date initial assessment',
                e.applicants[i].dateInitialAssessment,
              ),
              ...roField('Date contract exam', e.applicants[i].dateContractExam),
              ...roField(
                'Skills / trade exam result',
                e.applicants[i].skillsTradeExamResult,
              ),
              ...roField('Date deliberation', e.applicants[i].dateDeliberation),
              ...roField('Date job offer', e.applicants[i].dateJobOffer),
              ...roField('Acceptance date', e.applicants[i].acceptanceDate),
              ...roField(
                'Date assumption to duty',
                e.applicants[i].dateAssumptionToDuty,
              ),
              ...roField(
                'No. of days to fill up',
                e.applicants[i].noOfDaysToFillUp,
              ),
              ...roField(
                'Overall cost per hire',
                e.applicants[i].overallCostPerHire,
              ),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> trainingNeedAnalysis(TrainingNeedAnalysisEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Header',
        children: [
          ...roField('CY / Year', e.cyYear),
          ...roField('Department', e.department),
        ],
      ),
    ];
    if (e.rows.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Table rows',
          children: [
            for (var i = 0; i < e.rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Row ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name / position', e.rows[i].namePosition),
              ...roField('Goal', e.rows[i].goal),
              ...roField('Behavior', e.rows[i].behavior),
              ...roField('Skills / knowledge', e.rows[i].skillsKnowledge),
              ...roField('Need for training', e.rows[i].needForTraining),
              ...roField(
                'Training recommendations',
                e.rows[i].trainingRecommendations,
              ),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }

  static List<Widget> actionBrainstorming(ActionBrainstormingEntry e) {
    final out = <Widget>[
      roFieldsGroup(
        title: 'Session',
        children: [
          ...roField('Department', e.department),
          ...roField('Date', e.date),
          ...roField('Certified by', e.certifiedBy),
          ...roField('Certification date', e.certificationDate),
        ],
      ),
    ];
    if (e.rows.isNotEmpty) {
      out.add(
        roFieldsGroup(
          title: 'Worksheet rows',
          children: [
            for (var i = 0; i < e.rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Row ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              ...roField('Name', e.rows[i].name),
              ...roField('Stop doing', e.rows[i].stopDoing),
              ...roField('Do less of', e.rows[i].doLessOf),
              ...roField('Keep doing', e.rows[i].keepDoing),
              ...roField('Do more of', e.rows[i].doMoreOf),
              ...roField('Start doing', e.rows[i].startDoing),
              ...roField('Goal', e.rows[i].goal),
            ],
          ],
        ),
      );
    }
    out.addAll(_timestamps(e.createdAt, e.updatedAt));
    return out;
  }
}
