const test = require('node:test');
const assert = require('node:assert/strict');

const {
  affectedAssignmentDateRange,
} = require('../src/services/assignmentReconciliation');

test('historical assignment changes cover the union of old and new effective periods', () => {
  const range = affectedAssignmentDateRange(
    { effective_from: '2026-06-16', effective_to: '2026-07-31' },
    { effective_from: '2026-07-01', effective_to: null },
    { today: '2026-08-28' }
  );

  assert.deepEqual(range, {
    dateFrom: '2026-06-16',
    dateTo: '2026-08-28',
  });
});

test('future-only assignment changes do not rebuild DTR or queue month-end work', () => {
  const range = affectedAssignmentDateRange(
    { effective_from: '2026-09-01', effective_to: null },
    { effective_from: '2026-10-01', effective_to: null },
    { today: '2026-08-28' }
  );

  assert.equal(range, null);
});
