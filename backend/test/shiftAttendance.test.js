const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getShiftType,
  getShiftExpectedLogs,
  interpretPunchesForShift,
  computeTotalHoursFromRecord,
} = require('../src/services/shiftAttendance');

test('auto mode preserves legacy 10 AM to 2 PM classification as full day', () => {
  const shift = {
    startMinutes: 10 * 60,
    endMinutes: 14 * 60,
    breakEndMinutes: null,
    punchMode: 'auto',
  };

  assert.equal(getShiftType(shift), 'full_day');
});

test('single-session shift expects Time In and Time Out only', () => {
  const shift = {
    startMinutes: 10 * 60,
    endMinutes: 14 * 60,
    breakEndMinutes: null,
    punchMode: 'single_session',
  };

  assert.equal(getShiftType(shift), 'single_session');
  assert.deepEqual(getShiftExpectedLogs(shift), {
    needsAm: false,
    needsPm: false,
    needsInOut: true,
  });
});

test('single-session biometric punches map to time_in and time_out', () => {
  const shift = {
    startMinutes: 10 * 60,
    endMinutes: 14 * 60,
    breakEndMinutes: null,
    punchMode: 'single_session',
  };
  const timeIn = '2026-05-22T02:00:00.000Z';
  const timeOut = '2026-05-22T06:00:00.000Z';

  const interpreted = interpretPunchesForShift(
    [timeIn, timeOut],
    shift,
    'Asia/Manila'
  );

  assert.equal(interpreted.timeIn, timeIn);
  assert.equal(interpreted.breakOut, null);
  assert.equal(interpreted.breakIn, null);
  assert.equal(interpreted.timeOut, timeOut);
  assert.equal(interpreted.status, 'present');
  assert.equal(interpreted.totalHours, 4);
});

test('single-session total hours use direct Time In to Time Out span', () => {
  const shift = {
    startMinutes: 10 * 60,
    endMinutes: 14 * 60,
    punchMode: 'single_session',
  };

  assert.equal(
    computeTotalHoursFromRecord(
      {
        time_in: '2026-05-22T02:15:00.000Z',
        time_out: '2026-05-22T05:30:00.000Z',
      },
      shift
    ),
    3.25
  );
});
