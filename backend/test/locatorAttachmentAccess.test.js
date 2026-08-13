const test = require('node:test');
const assert = require('node:assert/strict');

const {
  recordLocatorAttachmentAccess,
  resolveLocatorAttachmentAccess,
} = require('../src/services/locatorAttachmentAccess');

const base = {
  role: 'employee',
  userId: 'reviewer-1',
  ownerUserId: 'employee-1',
  requestStatus: 'pending_department_head',
  assignedDepartmentHeadId: null,
  reviewingDepartmentHeadId: null,
};

test('owner and HR/admin can access a locator attachment', () => {
  assert.deepEqual(
    resolveLocatorAttachmentAccess({ ...base, userId: 'employee-1' }),
    { allowed: true, reason: 'request_owner' }
  );
  assert.equal(resolveLocatorAttachmentAccess({ ...base, role: 'hr' }).allowed, true);
  assert.equal(resolveLocatorAttachmentAccess({ ...base, role: 'admin' }).allowed, true);
});

test('only the assigned department head can access a pending locator attachment', () => {
  assert.deepEqual(
    resolveLocatorAttachmentAccess({
      ...base,
      assignedDepartmentHeadId: 'reviewer-1',
    }),
    { allowed: true, reason: 'assigned_department_head' }
  );
  assert.equal(
    resolveLocatorAttachmentAccess({
      ...base,
      userId: 'other-head',
      assignedDepartmentHeadId: 'reviewer-1',
    }).allowed,
    false
  );
});

test('assignment access ends after review but the recorded reviewer keeps access', () => {
  assert.equal(
    resolveLocatorAttachmentAccess({
      ...base,
      requestStatus: 'pending_hr',
      assignedDepartmentHeadId: 'reviewer-1',
    }).allowed,
    false
  );
  assert.deepEqual(
    resolveLocatorAttachmentAccess({
      ...base,
      requestStatus: 'pending_hr',
      reviewingDepartmentHeadId: 'reviewer-1',
    }),
    { allowed: true, reason: 'recorded_department_head_reviewer' }
  );
});

test('unrelated users cannot access a locator attachment', () => {
  assert.deepEqual(resolveLocatorAttachmentAccess(base), {
    allowed: false,
    reason: 'not_authorized',
  });
});

test('locator attachment access audit records the decision and request context', async () => {
  const calls = [];
  const db = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rows: [] };
    },
  };
  await recordLocatorAttachmentAccess(db, {
    locatorSlipId: '11111111-1111-1111-1111-111111111111',
    attachmentName: 'support.pdf',
    accessedBy: '22222222-2222-2222-2222-222222222222',
    actorRole: 'employee',
    accessReason: 'assigned_department_head',
    accessOutcome: 'allowed',
    ipAddress: '127.0.0.1',
    userAgent: 'test-agent',
  });

  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /INSERT INTO locator_attachment_access_logs/i);
  assert.deepEqual(calls[0].params, [
    '11111111-1111-1111-1111-111111111111',
    'support.pdf',
    '22222222-2222-2222-2222-222222222222',
    'employee',
    'assigned_department_head',
    'allowed',
    '127.0.0.1',
    'test-agent',
  ]);
});
