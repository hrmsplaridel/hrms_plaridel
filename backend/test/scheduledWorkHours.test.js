const test = require('node:test');
const assert = require('node:assert/strict');
const attendance = require('../src/services/shiftAttendance');
const { isOvernight } = require('../src/services/shiftTimeline');

const stamp = (time, date = '2026-11-08') => `${date}T${time}+08:00`;
const evening = { startMinutes: 1140, endMinutes: 1200, punchMode: 'single_session' };
const fullDay = { startMinutes: 480, endMinutes: 1020, punchMode: 'full_day',
  breakStartMinutes: 720, breakEndMinutes: 780 };
const record = (start, end, extra = {}) => ({
  attendance_date_iso: '2026-11-08', time_in: stamp(start), time_out: stamp(end), ...extra,
});

test('evening worked hours exclude early arrival, preserve seconds and do not alter punches or undertime', () => {
  const punches = [stamp('18:56:53'), stamp('19:27:10')];
  const result = attendance.interpretPunchesForShift(punches, evening, 'Asia/Manila');
  assert.equal(result.totalHours, 0.45);
  assert.equal(result.timeIn, punches[0]);
  assert.equal(result.timeOut, punches[1]);
  assert.equal(attendance.computeTotalHoursFromRecord(record('18:56:53', '19:27:10'), evening), 0.45);
  assert.equal(attendance.computeClockOutUndertimeMinutes({ shiftInfo: evening, timeOutMinutes: 1167 }), 33);
});

test('single-session credit is bounded by the shift, with no automatic credit for grace or extra time', () => {
  for (const [start, end, expected] of [
    ['18:00:00', '21:00:00', 1],
    ['19:05:00', '20:10:00', 0.92],
    ['18:00:00', '18:50:00', 0],
    ['20:05:00', '21:00:00', 0],
    ['19:30:00', '19:15:00', 0],
  ]) {
    assert.equal(attendance.computeTotalHoursFromRecord(record(start, end), { ...evening, graceMinutes: 5 }), expected);
  }
  assert.equal(attendance.computeTotalHoursFromRecord({ time_in: stamp('18:56:53') }, evening), 0);
});

test('AM-only and PM-only sessions count only their scheduled windows', () => {
  const am = { startMinutes: 480, endMinutes: 720, punchMode: 'am_only' };
  const pm = { startMinutes: 780, endMinutes: 1020, punchMode: 'pm_only' };
  assert.equal(attendance.interpretPunchesForShift([stamp('07:30:00'), stamp('12:30:00')], am, 'Asia/Manila').totalHours, 4);
  assert.equal(attendance.interpretPunchesForShift([stamp('12:30:00'), stamp('17:30:00')], pm, 'Asia/Manila').totalHours, 4);
});

test('full-day credit excludes scheduled lunch and early returns, without compensating for late arrivals', () => {
  const punches = [stamp('08:15:00'), stamp('12:30:00'), stamp('12:45:00'), stamp('17:30:00')];
  assert.equal(attendance.interpretPunchesForShift(punches, fullDay, 'Asia/Manila').totalHours, 7.75);
  const shortSessions = [stamp('07:30:00'), stamp('11:45:00'), stamp('13:15:00'), stamp('17:30:00')];
  assert.equal(attendance.interpretPunchesForShift(shortSessions, fullDay, 'Asia/Manila').totalHours, 7.5);
  const pmOnly = attendance.interpretPunchesForShift([stamp('13:15:00'), stamp('17:30:00')], fullDay, 'Asia/Manila');
  assert.equal(pmOnly.totalHours, 3.75);
  assert.equal(pmOnly.timeIn, null);
});

test('overnight credit clips both sides of midnight and excludes the scheduled break', () => {
  const night = { startMinutes: 1320, endMinutes: 360, punchMode: 'single_session' };
  const punches = [stamp('21:50:00'), stamp('06:20:00', '2026-11-09')];
  assert.equal(attendance.interpretPunchesForShift(punches, night, 'Asia/Manila').totalHours, 8);
  const split = { ...night, punchMode: 'full_day', breakStartMinutes: 120, breakEndMinutes: 180 };
  assert.equal(attendance.interpretPunchesForShift([
    punches[0], stamp('02:15:00', '2026-11-09'), stamp('02:45:00', '2026-11-09'), punches[1],
  ], split, 'Asia/Manila').totalHours, 7);
  assert.equal(attendance.interpretPunchesForShift([
    stamp('03:15:00', '2026-11-09'), punches[1],
  ], split, 'Asia/Manila').totalHours, 2.75);
});

test('attendance date anchors very early punches for a shift that starts after midnight', () => {
  const shift = { startMinutes: 60, endMinutes: 180, punchMode: 'single_session' };
  const input = record('00:30:00', '03:15:00', { time_in: stamp('23:30:00', '2026-11-07') });
  assert.equal(attendance.computeTotalHoursFromRecord(input, shift), 2);
});

test('missing schedule retains elapsed-time compatibility and historical single-session slot pairs', () => {
  assert.equal(attendance.computeTotalHoursFromRecord(record('18:56:53', '19:27:10')), 0.5);
  assert.equal(attendance.computeTotalHoursFromRecord({ break_in: stamp('18:56:53'), time_out: stamp('19:27:10') }, evening), 0.45);
  assert.equal(attendance.computeTotalHoursFromRecord({ time_in: stamp('18:56:53'), break_out: stamp('19:27:10') }, evening), 0.45);
});

test('manual entry calculation shares the same scheduled hours as biometric imports', () => {
  const { computeTotalHours } = require('../src/modules/dtr/services/shifts')({
    computeTotalHoursFromRecord: attendance.computeTotalHoursFromRecord,
  });
  assert.equal(computeTotalHours(stamp('18:56:53'), null, null, stamp('19:27:10'), evening, '2026-11-08'), 0.45);
});

function savedRow(extra = {}) {
  return { id: 'entry', employee_id: 'employee', ...record('18:56:53', '19:27:10'),
    total_hours: '0.50', status: 'present', source: 'system', undertime_minutes: 33,
    shift_snapshot: evening, ...extra };
}

test('Time Logs and reports correct stored hours on read using the saved shift without changing evidence', async () => {
  const { mapSavedAttendanceRow } = require('../src/modules/dtr/services/reportRows')({
    computeTotalHoursFromRecord: attendance.computeTotalHoursFromRecord,
    getShiftInfoForDateFromAssignments: () => ({ ...evening, startMinutes: 1200, endMinutes: 1260 }),
    resolveAttendanceHolidayOverlay: (r) => ({ status: r.status }),
    computeAttendanceRemark: async () => 'Undertime',
    isOvernight, resolveShiftType: attendance.getShiftType,
  });
  for (const source of ['system', 'manual', 'adjusted']) {
    const input = savedRow({ source });
    const before = structuredClone(input);
    const result = await mapSavedAttendanceRow(input, {
      activeHolidayByDate: new Map(), rawAssignmentsByEmployee: new Map(), savedShiftsByDate: new Map(),
    });
    assert.equal(result.total_hours, 0.45);
    assert.equal(result.undertime_minutes, 33);
    assert.equal(result.time_in, input.time_in);
    assert.equal(result.time_out, input.time_out);
    assert.deepEqual(input, before);
  }
});

test('today endpoint returns the same corrected hours and preserves empty holiday/leave hours', async () => {
  for (const row of [savedRow(), savedRow({ time_in: null, time_out: null, total_hours: null, is_leave_covered: true })]) {
    const { getTodayRecord } = require('../src/modules/dtr/controllers/today.controller')({
      _holidaysHasCoverageColumn: async () => true,
      pool: { query: async () => ({ rows: [row] }) },
      todayInHrmsTimezone: () => '2026-11-08',
      loadHolidayOverlayMap: async () => new Map(),
      resolveAttendanceHolidayOverlay: (r) => ({ status: r.status }),
      computeTotalHoursFromRecord: attendance.computeTotalHoursFromRecord,
      getAssignmentShiftForDate: async () => { assert.fail('saved shift must take priority'); },
    });
    const res = { status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; } };
    await getTodayRecord({ user: { id: 'employee' } }, res);
    assert.equal(res.statusCode, undefined);
    assert.equal(res.body.total_hours, row.total_hours == null ? null : 0.45);
    assert.equal(res.body.time_in, row.time_in);
  }
});
