const test = require('node:test');
const assert = require('node:assert/strict');
const { runScheduledCompletedMonthEnd } = require('../src/jobs/leaveMonthlyAccrualScheduler');

for (const fail of [false, true]) {
  test(`month-end notification waits for both steps; attendance failure=${fail}`, async () => {
    const calls = [];
    const pool = { connect: async () => ({ release() {}, query: async sql => ({ rows: [{ got: !sql.includes('unlock') }] }) }) };
    const run = runScheduledCompletedMonthEnd(pool, {
      now: new Date('2026-10-01T00:00:00Z'),
      accrualRunner: async () => { calls.push('accrual'); return { targetYearMonth: '2026-09', details: [] }; },
      attendanceRunner: async () => { calls.push('attendance'); if (fail) throw Error('attendance failed'); return { details: [] }; },
      queueEmployeeLoader: async () => [], queueLoader: async () => [], resultBroadcaster: () => 0,
      monthEndNotifier: async (_, options) => { calls.push('summary'); assert.equal(options.targetYearMonth, '2026-09'); },
      failureNotifier: async (_, options) => { calls.push('failure'); assert.equal(options.targetYearMonth, '2026-09'); },
    });
    if (fail) await assert.rejects(run, /attendance failed/); else await run;
    assert.deepEqual(calls, ['accrual', 'attendance', fail ? 'failure' : 'summary']);
  });
}
