const test = require('node:test');
const assert = require('node:assert/strict');
const { getExpectedWorkMinutes, interpretPunchesForShift, computeTotalHoursFromRecord } = require('../src/services/shiftAttendance');
const { groupPunchesForSchedules, overnightPenalties, hasShiftEnded } = require('../src/services/shiftTimeline');
const { ensureSupportedShiftRange, ensureCompatiblePunchModeSchedule } = require('../src/services/shiftLifecycle');
const night = { startMinutes: 1200, endMinutes: 420, punchMode: 'single_session', graceMinutes: 5,
  captureWindowMinutes: 120 };
const stamp = (date, time) => `${date}T${time}:00+08:00`;

test('night shift validation permits two and four punches but rejects 24-hour shifts', () => {
  ensureSupportedShiftRange('20:00', '07:00');
  assert.throws(() => ensureSupportedShiftRange('20:00', '20:00'));
  assert.equal(ensureCompatiblePunchModeSchedule({ startTime: '20:00', endTime: '07:00', punchMode: 'auto' }), 'single_session');
  ensureCompatiblePunchModeSchedule({ startTime: '20:00', endTime: '07:00', punchMode: 'full_day', breakStart: '00:00', breakEnd: '01:00' });
  assert.throws(() => ensureCompatiblePunchModeSchedule({ startTime: '20:00', endTime: '07:00', punchMode: 'full_day', breakStart: '06:00', breakEnd: '01:00' }));
});

test('two-punch night shift pairs across month end without an automatic deduction', () => {
  const punches = [stamp('2026-09-30', '20:00'), stamp('2026-10-01', '07:00')];
  assert.equal(getExpectedWorkMinutes(night), 660);
  assert.equal(interpretPunchesForShift(punches, night, 'Asia/Manila').totalHours, 11);
});

test('four-punch night shift measures the break and return lateness on the next date', () => {
  const shift = { ...night, punchMode: 'full_day', breakStartMinutes: 0, breakEndMinutes: 60 };
  const punches = [stamp('2026-09-30', '20:00'), stamp('2026-10-01', '00:00'), stamp('2026-10-01', '01:15'), stamp('2026-10-01', '06:45')];
  const record = interpretPunchesForShift(punches, shift, 'Asia/Manila');
  assert.equal(record.status, 'present');
  assert.equal(record.totalHours, 9.5);
  assert.deepEqual(overnightPenalties(shift, '2026-09-30', record), { lateMinutes: 10, undertimeMinutes: 15 });
});

test('missing clock-out is not penalized before next-morning shift end', () => {
  const record = { timeIn: stamp('2026-09-30', '20:05') };
  assert.equal(hasShiftEnded(night, '2026-09-30', stamp('2026-10-01', '02:00')), false);
  assert.equal(overnightPenalties(night, '2026-09-30', record, stamp('2026-10-01', '02:00')).undertimeMinutes, 0);
  assert.equal(overnightPenalties(night, '2026-09-30', record, stamp('2026-10-01', '08:00')).undertimeMinutes, 660);
});

test('consecutive night shifts consume each punch once including late departures', async () => {
  const rows = [{ user_id: 'employee', punches: [stamp('2026-09-30', '19:55'), stamp('2026-10-01', '07:15'), stamp('2026-10-01', '20:00'), stamp('2026-10-02', '07:00')] }];
  const groups = await groupPunchesForSchedules(rows, async () => night, '2026-09-30', '2026-10-01');
  assert.deepEqual(groups.map((g) => [g.attendance_date, g.punches.length]), [['2026-09-30', 2], ['2026-10-01', 2]]);
});

test('morning-only import rebuilds previous night without consuming the next night', async () => {
  const rows = [{ user_id: 'employee', punches: [stamp('2026-09-30', '20:00'), stamp('2026-10-01', '07:00')] }];
  const groups = await groupPunchesForSchedules(rows, async (_, date) => date >= '2026-09-30' ? night : null, '2026-10-01', '2026-10-01');
  assert.equal(groups[0].attendance_date, '2026-09-30');
  assert.equal(groups[0].punches.length, 2);
});

test('daytime legacy work-hour calculations remain unchanged', () => {
  const record = { timeIn: stamp('2026-09-30', '08:00'), breakOut: stamp('2026-09-30', '12:00'), breakIn: stamp('2026-09-30', '13:00'), timeOut: stamp('2026-09-30', '17:00') };
  const day = { startMinutes: 480, endMinutes: 1020, breakEndMinutes: 780, punchMode: 'full_day' };
  assert.equal(getExpectedWorkMinutes(day), 480);
  assert.equal(computeTotalHoursFromRecord(record, day), 8);
});

test('night shifts without policy controls use elapsed sessions and actual breaks', () => {
  const single = night;
  const punches = [stamp('2026-09-30', '20:00'), stamp('2026-10-01', '07:00')];
  assert.equal(getExpectedWorkMinutes(single), 660);
  assert.equal(interpretPunchesForShift(punches, single, 'Asia/Manila').totalHours, 11);
  const full = { ...single, punchMode: 'full_day', breakStartMinutes: 0, breakEndMinutes: 60 };
  const fourPunches = [punches[0], stamp('2026-10-01', '00:00'), stamp('2026-10-01', '01:00'), punches[1]];
  assert.equal(getExpectedWorkMinutes(full), 600);
  assert.equal(interpretPunchesForShift(fourPunches, full, 'Asia/Manila').totalHours, 10);
});

test('retired policy metadata cannot change attendance calculations', () => {
  for (const breakMode of ['paid', 'fixed', 'recorded']) {
    const shift = { ...night, breakMode, unpaidBreakMinutes: 60 };
    assert.equal(getExpectedWorkMinutes(shift), 660);
    const punches = [stamp('2026-09-30', '20:00'), stamp('2026-10-01', '07:00')];
    assert.equal(interpretPunchesForShift(punches, shift, 'Asia/Manila').totalHours, 11);
    const split = { ...shift, punchMode: 'full_day', breakStartMinutes: 0, breakEndMinutes: 60 };
    const fourPunches = [punches[0], stamp('2026-10-01', '00:00'), stamp('2026-10-01', '01:00'), punches[1]];
    assert.equal(getExpectedWorkMinutes(split), 600);
    assert.equal(interpretPunchesForShift(fourPunches, split, 'Asia/Manila').totalHours, 10);
  }
});

test('start-date partial holidays do not incorrectly suspend the next morning', () => {
  const { getExpectedWorkMinutesForCoverage } = require('../src/services/shiftAttendance');
  assert.equal(getExpectedWorkMinutesForCoverage(night, 'am_only'), 660);
  assert.equal(getExpectedWorkMinutesForCoverage(night, 'pm_only'), 420);
  assert.equal(getExpectedWorkMinutesForCoverage(night, 'whole_day'), 0);
  const late = overnightPenalties(night, '2026-09-30', {
    timeIn: stamp('2026-10-01', '00:15'), timeOut: stamp('2026-10-01', '06:45'),
  }, stamp('2026-10-01', '08:00'), 'pm_only');
  assert.deepEqual(late, { lateMinutes: 15, undertimeMinutes: 15 });
});

test('two scans in a four-punch night schedule remain incomplete', () => {
  const shift = { ...night, punchMode: 'full_day', breakStartMinutes: 0, breakEndMinutes: 60 };
  const result = interpretPunchesForShift([stamp('2026-09-30', '20:00'), stamp('2026-10-01', '07:00')], shift, 'Asia/Manila');
  assert.equal(result.status, 'incomplete');
  assert.equal(result.timeOut, null);
  assert.equal(result.totalHours, 0);
  const under = overnightPenalties(shift, '2026-09-30', {
    breakIn: stamp('2026-10-01', '01:00'), timeOut: stamp('2026-10-01', '07:00'),
  }, stamp('2026-10-01', '08:00'));
  assert.equal(under.undertimeMinutes, 240);
});

test('rest-day override blocks a new night but permits finishing the previous working night', async () => {
  const rows = [{ user_id: 'employee', punches: [stamp('2026-10-01', '07:00'), stamp('2026-10-01', '20:00')] }];
  const groups = await groupPunchesForSchedules(rows, async (_, date) => ({ ...night, isWorkingDay: date === '2026-09-30' }), '2026-10-01', '2026-10-01');
  assert.deepEqual(groups.map(g => [g.attendance_date, g.punches.length]), [['2026-09-30', 1]]);
});

test('assignment transition selects the closer shift rather than stealing a day-shift arrival', async () => {
  const rows = [{ user_id: 'employee', punches: [stamp('2026-10-01', '08:00')] }];
  const groups = await groupPunchesForSchedules(rows, async (_, date) => date === '2026-09-30' ? night : { startMinutes: 480, endMinutes: 1020 }, '2026-10-01', '2026-10-01');
  assert.equal(groups[0].attendance_date, '2026-10-01');
});

test('duplicate clock punches within a minute do not fill extra overnight slots', async () => {
  const rows = [{ user_id: 'employee', punches: [stamp('2026-09-30', '20:00'), '2026-09-30T20:00:15+08:00', stamp('2026-10-01', '07:00')] }];
  const groups = await groupPunchesForSchedules(rows, async () => night, '2026-09-30', '2026-09-30');
  assert.equal(groups[0].punches.length, 2);
});
