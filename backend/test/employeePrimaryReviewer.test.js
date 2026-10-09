const test = require('node:test');
const assert = require('node:assert/strict');
const { resolveDepartmentReviewers } = require('../src/services/departmentReviewerService');
const { resolveFinalLeaveReviewerConfiguration } = require('../src/services/leaveFinalReviewerService');

test('department reviewer comes from the designated employee, not another position holder', async () => {
  const db = { query: async (sql, params) => {
    if (sql.includes('department_reviewer_backups')) return { rows: [] };
    assert.match(sql, /primary_reviewer_designations/);
    assert.doesNotMatch(sql, /position_department_head_periods/);
    assert.deepEqual(params, ['department', '2026-10-09', null]);
    return { rows: [{ reviewer_id: 'chosen-employee', reviewer_name: 'Chosen Employee' }] };
  } };
  const result = await resolveDepartmentReviewers(db, { departmentId: 'department', effectiveDate: '2026-10-09' });
  assert.equal(result.primary.reviewerId, 'chosen-employee');
});

test('final HR reviewer comes from the designated employee with effective dates', async () => {
  const db = { query: async (sql, params) => {
    if (sql.includes('leave_final_reviewer_backups')) return { rows: [] };
    assert.match(sql, /primary_reviewer_designations/);
    assert.doesNotMatch(sql, /is_leave_final_reviewer/);
    assert.deepEqual(params, ['2026-10-09']);
    return { rows: [{ id: 'chosen-hr', name: 'Chosen HR', position_title: 'HR Officer' }] };
  } };
  const result = await resolveFinalLeaveReviewerConfiguration(db, '2026-10-09');
  assert.equal(result.primary.id, 'chosen-hr');
});
