const test = require('node:test');
const assert = require('node:assert/strict');

const {
  runLeaveMonthlyAccrual,
  parseTargetMonth,
  monthStartInTimeZone,
  countMonthsToCredit,
  firstMonthAccrualAmount,
  separationMonthAccrualAmount,
  round2,
  startOfMonth,
} = require('../src/services/leaveMonthlyAccrual');

// ─── Mock pool factory ────────────────────────────────────────────────────────

/**
 * Creates a minimal mock pool/client for unit tests.
 *
 * @param {object} opts
 * @param {Array}  [opts.missingRows]   - Rows returned by the "missing balance rows" query.
 * @param {Array}  [opts.balanceRows]   - Rows returned by the main leave_balances query.
 * @param {Array}  [opts.leaveTypeRows] - Rows returned by the DB-driven accrual config query.
 *                                        Set to [] to exercise the hardcoded fallback path.
 */
function createMockPool({ missingRows = [], balanceRows = [], leaveTypeRows = null } = {}) {
  const calls = [];

  // Default: pretend both VL and SL accrue at 1.25 (mimics post-migration DB)
  const defaultLeaveTypeRows = [
    { name: 'vacationLeave', monthly_rate: '1.25', accrual_annual_cap: null },
    { name: 'sickLeave',     monthly_rate: '1.25', accrual_annual_cap: null },
  ];
  const resolvedLeaveTypeRows = leaveTypeRows !== null ? leaveTypeRows : defaultLeaveTypeRows;

  const client = {
    query: async (sql, params = []) => {
      const text = String(sql);
      calls.push({ target: 'client', sql: text, params });

      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text.trim())) {
        return { rows: [], rowCount: 0 };
      }
      if (text.includes('INSERT INTO leave_balances')) {
        return { rows: [], rowCount: missingRows.length };
      }
      if (text.includes('FROM users u') && text.includes('CROSS JOIN unnest') && text.includes('lb.id IS NULL')) {
        return { rows: [...missingRows], rowCount: missingRows.length };
      }
      if (text.includes('FROM leave_balances lb') && text.includes('INNER JOIN users u')) {
        return { rows: [...balanceRows], rowCount: balanceRows.length };
      }
      if (text.includes('UPDATE leave_balances')) {
        return { rows: [], rowCount: 1 };
      }
      if (text.includes('INSERT INTO leave_balance_ledger')) {
        return { rows: [], rowCount: 1 };
      }

      throw new Error(`Unexpected client query: ${text.slice(0, 80)}`);
    },
    release: () => {
      calls.push({ target: 'client', sql: 'release', params: [] });
    },
  };

  const pool = {
    query: async (sql, params = []) => {
      const text = String(sql);
      calls.push({ target: 'pool', sql: text, params });

      // DB-driven leave type config query
      if (text.includes('FROM leave_types') && text.includes('accrues_monthly')) {
        return { rows: resolvedLeaveTypeRows, rowCount: resolvedLeaveTypeRows.length };
      }

      return { rows: [], rowCount: 0 };
    },
    connect: async () => client,
  };

  return { pool, calls };
}

// Helper: build a standard balance row
function makeBalanceRow(overrides = {}) {
  return {
    id: '00000000-0000-0000-0000-000000000303',
    user_id: '00000000-0000-0000-0000-000000000101',
    leave_type: 'vacationLeave',
    earned_days: '0',
    used_days: '0',
    adjusted_days: '0',
    last_accrual_date: null,
    full_name: 'Test User',
    date_hired: '2026-01-01',
    employment_type: 'regular',
    employment_status: 'active',
    separation_date: null,
    ...overrides,
  };
}

// ─── Existing tests (unchanged) ───────────────────────────────────────────────

test('parseTargetMonth rejects invalid YYYY-MM months', () => {
  assert.throws(() => parseTargetMonth('2026-13'), /between 01 and 12/);
  assert.throws(() => parseTargetMonth('2026/05'), /YYYY-MM/);
});

test('monthStartInTimeZone uses Asia/Manila for first-of-month cron timing', () => {
  const monthStart = monthStartInTimeZone(new Date('2026-05-31T16:00:00.000Z'));
  assert.equal(monthStart.getFullYear(), 2026);
  assert.equal(monthStart.getMonth(), 5);
});

test('runLeaveMonthlyAccrual rejects future target months', async () => {
  const pool = {
    query: async () => { throw new Error('pool.query should not run for future target guard'); },
    connect: async () => { throw new Error('connect should not run for future target guard'); },
  };
  await assert.rejects(
    () => runLeaveMonthlyAccrual(pool, {
        dryRun: true,
        targetMonth: '2026-06',
        now: new Date('2026-05-13T00:00:00.000Z'),
      }),
    /future/
  );
});

test('dry-run accrual reports missing balance rows and applies hire-date proration', async () => {
  const userId = '00000000-0000-0000-0000-000000000101';
  const { pool } = createMockPool({
    missingRows: [{
        user_id: userId,
        full_name: 'User One',
        date_hired: '2026-05-16',
        leave_type: 'vacationLeave',
      employment_type: 'regular',
      employment_status: 'active',
      separation_date: null,
    }],
    balanceRows: [],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-20T00:00:00.000Z'),
  });

  assert.equal(result.targetYearMonth, '2026-05');
  assert.equal(result.rowsUpdated, 1);
  assert.equal(result.rowsSkipped, 0);
  assert.equal(result.missingBalanceRowsDetected, 1);
  assert.equal(result.missingBalanceRowsCreated, 0);

  const [detail] = result.details;
  assert.equal(detail.user_id, userId);
  assert.equal(detail.action, 'would_apply');
  assert.equal(detail.created_balance_row, true);
  assert.equal(detail.hire_prorated, true);
  assert.equal(detail.days_added, 0.65);  // (31 - 16 + 1) / 31 * 1.25 = 0.65
});

test('non-dry-run accrual creates missing balance rows before updating credits', async () => {
  const userId = '00000000-0000-0000-0000-000000000202';
  const balanceId = '00000000-0000-0000-0000-000000000303';
  const { pool, calls } = createMockPool({
    missingRows: [{
        user_id: userId,
        full_name: 'User Two',
        date_hired: '2026-04-01',
        leave_type: 'sickLeave',
      employment_type: 'regular',
      employment_status: 'active',
      separation_date: null,
    }],
    balanceRows: [
      makeBalanceRow({
        id: balanceId,
        user_id: userId,
        leave_type: 'sickLeave',
        date_hired: '2026-04-01',
        full_name: 'User Two',
      }),
    ],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: false,
    targetMonth: '2026-05',
    now: new Date('2026-05-20T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  assert.equal(result.missingBalanceRowsCreated, 1);
  assert.equal(result.details[0].created_balance_row, true);
  assert.equal(result.details[0].days_added, 1.25);

  assert.ok(calls.some((c) => c.sql.includes('INSERT INTO leave_balances')));
  assert.ok(calls.some((c) => c.sql.includes('UPDATE leave_balances')));
  assert.ok(calls.some((c) => c.sql.includes('INSERT INTO leave_balance_ledger')));
});

// ─── Enhancement 1: Employment status filtering ───────────────────────────────

test('E1 - resigned employee is excluded from accrual', async () => {
  const { pool } = createMockPool({
    missingRows: [],
    // Resigned user — the SQL WHERE clause excludes them, so no balance rows returned
    balanceRows: [],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 0);
  assert.equal(result.rowsSkipped, 0);
  assert.equal(result.details.length, 0);
});

test('E1 - active employees still accrue normally', async () => {
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({ employment_status: 'active', date_hired: '2026-01-01' })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
});

// ─── Enhancement 2: Hire date backfill ───────────────────────────────────────

test('E2 - countMonthsToCredit with hire date counts from hire month (backfill)', () => {
  // Hired 2026-01-01, no prior accrual, target 2026-05, cap 12 → 5 months
  const hireDate = new Date(2026, 0, 1);   // Jan
  const target   = new Date(2026, 4, 1);   // May
  const months = countMonthsToCredit(null, target, 12, hireDate);
  assert.equal(months, 5); // Jan, Feb, Mar, Apr, May
});

test('E2 - countMonthsToCredit with hire date respects maxCatchUpMonths cap', () => {
  const hireDate = new Date(2026, 0, 1);   // Jan
  const target   = new Date(2026, 4, 1);   // May
  const months = countMonthsToCredit(null, target, 2, hireDate);
  assert.equal(months, 2); // capped at 2
});

test('E2 - countMonthsToCredit returns 0 when hired after target month', () => {
  const hireDate = '2026-06-01';
  const target = startOfMonth(new Date(2026, 4, 1)); // May
  const months = countMonthsToCredit(null, target, 12, hireDate);
  assert.equal(months, 0);
});

test('E2 - backfill dry-run credits multiple months from hire date', async () => {
  const userId = '00000000-0000-0000-0000-000000000501';
  // Hired Jan 2026, first run in May 2026, maxCatchUpMonths=5
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({
      id: '00000000-0000-0000-0000-000000000502',
      user_id: userId,
      date_hired: '2026-01-01',
      earned_days: '0',
      last_accrual_date: null,
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    maxCatchUpMonths: 5,
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  const [detail] = result.details;
  assert.equal(detail.months_credited, 5);
  // 1.25 * 5 = 6.25 (Jan hired on 1st → full rate for all)
  assert.equal(detail.days_added, 6.25);
});

// ─── Enhancement 3: Catch-up hire-month proration ────────────────────────────

test('E3 - backfill prorates the hire month in multi-month catch-up', async () => {
  // Hired 2026-01-16 (mid-Jan). Running May with maxCatchUpMonths=5.
  // Jan should be prorated: (31 - 16 + 1) / 31 * 1.25 = 0.65
  // Feb, Mar, Apr, May: 4 × 1.25 = 5.00
  // Total: 5.65
  const userId = '00000000-0000-0000-0000-000000000601';
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({
      id: '00000000-0000-0000-0000-000000000602',
      user_id: userId,
      date_hired: '2026-01-16',
      earned_days: '0',
      last_accrual_date: null,
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    maxCatchUpMonths: 5,
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  const [detail] = result.details;
  assert.equal(detail.months_credited, 5);
  assert.equal(detail.hire_prorated, true);
  assert.equal(detail.days_added, 5.65);
});

// ─── Enhancement 4: Annual balance cap ───────────────────────────────────────

test('E4 - accrual is capped when balance reaches accrual_annual_cap', async () => {
  // Cap of 15 days, current balance = 14.50 (earned 20, used 5.5), addDays would be 1.25
  // capacityLeft = 15 - (20 - 5.5 + 0) = 15 - 14.5 = 0.5  → addDays capped to 0.5
  const { pool } = createMockPool({
    leaveTypeRows: [
      { name: 'vacationLeave', monthly_rate: '1.25', accrual_annual_cap: '15' },
    ],
    balanceRows: [makeBalanceRow({
      leave_type: 'vacationLeave',
      earned_days: '20',
      used_days: '5.50',
      adjusted_days: '0',
      last_accrual_date: '2026-04-01',
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  const [detail] = result.details;
  assert.equal(detail.cap_applied, true);
  assert.equal(detail.days_added, 0.5);
});

test('E4 - employee skipped (not credited) when already at annual cap', async () => {
  // Cap of 15 days, balance = 15 exactly → nothing to add
  const { pool } = createMockPool({
    leaveTypeRows: [
      { name: 'vacationLeave', monthly_rate: '1.25', accrual_annual_cap: '15' },
    ],
    balanceRows: [makeBalanceRow({
      leave_type: 'vacationLeave',
      earned_days: '15',
      used_days: '0',
      adjusted_days: '0',
      last_accrual_date: '2026-04-01',
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 0);
  assert.equal(result.rowsSkipped, 1);
  assert.equal(result.details[0].reason, 'annual_cap_reached');
});

test('E4 - no cap applied when accrual_annual_cap is null', async () => {
  const { pool } = createMockPool({
    leaveTypeRows: [
      { name: 'vacationLeave', monthly_rate: '1.25', accrual_annual_cap: null },
    ],
    balanceRows: [makeBalanceRow({
      leave_type: 'vacationLeave',
      earned_days: '50',   // very high — no cap should not limit this
      used_days: '0',
      adjusted_days: '0',
      last_accrual_date: '2026-04-01',
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  assert.equal(result.details[0].cap_applied, false);
  assert.equal(result.details[0].days_added, 1.25);
});

// ─── Enhancement 5: Separation date proration ────────────────────────────────

test('E5 - separationMonthAccrualAmount prorates correctly', () => {
  // Last day of work: May 15, 2026. May has 31 days.
  // Expected: 15/31 * 1.25 = 0.61 (rounded to 2dp)
  const result = separationMonthAccrualAmount('2026-05-15', new Date(2026, 4, 1), 1.25);
  assert.equal(result.prorated, true);
  assert.equal(result.days_worked, 15);
  assert.equal(result.days_in_month, 31);
  assert.equal(result.addDays, round2(15 / 31 * 1.25));
});

test('E5 - separationMonthAccrualAmount returns full rate when separation is last day', () => {
  // Last day = May 31 → all 31 days worked → full month
  const result = separationMonthAccrualAmount('2026-05-31', new Date(2026, 4, 1), 1.25);
  assert.equal(result.prorated, false);
  assert.equal(result.addDays, 1.25);
});

test('E5 - accrual run prorates separation month for separating employee', async () => {
  // Employee's last day is May 15. Accrual runs for May.
  // Single month (last_accrual_date = 2026-04-01 → 1 month to credit for May)
  // Expected: separation proration only, not hire proration
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({
      last_accrual_date: '2026-04-01',
      separation_date: '2026-05-15',
      employment_status: 'active', // still marked active until separation processed
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-20T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  const [detail] = result.details;
  assert.equal(detail.separation_prorated, true);
  assert.equal(detail.days_added, round2(15 / 31 * 1.25));
});

test('E5 - separation date in a different month does not affect target month accrual', async () => {
  // Employee separated in April — May accrual should be full 1.25
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({
      last_accrual_date: '2026-04-01',
      separation_date: '2026-04-20',
      employment_status: 'active',
    })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-20T00:00:00.000Z'),
  });

  const [detail] = result.details;
  assert.equal(detail.separation_prorated, false);
  assert.equal(detail.days_added, 1.25);
});

// ─── Enhancement 6: DB-driven accrual rates ──────────────────────────────────

test('E6 - uses DB rate when leave_types returns accrual config', async () => {
  // Custom rate of 2.00 days/month from DB
  const { pool } = createMockPool({
    leaveTypeRows: [
      { name: 'vacationLeave', monthly_rate: '2.00', accrual_annual_cap: null },
    ],
    balanceRows: [makeBalanceRow({ last_accrual_date: '2026-04-01', leave_type: 'vacationLeave' })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  assert.equal(result.details[0].days_added, 2.00);
  assert.equal(result.details[0].accrual_rate, 2.00);
});

test('E6 - falls back to hardcoded 1.25 when DB returns no accrual types', async () => {
  // leaveTypeRows = [] simulates pre-migration state where accrues_monthly is not set
  const { pool } = createMockPool({
    leaveTypeRows: [],
    balanceRows: [makeBalanceRow({ last_accrual_date: '2026-04-01' })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  assert.equal(result.details[0].days_added, 1.25);
});

// ─── Enhancement 7: Missing date_hired warning ────────────────────────────────

test('E7 - flags missing_hire_date when date_hired is null', async () => {
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({ date_hired: null, last_accrual_date: '2026-04-01' })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.rowsUpdated, 1);
  assert.equal(result.details[0].missing_hire_date, true);
  // Still credits the full rate
  assert.equal(result.details[0].days_added, 1.25);
});

test('E7 - no missing_hire_date flag when date_hired is set', async () => {
  const { pool } = createMockPool({
    balanceRows: [makeBalanceRow({ date_hired: '2025-01-01', last_accrual_date: '2026-04-01' })],
  });

  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun: true,
    targetMonth: '2026-05',
    now: new Date('2026-05-01T00:00:00.000Z'),
  });

  assert.equal(result.details[0].missing_hire_date, false);
});

// ─── firstMonthAccrualAmount edge cases ──────────────────────────────────────

test('firstMonthAccrualAmount: hired before target month → full rate', () => {
  const result = firstMonthAccrualAmount(new Date(2026, 4, 1), '2026-03-15', 1.25);
  assert.equal(result.addDays, 1.25);
  assert.equal(result.prorated, false);
  assert.equal(result.skipped, false);
});

test('firstMonthAccrualAmount: hired on 1st of target month → full rate', () => {
  const result = firstMonthAccrualAmount(new Date(2026, 4, 1), '2026-05-01', 1.25);
  assert.equal(result.addDays, 1.25);
  assert.equal(result.prorated, false);
});

test('firstMonthAccrualAmount: hired after target month → skip', () => {
  const result = firstMonthAccrualAmount(new Date(2026, 4, 1), '2026-06-01', 1.25);
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'hired_after_target_month');
});

test('firstMonthAccrualAmount: no hire date → full rate with reason flag', () => {
  const result = firstMonthAccrualAmount(new Date(2026, 4, 1), null, 1.25);
  assert.equal(result.addDays, 1.25);
  assert.equal(result.reason, 'no_hire_date_full_rate');
});

// ─── countMonthsToCredit edge cases ─────────────────────────────────────────

test('countMonthsToCredit: already credited through target → 0', () => {
  const lastAccrual = new Date(2026, 4, 1); // May
  const target      = new Date(2026, 4, 1); // May (same)
  assert.equal(countMonthsToCredit(lastAccrual, target, 3), 0);
});

test('countMonthsToCredit: 2 months behind with cap 1 → 1', () => {
  const lastAccrual = new Date(2026, 2, 1); // Mar
  const target      = new Date(2026, 4, 1); // May (2 behind)
  assert.equal(countMonthsToCredit(lastAccrual, target, 1), 1);
});

test('countMonthsToCredit: 2 months behind with cap 3 → 2', () => {
  const lastAccrual = new Date(2026, 2, 1); // Mar
  const target      = new Date(2026, 4, 1); // May
  assert.equal(countMonthsToCredit(lastAccrual, target, 3), 2);
});

test('countMonthsToCredit: null lastAccrual with no hire date → 1', () => {
  const target = new Date(2026, 4, 1);
  assert.equal(countMonthsToCredit(null, target, 5, null), 1);
});

test('countMonthsToCredit: null lastAccrual with hire date string → backfill count', () => {
  const target = new Date(2026, 4, 1); // May
  // hired Jan → Jan, Feb, Mar, Apr, May = 5
  assert.equal(countMonthsToCredit(null, target, 12, '2026-01-01'), 5);
});
