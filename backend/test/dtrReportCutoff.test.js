'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { isAttendanceDateFinalized } = require('../src/services/dtrReportCutoff');

const dayShift = {
  startMinutes: 8 * 60,
  endMinutes: 17 * 60,
  breakEndMinutes: 13 * 60,
  punchMode: 'full_day',
  workingDays: [1, 2, 3, 4, 5],
};

test('today becomes reportable only after the required shift session ends', () => {
  const common = {
    dateStr: '2026-08-24',
    todayStr: '2026-08-24',
    shiftInfo: dayShift,
    holidayInfo: null,
  };

  assert.equal(isAttendanceDateFinalized({ ...common, nowMinutes: 9 * 60 }), false);
  assert.equal(isAttendanceDateFinalized({ ...common, nowMinutes: 18 * 60 }), true);
});

test('PM suspension finalizes after the remaining AM session', () => {
  assert.equal(
    isAttendanceDateFinalized({
      dateStr: '2026-08-24',
      todayStr: '2026-08-24',
      nowMinutes: 12 * 60 + 1,
      shiftInfo: dayShift,
      holidayInfo: { coverage: 'pm_only' },
    }),
    true
  );
});

test('whole-day holidays and rest days are immediately reportable', () => {
  const common = {
    dateStr: '2026-08-24',
    todayStr: '2026-08-24',
    nowMinutes: 8 * 60,
    shiftInfo: dayShift,
  };

  assert.equal(
    isAttendanceDateFinalized({
      ...common,
      holidayInfo: { coverage: 'whole_day' },
    }),
    true
  );
  assert.equal(
    isAttendanceDateFinalized({
      ...common,
      dateStr: '2026-08-23',
      holidayInfo: null,
    }),
    true
  );
});

test('a suspension covering the employee entire short shift is immediately reportable', () => {
  const amOnlyShift = {
    startMinutes: 8 * 60,
    endMinutes: 12 * 60,
    punchMode: 'am_only',
    workingDays: [1],
  };

  assert.equal(
    isAttendanceDateFinalized({
      dateStr: '2026-08-24',
      todayStr: '2026-08-24',
      nowMinutes: 8 * 60,
      shiftInfo: amOnlyShift,
      holidayInfo: { coverage: 'am_only' },
    }),
    true
  );
});

test('an overnight shift stays open until its next-day end time', () => {
  const overnight = {
    startMinutes: 22 * 60,
    endMinutes: 6 * 60,
    punchMode: 'single_session',
    workingDays: [7],
  };
  const common = {
    dateStr: '2026-08-23',
    todayStr: '2026-08-24',
    shiftInfo: overnight,
    holidayInfo: null,
  };

  assert.equal(isAttendanceDateFinalized({ ...common, nowMinutes: 5 * 60 }), false);
  assert.equal(isAttendanceDateFinalized({ ...common, nowMinutes: 7 * 60 }), true);
});
