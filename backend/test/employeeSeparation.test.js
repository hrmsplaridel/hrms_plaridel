const test = require('node:test');
const assert = require('node:assert/strict');

const {
  closeEmployeeAssignmentsForSeparation,
} = require('../src/services/employeeSeparation');

test('separation closes future and overlapping periods without archiving history', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql: sql.replace(/\s+/g, ' '), params });
      return { rowCount: 1 };
    },
  };
  const employeeId = '11111111-1111-4111-8111-111111111111';

  await closeEmployeeAssignmentsForSeparation(
    db,
    employeeId,
    '2026-07-27'
  );

  assert.equal(calls.length, 4);
  for (const call of calls) {
    assert.deepEqual(call.params, [employeeId, '2026-07-27']);
  }
  assert.match(calls[0].sql, /UPDATE assignments.*SET is_active = false/);
  assert.match(calls[0].sql, /effective_from > \$2::date/);
  assert.match(calls[1].sql, /UPDATE assignments.*SET effective_to = \$2::date/);
  assert.match(calls[1].sql, /effective_from <= \$2::date/);
  assert.match(calls[2].sql, /UPDATE policy_assignments.*SET is_active = false/);
  assert.match(calls[2].sql, /effective_from > \$2::date/);
  assert.match(calls[3].sql, /UPDATE policy_assignments.*SET effective_to = \$2::date/);
  assert.doesNotMatch(calls[3].sql, /is_active = false/);
});
