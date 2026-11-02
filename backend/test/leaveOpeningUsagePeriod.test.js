const test = require('node:test');
const assert = require('node:assert/strict');
const { applyOpeningBalances, verifyOpeningUsage } = require('../src/services/leaveOpeningBalances');
const createControllers = require('../src/modules/leave/controllers/openingBalances.controller');
const USER = '11111111-1111-4111-8111-111111111111';
const actor = { id: '22222222-2222-4222-8222-222222222222', role: 'hr' };

function fixture({ cutoff, hired = null, legacy = false }) {
  const queries = [];
  const employee = { id: USER, date_hired: hired, role: 'employee', employment_type: 'permanent',
    leave_credit_eligible: true, is_active: true, employment_status: 'active' };
  const db = {
    queries,
    release() {},
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('FROM users')) return { rows: [employee] };
      if (sql.includes('FROM leave_opening_balance_setups')) return { rows: legacy
        ? [{ cutoff_date: cutoff, qualifying_leave_days: null, date_hired: hired }] : [] };
      if (sql.includes('FROM leave_balances')) return { rows: ['sickLeave', 'vacationLeave'].map(leave_type => ({
        leave_type, earned_days: 0, used_days: 0, pending_days: 0, adjusted_days: 0,
      })) };
      if (sql.includes('UPDATE leave_balances')) return { rows: [{ leave_type: params[1], adjusted_days: params[2] }] };
      if (sql.includes('INSERT INTO leave_opening_balance_setups')) return { rows: [{ cutoff_date: cutoff, qualifying_leave_days: params[6] }] };
      if (sql.includes('UPDATE leave_opening_balance_setups')) return { rows: [{ cutoff_date: cutoff, qualifying_leave_days: params[1] }] };
      return { rows: [] };
    },
  };
  return db;
}

const cases = [
  ['January example', '2026-01-31', '2026-01-01', 366, false],
  ['January over limit', '2026-01-31', null, 32, false],
  ['January exact limit', '2026-01-31', null, 31, true],
  ['January fractional overflow', '2026-01-31', null, 31.001, false],
  ['zero usage', '2026-01-31', null, 0, true],
  ['fractional usage', '2026-01-31', null, 0.5, true],
  ['leap February exact limit', '2024-02-29', '2020-01-01', 60, true],
  ['leap February overflow', '2024-02-29', '2020-01-01', 60.001, false],
  ['non-leap February exact limit', '2025-02-28', null, 59, true],
  ['non-leap February overflow', '2025-02-28', null, 60, false],
  ['non-leap full-year exact limit', '2026-12-31', null, 365, true],
  ['non-leap full-year overflow', '2026-12-31', null, 366, false],
  ['leap full-year exact limit', '2024-12-31', null, 366, true],
  ['mid-month hire exact limit', '2026-01-31', '2026-01-16', 16, true],
  ['mid-month hire overflow', '2026-01-31', '2026-01-16', 17, false],
  ['cutoff-day hire exact limit', '2026-01-31', '2026-01-31', 1, true],
  ['cutoff-day hire fractional overflow', '2026-01-31', '2026-01-31', 1.001, false],
  ['old hire counts only cutoff year', '2026-01-31', '2024-01-01', 32, false],
  ['year-end new hire exact limit', '2026-12-31', '2026-12-20', 12, true],
  ['year-end new hire overflow', '2026-12-31', '2026-12-20', 12.001, false],
];

for (const legacy of [false, true]) {
  for (const [name, cutoff, hired, days, valid] of cases) {
    test(`${legacy ? 'usage verification' : 'opening setup'} bounds ${name}`, async () => {
      const db = fixture({ cutoff, hired, legacy });
      const input = { userId: USER, actor, cutoff_date: cutoff, qualifying_leave_days: days,
        sick_leave_days: 25, vacation_leave_days: 30, confirmed: true,
        reason: 'Verified HR leave card', reference: 'Verified HR leave card' };
      const run = () => legacy ? verifyOpeningUsage(db, input)
        : applyOpeningBalances(db, input, { today: '2027-01-01' });
      if (!valid) {
        await assert.rejects(run(), err => err.statusCode === 400 && /qualifying|calendar/i.test(err.message));
        assert.equal(db.queries.some(q => /UPDATE leave_balances|INSERT INTO leave_balance_ledger|INSERT INTO leave_opening_balance_setups|UPDATE leave_opening_balance_setups/.test(q.sql)), false);
      } else {
        const result = await run();
        assert.equal(Number(result.setup.qualifying_leave_days), days);
        if (legacy) {
          assert.equal(db.queries.some(q => /UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(q.sql)), false);
        } else {
          const setup = db.queries.find(q => q.sql.includes('INSERT INTO leave_opening_balance_setups'));
          assert.equal(setup.params[2], 25, 'Carried-over SL credits are not restricted to this period');
          assert.equal(setup.params[3], 30, 'Carried-over VL credits are not restricted to this period');
        }
      }
    });
  }
}

for (const legacy of [false, true]) {
  test(`${legacy ? 'verification' : 'setup'} rolls back invalid usage and never broadcasts success`, async () => {
    const db = fixture({ cutoff: '2026-01-31', hired: '2026-01-16', legacy });
    const broadcasts = [];
    const controller = createControllers({ pool: { connect: async () => db },
      broadcastLeaveUpdated: (...args) => broadcasts.push(args) });
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    const req = { params: { userId: USER }, user: actor, body: {
      cutoff_date: '2026-01-31', qualifying_leave_days: 17, sick_leave_days: 25, vacation_leave_days: 30,
      confirmed: true, reason: 'HR card', reference: 'HR card',
    } };
    await controller[legacy ? 'verifyOpeningUsage' : 'saveOpeningBalances'](req, res);
    assert.equal(res.code, 400);
    assert.equal(db.queries.some(q => q.sql === 'ROLLBACK'), true);
    assert.equal(db.queries.some(q => q.sql === 'COMMIT'), false);
    assert.deepEqual(broadcasts, []);
  });
}

test('opening details return authoritative hire date for the form validation period', async () => {
  const db = fixture({ cutoff: '2026-01-31', hired: '2026-01-16' });
  const controller = createControllers({ pool: db, todayInHrmsTimezone: () => '2026-02-01' });
  const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
  await controller.getOpeningBalances({ params: { userId: USER } }, res);
  assert.equal(res.code, 200);
  assert.equal(res.body.date_hired, '2026-01-16');
});
