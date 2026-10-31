'use strict';

// Read-only UI capability. PATCH /:id/revoke still rechecks authority, status
// and the deadline while holding the request lock before changing accounting.
async function canRevokeSharedWorkflow(db, kind, row, user) {
  const engine = require('./approvalWorkflows');
  if (!engine.isShared(row?.workflow_snapshot) || row.status !== 'approved' ||
      row.paper_approval_record ||
      !user?.id || !['admin', 'hr', 'mayor', 'employee'].includes(user.role) ||
      String(row.employee_id || row.user_id) === String(user.id)) return false;
  if (user.role === 'admin' && !(await require('../middleware/dtrAccess').loadDtrAccess(user.id, db))?.[`${kind}_allowed`]) return false;
  if (user.role === 'mayor' && !await engine.isCurrentMayor(db, user)) return false;
  const reviewers = await engine.resolveWorkflowReviewers(db, kind, {
    ...row,
    workflow_snapshot: {...row.workflow_snapshot, current_step: row.workflow_snapshot.steps.length},
  });
  return reviewers.some(reviewer => String(reviewer.id) === String(user.id));
}

const canRevokeSharedLeave = (db, row, user) => canRevokeSharedWorkflow(db, 'leave', row, user);
const canRevokeSharedLocator = (db, row, user) => canRevokeSharedWorkflow(db, 'locator', row, user);

async function requireEmployeeWorkflowRevocation(kind, req, res, next) {
  try {
    const db = require('../config/db').pool;
    const engine = require('./approvalWorkflows');
    const row = (await db.query(`SELECT * FROM ${engine.tableFor(kind)} WHERE id=$1::uuid`, [req.params.id])).rows[0];
    if (!await canRevokeSharedWorkflow(db, kind, row, req.user)) {
      return res.status(403).json({error:'Only an eligible final workflow reviewer can revoke this approval.'});
    }
    return next();
  } catch (_) {
    return res.status(503).json({error:'Revocation authority could not be verified.'});
  }
}

module.exports = { canRevokeSharedLeave, canRevokeSharedLocator, requireEmployeeWorkflowRevocation };
