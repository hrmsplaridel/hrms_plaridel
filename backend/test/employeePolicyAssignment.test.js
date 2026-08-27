'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  EmployeePolicyAssignmentError,
  upsertEmployeePolicyAssignment,
} = require('../src/services/employeePolicyAssignment');

const EMPLOYEE_ID = '11111111-1111-4111-8111-111111111111';
const POLICY_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const POLICY_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

function policyDb(overlappingRows = []) {
  const calls = [];
  let replacementNumber = 0;
  return {
    calls,
    async query(sql, params = []) {
      const text = String(sql).trim();
      calls.push({ text, params });
      if (text.startsWith('SELECT pg_advisory_xact_lock')) {
        return { rowCount: 1, rows: [{}] };
      }
      if (text.startsWith('SELECT id, attendance_policy_id')) {
        return { rowCount: overlappingRows.length, rows: overlappingRows };
      }
      if (text.startsWith('UPDATE policy_assignments')) {
        return { rowCount: overlappingRows.length, rows: [] };
      }
      if (text.startsWith('INSERT INTO policy_assignments')) {
        if (!text.includes('RETURNING')) {
          return { rowCount: 1, rows: [] };
        }
        replacementNumber += 1;
        return {
          rowCount: 1,
          rows: [{
            id: `replacement-${replacementNumber}`,
            attendance_policy_id: params[0],
            employee_id: params[1],
            effective_from: params[2],
            effective_to: params[3],
            is_active: params[4],
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };
}

function insertedRanges(db) {
  return db.calls
    .filter((call) => call.text.startsWith('INSERT INTO policy_assignments'))
    .map((call) => call.params);
}

test('replacing a middle policy period preserves both surrounding ranges', async () => {
  const db = policyDb([{
    id: 'existing-a',
    attendance_policy_id: POLICY_A,
    effective_from: '2026-01-01',
    effective_to: '2026-12-31',
  }]);

  const result = await upsertEmployeePolicyAssignment(db, {
    employeeId: EMPLOYEE_ID,
    attendancePolicyId: POLICY_B,
    effectiveFrom: '2026-06-01',
    effectiveTo: '2026-06-30',
  });

  assert.equal(result.attendance_policy_id, POLICY_B);
  assert.deepEqual(insertedRanges(db), [
    [POLICY_A, EMPLOYEE_ID, '2026-01-01', '2026-05-31'],
    [POLICY_A, EMPLOYEE_ID, '2026-07-01', '2026-12-31'],
    [POLICY_B, EMPLOYEE_ID, '2026-06-01', '2026-06-30', true],
  ]);
});

test('clearing a middle period preserves surrounding policy coverage', async () => {
  const db = policyDb([{
    id: 'existing-a',
    attendance_policy_id: POLICY_A,
    effective_from: '2026-01-01',
    effective_to: '2026-12-31',
  }]);

  const result = await upsertEmployeePolicyAssignment(db, {
    employeeId: EMPLOYEE_ID,
    attendancePolicyId: null,
    effectiveFrom: '2026-06-01',
    effectiveTo: '2026-06-30',
  });

  assert.equal(result, null);
  assert.deepEqual(insertedRanges(db), [
    [POLICY_A, EMPLOYEE_ID, '2026-01-01', '2026-05-31'],
    [POLICY_A, EMPLOYEE_ID, '2026-07-01', '2026-12-31'],
  ]);
});

test('an open-ended replacement preserves only the earlier policy period', async () => {
  const db = policyDb([{
    id: 'existing-a',
    attendance_policy_id: POLICY_A,
    effective_from: '2026-01-01',
    effective_to: null,
  }]);

  await upsertEmployeePolicyAssignment(db, {
    employeeId: EMPLOYEE_ID,
    attendancePolicyId: POLICY_B,
    effectiveFrom: '2026-07-01',
    effectiveTo: null,
  });

  assert.deepEqual(insertedRanges(db), [
    [POLICY_A, EMPLOYEE_ID, '2026-01-01', '2026-06-30'],
    [POLICY_B, EMPLOYEE_ID, '2026-07-01', null, true],
  ]);
});

test('policy transitions reject invalid effective ranges before writing', async () => {
  const db = policyDb();

  await assert.rejects(
    upsertEmployeePolicyAssignment(db, {
      employeeId: EMPLOYEE_ID,
      attendancePolicyId: POLICY_B,
      effectiveFrom: '2026-07-01',
      effectiveTo: '2026-06-30',
    }),
    (error) =>
      error instanceof EmployeePolicyAssignmentError &&
      error.message === 'effective_to must be on or after effective_from'
  );
  assert.equal(db.calls.length, 0);
});
