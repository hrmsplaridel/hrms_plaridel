'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getLeaveSourceWorkflow,
  leaveStepIndicators,
} = require('../src/services/docutrackerLeaveSourceWorkflowService');

const LEAVE_ID = '11111111-1111-4111-8111-111111111111';
const APPLICANT = '22222222-2222-4222-8222-222222222222';
const DEPT_HEAD = '33333333-3333-4333-8333-333333333333';
const HR = '44444444-4444-4444-8444-444444444444';

function fakeDb({ canView = true, status, history = [], reviewers = [] }) {
  const queries = [];
  return {
    queries,
    async query(sql, params) {
      queries.push({ sql, params });
      if (/^\s*SELECT 1/.test(sql)) {
        return { rowCount: canView ? 1 : 0, rows: canView ? [{}] : [] };
      }
      if (sql.includes('FROM leave_requests l') && sql.includes('assigned_department_head_name')) {
        return {
          rowCount: 1,
          rows: [
            {
              status,
              assigned_department_head_id: DEPT_HEAD,
              assigned_department_head_name: 'Dana Head',
            },
          ],
        };
      }
      if (sql.includes('FROM leave_request_history h')) {
        return { rowCount: history.length, rows: history };
      }
      if (sql.includes('FROM leave_request_department_reviewers')) {
        return { rowCount: reviewers.length, rows: reviewers };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
}

const configuredFinal = async () => ({
  primary: { id: HR, name: 'Helen HR' },
  backups: [],
});

test('department step is current while awaiting department head', () => {
  const result = leaveStepIndicators('pending_department_head', [
    { action: 'submitted', from_status: 'draft', to_status: 'pending_department_head' },
  ]);
  assert.equal(result.department.kind, 'current');
  assert.equal(result.final.kind, 'upcoming');
});

test('department step is not required when submission went straight to HR', () => {
  const result = leaveStepIndicators('approved', [
    { action: 'submitted', from_status: 'draft', to_status: 'pending_hr' },
    { action: 'approved', from_status: 'pending_hr', to_status: 'approved' },
  ]);
  assert.equal(result.department.label, 'NOT REQUIRED');
  assert.equal(result.final.kind, 'approved');
});

test('cancellation marks the stage it was cancelled from', () => {
  const atDept = leaveStepIndicators('cancelled', [
    { action: 'submitted', from_status: 'draft', to_status: 'pending_department_head' },
    { action: 'cancelled', from_status: 'pending_department_head', to_status: 'cancelled' },
  ]);
  assert.equal(atDept.department.kind, 'cancelled');
  assert.equal(atDept.final.kind, 'upcoming');

  const atHr = leaveStepIndicators('cancelled', [
    { action: 'submitted', from_status: 'draft', to_status: 'pending_department_head' },
    { action: 'department_head_approved', from_status: 'pending_department_head', to_status: 'pending_hr' },
    { action: 'cancelled', from_status: 'pending_hr', to_status: 'cancelled' },
  ]);
  assert.equal(atHr.department.kind, 'approved');
  assert.equal(atHr.final.kind, 'cancelled');
});

test('returns null when the user has no relationship to the leave', async () => {
  const db = fakeDb({ canView: false, status: 'pending_hr' });
  const result = await getLeaveSourceWorkflow(db, { id: APPLICANT, role: 'employee' }, LEAVE_ID, {
    finalReviewerResolver: configuredFinal,
  });
  assert.equal(result, null);
  assert.equal(db.queries.length, 1);
});

test('builds steps with recorded reviewers and maps history to DocuTracker shape', async () => {
  const actedAt = new Date('2026-10-01T02:00:00Z');
  const db = fakeDb({
    status: 'cancelled',
    reviewers: [{ id: DEPT_HEAD, name: 'Dana Head', role: 'primary', backup_rank: null }],
    history: [
      { id: '1', action: 'saved_draft', from_status: null, to_status: 'draft', acted_by: APPLICANT, acted_at: actedAt, remarks: null, actor_name: 'Amy Applicant' },
      { id: '2', action: 'signed', from_status: 'draft', to_status: 'draft', acted_by: APPLICANT, acted_at: actedAt, remarks: null, actor_name: 'Amy Applicant' },
      { id: '3', action: 'submitted', from_status: 'draft', to_status: 'pending_department_head', acted_by: APPLICANT, acted_at: actedAt, remarks: null, actor_name: 'Amy Applicant' },
      { id: '4', action: 'cancelled', from_status: 'pending_department_head', to_status: 'cancelled', acted_by: APPLICANT, acted_at: actedAt, remarks: 'No longer needed', actor_name: 'Amy Applicant' },
    ],
  });
  const result = await getLeaveSourceWorkflow(db, { id: APPLICANT, role: 'employee' }, LEAVE_ID, {
    finalReviewerResolver: configuredFinal,
  });

  assert.equal(result.status, 'cancelled');
  assert.deepEqual(result.steps.map((s) => s.label), ['Department Review', 'Final HR Review']);
  assert.equal(result.steps[0].indicator.kind, 'cancelled');
  assert.deepEqual(result.steps[0].reviewers.map((r) => r.name), ['Dana Head']);
  assert.deepEqual(result.steps[1].reviewers.map((r) => r.name), ['Helen HR']);

  assert.equal(result.history.length, 4);
  assert.equal(result.history[0].document_id, `source:dtr:${LEAVE_ID}`);
  assert.equal(result.history[0].to_status, 'draft');
  assert.equal(result.history[1].from_status, null, 'unchanged status is collapsed');
  assert.equal(result.history[2].to_status, 'in_review');
  assert.equal(result.history[3].remarks, 'No longer needed');
  assert.equal(result.history[3].created_at, actedAt.toISOString());
});

test('final step shows the HR actor who decided instead of configured reviewers', async () => {
  let resolverCalled = false;
  const db = fakeDb({
    status: 'approved',
    history: [
      { id: '1', action: 'submitted', from_status: 'draft', to_status: 'pending_hr', acted_by: APPLICANT, acted_at: new Date(), actor_name: 'Amy Applicant' },
      { id: '2', action: 'approved', from_status: 'pending_hr', to_status: 'approved', acted_by: HR, acted_at: new Date(), actor_name: 'Hank Decider' },
    ],
  });
  const result = await getLeaveSourceWorkflow(db, { id: HR, role: 'hr' }, LEAVE_ID, {
    finalReviewerResolver: async () => {
      resolverCalled = true;
      return { primary: null, backups: [] };
    },
  });
  assert.equal(resolverCalled, false);
  assert.deepEqual(result.steps[1].reviewers.map((r) => r.name), ['Hank Decider']);
  assert.equal(result.steps[1].indicator.kind, 'approved');
  assert.deepEqual(result.steps[0].reviewers.map((r) => r.name), ['Dana Head'], 'falls back to assigned head');
});
