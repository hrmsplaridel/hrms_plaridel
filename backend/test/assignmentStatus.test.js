const test = require('node:test');
const assert = require('node:assert/strict');

const {
  AssignmentStatusError,
  assignmentStatusContext,
  assignmentStatusWhereSql,
  computedAssignmentStatusSql,
  normalizeAssignmentStatus,
} = require('../src/services/assignmentStatus');

test('assignment status accepts the shared contract and legacy aliases', () => {
  assert.equal(normalizeAssignmentStatus('Current'), 'Current');
  assert.equal(normalizeAssignmentStatus('upcoming'), 'Upcoming');
  assert.equal(normalizeAssignmentStatus('Expired'), 'Expired');
  assert.equal(normalizeAssignmentStatus('Archived'), 'Archived');
  assert.equal(normalizeAssignmentStatus('All'), 'All');
  assert.equal(normalizeAssignmentStatus('Active'), 'Current');
  assert.equal(normalizeAssignmentStatus('Inactive'), 'Archived');
});

test('invalid assignment status is rejected', () => {
  assert.throws(
    () => normalizeAssignmentStatus('Enabled'),
    (error) => error instanceof AssignmentStatusError && error.statusCode === 400
  );
});

test('computed status prioritizes archive before effective dates', () => {
  const sql = computedAssignmentStatusSql('a', '$2');
  assert.match(sql, /is_active[\s\S]*Archived[\s\S]*effective_from[\s\S]*Upcoming/);
  assert.match(sql, /effective_to[\s\S]*Expired[\s\S]*ELSE 'Current'/);
});

test('all status has no row filter while specific statuses share the same expression', () => {
  assert.equal(assignmentStatusWhereSql('a', 'All', '$2'), '');
  for (const status of ['Current', 'Upcoming', 'Expired', 'Archived']) {
    const sql = assignmentStatusWhereSql('a', status, '$2');
    assert.match(sql, new RegExp(`= '${status}'$`));
  }
});

test('status context calculates the business date in the configured HRMS timezone', () => {
  const timeZone = process.env.HRMS_TIMEZONE || 'Asia/Manila';
  const now = new Date('2026-08-29T16:30:00.000Z');
  const context = assignmentStatusContext('Current', {
    now,
  });
  const expectedParts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const values = Object.fromEntries(
    expectedParts.map((part) => [part.type, part.value])
  );
  assert.deepEqual(context, {
    status: 'Current',
    today: `${values.year}-${values.month}-${values.day}`,
  });
});
