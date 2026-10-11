/**
 * Rules for the HR-issued form that sits between Document Review and Assessment.
 * Pure helpers so the gate can be tested without a database.
 */

const FORM_TYPES = new Set(['bi', 'ojt']);

const FORM_STATUSES = new Set([
  'waiting_for_hr_form',
  'assigned',
  'in_progress',
  'submitted_for_review',
  'needs_revision',
  'resubmitted_for_review',
  'approved',
]);

const APPLICANT_EDITABLE = new Set(['assigned', 'in_progress', 'needs_revision']);
const HR_REVIEWABLE = new Set(['submitted_for_review', 'resubmitted_for_review']);
const REASSIGNABLE = new Set([
  'waiting_for_hr_form',
  'assigned',
  'in_progress',
]);

function assessmentBlocked(row) {
  if (!row || row.step2_gate_required !== true) return false;
  return row.required_form_status !== 'approved';
}

function shouldEnableIssuedFormGate(previousStatus) {
  return previousStatus === 'submitted' || previousStatus === 'document_declined';
}

function statusAfterApplicantSubmit(currentStatus) {
  if (currentStatus === 'needs_revision') return 'resubmitted_for_review';
  return 'submitted_for_review';
}

function isFormType(value) {
  return FORM_TYPES.has(value);
}

function applicantCanEdit(status) {
  return APPLICANT_EDITABLE.has(status);
}

function hrCanReview(status) {
  return HR_REVIEWABLE.has(status);
}

function canReassign(status) {
  return status == null || status === '' || REASSIGNABLE.has(status);
}

function validateBiSubmission(row) {
  const missing = [];
  if (!text(row.applicant_name)) missing.push('applicant name');
  if (!text(row.respondent_name)) missing.push('respondent name');
  for (let i = 1; i <= 9; i += 1) {
    const rating = Number(row[`rating_${i}`]);
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      missing.push(`competency rating ${i}`);
    }
  }
  const areas = Array.isArray(row.functional_areas) ? row.functional_areas : [];
  const hasArea = areas.some((item) => text(item)) || text(row.other_functional_area);
  if (!hasArea) missing.push('at least one functional area');
  const hasPerformance =
    text(row.performance_3_years) ||
    text(row.challenges_coping) ||
    text(row.compliance_attendance);
  if (!hasPerformance) missing.push('performance information');
  if (!text(row.other_relevant_information)) missing.push('other information');
  return missing;
}

function validateOjtApplicant(row) {
  const missing = [];
  if (!text(row.ojt_immersion)) missing.push('OJT / immersion');
  if (!text(row.school)) missing.push('school');
  return missing;
}

function ojtReadyForApproval(row) {
  const scores = [
    row.problem_solving_score,
    row.communication_score,
    row.teamwork_score,
    row.adaptability_score,
  ];
  const scoresOk = scores.every((value) => {
    const n = Number(value);
    return Number.isInteger(n) && n >= 1 && n <= 5;
  });
  return (
    scoresOk &&
    text(row.overall_recommendation) &&
    text(row.interviewer)
  );
}

function text(value) {
  return value != null && String(value).trim() !== '';
}

module.exports = {
  FORM_STATUSES,
  APPLICANT_EDITABLE,
  HR_REVIEWABLE,
  assessmentBlocked,
  shouldEnableIssuedFormGate,
  statusAfterApplicantSubmit,
  isFormType,
  applicantCanEdit,
  hrCanReview,
  canReassign,
  validateBiSubmission,
  validateOjtApplicant,
  ojtReadyForApproval,
};
