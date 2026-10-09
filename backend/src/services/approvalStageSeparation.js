'use strict';

// A resubmission starts a new review cycle. Earlier endorsements do not grant
// (or remove) authority for that cycle. Locator explicitly clears its reviewer.
function departmentApproverSql(kind, alias) {
  if (kind === 'locator') return `${alias}.dept_head_reviewer_id`;
  return `(SELECT CASE WHEN stage.action = 'department_head_approved' THEN stage.acted_by END
    FROM leave_request_history stage
    WHERE stage.leave_request_id = ${alias}.id
      AND stage.action IN ('submitted', 'department_head_approved',
                           'department_head_rejected', 'department_head_returned')
    ORDER BY stage.acted_at DESC, stage.id DESC LIMIT 1)`;
}

function finalQueueVisibilitySql(kind, alias, actorSql) {
  return `(${alias}.status NOT IN ('pending', 'pending_hr') OR
    ${departmentApproverSql(kind, alias)} IS DISTINCT FROM ${actorSql})`;
}

async function loadDepartmentApprover(db, kind, requestId) {
  if (!requestId) return null;
  const table = kind === 'locator' ? 'locator_slips' : 'leave_requests';
  const result = await db.query(
    `SELECT ${departmentApproverSql(kind, 'request')} AS department_approver_id
     FROM ${table} request WHERE request.id = $1::uuid`, [requestId]);
  return result.rows[0]?.department_approver_id || null;
}

module.exports = { departmentApproverSql, finalQueueVisibilitySql, loadDepartmentApprover };
