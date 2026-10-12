/**
 * Rules for the Turn-Around Time and CSC confirmation that must finish
 * before the existing Final Requirements flow. CSC is recorded by HR.
 * There is no CSC account or external integration.
 */

const link = require('./rspPreDeliberationPolicy');

function text(value) {
  return String(value || '').trim();
}

function shouldEnableStep5Gate(row, recordingPass) {
  if (!row || recordingPass !== true) return false;
  if (row.step5_gate_required === true) return false;
  if (row.final_interview_passed === true) return false;
  if (row.final_requirements_approved === true) return false;
  if (row.hired_user_id) return false;
  if (row.hr_account_setup_done === true) return false;
  if (row.orientation_at) return false;
  if (String(row.status || '') === 'registered') return false;
  if (
    text(row.doc_medical_certificate_path) ||
    text(row.doc_drug_test_path) ||
    text(row.doc_nbi_clearance_path)
  ) {
    return false;
  }
  return true;
}

function missingFinalHiringPrerequisites(row) {
  if (!row || row.step5_gate_required !== true) return [];
  const missing = [];
  if (row.tat_status !== 'completed') missing.push('Turn-Around Time not completed');
  if (row.csc_approval_status !== 'approved') missing.push('CSC approval not confirmed');
  return missing;
}

function finalHiringBlocked(row) {
  return missingFinalHiringPrerequisites(row).length > 0;
}

module.exports = {
  shouldEnableStep5Gate,
  missingFinalHiringPrerequisites,
  finalHiringBlocked,
  canonicalApplicationId: link.canonicalApplicationId,
  applicationIdsFromEntry: link.applicationIdsFromEntry,
  rowsWithoutApplicationId: link.rowsWithoutApplicationId,
  uniqueNamePositionMatches: link.uniqueNamePositionMatches,
};
