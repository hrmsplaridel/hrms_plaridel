const test = require('node:test');
const assert = require('node:assert/strict');
const { projectAttendanceCoverage } = require('../src/services/attendanceCoverageProjection');

const shift = { punchMode: 'full_day', startMinutes: 480, endMinutes: 1020,
  breakStartMinutes: 720, breakEndMinutes: 780, graceMinutes: 0 };
const record = { record_date: '2026-09-01', status: 'late', source: 'system',
  time_in: '2026-09-01T08:30:00+08:00', break_out: '2026-09-01T11:30:00+08:00',
  break_in: '2026-09-01T13:15:00+08:00', time_out: '2026-09-01T16:00:00+08:00',
  late_minutes: 45, undertime_minutes: 90, total_hours: 6.75 };
const policy = { deductLate: true, deductUndertime: true, deductionMultiplier: 1 };
const project = (options = {}) => projectAttendanceCoverage({ record, date: record.record_date,
  shiftInfo: shift, policy, ...options });
const allSlots = { am_in: true, am_out: true, pm_in: true, pm_out: true };

for (const [name, options, status] of [
  ['leave', { leave: { number_of_days: 1, start_date: '2026-09-01', end_date: '2026-09-01' } }, 'on_leave'],
  ['holiday', { holidayInfo: { coverage: 'whole_day' } }, 'holiday'],
  ['locator', { locator: allSlots }, 'on_field'],
]) {
  test(`full ${name} hides saved punches and hours without mutating evidence`, async () => {
    const original = structuredClone(record);
    const result = await project(options);
    for (const field of ['time_in', 'break_out', 'break_in', 'time_out', 'total_hours']) {
      assert.equal(result[field], null, field);
    }
    assert.equal(result.status, status);
    assert.equal(result.late_minutes, 0);
    assert.equal(result.undertime_minutes, 0);
    assert.deepEqual(record, original);
    const noPunch = await project({ ...options, record: { record_date: record.record_date } });
    assert.equal(noPunch.status, result.status, 'approval order must not change coverage');
  });
}

test('partial locator hides only approved slots and recalculates uncovered penalties', async () => {
  const result = await project({ locator: { am_in: true, am_out: true } });
  assert.equal(result.time_in, null);
  assert.equal(result.break_out, null);
  assert.equal(result.break_in, record.break_in);
  assert.equal(result.time_out, record.time_out);
  assert.equal(result.total_hours, 2.75);
  assert.equal(result.late_minutes, 15);
  assert.equal(result.undertime_minutes, 60);
});

test('one approved slot must not erase the other slots or their penalties', async () => {
  const result = await project({ locator: { am_in: true } });
  assert.equal(result.time_in, null);
  assert.equal(result.break_out, record.break_out);
  assert.equal(result.late_minutes, 15);
  assert.equal(result.undertime_minutes, 90);
});

test('partial holiday hides its session while uncovered PM remains assessable', async () => {
  const result = await project({ holidayInfo: { coverage: 'am_only' } });
  assert.equal(result.time_in, null);
  assert.equal(result.break_out, null);
  assert.equal(result.break_in, record.break_in);
  assert.equal(result.total_hours, 2.75);
  assert.equal(result.late_minutes, 15);
  assert.equal(result.undertime_minutes, 60);
});

test('combined partial holiday and locator can cover the whole shift', async () => {
  const result = await project({ holidayInfo: { coverage: 'am_only' },
    locator: { pm_in: true, pm_out: true } });
  assert.equal(result.time_out, null);
  assert.equal(result.total_hours, null);
  assert.equal(result.late_minutes + result.undertime_minutes, 0);
});

test('single-session and overnight locator coverage follows shift slots, not clock AM/PM', async () => {
  for (const session of [
    { punchMode: 'single_session', startMinutes: 1140, endMinutes: 1200 },
    { punchMode: 'single_session', startMinutes: 1320, endMinutes: 360 },
    { punchMode: 'pm_only', startMinutes: 780, endMinutes: 1020 },
  ]) {
    const locator = session.punchMode === 'pm_only' ? { pm_in: true, pm_out: true }
      : { am_in: true, pm_out: true };
    const result = await project({ shiftInfo: session, locator });
    assert.equal(result.total_hours, null);
    assert.equal(result.time_in, null);
    assert.equal(result.time_out, null);
  }
});

test('revoked/absent coverage exposes original punches and values again', async () => {
  await project({ locator: allSlots });
  const restored = await project();
  assert.equal(restored.time_in, record.time_in);
  assert.equal(restored.time_out, record.time_out);
  assert.equal(restored.late_minutes, 45);
  assert.equal(restored.undertime_minutes, 90);
});

test('half-day leave without a recorded session does not hide a guessed half', async () => {
  const result = await project({ leave: { number_of_days: 0.5,
    start_date: '2026-09-01', end_date: '2026-09-01' } });
  assert.equal(result.time_in, record.time_in);
  assert.equal(result.time_out, record.time_out);
  const missingDates = await project({ leave: { number_of_days: 0.5 } });
  assert.equal(missingDates.time_in, record.time_in);
});

test('AM-only holiday fully covering an AM shift has no displayed work hours', async () => {
  const result = await project({ shiftInfo: { ...shift, punchMode: 'am_only', endMinutes: 720 },
    holidayInfo: { coverage: 'am_only' } });
  assert.equal(result.total_hours, null);
  assert.equal(result.time_in, null);
  assert.equal(result.break_out, null);
});

test('policy switches and multiplier apply once to uncovered penalties', async () => {
  const result = await project({ locator: { am_in: true, am_out: true },
    policy: { deductLate: false, deductUndertime: true, deductionMultiplier: 2 } });
  assert.equal(result.late_minutes, 0);
  assert.equal(result.undertime_minutes, 120);
});

test('partial locator still charges a missing uncovered session after shift end', async () => {
  const result = await project({ record: { record_date: record.record_date, status: 'absent' },
    locator: { am_in: true, am_out: true } });
  assert.equal(result.undertime_minutes, 240);
});

test('an uncovered missing PM out charges only PM, not the already covered AM', async () => {
  const result = await project({ record: { ...record, time_out: null },
    locator: { am_in: true, am_out: true } });
  assert.equal(result.undertime_minutes, 240);
});
