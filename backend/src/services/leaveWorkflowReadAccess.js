'use strict';

const workflowEngine = require('./approvalWorkflows');
const {canRead} = require('./sharedWorkflowInbox');

// Request-scoped access for current workflow reviewers and recorded participants.
// This grants no access to other employees' general balances or approval actions.
async function canReadSharedLeaveRequest(db, requestId, user) {
  if (!user?.id) return false;
  const result = await db.query(
    `SELECT id,user_id,employee_id,status,workflow_snapshot FROM leave_requests
     WHERE id=$1::uuid AND discarded_at IS NULL`,
    [requestId]
  );
  const row = result.rows[0];
  return workflowEngine.isShared(row?.workflow_snapshot) &&
    await canRead(db, 'leave', row, user);
}

module.exports = {canReadSharedLeaveRequest};
