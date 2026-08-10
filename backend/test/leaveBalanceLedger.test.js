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
