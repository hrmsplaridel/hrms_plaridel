const test = require('node:test');
const assert = require('node:assert/strict');
const createBalanceControllers = require('../src/modules/leave/controllers/balances.controller');
const { canAdjustLeaveCredits } = require('../src/services/leaveCreditAdjustmentEligibility');

const employeeId = '11111111-1111-4111-8111-111111111111';
const actorId = '22222222-2222-4222-8222-222222222222';

async function invoke(dateFields = {}, { adjustmentError } = {}) {
  const calls = [], adjustments = [], broadcasts = [];
  let connections = 0;
  const client = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('FROM users')) return { rows: [{ employment_type: 'permanent', leave_credit_eligible: true, full_name: 'Sample Employee' }] };
      return { rows: [] };
    },
    release() { calls.push({ sql: 'release' }); },
  };
  const controller = createBalanceControllers({
    pool: { connect: async () => { connections++; return client; } },
    canAdjustLeaveCredits,
    resolveBalanceLedgerLeaveType: async (_db, name) => name,
    applyAdminLeaveBalanceAdjustment: async (db, input) => {
      assert.equal(db, client);
      adjustments.push(input);
      if (adjustmentError) throw adjustmentError;
      return { row: { id: 'balance-id', user_id: employeeId, leave_type: 'sickLeave', earned_days: 10,
        used_days: 1, pending_days: 0, adjusted_days: 2, as_of_date: input.asOfDate } };
    },
    broadcastLeaveUpdated: (...args) => broadcasts.push(args),
  }).adjustBalance;
  const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
  await controller({ params: { userId: employeeId }, user: { id: actorId, role: 'hr' },
    body: { leave_type: 'sickLeave', adjustment_days: 2, remarks: 'Verified HR correction', ...dateFields } }, res);
  return { res, calls, adjustments, broadcasts, connections };
}

for (const alias of ['as_of_date', 'asOfDate']) {
  for (const value of ['2026-02-30', '2025-02-29', '1900-02-29', '2026-04-31', '2026-13-01',
    '2026-00-01', '2026-01-00', '2026-01-32', '0000-01-01', 'junk', '2026-2-01',
    '2026-11-01T00:00:00Z', ' 2026-11-01', '2026-11-01 ', '   ', false, true, 20261101, {}, [], ['2026-11-01']]) {
    test(`adjustment rejects invalid ${alias} before connecting: ${JSON.stringify(value)}`, async () => {
      const { res, calls, adjustments, broadcasts, connections } = await invoke({ [alias]: value });
      assert.equal(res.code, 400);
      assert.match(res.body.error, /as_of_date.*(real|valid).*YYYY-MM-DD/i);
      assert.equal(connections, 0, 'Invalid dates must be rejected before a transaction is started');
      assert.deepEqual(calls, []);
      assert.deepEqual(adjustments, []);
      assert.deepEqual(broadcasts, []);
    });
  }

  for (const value of ['2026-11-01', '2024-02-29', '2000-02-29', '2026-04-30', '2026-12-31', '2027-01-01', null, '']) {
    test(`adjustment preserves valid or cleared ${alias}: ${JSON.stringify(value)}`, async () => {
      const { res, calls, adjustments, broadcasts, connections } = await invoke({ [alias]: value });
      assert.equal(res.code, 201);
      assert.equal(connections, 1);
      assert.equal(adjustments.length, 1);
      assert.deepEqual(adjustments[0], {
        userId: employeeId, leaveType: 'sickLeave', daysChanged: 2, actorUserId: actorId,
        actorKind: 'hr', remarks: 'Verified HR correction', asOfDate: value || null,
      });
      assert.equal(res.body.as_of_date, value || null);
      assert.ok(calls.some(c => c.sql === 'BEGIN'));
      assert.ok(calls.some(c => c.sql === 'COMMIT'));
      assert.ok(!calls.some(c => c.sql === 'ROLLBACK'));
      assert.equal(calls.at(-1).sql, 'release');
      assert.equal(broadcasts.length, 1);
    });
  }
}

test('an omitted adjustment date remains null for the existing service default', async () => {
  const { res, adjustments } = await invoke();
  assert.equal(res.code, 201);
  assert.equal(adjustments[0].asOfDate, null);
});

for (const [fields, expected] of [
  [{ as_of_date: '2026-11-01', asOfDate: '2026-10-31' }, '2026-11-01'],
  [{ as_of_date: null, asOfDate: '2026-10-31' }, '2026-10-31'],
  [{ as_of_date: '', asOfDate: '2026-10-31' }, null],
]) {
  test(`date aliases retain existing selection semantics: ${JSON.stringify(fields)}`, async () => {
    const { res, adjustments } = await invoke(fields);
    assert.equal(res.code, 201);
    assert.equal(adjustments[0].asOfDate, expected);
  });
}

test('an invalid selected snake-case date cannot fall back to a valid camel-case alias', async () => {
  const { res, connections } = await invoke({ as_of_date: '2026-02-30', asOfDate: '2026-02-28' });
  assert.equal(res.code, 400);
  assert.equal(connections, 0);
});

test('a valid date retains adjustment-failure rollback and prevents success broadcasts', async t => {
  t.mock.method(console, 'error', () => {});
  const { res, calls, broadcasts } = await invoke({ as_of_date: '2026-11-01' }, {
    adjustmentError: Object.assign(new Error('Adjustment rejected'), { statusCode: 400 }),
  });
  assert.equal(res.code, 400);
  assert.ok(calls.some(c => c.sql === 'ROLLBACK'));
  assert.ok(!calls.some(c => c.sql === 'COMMIT'));
  assert.equal(calls.at(-1).sql, 'release');
  assert.deepEqual(broadcasts, []);
});
