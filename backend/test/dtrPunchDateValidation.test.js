'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { validateDtrPunchDates } = require('../src/services/dtrPunchDateValidation');

const base = {
  attendanceDate: '2026-06-01',
  todayDate: '2026-08-21',
  timeZone: 'Asia/Manila',
  shiftInfo: { startMinutes: 480, endMinutes: 1020 },
};

test('accepts punches whose Manila date matches the attendance date', () => {
  const result = validateDtrPunchDates({
    ...base,
    punches: {
      time_in: '2026-06-01T00:00:00.000Z',
      time_out: '2026-06-01T09:00:00.000Z',
    },
  });
  assert.equal(result.valid, true);
});

test('uses the Manila date instead of the raw UTC date', () => {
  const result = validateDtrPunchDates({
    ...base,
    punches: { time_in: '2026-05-31T16:30:00.000Z' },
  });
  assert.equal(result.valid, true);
});

test('rejects a punch belonging to another Manila date', () => {
  const result = validateDtrPunchDates({
    ...base,
    punches: { time_in: '2026-08-13T00:00:00.000Z' },
  });
  assert.equal(result.valid, false);
  assert.match(result.error, /Time In must belong to 2026-06-01/);
});

test('rejects future attendance dates', () => {
  const result = validateDtrPunchDates({
    ...base,
    attendanceDate: '2026-08-22',
    punches: {},
  });
  assert.equal(result.valid, false);
  assert.match(result.error, /Future attendance is not allowed/);
});

test('allows the valid next-day portion of an overnight shift', () => {
  const result = validateDtrPunchDates({
    attendanceDate: '2026-08-13',
    todayDate: '2026-08-21',
    timeZone: 'Asia/Manila',
    shiftInfo: { startMinutes: 1320, endMinutes: 360 },
    punches: {
      time_in: '2026-08-13T14:00:00.000Z',
      time_out: '2026-08-13T22:00:00.000Z',
    },
  });
  assert.equal(result.valid, true);
  assert.equal(result.isOvernight, true);
  assert.equal(result.followingDate, '2026-08-14');
});

test('rejects a next-day overnight punch after the shift end', () => {
  const result = validateDtrPunchDates({
    attendanceDate: '2026-08-13',
    todayDate: '2026-08-21',
    timeZone: 'Asia/Manila',
    shiftInfo: { startMinutes: 1320, endMinutes: 360 },
    punches: { time_out: '2026-08-13T23:00:00.000Z' },
  });
  assert.equal(result.valid, false);
  assert.match(result.error, /overnight shift ending 2026-08-14/);
});

test('rejects impossible attendance dates and invalid punch timestamps', () => {
  assert.equal(
    validateDtrPunchDates({ ...base, attendanceDate: '2026-02-31', punches: {} }).valid,
    false
  );
  assert.equal(
    validateDtrPunchDates({ ...base, punches: { time_in: 'not-a-date' } }).valid,
    false
  );
});
