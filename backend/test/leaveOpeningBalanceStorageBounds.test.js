const test = require('node:test');
const assert = require('node:assert/strict');
const { applyOpeningBalances } = require('../src/services/leaveOpeningBalances');
const createControllers = require('../src/modules/leave/controllers/openingBalances.controller');

const USER = '11111111-1111-4111-8111-111111111111';
const actor = { id: '22222222-2222-4222-8222-222222222222', role: 'hr' };
const input = { userId: USER, actor, cutoff_date: '2026-10-31', sick_leave_days: 25,
  vacation_leave_days: 40, qualifying_leave_days: 0, confirmed: true, reason: 'Verified HR leave card' };
const MAX = 9999999.999;

function fixture(overrides = {}) {
  const calls = [], ledger = [], broadcasts = [];
  const rows = ['sickLeave', 'vacationLeave'].map(leave_type => ({
    leave_type, earned_days: '10.000', used_days: '5.000', pending_days: '0.000',
    adjusted_days: '0.000', last_accrual_date: null, ...overrides[leave_type],
  }));
  const db = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('FROM users')) return { rows: [{ id: USER, role: 'employee', employment_type: 'permanent',
        is_active: true, employment_status: 'active', leave_credit_eligible: true, date_hired: '2020-01-01' }] };
      if (sql.includes('FROM leave_balances')) return { rows: rows.map(row => ({ ...row })) };
      if (sql.includes('UPDATE leave_balances')) {
        const row = rows.find(row => row.leave_type === params[1]);
        row.adjusted_days = params[2];
        row.last_accrual_date = params[3];
        return { rows: [{ ...row }] };
      }
      if (sql.includes('INSERT INTO leave_balance_ledger')) ledger.push(params);
      if (sql.includes('INSERT INTO leave_opening_balance_setups')) return { rows: [{ user_id: USER, cutoff_date: params[1] }] };
      return { rows: [] };
    },
    release() { calls.push({ sql: 'release' }); },
  };
  return { db, rows, calls, ledger, broadcasts };
}

function assertNoOpeningUpdates(h) {
  assert.equal(h.calls.some(c => /UPDATE leave_balances|INSERT INTO leave_balance_ledger|INSERT INTO leave_opening_balance_setups/.test(c.sql)), false);
}

for (const leaveType of ['sickLeave', 'vacationLeave']) {
  for (const [name, row] of [
    ['positive computed overflow', { earned_days: 0, used_days: MAX }],
    ['positive overflow by one thousandth', { earned_days: 0, used_days: leaveType === 'sickLeave' ? 9999975 : 9999960 }],
    ['stored value beyond its negative-result boundary', { earned_days: 10000000, used_days: 0 }],
    ['nonfinite earned credits', { earned_days: 'NaN' }],
    ['infinite used credits', { used_days: Infinity }],
    ['negative infinite earned credits', { earned_days: -Infinity }],
    ['nonfinite pending credits', { pending_days: 'NaN' }],
    ['nonfinite old adjustment', { adjusted_days: 'NaN' }],
    ['infinite old adjustment', { adjusted_days: Infinity }],
  ]) {
    test(`opening setup rejects ${leaveType} ${name} before either balance update`, async () => {
      const h = fixture({ [leaveType]: row });
      await assert.rejects(applyOpeningBalances(h.db, input, { today: '2026-11-01' }), error =>
        error.statusCode === 400 && /balance|adjustment|credits|range/i.test(error.message));
      assertNoOpeningUpdates(h);
      assert.ok(h.calls.some(c => c.sql.includes('FOR UPDATE')), 'Validation must use the locked balances');
    });
  }
}

for (const [name, overrides, values, expected] of [
  ['normal 25 and 40 available credits', {}, {}, [20, 35]],
  ['exact positive storage boundary', { sickLeave: { earned_days: 0, used_days: '9999974.999' } }, {}, [MAX, 35]],
  ['one thousandth inside the positive boundary', { sickLeave: { earned_days: 0, used_days: '9999974.998' } }, {}, [9999999.998, 35]],
  ['exact negative storage boundary', { sickLeave: { earned_days: '9999999.999', used_days: 0 } }, { sick_leave_days: 0 }, [-MAX, 35]],
  ['one thousandth inside the negative boundary', { sickLeave: { earned_days: '9999999.999', used_days: 0 } }, { sick_leave_days: 0.001 }, [-9999999.998, 35]],
  ['ordinary negative adjustments', { sickLeave: { earned_days: 100, used_days: 0 } }, {}, [-75, 35]],
  ['precise three-decimal cancellation', { sickLeave: { earned_days: '0.300', used_days: '0.100' } }, { sick_leave_days: 0.2 }, [0, 35]],
]) {
  test(`opening setup preserves ${name}`, async () => {
    const h = fixture(overrides);
    const requested = { ...input, ...values };
    const result = await applyOpeningBalances(h.db, requested, { today: '2026-11-01' });
    assert.deepEqual(result.balances.map(row => row.adjusted_days), expected);
    assert.equal(h.ledger.length, 2);
    assert.ok(h.calls.some(c => c.sql.includes('INSERT INTO leave_opening_balance_setups')));
    for (const [index, row] of h.rows.entries()) {
      const available = Number(row.earned_days) - Number(row.used_days) + Number(row.adjusted_days) - Number(row.pending_days);
      assert.ok(Math.abs(available - (index === 0 ? requested.sick_leave_days : requested.vacation_leave_days)) < 0.000001);
    }
  });
}

test('a valid movement between opposite boundaries is allowed by the unbounded ledger column', async () => {
  const h = fixture({ sickLeave: { earned_days: 0, used_days: '9999974.999', adjusted_days: '-9999999.999' } });
  await applyOpeningBalances(h.db, input, { today: '2026-11-01' });
  const entry = h.ledger[0];
  assert.equal(entry[4], 19999999.998);
  assert.equal(entry[5], -MAX);
  assert.equal(entry[6], MAX);
});

for (const invalid of [false, true]) {
  test(`opening API ${invalid ? 'rolls back overflow' : 'commits valid balances'} without misleading broadcasts`, async () => {
    const h = fixture(invalid ? { vacationLeave: { earned_days: 0, used_days: MAX } } : {});
    const before = h.rows.map(row => ({ ...row }));
    const controllers = createControllers({ pool: { connect: async () => h.db },
      broadcastLeaveUpdated: (...args) => h.broadcasts.push(args) });
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    await controllers.saveOpeningBalances({ params: { userId: USER }, user: actor, body: input }, res);
    assert.equal(res.code, invalid ? 400 : 201);
    assert.equal(h.calls.some(c => c.sql === 'COMMIT'), !invalid);
    assert.equal(h.calls.some(c => c.sql === 'ROLLBACK'), invalid);
    assert.equal(h.broadcasts.length, invalid ? 0 : 1);
    assert.equal(h.calls.at(-1).sql, 'release');
    if (invalid) {
      assert.match(res.body.error, /balance|adjustment|credits|range/i);
      assertNoOpeningUpdates(h);
      assert.deepEqual(h.rows, before);
    }
  });
}
