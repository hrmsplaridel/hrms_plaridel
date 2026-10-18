'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const engine = require('../src/services/approvalWorkflows');
const row = { id: 'request', employee_id: 'applicant', status: 'approved', approved_at: '2026-10-18T02:00:00Z', reviewed_at: '2026-10-10T01:00:00Z',
  workflow_snapshot: { name: 'Complete', current_step: 3, steps: [
    { label: 'Dept', assignee_source: 'submitter_department_reviewers' },
    { label: 'HR', assignee_source: 'final_hr_reviewers' },
    { label: 'Mayor', assignee_source: 'active_mayor' },
  ], decisions: [{ step: 2, actor_id: 'mayor', action: 'approve' }] } };

test('approved shared inbox records expose final approval time and request-specific revoke access', async () => {
  const restore = withMockedModule('../src/services/approvalWorkflows', { ...engine,
    resolveWorkflowReviewers: async () => [{ id: 'mayor' }], isCurrentMayor: async () => true,
  });
  clearModule('../src/services/sharedWorkflowInbox');
  try {
    const db = { query: async sql => ({ rows: sql.includes('FROM leave_requests r') ? [row] : [] }) };
    const result = await require('../src/services/sharedWorkflowInbox').listInbox(db, { id: 'mayor', role: 'mayor' }, { includeHistory: true });
    assert.equal(result[0].request_data.approved_at, row.approved_at);
    assert.equal(result[0].request_data.can_revoke_approval, true);
  } finally { clearModule('../src/services/sharedWorkflowInbox'); restore(); }
});

test('shared revoke capability follows final assignment, global role and administrator access', async () => {
  const restores = [
    withMockedModule('../src/services/approvalWorkflows', { ...engine,
      resolveWorkflowReviewers: async () => [{ id: 'mayor' }, { id: 'final-hr' }, { id: 'admin' }, { id: 'employee-final' }],
      isCurrentMayor: async (_, user) => user.id === 'mayor',
    }),
    withMockedModule('../src/middleware/dtrAccess', { loadDtrAccess: async id => ({ leave_allowed: id === 'admin' }) }),
  ];
  const target = '../src/services/leaveRevocationAccess';
  try {
    const { canRevokeSharedLeave } = require(target);
    for (const [id, role, allowed] of [
      ['mayor', 'mayor', true], ['former-mayor', 'mayor', false], ['final-hr', 'hr', true], ['admin', 'admin', true],
      ['disabled-admin', 'admin', false], ['department-head', 'hr', false], ['unrelated-backup', 'hr', false],
      ['employee-final', 'employee', false], ['applicant', 'hr', false],
    ]) assert.equal(await canRevokeSharedLeave({}, row, { id, role }), allowed, id);
    assert.equal(await canRevokeSharedLeave({}, { ...row, status: 'pending_mayor' }, { id: 'mayor', role: 'mayor' }), false);
  } finally { clearModule(target); restores.reverse().forEach(r => r()); }
});

for (const action of ['revoke', 'approve', 'return', 'reject']) {
  test(`Mayor route guard on completed workflow: ${action}`, async () => {
    const restores = [
      withMockedModule('../src/config/db', { pool: { query: async () => ({ rows: [{ workflow_snapshot: row.workflow_snapshot }] }) } }),
      withMockedModule('../src/services/officialSignatoryService', { resolveActiveMayor: async () => ({ employee_id: 'mayor' }) }),
    ];
    clearModule('../src/services/leaveRouting');
    try {
      let allowed = false;
      const res = { code: 200, status(code) { this.code = code; return this; }, json(data) { this.data = data; } };
      await require('../src/services/leaveRouting').requireLeaveFinalRole({
        method: 'PATCH', path: `/request/${action}`, route: { path: `/:id/${action}` }, params: { id: 'request' }, user: { id: 'mayor', role: 'mayor' },
      }, res, () => { allowed = true; });
      assert.equal(allowed, action === 'revoke');
      assert.equal(res.code, action === 'revoke' ? 200 : 403);
    } finally { clearModule('../src/services/leaveRouting'); restores.reverse().forEach(r => r()); }
  });
}

test('current Mayor assigned as a specific final reviewer may revoke a completed shared workflow', async () => {
  const snapshot = { current_step: 1, steps: [{ assignee_source: 'specific_users', user_ids: ['mayor'] }], decisions: [{ step: 0, actor_id: 'mayor', action: 'approve' }] };
  const restores = [
    withMockedModule('../src/config/db', { pool: { query: async sql => ({ rows: sql.startsWith('SELECT workflow_snapshot') ? [{ workflow_snapshot: snapshot }] : [{ id: 'mayor', role: 'mayor' }] }) } }),
    withMockedModule('../src/services/officialSignatoryService', { resolveActiveMayor: async () => ({ employee_id: 'mayor' }) }),
    withMockedModule('../src/services/docutrackerWorkflowService', { resolveStepAssignees: async () => ['mayor'] }),
  ];
  clearModule('../src/services/leaveRouting');
  try {
    let allowed = false;
    const res = { status() { return this; }, json() {} };
    await require('../src/services/leaveRouting').requireLeaveFinalRole({
      method: 'PATCH', path: '/request/revoke', route: { path: '/:id/revoke' }, params: { id: 'request' }, user: { id: 'mayor', role: 'mayor' },
    }, res, () => { allowed = true; });
    assert.equal(allowed, true);
  } finally { clearModule('../src/services/leaveRouting'); restores.reverse().forEach(r => r()); }
});
