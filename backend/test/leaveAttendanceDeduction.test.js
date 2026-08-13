const test = require('node:test');
const assert = require('node:assert/strict');

const {
  runMonthlyAttendanceDeductions,
  calculateMonthlyAttendanceDeductions,
  equivalentDaysFromMinutes,
  expectedMinutesForCoverage,
  desiredPosting,
  assignmentForDate,
  hasPhysicalDtrPunches,
  expectedLocatorSlotsForAssignment,
  locatorCoversExpectedShiftSlots,
  loadAssignments,
  loadEmployees,
  loadFullLocatorKeys,
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

test('month-end distinguishes locator-only dates from dates with physical punches', () => {
  assert.equal(hasPhysicalDtrPunches({}), false);
  assert.equal(hasPhysicalDtrPunches({ time_in: null, time_out: null }), false);
  assert.equal(
    hasPhysicalDtrPunches({ break_in: '2026-08-04T05:00:00.000Z' }),
    true
  );
});

function createPostingPool() {
  const state = {
    used: 0,
    posting: null,
    ledgerRows: 0,
    ledgerActions: [],
    locatorReconciliationClears: 0,
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
      if (text.includes('UPDATE locator_slips')) {
        state.locatorReconciliationClears += 1;
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

test('approved locator coverage follows the expected slots for each shift type', () => {
  const fullCoverage = {
    am_in: true,
    am_out: true,
    pm_in: true,
    pm_out: true,
  };
  const pmCoverage = {
    am_in: false,
    am_out: false,
    pm_in: true,
    pm_out: true,
  };
  const amCoverage = {
    am_in: true,
    am_out: true,
    pm_in: false,
    pm_out: false,
  };
  const singleSessionCoverage = {
    am_in: true,
    am_out: false,
    pm_in: false,
    pm_out: true,
  };

  assert.deepEqual(
    expectedLocatorSlotsForAssignment({ punchMode: 'full_day' }),
    ['am_in', 'am_out', 'pm_in', 'pm_out']
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(fullCoverage, { punchMode: 'full_day' }),
    true
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(pmCoverage, { punchMode: 'full_day' }),
    false
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(pmCoverage, { punchMode: 'pm_only' }),
    true
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(pmCoverage, {
      punchMode: 'auto',
      startMinutes: 18 * 60,
      endMinutes: 19 * 60,
    }),
    true,
    'an auto-mode 6 PM to 7 PM shift must require only PM locator slots'
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(amCoverage, { punchMode: 'am_only' }),
    true
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(singleSessionCoverage, {
      punchMode: 'single_session',
    }),
    true
  );
});

test('full locator keys use the assignment effective on the locator date', async () => {
  const client = {
    async query(sql) {
      assert.doesNotMatch(String(sql), /AND am_in = true/i);
      return {
        rows: [
          {
            employee_id: USER_ID,
            slip_date: '2026-06-10',
            am_in: false,
            am_out: false,
            pm_in: true,
            pm_out: true,
          },
          {
            employee_id: USER_ID,
            slip_date: '2026-06-20',
            am_in: false,
            am_out: false,
            pm_in: true,
            pm_out: true,
          },
        ],
      };
    },
  };
  const assignments = new Map([
    [
      USER_ID,
      [
        {
          effectiveFrom: '2026-06-16',
          effectiveTo: null,
          punchMode: 'full_day',
        },
        {
          effectiveFrom: '2026-06-01',
          effectiveTo: '2026-06-15',
          punchMode: 'pm_only',
        },
      ],
    ],
  ]);

  const keys = await loadFullLocatorKeys(
    client,
    [USER_ID],
    '2026-06-01',
    '2026-06-30',
    assignments
  );

  assert.equal(keys.has(`${USER_ID}|2026-06-10`), true);
  assert.equal(keys.has(`${USER_ID}|2026-06-20`), false);
});

test('full locator keys honor partial-holiday shift coverage', async () => {
  const client = {
    async query() {
      return {
        rows: [
          {
            employee_id: USER_ID,
            slip_date: '2026-06-10',
            am_in: false,
            am_out: false,
            pm_in: true,
            pm_out: true,
          },
        ],
      };
    },
  };
  const assignments = new Map([
    [
      USER_ID,
      [
        {
          effectiveFrom: '2026-06-01',
          effectiveTo: null,
          punchMode: 'full_day',
          workingDays: [1, 2, 3, 4, 5],
        },
      ],
    ],
  ]);

  const keys = await loadFullLocatorKeys(
    client,
    [USER_ID],
    '2026-06-01',
    '2026-06-30',
    assignments,
    new Map([['2026-06-10', 'am_only']])
  );

  assert.equal(keys.has(`${USER_ID}|2026-06-10`), true);
});

test('completed-month DTR processing includes closed historical assignments', async () => {
  const sqlCalls = [];
  const client = {
    async query(sql) {
      const text = String(sql);
      sqlCalls.push(text);
      if (text.includes('SELECT DISTINCT u.id AS user_id')) {
        return {
          rows: [{ user_id: USER_ID, full_name: 'Transferred Employee' }],
        };
      }
      if (text.includes('FROM assignments a')) {
        return {
          rows: [{
            employee_id: USER_ID,
            department_id: '00000000-0000-0000-0000-000000000301',
            shift_id: '00000000-0000-0000-0000-000000000401',
            effective_from: '2026-06-01',
            effective_to: '2026-06-30',
            start_time: '08:00:00',
            end_time: '17:00:00',
            break_end: '13:00:00',
            punch_mode: 'full_day',
            working_days: [1, 2, 3, 4, 5],
          }],
        };
      }
      throw new Error(`Unexpected query: ${text.slice(0, 80)}`);
    },
  };

  const employees = await loadEmployees(client, '2026-06-01', '2026-06-30');
  const assignments = await loadAssignments(
    client,
    [USER_ID],
    '2026-06-01',
    '2026-06-30'
  );

  assert.equal(employees.length, 1);
  assert.equal(assignmentForDate(assignments, USER_ID, '2026-06-16')?.startMinutes, 480);
  assert.equal(
    sqlCalls.some((sql) => /a\.is_active/i.test(sql)),
    false,
    'historical assignment queries must not filter out closed rows'
  );
});

test('month-end calculation never overlaps queries on one pg client', async () => {
  let activeQueries = 0;
  let maximumActiveQueries = 0;
  const client = {
    async query(sql) {
      activeQueries += 1;
      maximumActiveQueries = Math.max(maximumActiveQueries, activeQueries);
      try {
        await new Promise((resolve) => setImmediate(resolve));
        const text = String(sql);
        if (text.includes('FROM attendance_policies')) {
          return {
            rows: [{
              work_hours_per_day: 8,
              use_equivalent_day_conversion: true,
              deduct_late: true,
              deduct_undertime: true,
              absent_equals_full_day_deduction: true,
              deduction_multiplier: 1,
            }],
          };
        }
        return { rows: [], rowCount: 0 };
      } finally {
        activeQueries -= 1;
      }
    },
  };

  await calculateMonthlyAttendanceDeductions(
    client,
    new Date('2026-06-01T00:00:00.000Z'),
    {
      employees: [{ userId: USER_ID, employeeName: 'Test User' }],
    }
  );

  assert.equal(maximumActiveQueries, 1);
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
  assert.equal(first.locatorReconciliationsCleared, 1);
  assert.equal(state.locatorReconciliationClears, 2);
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
