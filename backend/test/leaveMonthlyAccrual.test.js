const test = require('node:test');
const assert = require('node:assert/strict');

const {
  runLeaveMonthlyAccrual,
  parseTargetMonth,
  monthStartInTimeZone,
} = require('../src/services/leaveMonthlyAccrual');

function createMockPool({ missingRows = [], balanceRows = [] } = {}) {
  const calls = [];
  const client = {
    query: async (sql, params = []) => {
      const text = String(sql);
      calls.push({ target: 'client', sql: text, params });

      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text)) {
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

      throw new Error(`Unexpected client query: ${text}`);
    },
    release: () => {
      calls.push({ target: 'client', sql: 'release', params: [] });
    },
  };

  const pool = {
    query: async (sql, params = []) => {
      calls.push({ target: 'pool', sql: String(sql), params });
      return { rows: [], rowCount: 0 };
    },
    connect: async () => client,
  };

  return { pool, calls };
}

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
    query: async () => {
      throw new Error('pool.query should not run for future target guard');
    },
    connect: async () => {
      throw new Error('connect should not run for future target guard');
    },
  };

  await assert.rejects(
    () =>
      runLeaveMonthlyAccrual(pool, {
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
    missingRows: [
      {
        user_id: userId,
        full_name: 'User One',
        date_hired: '2026-05-16',
        leave_type: 'vacationLeave',
      },
    ],
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
  assert.equal(detail.days_added, 0.65);
});

test('non-dry-run accrual creates missing balance rows before updating credits', async () => {
  const userId = '00000000-0000-0000-0000-000000000202';
  const balanceId = '00000000-0000-0000-0000-000000000303';
  const { pool, calls } = createMockPool({
    missingRows: [
      {
        user_id: userId,
        full_name: 'User Two',
        date_hired: '2026-04-01',
        leave_type: 'sickLeave',
      },
    ],
    balanceRows: [
      {
        id: balanceId,
        user_id: userId,
        full_name: 'User Two',
        date_hired: '2026-04-01',
        leave_type: 'sickLeave',
        earned_days: '0',
        last_accrual_date: null,
      },
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

  assert.equal(calls.some((call) => call.sql.includes('INSERT INTO leave_balances')), true);
  assert.equal(calls.some((call) => call.sql.includes('UPDATE leave_balances')), true);
  assert.equal(calls.some((call) => call.sql.includes('INSERT INTO leave_balance_ledger')), true);
});
