/**
 * Rules for the preparation that must finish before deliberation can be scheduled.
 * Pure helpers so the gate can be tested without a database.
 */

const WES_EDITABLE = new Set(['assigned', 'in_progress', 'needs_revision']);
const WES_REVIEWABLE = new Set(['submitted_for_review', 'resubmitted_for_review']);

function text(value) {
  return String(value || '').trim();
}

function shouldEnableStep4Gate(row, nextStatus) {
  if (!row || nextStatus !== 'passed') return false;
  if (row.step4_gate_required === true) return false;
  if (row.final_interview_at) return false;
  if (row.final_interview_passed === true || row.final_interview_passed === false) return false;
  if (row.hired_user_id) return false;
  if (row.status === 'passed' || row.status === 'registered') return false;
  return row.status === 'exam_taken' || row.status === 'document_approved';
}

function missingPrerequisites(row) {
  if (!row || row.step4_gate_required !== true) return [];
  const missing = [];
  if (row.wes_status !== 'approved') missing.push('Work Experience Sheet not approved');
  if (row.applicants_profile_status !== 'completed') {
    missing.push('Applicants Profile not completed');
  }
  if (row.selection_lineup_status !== 'completed') {
    missing.push('Selection Line-Up not completed');
  }
  return missing;
}

function deliberationBlocked(row) {
  return missingPrerequisites(row).length > 0;
}

function applicantCanEditWes(status) {
  return WES_EDITABLE.has(status);
}

function hrCanReviewWes(status) {
  return WES_REVIEWABLE.has(status);
}

function statusAfterWesSubmit(currentStatus) {
  if (currentStatus === 'needs_revision') return 'resubmitted_for_review';
  return 'submitted_for_review';
}

function normalizeLabel(value) {
  return String(value || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

const APPLICATION_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function canonicalApplicationId(value) {
  const text = String(value || '').trim().toLowerCase();
  return APPLICATION_ID_RE.test(text) ? text : null;
}

function applicationIdsFromEntry(entry) {
  const ids = new Set();
  const columnId = canonicalApplicationId(entry && entry.application_id);
  if (columnId) ids.add(columnId);
  const applicants = Array.isArray(entry && entry.applicants) ? entry.applicants : [];
  for (const item of applicants) {
    const id = canonicalApplicationId(item && (item.application_id || item.applicationId));
    if (id) ids.add(id);
  }
  return [...ids];
}

function rowsWithoutApplicationId(applicants) {
  if (!Array.isArray(applicants)) return [];
  return applicants.filter((item) => !canonicalApplicationId(item && (item.application_id || item.applicationId)));
}

function applicationMatchesSharedForm(application, { names, position }) {
  const name = normalizeLabel(application && application.full_name);
  if (!name || !names.includes(name)) return false;
  const formPosition = normalizeLabel(position);
  const applied = normalizeLabel(application && application.position_applied_for);
  if (formPosition && applied && formPosition !== applied) return false;
  return true;
}

function uniqueNamePositionMatches(applications, { name, position }) {
  const label = normalizeLabel(name);
  if (!label) return [];
  return applications.filter((row) => applicationMatchesSharedForm(row, {
    names: [label],
    position,
  }));
}

function validateWes(row) {
  const missing = [];
  if (!text(row.position_applied_for)) missing.push('position applied for');
  if (!text(row.department)) missing.push('department');
  if (!text(row.min_education)) missing.push('education');
  if (!text(row.min_experience)) missing.push('experience');
  if (!text(row.min_training)) missing.push('training');
  // Job vacancies do not post an eligibility standard, so a blank field must not block submit.
  if (!text(row.job_description_last_work)) missing.push('job description of last work');
  if (!text(row.applicant_name)) missing.push('applicant name');
  return missing;
}

module.exports = {
  shouldEnableStep4Gate,
  missingPrerequisites,
  deliberationBlocked,
  applicantCanEditWes,
  hrCanReviewWes,
  statusAfterWesSubmit,
  validateWes,
  normalizeLabel,
  canonicalApplicationId,
  applicationIdsFromEntry,
  rowsWithoutApplicationId,
  applicationMatchesSharedForm,
  uniqueNamePositionMatches,
};
