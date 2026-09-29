'use strict';

const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

function reviewError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = statusCode === 403 ? 'FORBIDDEN' : 'CONFLICT';
  return error;
}

async function resolveFinalLeaveReviewers(db, date = todayInHrmsTimezone()) {
  const primary = await db.query(
    `SELECT u.id, u.full_name AS name
     FROM positions p
     JOIN assignments a ON a.position_id = p.id
     JOIN users u ON u.id = a.employee_id
     WHERE p.is_leave_final_reviewer = true
       AND p.is_active = true
       AND a.is_active = true
       AND a.effective_from <= $1::date
       AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
       AND u.is_active = true
       AND u.role IN ('admin', 'hr')
     ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
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
  return [...primary.rows, ...backups.rows].filter((row) => {
    const id = String(row.id);
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

async function assertFinalLeaveReviewer(db, applicantId, actorId, requestType = 'leave') {
  if (String(applicantId) === String(actorId)) {
    throw reviewError(`You cannot review your own ${requestType} request`, 403);
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

module.exports = { assertFinalLeaveReviewer, assertLeaveSubmissionReviewer, resolveFinalLeaveReviewers };
