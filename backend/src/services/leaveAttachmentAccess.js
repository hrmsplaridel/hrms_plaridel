const DEPARTMENT_HEAD_HISTORY_ACTIONS = new Set([
  'department_head_approved',
  'department_head_rejected',
  'department_head_returned',
]);

const ACCESS_OUTCOMES = new Set([
  'allowed',
  'denied',
  'missing_attachment',
  'missing_file',
]);

let _ensurePromise = null;

function sameUser(left, right) {
  const a = String(left || '').trim();
  const b = String(right || '').trim();
  return a.length > 0 && a === b;
}

function resolveLeaveAttachmentAccess({
  role,
  userId,
  ownerUserId,
  requestStatus,
  assignedDepartmentHeadId,
  historicalDepartmentHeadAction,
}) {
  const normalizedRole = String(role || '').trim().toLowerCase();
  if (normalizedRole === 'admin' || normalizedRole === 'hr') {
    return { allowed: true, reason: 'hr_or_admin' };
  }
  if (sameUser(userId, ownerUserId)) {
    return { allowed: true, reason: 'request_owner' };
  }
  if (
    requestStatus === 'pending_department_head' &&
    sameUser(userId, assignedDepartmentHeadId)
  ) {
    return { allowed: true, reason: 'assigned_department_head' };
  }
  if (DEPARTMENT_HEAD_HISTORY_ACTIONS.has(historicalDepartmentHeadAction)) {
    return { allowed: true, reason: 'historical_department_head_reviewer' };
  }
  return { allowed: false, reason: 'not_authorized' };
}

async function ensureLeaveAttachmentAccessLogTable(db) {
  await db.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await db.query(`
    CREATE TABLE IF NOT EXISTS leave_attachment_access_logs (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      leave_request_id UUID REFERENCES leave_requests(id) ON DELETE SET NULL,
      attachment_name TEXT,
      accessed_by UUID REFERENCES users(id) ON DELETE SET NULL,
      actor_role TEXT,
      access_reason TEXT NOT NULL,
      access_outcome TEXT NOT NULL
        CHECK (access_outcome IN ('allowed', 'denied', 'missing_attachment', 'missing_file')),
      ip_address TEXT,
      user_agent TEXT,
      accessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_leave_attachment_access_request_time
      ON leave_attachment_access_logs(leave_request_id, accessed_at DESC);
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_leave_attachment_access_actor_time
      ON leave_attachment_access_logs(accessed_by, accessed_at DESC);
  `);
}

function initLeaveAttachmentAccessLog(dbPool) {
  if (_ensurePromise) return _ensurePromise;
  _ensurePromise = ensureLeaveAttachmentAccessLogTable(dbPool).catch((err) => {
    console.error('[leaveAttachmentAccess] ensure table failed', err);
    throw err;
  });
  return _ensurePromise;
}

async function recordLeaveAttachmentAccess(
  dbOrClient,
  {
    leaveRequestId,
    attachmentName = null,
    accessedBy,
    actorRole = null,
    accessReason,
    accessOutcome,
    ipAddress = null,
    userAgent = null,
  }
) {
  if (_ensurePromise) await _ensurePromise;
  if (!ACCESS_OUTCOMES.has(accessOutcome)) {
    throw new Error(`Invalid leave attachment access outcome: ${accessOutcome}`);
  }
  return dbOrClient.query(
    `INSERT INTO leave_attachment_access_logs (
       leave_request_id,
       attachment_name,
       accessed_by,
       actor_role,
       access_reason,
       access_outcome,
       ip_address,
       user_agent,
       accessed_at
     )
     VALUES ($1::uuid, $2::text, $3::uuid, $4::text, $5::text, $6::text, $7::text, $8::text, now())`,
    [
      leaveRequestId,
      attachmentName,
      accessedBy,
      actorRole ? String(actorRole).slice(0, 100) : null,
      accessReason,
      accessOutcome,
      ipAddress ? String(ipAddress).slice(0, 255) : null,
      userAgent ? String(userAgent).slice(0, 1000) : null,
    ]
  );
}

module.exports = {
  ACCESS_OUTCOMES,
  DEPARTMENT_HEAD_HISTORY_ACTIONS,
  initLeaveAttachmentAccessLog,
  recordLeaveAttachmentAccess,
  resolveLeaveAttachmentAccess,
};
