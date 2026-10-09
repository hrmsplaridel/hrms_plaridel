'use strict';

const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { loadDepartmentApprover } = require('./approvalStageSeparation');

function reviewError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = statusCode === 403 ? 'FORBIDDEN' : 'CONFLICT';
  return error;
}

async function resolveFinalLeaveReviewerConfiguration(
  db,
  date = todayInHrmsTimezone()
) {
  const primary = await db.query(
    `SELECT u.id, u.full_name AS name, designation.position_title_snapshot AS position_title,
            designation.id AS designation_id, designation.effective_from::text AS effective_from,
            designation.effective_to::text AS effective_to
     FROM primary_reviewer_designations designation
     JOIN users u ON u.id = designation.employee_id
     WHERE designation.scope_key = 'final_hr' AND designation.is_active = true
       AND designation.effective_from <= $1::date
       AND (designation.effective_to IS NULL OR designation.effective_to >= $1::date)
       AND u.is_active = true AND u.role IN ('admin', 'hr')
     LIMIT 1`,
    [date]
  );
  const backups = await db.query(
    `SELECT u.id, u.full_name AS name
     FROM leave_final_reviewer_backups b
     JOIN users u ON u.id = b.employee_id
     WHERE b.is_active = true
       AND b.effective_from <= $1::date
       AND (b.effective_to IS NULL OR b.effective_to >= $1::date)
       AND u.is_active = true
       AND u.role IN ('admin', 'hr')
     ORDER BY b.backup_rank`,
    [date]
  );
  const seen = new Set();
  const primaryReviewer = primary.rows[0] || null;
  const backupReviewers = backups.rows.filter((row) => {
    const id = String(row.id);
    if (primaryReviewer && id === String(primaryReviewer.id)) return false;
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });
  return {
    primary: primaryReviewer,
    backups: backupReviewers,
    reviewers: [
      ...(primaryReviewer ? [primaryReviewer] : []),
      ...backupReviewers,
    ],
  };
}

async function resolveFinalLeaveReviewers(db, date = todayInHrmsTimezone()) {
  const config = await resolveFinalLeaveReviewerConfiguration(db, date);
  return config.reviewers;
}

async function resolveEligibleFinalReviewers(db, applicantId, requestType, requestId) {
  const departmentApprover = await loadDepartmentApprover(db, requestType, requestId);
  const reviewers = await resolveFinalLeaveReviewers(db);
  return reviewers.filter(r => String(r.id) !== String(applicantId) &&
    String(r.id) !== String(departmentApprover));
}

async function assertFinalLeaveReviewer(db, applicantId, actorId, requestType = 'leave', requestId = null) {
  if (String(applicantId) === String(actorId)) {
    throw reviewError(`You cannot review your own ${requestType} request`, 403);
  }
  const departmentApprover = await loadDepartmentApprover(db, requestType, requestId);
  if (departmentApprover && String(departmentApprover) === String(actorId)) {
    throw reviewError('A different reviewer must perform final HR review after your department approval.', 403);
  }
  const reviewers = await resolveFinalLeaveReviewers(db);
  if (!reviewers.length) {
    throw reviewError(`No final ${requestType} reviewer is configured or available`, 409);
  }
  if (!reviewers.some((reviewer) => String(reviewer.id) === String(actorId))) {
    throw reviewError(`Only an assigned final ${requestType} reviewer can decide this request`, 403);
  }
}

async function assertLeaveSubmissionReviewer(db, applicantId, requestType = 'leave') {
  const reviewers = await resolveFinalLeaveReviewers(db);
  if (!reviewers.some((reviewer) => String(reviewer.id) !== String(applicantId))) {
    throw reviewError(`No eligible final ${requestType} reviewer is configured or available for this request. Contact HR before submitting.`, 409);
  }
}

module.exports = {
  resolveEligibleFinalReviewers,
  assertFinalLeaveReviewer,
  assertLeaveSubmissionReviewer,
  resolveFinalLeaveReviewerConfiguration,
  resolveFinalLeaveReviewers,
};
