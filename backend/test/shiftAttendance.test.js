const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getShiftType,
  getExpectedWorkMinutesForCoverage,
  getShiftExpectedLogs,
  interpretPunchesForShift,
  computeTotalHoursFromRecord,
  computeClockOutUndertimeMinutes,
} = require('../src/services/shiftAttendance');

test('partial holiday coverage keeps only the scheduled shift session', () => {
  const fullDay = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };
  const amOnly = {
    startMinutes: 8 * 60,
    endMinutes: 12 * 60,
    punchMode: 'am_only',
  };
  const pmOnly = {
    startMinutes: 13 * 60,
    endMinutes: 17 * 60,
    punchMode: 'pm_only',
  };
  const eveningSession = {
    startMinutes: 18 * 60,
    endMinutes: 19 * 60,
    punchMode: 'single_session',
  };

  assert.equal(getExpectedWorkMinutesForCoverage(fullDay, 'whole_day'), 0);
  assert.equal(getExpectedWorkMinutesForCoverage(fullDay, 'am_only'), 240);
  assert.equal(getExpectedWorkMinutesForCoverage(fullDay, 'pm_only'), 240);
  assert.equal(getExpectedWorkMinutesForCoverage(amOnly, 'am_only'), 0);
  assert.equal(getExpectedWorkMinutesForCoverage(amOnly, 'pm_only'), 240);
  assert.equal(getExpectedWorkMinutesForCoverage(pmOnly, 'am_only'), 240);
  assert.equal(getExpectedWorkMinutesForCoverage(pmOnly, 'pm_only'), 0);
  assert.equal(getExpectedWorkMinutesForCoverage(eveningSession, 'am_only'), 60);
  assert.equal(getExpectedWorkMinutesForCoverage(eveningSession, 'pm_only'), 0);
});

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

test('full-day shift counts early AM Out as undertime', () => {
  const shift = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };

  assert.equal(
    computeClockOutUndertimeMinutes({
      shiftInfo: shift,
      breakOutMinutes: 11 * 60 + 55,
      timeOutMinutes: 17 * 60,
    }),
    5
  );
});

test('full-day shift adds AM and PM undertime', () => {
  const shift = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };

  assert.equal(
    computeClockOutUndertimeMinutes({
      shiftInfo: shift,
      breakOutMinutes: 11 * 60 + 55,
      timeOutMinutes: 16 * 60 + 45,
    }),
    20
  );
});

test('full-day shift has no undertime when both clock-out segments are on time', () => {
  const shift = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };

  assert.equal(
    computeClockOutUndertimeMinutes({
      shiftInfo: shift,
      breakOutMinutes: 12 * 60,
      timeOutMinutes: 17 * 60,
    }),
    0
  );
});

test('missing clock-out values are left for incomplete-record handling', () => {
  const shift = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };

  assert.equal(
    computeClockOutUndertimeMinutes({
      shiftInfo: shift,
      breakOutMinutes: null,
      timeOutMinutes: null,
    }),
    0
  );
});

test('covered or suspended AM segment does not create AM undertime', () => {
  const shift = {
    startMinutes: 8 * 60,
    endMinutes: 17 * 60,
    breakEndMinutes: 13 * 60,
    punchMode: 'full_day',
  };

  assert.equal(
    computeClockOutUndertimeMinutes({
      shiftInfo: shift,
      breakOutMinutes: 11 * 60 + 55,
      timeOutMinutes: 17 * 60,
      coveredSegments: ['AM OUT'],
    }),
    0
  );
  assert.equal(
    computeClockOutUndertimeMinutes({
      shiftInfo: shift,
      breakOutMinutes: 11 * 60 + 55,
      timeOutMinutes: 17 * 60,
      evaluateAm: false,
    }),
    0
  );
});
