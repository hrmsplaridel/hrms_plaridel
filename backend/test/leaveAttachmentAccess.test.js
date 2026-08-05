const test = require('node:test');
const assert = require('node:assert/strict');

const {
  recordLeaveAttachmentAccess,
  resolveLeaveAttachmentAccess,
} = require('../src/services/leaveAttachmentAccess');

const base = {
  role: 'employee',
  userId: 'reviewer-1',
  ownerUserId: 'employee-1',
  requestStatus: 'pending_department_head',
  assignedDepartmentHeadId: null,
  historicalDepartmentHeadAction: null,
};

test('owner and HR/admin can access a leave attachment', () => {
  assert.deepEqual(
    resolveLeaveAttachmentAccess({ ...base, userId: 'employee-1' }),
    { allowed: true, reason: 'request_owner' }
  );
  assert.equal(resolveLeaveAttachmentAccess({ ...base, role: 'hr' }).allowed, true);
  assert.equal(resolveLeaveAttachmentAccess({ ...base, role: 'admin' }).allowed, true);
});

test('only the assigned department head can access a pending attachment', () => {
  assert.deepEqual(
    resolveLeaveAttachmentAccess({
      ...base,
      assignedDepartmentHeadId: 'reviewer-1',
    }),
    { allowed: true, reason: 'assigned_department_head' }
  );
  assert.deepEqual(
    resolveLeaveAttachmentAccess({
      ...base,
      userId: 'other-head',
      assignedDepartmentHeadId: 'reviewer-1',
    }),
    { allowed: false, reason: 'not_authorized' }
  );
});

test('assignment access ends after department-head review, but actor history remains valid', () => {
  assert.equal(
    resolveLeaveAttachmentAccess({
      ...base,
      requestStatus: 'pending_hr',
      assignedDepartmentHeadId: 'reviewer-1',
    }).allowed,
    false
  );
  assert.deepEqual(
    resolveLeaveAttachmentAccess({
      ...base,
      requestStatus: 'pending_hr',
      historicalDepartmentHeadAction: 'department_head_approved',
    }),
    { allowed: true, reason: 'historical_department_head_reviewer' }
  );
});

test('unrelated history actions do not grant attachment access', () => {
  assert.equal(
    resolveLeaveAttachmentAccess({
      ...base,
      requestStatus: 'approved',
      historicalDepartmentHeadAction: 'submitted',
    }).allowed,
    false
  );
});

test('attachment access audit writes the decision and request context', async () => {
  const calls = [];
  const db = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rows: [] };
    },
  };
  await recordLeaveAttachmentAccess(db, {
    leaveRequestId: '11111111-1111-1111-1111-111111111111',
    attachmentName: 'medical.pdf',
    accessedBy: '22222222-2222-2222-2222-222222222222',
    actorRole: 'employee',
    accessReason: 'assigned_department_head',
    accessOutcome: 'allowed',
    ipAddress: '127.0.0.1',
    userAgent: 'test-agent',
  });

  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /INSERT INTO leave_attachment_access_logs/i);
  assert.deepEqual(calls[0].params, [
    '11111111-1111-1111-1111-111111111111',
    'medical.pdf',
    '22222222-2222-2222-2222-222222222222',
    'employee',
    'assigned_department_head',
    'allowed',
    '127.0.0.1',
    'test-agent',
  ]);
});
