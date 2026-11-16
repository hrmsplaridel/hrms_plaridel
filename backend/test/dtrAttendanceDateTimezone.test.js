'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const createUpdateControllers = require('../src/modules/dtr/controllers/update.controller');
const createRecalculateControllers = require('../src/modules/dtr/controllers/recalculate.controller');
const calendar = require('../src/modules/dtr/policies/calendar')({ HRMS_TIMEZONE: 'Asia/Manila' });
const { validateDtrPunchDates } = require('../src/services/dtrPunchDateValidation');
const { computeTotalHoursFromRecord, getShiftType } = require('../src/services/shiftAttendance');
const { computeTotalHours } = require('../src/modules/dtr/services/shifts')({ computeTotalHoursFromRecord });
const { dtrAuditSnapshot } = require('../src/modules/dtr/serializers/audit')(calendar);

const DATE = '2026-10-02';
const ID = '11111111-1111-4111-8111-111111111111';
const stamp = (time, date = DATE) => `${date}T${time}:00+08:00`;
const dayShift = {
  startMinutes: 480, endMinutes: 1020, breakStartMinutes: 720,
  breakEndMinutes: 780, graceMinutes: 0, punchMode: 'full_day',
};
const dayPunches = {
  time_in: stamp('08:00'), break_out: stamp('11:55'),
  break_in: stamp('12:50'), time_out: stamp('17:10'),
};

test.beforeEach(t => t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-11-16T04:00:00Z') }));

function fixture({ shift = dayShift, punches = dayPunches, covered = false, holiday = false } = {}) {
  const calls = [], lookups = [], broadcasts = [];
  let released = false;
  let row = {
    id: ID, employee_id: ID,
    // A PostgreSQL DATE decoded at midnight in a UTC+08 server timezone.
    attendance_date: new Date(`${DATE}T00:00:00+08:00`),
    attendance_date_iso: DATE, ...punches, shift_snapshot: null,
    total_hours: 8, late_minutes: 0, undertime_minutes: 0,
    status: 'present', source: 'system', holiday_id: null,
  };
  const query = async (sql, params = []) => {
    calls.push({ sql, params });
    if (sql.includes('SELECT d.*')) return { rows: [{ ...row }] };
    if (sql.includes('UPDATE dtr_daily_summary')) {
      for (const match of sql.matchAll(/\b([a-z_]+)\s*=\s*\$(\d+)/g)) {
        row[match[1]] = params[Number(match[2]) - 1];
      }
      return { rows: [{ ...row }] };
    }
    if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes('INSERT INTO audit_logs')) {
      return { rows: [] };
    }
    throw new Error(`Unexpected SQL: ${sql}`);
  };
  const dateLookup = (name, result) => async (_employeeId, date) => {
    lookups.push({ name, date });
    return typeof result === 'function' ? result(date) : result;
  };
  const dependencies = {
    ...calendar,
    HRMS_TIMEZONE: 'Asia/Manila',
    todayInHrmsTimezone: () => '2026-11-16',
    pool: { connect: async () => ({ query, release() { released = true; } }) },
    _holidaysHasCoverageColumn: async () => true,
    validateDtrPunchDates, computeTotalHours, computeTotalHoursFromRecord, dtrAuditSnapshot,
    resolveShiftType: getShiftType,
    getAssignmentShiftForDate: dateLookup('shift', shift),
    getApprovedLeaveCoverageForDate: dateLookup('leave', date => covered && date === DATE
      ? { leave_request_id: 'approved-leave' } : null),
    computeStatusFromShift: dateLookup('status', 'present'),
    computePmLateStatus: dateLookup('pm_status', 'present'),
    computeLateMinutes: dateLookup('late', 0),
    computeUndertimeMinutes: dateLookup('undertime', 0),
    applyAttendancePolicyPenalties: dateLookup('policy', { lateMinutes: 0, undertimeMinutes: 0 }),
    computeAttendanceRemark: async () => null,
    loadHolidayOverlayMap: async (_db, from, to) => {
      lookups.push({ name: 'holiday_from', date: from }, { name: 'holiday_to', date: to });
      return holiday && from === DATE && to === DATE
        ? new Map([[DATE, { id: 'holiday', coverage: 'whole_day', name: 'Local holiday' }]])
        : new Map();
    },
    broadcastBiometricUpdate: (...args) => broadcasts.push(args),
  };
  return {
    calls, lookups, broadcasts,
    get released() { return released; },
    async invoke(method, body = {}) {
      const res = {
        code: 200,
        status(code) { this.code = code; return this; },
        json(value) { this.body = value; return this; },
      };
      const handle = method === 'update'
        ? createUpdateControllers(dependencies).updateRecord
        : createRecalculateControllers(dependencies).recalculateRecord;
      await handle({ params: { id: ID }, user: { id: ID }, body }, res);
      return res;
    },
  };
}

function assertSavedOnAttendanceDate(f, res) {
  assert.equal(res.code, 200, res.body?.error);
  assert.equal(res.body.record_date, DATE);
  assert.ok(f.lookups.length > 0);
  for (const lookup of f.lookups) assert.equal(lookup.date, DATE, lookup.name);
  const audit = JSON.parse(f.calls.find(c => c.sql.includes('INSERT INTO audit_logs')).params[2]);
  assert.equal(audit.attendance_date, DATE);
  assert.equal(audit.before.attendance_date, DATE);
  assert.equal(audit.after.attendance_date, DATE);
  assert.equal(f.calls.some(c => c.sql === 'COMMIT'), true);
  assert.equal(f.calls.some(c => c.sql === 'ROLLBACK'), false);
  assert.equal(f.broadcasts.length, 1);
  assert.equal(f.broadcasts[0][1].date, DATE);
  assert.deepEqual(f.broadcasts[0][1].dates, [DATE]);
  assert.equal(f.released, true);
}

test('editing October 2 uses the stored calendar date when the Date object is October 1 in UTC', async () => {
  const f = fixture();
  const res = await f.invoke('update', { break_in: stamp('12:40') });
  assertSavedOnAttendanceDate(f, res);
  assert.equal(res.body.break_in, stamp('12:40'));
});

test('date normalization does not allow punches from the previous or following Manila date', async () => {
  for (const date of ['2026-10-01', '2026-10-03']) {
    const f = fixture();
    const res = await f.invoke('update', { time_in: stamp('08:00', date) });
    assert.equal(res.code, 400);
    assert.match(res.body.error, /Time In must belong to 2026-10-02 in Asia\/Manila/);
    assert.equal(f.calls.some(c => c.sql.includes('UPDATE dtr_daily_summary') || c.sql.includes('INSERT INTO audit_logs') || c.sql === 'COMMIT'), false);
    assert.equal(f.calls.some(c => c.sql === 'ROLLBACK'), true);
    assert.deepEqual(f.broadcasts, []);
    assert.equal(f.released, true);
  }
});

test('approved leave on the stored calendar date still blocks an ordinary edit', async () => {
  const f = fixture({ covered: true });
  const res = await f.invoke('update', { break_in: stamp('12:40') });
  assert.equal(res.code, 409);
  assert.equal(res.body.leave_request_id, 'approved-leave');
  assert.deepEqual(f.lookups, [{ name: 'leave', date: DATE }]);
  assert.equal(f.calls.some(c => c.sql === 'ROLLBACK'), true);
  assert.equal(f.calls.some(c => c.sql.includes('UPDATE dtr_daily_summary')), false);
});

test('overnight edits allow valid next-day punches while keeping the attendance date', async () => {
  const f = fixture({
    shift: { startMinutes: 1320, endMinutes: 360, punchMode: 'single_session', captureWindowMinutes: 120 },
    punches: { time_in: stamp('22:00'), break_out: null, break_in: null, time_out: stamp('06:00', '2026-10-03') },
  });
  const res = await f.invoke('update', { time_out: stamp('06:00', '2026-10-03') });
  assertSavedOnAttendanceDate(f, res);
  assert.equal(res.body.total_hours, 8);
});

test('recalculation uses the stored calendar date for holidays, audit, response, and refresh', async () => {
  const f = fixture({ holiday: true });
  const res = await f.invoke('recalculate');
  assertSavedOnAttendanceDate(f, res);
  assert.equal(res.body.status, 'holiday');
});
