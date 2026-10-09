const test = require('node:test');
const assert = require('node:assert/strict');
const { notifyLeaveMonthEnd, buildMonthEndMessage } = require('../src/services/leaveMonthEndNotifications');

test('monthly summary uses actual credits and deductions; corrections contain only deltas', () => {
  const totals = { vacationLeave: { earned: 1.25, deducted: 1 }, sickLeave: { earned: 0.625, deducted: 0 } };
  const initial = buildMonthEndMessage('2026-09', totals, null);
  assert.match(initial.body, /Vacation Leave: \+1.25 days earned, 1 day deducted/);
  assert.match(initial.body, /Sick Leave: \+0.625 days earned/);
  const corrected = buildMonthEndMessage('2026-09', { ...totals, vacationLeave: { earned: 1.25, deducted: 0.5 } }, totals);
  assert.match(corrected.title, /correction/i);
  assert.match(corrected.body, /0.5 days deduction reversed/);
  assert.doesNotMatch(corrected.body, /1.25|Sick Leave/);
  assert.equal(buildMonthEndMessage('2026-09', totals, totals), null);
  assert.equal(buildMonthEndMessage('2026-09', {}, null), null);
});

test('persisted summaries survive retries and publish only after commit', async () => {
  let previous = null;
  const totals = { vacationLeave: { earned: 1.25, deducted: 1 } };
  const calls = [], published = [];
  const client = { release() {}, query: async (sql, params) => {
    calls.push(sql);
    if (sql.includes('WITH notification_months')) return { rows: [{ user_id: 'employee', totals, previous_totals: previous }] };
    if (sql.includes('INSERT INTO user_notifications')) return { rows: [{ id: 'notification', user_id: 'employee' }] };
    if (sql.includes('INSERT INTO leave_month_end_notification_state')) previous = JSON.parse(params[2]);
    return { rows: [] };
  } };
  const pool = { connect: async () => client };
  const publish = async (_, row) => { assert.equal(calls.at(-1), 'COMMIT'); published.push(row); };
  assert.equal((await notifyLeaveMonthEnd(pool, { targetYearMonth: '2026-09', publish })).sent, 1);
  assert.equal((await notifyLeaveMonthEnd(pool, { targetYearMonth: '2026-09', publish })).sent, 0);
  assert.equal(published.length, 1);
  const before = calls.length;
  await notifyLeaveMonthEnd(pool, { targetYearMonth: '2026-09', dryRun: true, publish });
  assert.equal(calls.length, before);
});

test('notification storage failure rolls back without announcing success', async (t) => {
  t.mock.method(console, 'error', () => {});
  const calls = [];
  let delivered = false;
  const pool = { connect: async () => ({ release() {}, query: async (sql) => {
    calls.push(sql);
    if (sql.includes('WITH notification_months')) return { rows: [{ user_id: 'employee', totals: { vacationLeave: { earned: 1.25, deducted: 0 } } }] };
    if (sql.includes('INSERT INTO user_notifications')) throw Error('storage failure');
    return { rows: [] };
  } }) };
  await notifyLeaveMonthEnd(pool, { targetYearMonth: '2026-09', publish: async () => { delivered = true; } });
  assert.equal(calls.at(-1), 'ROLLBACK');
  assert.equal(delivered, false);
});
