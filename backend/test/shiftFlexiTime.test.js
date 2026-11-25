const test = require('node:test');
const assert = require('node:assert/strict');

const shiftAttendance = require('../src/services/shiftAttendance');
const { isOvernight, overnightPenalties } = require('../src/services/shiftTimeline');
const { projectAttendanceCoverage } = require('../src/services/attendanceCoverageProjection');
const {
  SHIFT_SCHEDULE_FIELDS,
  changedShiftScheduleFields,
  ensureFlexiArrivalWindow,
  shiftAuditSnapshot,
} = require('../src/services/shiftLifecycle');
const createPenalties = require('../src/modules/dtr/services/penalties');

const { applyFlexiArrival, computeTotalHoursFromRecord } = shiftAttendance;

// 7:00 AM - 4:00 PM, lunch 12-1, arrival window 7:00 - 9:30 AM.
const flexi = {
  punchMode: 'full_day',
  startMinutes: 420,
  endMinutes: 960,
  breakStartMinutes: 720,
  breakEndMinutes: 780,
  graceMinutes: 0,
  flexiLatestStartMinutes: 570,
};
const DATE = '2026-03-02';
const at = (hhmm) => `${DATE}T${hhmm}:00+08:00`;

test('fixed shifts are returned unchanged', () => {
  const fixed = { ...flexi, flexiLatestStartMinutes: null };
  assert.equal(applyFlexiArrival(fixed, { timeIn: at('09:00') }), fixed);
});

test('arrival inside the window moves start and expected end together', () => {
  const day = applyFlexiArrival(flexi, { timeIn: at('09:00') });
  assert.equal(day.startMinutes, 540);
  assert.equal(day.endMinutes, 1080);
  assert.equal(day.breakStartMinutes, 720);
  assert.equal(day.breakEndMinutes, 780);
  assert.equal(flexi.startMinutes, 420, 'input must not be mutated');
});

test('arrival before the window keeps the earliest schedule', () => {
  assert.equal(applyFlexiArrival(flexi, { timeIn: at('06:40') }), flexi);
});

test('arrival after the window caps at the latest start', () => {
  const day = applyFlexiArrival(flexi, { timeIn: at('10:00') });
  assert.equal(day.startMinutes, 570);
  assert.equal(day.endMinutes, 1110);
});

test('missing arrival punch keeps the earliest schedule', () => {
  assert.equal(applyFlexiArrival(flexi, { timeIn: null }), flexi);
});

test('single-session flexi uses the first punch as arrival', () => {
  const session = { ...flexi, punchMode: 'single_session', breakStartMinutes: null, breakEndMinutes: null };
  assert.equal(applyFlexiArrival(session, { breakIn: at('08:00') }).startMinutes, 480);
});

test('worked hours follow the shifted window', () => {
  const record = {
    record_date: DATE, time_in: at('09:00'), break_out: at('12:00'),
    break_in: at('13:00'), time_out: at('18:00'),
  };
  assert.equal(computeTotalHoursFromRecord(record, flexi), 8);
});

function penalties(shiftInfo) {
  return createPenalties({
    ...shiftAttendance,
    minutesFromMidnightInTimeZone: (value) =>
      shiftAttendance.minutesFromMidnightInTimeZone(value, 'Asia/Manila'),
    getAssignmentShiftForDate: async () => shiftInfo,
    isOvernight,
    overnightPenalties,
    nowMinutesInHrmsTimezone: () => 0,
    todayInHrmsTimezone: () => '2026-12-31',
    resolveExpectedWorkMinutes: shiftAttendance.getExpectedWorkMinutes,
  });
}

for (const [label, timeIn, timeOut, late, undertime] of [
  ['earliest arrival, full hours', '07:00', '16:00', 0, 0],
  ['late in window, full hours', '09:00', '18:00', 0, 0],
  ['after window', '09:45', '18:45', 15, 0],
  ['short hours', '07:30', '15:30', 0, 60],
]) {
  test(`DTR penalties for flexi: ${label}`, async () => {
    const { computeLateMinutes, computeUndertimeMinutes, computeStatusFromShift } = penalties(flexi);
    const breakOut = at('12:00');
    const breakIn = at('13:00');
    assert.equal(
      await computeLateMinutes('e', DATE, at(timeIn), breakIn, 'present', null, null),
      late
    );
    assert.equal(
      await computeUndertimeMinutes('e', DATE, at(timeOut), breakOut, 'present', null, null,
        at(timeIn), breakIn),
      undertime
    );
    assert.equal(await computeStatusFromShift('e', DATE, at(timeIn)), late > 0 ? 'late' : 'present');
  });
}

test('locator projection assesses uncovered slots against the flexi schedule', async () => {
  const record = {
    record_date: DATE, status: 'present', source: 'system',
    time_in: at('09:00'), break_out: at('12:00'), break_in: at('13:00'), time_out: null,
  };
  const result = await projectAttendanceCoverage({
    record, date: DATE, shiftInfo: flexi,
    policy: { deductLate: true, deductUndertime: true, deductionMultiplier: 1 },
    locator: { pm_out: true },
  });
  assert.equal(result.late_minutes, 0);
  assert.equal(result.undertime_minutes, 0);
});

test('flexi arrival window validation', () => {
  const base = { startTime: '07:00', endTime: '16:00', breakStart: '12:00', breakEnd: '13:00', punchMode: 'full_day' };
  assert.equal(ensureFlexiArrivalWindow({ ...base, flexiLatestStart: null }), undefined);
  assert.doesNotThrow(() => ensureFlexiArrivalWindow({ ...base, flexiLatestStart: '09:30:00' }));
  for (const [overrides, field] of [
    [{ flexiLatestStart: '07:00:00' }, 'flexi_latest_start'],
    [{ flexiLatestStart: '12:30:00' }, 'flexi_latest_start'],
    [{ startTime: '20:00', endTime: '05:00', punchMode: 'single_session', breakStart: null, breakEnd: null,
      flexiLatestStart: '21:00:00' }, 'flexi_latest_start'],
    [{ punchMode: 'am_only', endTime: '12:00', breakEnd: null, flexiLatestStart: '08:00:00' }, 'flexi_latest_start'],
    [{ startTime: '13:00', endTime: '23:00', punchMode: 'single_session', breakStart: null, breakEnd: null,
      flexiLatestStart: '15:00:00' }, 'flexi_latest_start'],
  ]) {
    assert.throws(
      () => ensureFlexiArrivalWindow({ ...base, ...overrides }),
      (err) => err.statusCode === 400 && Boolean(err.details?.fields?.[field]),
      JSON.stringify(overrides)
    );
  }
});

test('flexi window is a protected schedule field and audited', () => {
  assert.ok(SHIFT_SCHEDULE_FIELDS.includes('flexi_latest_start'));
  assert.deepEqual(
    changedShiftScheduleFields({ flexi_latest_start: null }, { flexi_latest_start: '09:30:00' }),
    ['flexi_latest_start']
  );
  assert.deepEqual(
    changedShiftScheduleFields({ flexi_latest_start: '09:30:00' }, { flexi_latest_start: '09:30:00' }),
    []
  );
  assert.equal(shiftAuditSnapshot({ flexi_latest_start: '09:30:00' }).flexi_latest_start, '09:30:00');
  assert.equal(shiftAuditSnapshot({}).flexi_latest_start, null);
});

test('DTR assignment loaders expose the flexi window', async () => {
  const createAssignments = require('../src/modules/dtr/repositories/assignments');
  const row = {
    shift_start: '07:00:00', shift_end: '16:00:00', shift_break_end: '13:00:00',
    start_time: '07:00:00', end_time: '16:00:00', break_end: '13:00:00',
    employee_id: 'e', effective_from: '2026-01-01', punch_mode: 'full_day',
    grace_period_minutes: 0, flexi_latest_start: '09:30:00', working_days: [1, 2, 3, 4, 5],
  };
  const repo = createAssignments({
    pool: { query: async () => ({ rows: [row] }) },
    resolvedWorkingDay: () => true,
    timeToMinutes: (value) => {
      if (!value) return null;
      const [h, m] = String(value).split(':').map(Number);
      return h * 60 + m;
    },
  });
  const single = await repo.getAssignmentShiftForDate('e', DATE);
  assert.equal(single.flexiLatestStartMinutes, 570);
  const ranged = await repo.getAssignmentsForEmployeesInRange(['e'], DATE, DATE);
  assert.equal(ranged.get('e')[0].flexiLatestStartMinutes, 570);
});
