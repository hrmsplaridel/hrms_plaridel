const test = require('node:test');
const assert = require('node:assert/strict');

const {
  defaultWorkingDay,
  resolvedWorkingDay,
  scheduleKey,
  weekDates,
} = require('../src/services/employeeScheduleOverrides');

test('weekDates accepts Mondays and returns the seven calendar dates', () => {
  assert.deepEqual(weekDates('2026-09-28'), [
    '2026-09-28',
    '2026-09-29',
    '2026-09-30',
    '2026-10-01',
    '2026-10-02',
    '2026-10-03',
    '2026-10-04',
  ]);
  assert.equal(weekDates('2026-09-29'), null);
  assert.equal(weekDates('not-a-date'), null);
});

test('fixed shift working days remain the fallback without an override', () => {
  assert.equal(defaultWorkingDay([1, 2, 3, 4, 5, 6], '2026-10-03'), true);
  assert.equal(defaultWorkingDay([1, 2, 3, 4, 5, 6], '2026-10-04'), false);
  assert.equal(resolvedWorkingDay({
    employeeId: 'employee-1',
    dateStr: '2026-10-04',
    workingDays: [1, 2, 3, 4, 5, 6],
    overrides: new Map(),
  }), false);
});

test('an employee date override wins over the fixed shift schedule', () => {
  const overrides = new Map([
    [scheduleKey('employee-1', '2026-09-29'), false],
    [scheduleKey('employee-1', '2026-10-04'), true],
  ]);
  assert.equal(resolvedWorkingDay({
    employeeId: 'employee-1',
    dateStr: '2026-09-29',
    workingDays: [1, 2, 3, 4, 5, 6],
    overrides,
  }), false);
  assert.equal(resolvedWorkingDay({
    employeeId: 'employee-1',
    dateStr: '2026-10-04',
    workingDays: [1, 2, 3, 4, 5, 6],
    overrides,
  }), true);
});
