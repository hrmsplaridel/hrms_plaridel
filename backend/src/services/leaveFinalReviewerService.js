const {requestFinalReviewers,chooseLeaveRoute}=require('./leaveRouting');
const {locatorFinalReviewers}=require('./locatorRouting');
const {resolveActiveMayor}=require('./officialSignatoryService');
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
    `SELECT u.id, u.full_name AS name, u.role,
            COALESCE(access.leave_allowed, false) AS leave_allowed,
            COALESCE(access.locator_allowed, false) AS locator_allowed,
            designation.position_title_snapshot AS position_title,
            designation.id AS designation_id, designation.effective_from::text AS effective_from,
            designation.effective_to::text AS effective_to
     FROM primary_reviewer_designations designation
     JOIN users u ON u.id = designation.employee_id
     LEFT JOIN dtr_admin_access access ON access.admin_user_id = u.id
     WHERE designation.scope_key = 'final_hr' AND designation.is_active = true
       AND designation.effective_from <= $1::date
       AND (designation.effective_to IS NULL OR designation.effective_to >= $1::date)
       AND u.is_active = true AND u.role IN ('admin', 'hr')
     LIMIT 1`,
    [date]
  );
  const backups = await db.query(
    `SELECT u.id, u.full_name AS name, u.role,
            COALESCE(access.leave_allowed, false) AS leave_allowed,
            COALESCE(access.locator_allowed, false) AS locator_allowed
     FROM leave_final_reviewer_backups b
     JOIN users u ON u.id = b.employee_id
     LEFT JOIN dtr_admin_access access ON access.admin_user_id = u.id
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
  if (requestId) {
    const engine=require('./approvalWorkflows');
    const snapshot=await engine.loadRequestWorkflow(db,requestType,requestId);
    if (snapshot) return engine.resolveWorkflowReviewers(db,requestType,{id:requestId,employee_id:applicantId,workflow_snapshot:snapshot});
  }
  const departmentApprover = await loadDepartmentApprover(db, requestType, requestId);
  const reviewers = requestType === 'leave' ? await requestFinalReviewers(db, requestId, () => resolveFinalLeaveReviewers(db)) : await locatorFinalReviewers(db,requestId,()=>resolveFinalLeaveReviewers(db));
  return reviewers.filter(r => String(r.id) !== String(applicantId) &&
    String(r.id) !== String(departmentApprover));
}

async function assertFinalLeaveReviewer(db, applicantId, actorId, requestType = 'leave', requestId = null) {
  if (String(applicantId) === String(actorId)) {
    throw reviewError(`You cannot review your own ${requestType} request`, 403);
  }
  if(requestId && await require('./approvalWorkflows').loadRequestWorkflow(db,requestType,requestId)) {
    const eligible=await resolveEligibleFinalReviewers(db,applicantId,requestType,requestId);
    if(!eligible.some(r=>String(r.id)===String(actorId))) throw reviewError('Only a different eligible reviewer for the current workflow step can decide this request.',403);
    return;
  }
  const departmentApprover = await loadDepartmentApprover(db, requestType, requestId);
  if (departmentApprover && String(departmentApprover) === String(actorId)) {
    throw reviewError('A different reviewer must perform final HR review after your department approval.', 403);
  }
  const reviewers = requestType === 'leave' ? await requestFinalReviewers(db, requestId, () => resolveFinalLeaveReviewers(db)) : await locatorFinalReviewers(db,requestId,()=>resolveFinalLeaveReviewers(db));
  if (!reviewers.length) {
    throw reviewError(`No final ${requestType} reviewer is configured or available`, 409);
  }
  if (!reviewers.some((reviewer) => String(reviewer.id) === String(actorId))) {
    throw reviewError(`Only an assigned final ${requestType} reviewer can decide this request`, 403);
  }
}

async function assertLeaveSubmissionReviewer(db, applicantId, requestType = 'leave', rule = null, reviewSnapshot = null) {
  if(rule?.approval_workflow_id) {
    await require('./approvalWorkflows').prepareWorkflow(db,requestType,rule,applicantId,reviewSnapshot);
    return;
  }
  if(requestType==='leave' && rule?.approval_route==='mayor') {
    const profile=(await db.query('SELECT employment_type FROM users WHERE id=$1::uuid',[applicantId])).rows[0];
    if(chooseLeaveRoute(rule,profile?.employment_type)==='mayor') {
      const mayor=await resolveActiveMayor(db,todayInHrmsTimezone());
      if(!mayor || String(mayor.employee_id)===String(applicantId))throw reviewError('No eligible active Mayor is configured for this request. Contact HR before submitting.',409);
      return;
    }
  }
  const reviewers = (await resolveFinalLeaveReviewers(db)).filter(reviewer =>
    canUseFinalReviewModule(reviewer, requestType));
  if (!reviewers.some((reviewer) => String(reviewer.id) !== String(applicantId))) {
    throw reviewError(`No eligible final ${requestType} reviewer is configured or available for this request. Contact HR before submitting.`, 409);
  }
  if (reviewSnapshot?.departmentHeadUserId) {
    const departmentIds = new Set([
      reviewSnapshot.departmentHeadUserId,
      ...(reviewSnapshot.reviewerUserIds || []),
      ...(reviewSnapshot.reviewers || []).map(reviewer => reviewer.reviewerId),
    ].filter(id => id && String(id) !== String(applicantId)).map(String));
    const hasDistinctPair = [...departmentIds].some(departmentId =>
      reviewers.some(reviewer => String(reviewer.id) !== String(applicantId) &&
        String(reviewer.id) !== departmentId));
    if (!hasDistinctPair) {
      throw reviewError(`A different final HR reviewer is required after department approval for this ${requestType} request. Contact HR to configure another department or final reviewer before submitting.`, 409);
    }
  }
}

async function assertDepartmentApprovalFinalReviewer(db, applicantId, actorId, requestType, requestId) {
  const reviewers = await resolveEligibleFinalReviewers(db, applicantId, requestType, requestId);
  if (!reviewers.some(reviewer => String(reviewer.id) !== String(actorId) &&
      canUseFinalReviewModule(reviewer, requestType))) {
    throw reviewError('No different final HR reviewer is available after your department approval. Contact HR to assign another final reviewer or have another assigned department reviewer endorse this request.', 409);
  }
}

function canUseFinalReviewModule(reviewer, requestType) {
  return reviewer.role !== 'admin' || reviewer[`${requestType}_allowed`] === true;
}

module.exports = {
  resolveEligibleFinalReviewers,
  assertFinalLeaveReviewer,
  assertLeaveSubmissionReviewer,
  assertDepartmentApprovalFinalReviewer,
  resolveFinalLeaveReviewerConfiguration,
  resolveFinalLeaveReviewers,
};
