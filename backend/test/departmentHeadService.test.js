const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getDepartmentReviewSnapshot,
} = require('../src/services/departmentHeadService');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';
const DEPARTMENT_ID = '00000000-0000-0000-0000-000000000201';
const HEAD_ID = '00000000-0000-0000-0000-000000000301';

test('review snapshot resolves the assignment effective today without is_active filtering', async () => {
  const sqlCalls = [];
  const client = {
    async query(sql) {
      const text = String(sql);
      sqlCalls.push(text);
      if (text.includes('LEFT JOIN departments d')) {
        return {
          rows: [{
            department_id: DEPARTMENT_ID,
            department_name: 'Human Resources',
          }],
        };
      }
      if (text.includes('LOWER(p.name) = ANY')) {
        return { rows: [{ employee_id: HEAD_ID }] };
      }
      throw new Error(`Unexpected query: ${text.slice(0, 80)}`);
    },
  };

  const snapshot = await getDepartmentReviewSnapshot(client, EMPLOYEE_ID);

  assert.deepEqual(snapshot, {
    departmentHeadUserId: HEAD_ID,
    departmentId: DEPARTMENT_ID,
    departmentName: 'Human Resources',
  });
  assert.equal(sqlCalls.every((sql) => !/a\.is_active/i.test(sql)), true);
  assert.equal(sqlCalls.every((sql) => sql.includes('CURRENT_DATE')), true);
});

test('review snapshot retains the department when no head is configured', async () => {
  let call = 0;
  const client = {
    async query() {
      call += 1;
      if (call === 1) {
        return {
          rows: [{ department_id: DEPARTMENT_ID, department_name: 'Accounting' }],
        };
      }
      return { rows: [] };
    },
  };

  const snapshot = await getDepartmentReviewSnapshot(client, EMPLOYEE_ID);

  assert.deepEqual(snapshot, {
    departmentHeadUserId: null,
    departmentId: DEPARTMENT_ID,
    departmentName: 'Accounting',
  });
});
