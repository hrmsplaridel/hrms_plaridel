'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
const {
  applyRosterShift,
  loadRosterShifts,
  rosterShiftFromRow,
} = require('../src/services/employeeScheduleOverrides');

const EMP = '11111111-1111-4111-8111-111111111111';
const NIGHT = '22222222-2222-4222-8222-222222222222';
const MORNING = '33333333-3333-4333-8333-333333333333';
const DATE = '2026-12-02';

const nightRow = {
  roster_shift_id: NIGHT,
  roster_shift_name: 'Night duty',
  roster_start_time: '22:00:00',
  roster_end_time: '06:00:00',
  roster_break_start: null,
  roster_break_end: null,
  roster_punch_mode: 'single_session',
  roster_grace_period_minutes: 5,
  roster_capture_window_minutes: 120,
  roster_flexi_latest_start: null,
};

const regular = {
  departmentId: 'dept-hospital',
  shiftId: MORNING,
  startMinutes: 480,
  endMinutes: 1020,
  breakStartMinutes: 720,
  breakEndMinutes: 780,
  graceMinutes: 0,
  punchMode: 'full_day',
  workingDays: [1, 2, 3, 4, 5],
};

test('roster rows map to shift settings', () => {
  const roster = rosterShiftFromRow(nightRow);
  assert.equal(roster.shiftId, NIGHT);
  assert.equal(roster.startMinutes, 1320);
  assert.equal(roster.endMinutes, 360);
  assert.equal(roster.punchMode, 'single_session');
  assert.equal(roster.graceMinutes, 5);
  assert.equal(rosterShiftFromRow({ roster_shift_id: null }), null);
});

test('a rostered day replaces the regular shift but keeps the assignment context', () => {
  const day = applyRosterShift(regular, rosterShiftFromRow(nightRow));
  assert.equal(day.shiftId, NIGHT);
  assert.equal(day.rosterShiftId, NIGHT);
  assert.equal(day.startMinutes, 1320);
  assert.equal(day.endMinutes, 360);
  assert.equal(day.breakEndMinutes, null);
  assert.equal(day.punchMode, 'single_session');
  assert.equal(day.isWorkingDay, true);
  assert.equal(day.departmentId, 'dept-hospital');
  assert.equal(regular.startMinutes, 480, 'input must not be mutated');
  assert.equal(applyRosterShift(regular, null), regular);
});

test('roster shifts load per employee and date', async () => {
  let captured = null;
  const map = await loadRosterShifts(
    { query: async (sql, params) => { captured = { sql, params }; return { rows: [{ employee_id: EMP, schedule_date: DATE, ...nightRow }] }; } },
    [EMP], DATE, DATE
  );
  assert.match(captured.sql, /employee_schedule_overrides/);
  assert.match(captured.sql, /shift_id IS NOT NULL/);
  assert.equal(map.get(`${EMP}|${DATE}`).shiftId, NIGHT);
  assert.equal((await loadRosterShifts(null, [EMP], DATE, DATE)).size, 0);
});

test('report shift resolver uses the roster for that date', () => {
  const { getShiftInfoForDateFromAssignments } = require('../src/modules/dtr/services/shifts')({
    computeTotalHoursFromRecord: () => 0,
    getExpectedLogsForDay: () => [],
    getShiftExpectedLogs: () => [],
    resolveExpectedWorkMinutes: () => 0,
    resolveShiftType: () => 'full_day',
  });
  const assignments = new Map([[EMP, [{ ...regular, effective_from: '2026-01-01', effective_to: null }]]]);
  assignments.rosterByKey = new Map([[`${EMP}|${DATE}`, rosterShiftFromRow(nightRow)]]);
  assert.equal(getShiftInfoForDateFromAssignments(assignments, EMP, DATE).shiftId, NIGHT);
  assert.equal(getShiftInfoForDateFromAssignments(assignments, EMP, '2026-12-03').shiftId, MORNING);
});

function dtrAssignmentsRepo(rowsByQuery) {
  return require('../src/modules/dtr/repositories/assignments')({
    pool: {
      query: async (sql) => {
        for (const [pattern, rows] of rowsByQuery) {
          if (pattern.test(String(sql))) return { rows };
        }
        return { rows: [] };
      },
    },
    resolvedWorkingDay: () => false,
    timeToMinutes: (value) => {
      if (!value) return null;
      const [h, m] = String(value).split(':').map(Number);
      return h * 60 + m;
    },
  });
}

test('DTR single-date shift lookup applies the roster unless a saved snapshot exists', async () => {
  const base = {
    shift_snapshot: null, department_id: 'dept-hospital', shift_id: MORNING,
    shift_start: '08:00:00', shift_end: '17:00:00', shift_break_end: '13:00:00',
    punch_mode: 'full_day', grace_period_minutes: 0, working_days: [1, 2, 3, 4, 5],
  };
  const rostered = await dtrAssignmentsRepo([[/saved\.shift_snapshot/, [{ ...base, ...nightRow }]]])
    .getAssignmentShiftForDate(EMP, DATE);
  assert.equal(rostered.shiftId, NIGHT);
  assert.equal(rostered.startMinutes, 1320);
  assert.equal(rostered.isWorkingDay, true);
  assert.equal(rostered.departmentId, 'dept-hospital');

  const snapshot = { shiftId: MORNING, startMinutes: 480 };
  const saved = await dtrAssignmentsRepo([[/saved\.shift_snapshot/, [{ ...base, ...nightRow, shift_snapshot: snapshot }]]])
    .getAssignmentShiftForDate(EMP, DATE);
  assert.deepEqual(saved, snapshot);
});

test('DTR range loader attaches roster shifts for the report', async () => {
  const repo = dtrAssignmentsRepo([
    [/FROM assignments a/, [{
      id: 'assignment-1', employee_id: EMP, start_time: '08:00:00', end_time: '17:00:00',
      break_end: '13:00:00', effective_from: '2026-01-01', punch_mode: 'full_day',
    }]],
    [/FROM employee_schedule_overrides/, [{ employee_id: EMP, schedule_date: DATE, ...nightRow }]],
  ]);
  const map = await repo.getAssignmentsForEmployeesInRange([EMP], DATE, DATE);
  assert.equal(map.rosterByKey.get(`${EMP}|${DATE}`).shiftId, NIGHT);
});

test('month-end deductions resolve the rostered shift', () => {
  const { assignmentForDate } = require('../src/services/leaveAttendanceDeduction');
  const map = new Map([[EMP, [{ ...regular, effectiveFrom: '2026-01-01', effectiveTo: null }]]]);
  map.rosterByKey = new Map([[`${EMP}|${DATE}`, rosterShiftFromRow(nightRow)]]);
  assert.equal(assignmentForDate(map, EMP, DATE).shiftId, NIGHT);
  assert.equal(assignmentForDate(map, EMP, '2026-12-03').shiftId, MORNING);
});

test('bulk report schedule overrides carry the rostered shift', () => {
  const { scheduleOverridesForEmployee } = require('../src/modules/dtr/serializers/assignments')({});
  const overrides = new Map([[`${EMP}|${DATE}`, true], [`${EMP}|2026-12-05`, false]]);
  const roster = new Map([[`${EMP}|${DATE}`, rosterShiftFromRow(nightRow)]]);
  const rows = scheduleOverridesForEmployee(overrides, EMP, { effective_from: '2026-01-01' }, roster);
  assert.deepEqual(rows[0], {
    date: DATE, is_working_day: true, shift_id: NIGHT, shift_name: 'Night duty',
    start_time: '22:00:00', end_time: '06:00:00',
  });
  assert.deepEqual(rows[1], { date: '2026-12-05', is_working_day: false });
});

test('shifts used by a duty roster cannot be deleted or deactivated', () => {
  const {
    SHIFT_DELETE_DEPENDENCIES,
    shiftDeactivationCountsSql,
    shiftDeactivationCountsFromRow,
  } = require('../src/services/shiftLifecycle');
  assert.ok(SHIFT_DELETE_DEPENDENCIES.some(
    (d) => d.table === 'employee_schedule_overrides' && d.column === 'shift_id'
  ));
  assert.match(shiftDeactivationCountsSql(), /employee_schedule_overrides/);
  assert.equal(shiftDeactivationCountsFromRow({ deactivation_roster_days: 2 }).roster_days, 2);
});

// --- Weekly schedule API ---------------------------------------------------

const WEEK = '2026-11-30';

function responseRecorder() {
  return {
    statusCode: 200,
    payload: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.payload = body; return this; },
  };
}

async function withWeeklyRoute(pool, callback) {
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/weeklySchedules';
  clearModule(routePath);
  try {
    const router = require(routePath);
    const handler = (method, path) => {
      const layer = router.stack.find((e) => e.route?.path === path && e.route.methods[method]);
      return layer.route.stack.at(-1).handle;
    };
    await callback(handler);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
}

function putClient({ activeShifts = [NIGHT], existing = null, dtrExists = false } = {}) {
  const queries = [];
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/FROM users WHERE id/i.test(text)) return { rowCount: 1, rows: [{ id: EMP, full_name: 'Nurse' }] };
      if (/FROM shifts\s+WHERE id = ANY/i.test(text)) {
        return { rows: params[0].filter((id) => activeShifts.includes(id)).map((id) => ({ id })) };
      }
      if (/FROM assignments a/i.test(text)) return { rowCount: 1, rows: [{ working_days: [1, 2, 3, 4, 5] }] };
      if (/SELECT is_working_day, shift_id\s+FROM employee_schedule_overrides/i.test(text)) {
        return { rowCount: existing ? 1 : 0, rows: existing ? [existing] : [] };
      }
      if (/FROM dtr_daily_summary/i.test(text)) return { rowCount: dtrExists ? 1 : 0, rows: dtrExists ? [{ id: 'dtr' }] : [] };
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  return { client, queries };
}

async function put(days, options) {
  const { client, queries } = putClient(options);
  const res = responseRecorder();
  await withWeeklyRoute({ connect: async () => client }, async (handler) => {
    await handler('put', '/:employeeId/:weekStart')(
      { user: { id: 'admin-1', role: 'admin' }, params: { employeeId: EMP, weekStart: WEEK }, body: { days } },
      res
    );
  });
  return { res, queries };
}

test('PUT saves a duty shift for a day as a working day', async () => {
  const { res, queries } = await put([{ date: DATE, is_working_day: null, shift_id: NIGHT }]);
  assert.equal(res.statusCode, 200);
  const insert = queries.find(({ sql }) => /INSERT INTO employee_schedule_overrides/.test(sql));
  assert.match(insert.sql, /shift_id/);
  assert.deepEqual(insert.params.slice(0, 4), [EMP, DATE, true, NIGHT]);
  const audit = queries.find(({ sql }) => /INSERT INTO audit_logs/.test(sql));
  assert.equal(JSON.parse(audit.params[2]).days[0].shift_id, NIGHT);
});

test('PUT clearing the duty shift on a default day removes the override', async () => {
  const { res, queries } = await put(
    [{ date: DATE, is_working_day: null, shift_id: null }],
    { existing: { is_working_day: true, shift_id: NIGHT } }
  );
  assert.equal(res.statusCode, 200);
  assert.ok(queries.some(({ sql }) => /DELETE FROM employee_schedule_overrides/.test(sql)));
});

test('PUT without shift_id keeps the existing duty shift', async () => {
  const { res, queries } = await put(
    [{ date: DATE, is_working_day: true }],
    { existing: { is_working_day: true, shift_id: NIGHT } }
  );
  assert.equal(res.statusCode, 200);
  const insert = queries.find(({ sql }) => /INSERT INTO employee_schedule_overrides/.test(sql));
  assert.equal(insert.params[3], NIGHT);
});

for (const [label, days, options, status] of [
  ['an inactive or unknown shift', [{ date: DATE, is_working_day: null, shift_id: MORNING }], {}, 400],
  ['a malformed shift id', [{ date: DATE, is_working_day: null, shift_id: 'night' }], {}, 400],
  ['a duty shift on a rest day', [{ date: DATE, is_working_day: false, shift_id: NIGHT }], {}, 400],
  ['changing the shift after attendance exists', [{ date: DATE, is_working_day: null, shift_id: NIGHT }],
    { dtrExists: true }, 409],
]) {
  test(`PUT rejects ${label}`, async () => {
    const { res, queries } = await put(days, options);
    assert.equal(res.statusCode, status);
    assert.equal(queries.some(({ sql }) => /INSERT INTO employee_schedule_overrides/.test(sql)), false);
  });
}

test('GET returns the rostered shift for each day', async () => {
  const rows = [{
    employee_id: EMP, employee_number: 7, full_name: 'Nurse', schedule_date: DATE,
    department_id: 'dept-hospital', department_name: 'Hospital', shift_id: MORNING,
    shift_name: 'Morning', start_time: '08:00:00', end_time: '17:00:00',
    working_days: [1, 2, 3, 4, 5], override_is_working_day: true,
    roster_shift_id: NIGHT, roster_shift_name: 'Night duty',
    roster_start_time: '22:00:00', roster_end_time: '06:00:00',
  }];
  let sqlText = '';
  const res = responseRecorder();
  await withWeeklyRoute({ query: async (sql) => { sqlText = String(sql); return { rows }; } }, async (handler) => {
    await handler('get', '/')({ user: { role: 'admin' }, query: { week_start: WEEK } }, res);
  });
  assert.equal(res.statusCode, 200);
  assert.match(sqlText, /eso\.shift_id/);
  const day = res.payload.employees[0].days[0];
  assert.equal(day.roster_shift_id, NIGHT);
  assert.equal(day.roster_shift_name, 'Night duty');
  assert.equal(day.roster_start_time, '22:00:00');
  assert.equal(day.shift_id, MORNING);
});
