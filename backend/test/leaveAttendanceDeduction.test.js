const test = require('node:test');
const assert = require('node:assert/strict');

const {
  runMonthlyAttendanceDeductions,
  equivalentDaysFromMinutes,
  expectedMinutesForCoverage,
  desiredPosting,
} = require('../src/services/leaveAttendanceDeduction');

const USER_ID = '00000000-0000-0000-0000-000000000101';

function summary(computedDays) {
  return {
    user_id: USER_ID,
    employee_name: 'Test User',
    leave_type: 'vacationLeave',
    service_month: '2026-05-01',
    late_minutes: 0,
    undertime_minutes: Math.round(computedDays * 480),
    absence_minutes: 0,
    total_deduction_minutes: Math.round(computedDays * 480),
    computed_days: computedDays,
    source_record_count: 1,
    synthetic_absence_count: 0,
  };
}

function createPostingPool() {
  const state = {
    used: 0,
    posting: null,
    ledgerRows: 0,
    ledgerActions: [],
  };

  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text.trim())) {
        return { rows: [], rowCount: 0 };
      }
      if (text.includes('INSERT INTO leave_attendance_deductions')) {
        const created = state.posting == null;
        state.posting ??= {
          id: '00000000-0000-0000-0000-000000000202',
          computed_days: 0,
          deducted_days: 0,
          without_pay_days: 0,
        };
        return { rows: created ? [{ id: state.posting.id }] : [], rowCount: created ? 1 : 0 };
      }
      if (
        text.includes('FROM leave_attendance_deductions') &&
        text.includes('SELECT id')
      ) {
        return {
          rows: state.posting ? [{ ...state.posting }] : [],
          rowCount: state.posting ? 1 : 0,
        };
      }
      if (text.includes('INSERT INTO leave_balances')) {
        return { rows: [], rowCount: 0 };
      }
      if (
        text.includes('FROM leave_balances') &&
        text.includes('earned_days')
      ) {
        return {
          rows: [{
            earned_days: '2.000',
            used_days: state.used.toFixed(3),
            pending_days: '0.000',
            adjusted_days: '0.000',
          }],
          rowCount: 1,
        };
      }
      if (text.includes('UPDATE leave_balances')) {
        state.used = Number(params[2]);
        return { rows: [], rowCount: 1 };
      }
      if (text.includes('UPDATE leave_attendance_deductions')) {
        state.posting = {
          ...state.posting,
          computed_days: Number(params[6]),
          deducted_days: Number(params[7]),
          without_pay_days: Number(params[8]),
        };
        return { rows: [], rowCount: 1 };
      }
      if (text.includes('INSERT INTO leave_balance_ledger')) {
        state.ledgerRows += 1;
        state.ledgerActions.push(params[2]);
        return { rows: [], rowCount: 1 };
      }
      throw new Error(`Unexpected client query: ${text.slice(0, 100)}`);
    },
    release() {},
  };

  return {
    state,
    pool: {
      async query() {
        return { rows: [], rowCount: 0 };
      },
      async connect() {
        return client;
      },
    },
  };
}

test('equivalent day conversion preserves three-decimal DTR values', () => {
  assert.equal(equivalentDaysFromMinutes(75, 8), 0.156);
  assert.equal(equivalentDaysFromMinutes(480, 8), 1);
  assert.equal(equivalentDaysFromMinutes(0, 8), 0);
});

test('partial holiday coverage removes only the covered shift session', () => {
  const assignment = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };
  assert.equal(expectedMinutesForCoverage(assignment, 'whole_day'), 0);
  assert.equal(expectedMinutesForCoverage(assignment, 'am_only'), 240);
  assert.equal(expectedMinutesForCoverage(assignment, 'pm_only'), 240);
});

test('DTR posting uses available Vacation Leave and records the excess separately', () => {
  const result = desiredPosting(
    summary(1),
    null,
    { earned: 0.25, used: 0, pending: 0, adjusted: 0 }
  );
  assert.equal(result.deducted, 0.25);
  assert.equal(result.withoutPay, 0.75);
  assert.equal(result.delta, 0.25);
});

test('corrected DTR posts only the difference from the prior month posting', () => {
  const result = desiredPosting(
    summary(0.25),
    { deducted_days: 0.5 },
    { earned: 2, used: 0.5, pending: 0, adjusted: 0 }
  );
  assert.equal(result.deducted, 0.25);
  assert.equal(result.delta, -0.25);
});

test('month-end DTR posting is idempotent on rerun', async () => {
  const { pool, state } = createPostingPool();
  const options = {
    targetMonth: '2026-05',
    now: new Date('2026-06-01T00:00:00.000Z'),
    summaries: [summary(0.25)],
  };

  const first = await runMonthlyAttendanceDeductions(pool, options);
  const second = await runMonthlyAttendanceDeductions(pool, options);

  assert.equal(first.rowsUpdated, 1);
  assert.equal(first.details[0].action, 'applied');
  assert.equal(second.rowsUpdated, 0);
  assert.equal(second.details[0].reason, 'already_posted');
  assert.equal(state.used, 0.25);
  assert.equal(state.ledgerRows, 1);
});

test('corrected month-end DTR creates a correction ledger movement', async () => {
  const { pool, state } = createPostingPool();
  const options = {
    targetMonth: '2026-05',
    now: new Date('2026-06-01T00:00:00.000Z'),
  };

  await runMonthlyAttendanceDeductions(pool, {
    ...options,
    summaries: [summary(0.5)],
  });
  const corrected = await runMonthlyAttendanceDeductions(pool, {
    ...options,
    summaries: [summary(0.25)],
  });

  assert.equal(corrected.details[0].action, 'adjusted');
  assert.equal(corrected.details[0].balance_delta, -0.25);
  assert.equal(state.used, 0.25);
  assert.deepEqual(state.ledgerActions, [
    'attendance_deduction',
    'attendance_deduction_adjusted',
  ]);
});

test('month-end DTR posting rejects current-month processing', async () => {
  const pool = {
    query: async () => {
      throw new Error('database should not be queried');
    },
    connect: async () => {
      throw new Error('database should not be connected');
    },
  };
  await assert.rejects(
    () =>
      runMonthlyAttendanceDeductions(pool, {
        targetMonth: '2026-06',
        now: new Date('2026-06-15T00:00:00.000Z'),
        summaries: [],
      }),
    /completed month/
  );
});
