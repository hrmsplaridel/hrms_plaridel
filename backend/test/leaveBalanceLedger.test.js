const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyAdminLeaveBalanceAdjustment,
  buildLeaveBalanceHistoryFilters,
  normalizeLeaveBalanceAdjustment,
  normalizeLeaveBalanceAdjustmentReason,
} = require('../src/services/leaveBalanceLedger');

const USER_ID = '00000000-0000-0000-0000-000000000101';
const ACTOR_ID = '00000000-0000-0000-0000-000000000102';

test('ledger display omits only zero pending movements before counting and paging', () => {
  const filters = buildLeaveBalanceHistoryFilters({scopeAllUsers: true, hideZeroPending: true});
  assert.match(filters.whereSql, /NOT \(LOWER\(l.affected_bucket\) = 'pending' AND l.days_changed = 0\)/);
  assert.equal(filters.summaryWhereSql, 'true');
  assert.deepEqual(filters.params, []);
  assert.equal(buildLeaveBalanceHistoryFilters({scopeAllUsers: true}).whereSql, 'true');
});

test('balance-history summary includes both dates but excludes activity bucket', () => {
  const filters = buildLeaveBalanceHistoryFilters({
    scopedUserId: USER_ID,
    leaveType: 'vacationLeave',
    action: 'monthly_accrual',
    from: '2026-01-01',
    to: '2026-01-31',
    affectedBucket: 'earned',
  });

  assert.match(filters.summaryWhereSql, /created_at >= \$4::date/);
  assert.match(filters.summaryWhereSql, /created_at < \(\$5::date/);
  assert.doesNotMatch(filters.summaryWhereSql, /affected_bucket/);
  assert.deepEqual(filters.summaryParams, [
    USER_ID,
    'vacationLeave',
    'monthly_accrual',
    '2026-01-01',
    '2026-01-31',
  ]);

  assert.match(filters.whereSql, /affected_bucket\) = \$6/);
  assert.deepEqual(filters.params, [...filters.summaryParams, 'earned']);
  assert.equal(filters.nextParameter, 7);
});

test('admin adjustment changes only adjusted days and writes the exact ledger movement', async () => {
  const queries = [];
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ text, params });
      if (text.includes('INSERT INTO leave_balances')) {
        return { rows: [], rowCount: 0 };
      }
      if (text.includes('FROM leave_balances') && text.includes('FOR UPDATE')) {
        return {
          rows: [{
            earned_days: '10.000',
            used_days: '2.000',
            pending_days: '3.000',
            adjusted_days: '0.500',
          }],
          rowCount: 1,
        };
      }
      if (text.includes('UPDATE leave_balances')) {
        assert.match(text, /SET adjusted_days =/);
        assert.doesNotMatch(text, /SET earned_days =/);
        assert.doesNotMatch(text, /used_days\s*=/);
        assert.doesNotMatch(text, /pending_days\s*=/);
        return {
          rows: [{
            id: '00000000-0000-0000-0000-000000000201',
            user_id: USER_ID,
            leave_type: 'vacationLeave',
            earned_days: '10.000',
            used_days: '2.000',
            pending_days: '3.000',
            adjusted_days: '2.500',
          }],
          rowCount: 1,
        };
      }
      if (text.includes('INSERT INTO leave_balance_ledger')) {
        return { rows: [], rowCount: 1 };
      }
      throw new Error(`Unexpected query: ${text.slice(0, 100)}`);
    },
  };

  const result = await applyAdminLeaveBalanceAdjustment(client, {
    userId: USER_ID,
    leaveType: 'vacationLeave',
    daysChanged: 2,
    actorUserId: ACTOR_ID,
    actorKind: 'hr',
    remarks: 'Corrected imported opening balance',
    asOfDate: '2026-08-08',
  });

  assert.equal(result.daysChanged, 2);
  assert.equal(result.before.adjusted_days, 0.5);
  assert.equal(result.after.adjusted_days, 2.5);

  const ledger = queries.find((query) =>
    query.text.includes('INSERT INTO leave_balance_ledger')
  );
  assert.ok(ledger);
  assert.equal(ledger.params[2], 'admin_adjustment');
  assert.equal(ledger.params[3], 'adjusted');
  assert.equal(ledger.params[4], 2);
  assert.equal(ledger.params[5], 0.5);
  assert.equal(ledger.params[6], 2.5);
  assert.equal(ledger.params[8], ACTOR_ID);
  assert.equal(ledger.params[10], 'Corrected imported opening balance');
  assert.equal(ledger.params[11].available_before, 5.5);
  assert.equal(ledger.params[11].available_after, 7.5);
});

test('admin adjustment validates a non-zero three-decimal delta and required reason', () => {
  assert.equal(normalizeLeaveBalanceAdjustment('1.2504'), 1.25);
  assert.equal(normalizeLeaveBalanceAdjustment('-0.5'), -0.5);
  assert.throws(() => normalizeLeaveBalanceAdjustment(0), /must not be zero/);
  assert.throws(() => normalizeLeaveBalanceAdjustment('abc'), /must be a number/);
  assert.equal(
    normalizeLeaveBalanceAdjustmentReason('  Payroll correction  '),
    'Payroll correction'
  );
  assert.throws(() => normalizeLeaveBalanceAdjustmentReason('  '), /reason is required/i);
});

for (const value of [true, false, null, undefined, [], [2], {}, '', '  ', '0x10', '0b10',
  '1e2', '2days', NaN, Infinity, -Infinity, 1e308, -1e308, 10000000, -10000000,
  '9999999.9995', '-9999999.9996']) {
  test(`manual adjustment rejects invalid numeric input ${String(value)}`, async () => {
    const queries = [];
    await assert.rejects(applyAdminLeaveBalanceAdjustment({
      query: async sql => { queries.push(sql); return { rows: [] }; },
    }, { userId: USER_ID, leaveType: 'sickLeave', daysChanged: value, remarks: 'HR correction' }),
    err => err.statusCode === 400 && /adjustment_days/i.test(err.message));
    assert.deepEqual(queries, [], 'Invalid delta must be rejected before any balance SQL');
  });
}

for (const [input, expected] of [
  [' +2.000 ', 2], ['-0.500', -0.5], ['1.2504', 1.25], [-1.2504, -1.25],
  [9999999.999, 9999999.999], [-9999999.999, -9999999.999],
  ['9999999.9994', 9999999.999], ['-9999999.9994', -9999999.999],
]) {
  test(`manual adjustment preserves valid decimal normalization ${input}`, () => {
    assert.equal(normalizeLeaveBalanceAdjustment(input), expected);
  });
}

function adjustmentDb(current) {
  const queries = [];
  return {
    queries,
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('FOR UPDATE')) return { rows: [{
        earned_days: '0', used_days: '0', pending_days: '0', adjusted_days: String(current),
      }] };
      if (sql.includes('UPDATE leave_balances')) return { rows: [{
        user_id: USER_ID, leave_type: 'sickLeave', earned_days: '0', used_days: '0', pending_days: '0',
        adjusted_days: (Math.round(Number(current) * 1000) + Math.round(params[2] * 1000)) / 1000,
      }] };
      return { rows: [] };
    },
  };
}

for (const [current, delta] of [
  ['9999999.999', 0.001], ['-9999999.999', -0.001], ['9999999.998', 0.002],
  ['-9999999.998', -0.002], ['NaN', 1], ['Infinity', -1],
]) {
  test(`manual adjustment rejects invalid resulting bucket ${current} + ${delta}`, async () => {
    const db = adjustmentDb(current);
    await assert.rejects(applyAdminLeaveBalanceAdjustment(db, {
      userId: USER_ID, leaveType: 'sickLeave', daysChanged: delta, remarks: 'Verified correction',
    }), err => err.statusCode === 400 && /adjusted.*balance|balance.*range/i.test(err.message));
    assert.equal(db.queries.some(q => /UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(q.sql)), false);
  });
}

for (const [current, delta, expected] of [
  ['9999999.998', 0.001, 9999999.999], ['-9999999.998', -0.001, -9999999.999],
  ['9999999.999', -0.001, 9999999.998], ['0.002', -0.003, -0.001], ['0', -2.5, -2.5],
]) {
  test(`manual adjustment preserves in-range signed bucket ${current} + ${delta}`, async () => {
    const db = adjustmentDb(current);
    const result = await applyAdminLeaveBalanceAdjustment(db, {
      userId: USER_ID, leaveType: 'sickLeave', daysChanged: delta, remarks: 'Verified correction',
    });
    assert.equal(Number(result.row.adjusted_days), expected);
    const ledger = db.queries.find(q => q.sql.includes('INSERT INTO leave_balance_ledger'));
    assert.equal(ledger.params[4], delta);
    assert.equal(ledger.params[5], Number(current));
    assert.equal(ledger.params[6], expected);
    assert.equal(ledger.params[11].available_after, expected, 'Negative available balances remain supported');
  });
}

test('adjustment controller rolls back an overflowing result without broadcasting success', async t => {
  t.mock.method(console, 'error', () => {});
  const db = adjustmentDb('9999999.999');
  const query = db.query.bind(db);
  db.query = async (sql, params) => {
    if (sql.includes('SELECT employment_type')) {
      db.queries.push({ sql, params });
      return { rows: [{ employment_type: 'permanent', leave_credit_eligible: true }] };
    }
    return query(sql, params);
  };
  db.release = () => {};
  const broadcasts = [];
  const controller = require('../src/modules/leave/controllers/balances.controller')({
    pool: { connect: async () => db }, applyAdminLeaveBalanceAdjustment,
    canAdjustLeaveCredits: () => true, resolveBalanceLedgerLeaveType: async () => 'sickLeave',
    broadcastLeaveUpdated: (...args) => broadcasts.push(args),
  });
  const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
  await controller.adjustBalance({ user: { id: ACTOR_ID, role: 'hr' }, params: { userId: USER_ID },
    body: { leave_type: 'sickLeave', adjustment_days: 0.001, remarks: 'Verified correction' } }, res);
  assert.equal(res.code, 400);
  assert.equal(db.queries.at(-1).sql, 'ROLLBACK');
  assert.equal(db.queries.some(q => /UPDATE leave_balances|INSERT INTO leave_balance_ledger|COMMIT/.test(q.sql)), false);
  assert.deepEqual(broadcasts, []);
});
