'use strict';

// Read-only UI capability. PATCH /:id/revoke still rechecks authority, status
// and the deadline while holding the request lock before changing accounting.
async function canRevokeSharedLeave(db, row, user) {
  const engine = require('./approvalWorkflows');
  if (!engine.isShared(row?.workflow_snapshot) || row.status !== 'approved' ||
      !user?.id || !['admin', 'hr', 'mayor'].includes(user.role) ||
      String(row.employee_id || row.user_id) === String(user.id)) return false;
  if (user.role === 'admin' && !(await require('../middleware/dtrAccess').loadDtrAccess(user.id, db))?.leave_allowed) return false;
  if (user.role === 'mayor' && !await engine.isCurrentMayor(db, user)) return false;
  const reviewers = await engine.resolveWorkflowReviewers(db, 'leave', row);
  return reviewers.some(reviewer => String(reviewer.id) === String(user.id));
}

module.exports = { canRevokeSharedLeave };
