'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  dateInRecurringRange,
  expandRecurringToWindow,
} = require('../src/services/holidayRangeUtils');

test('recurring February 29 appears in leap years', () => {
  assert.deepEqual(
    expandRecurringToWindow('2024-02-29', '2024-02-29', '2024-02-01', '2024-03-02'),
    ['2024-02-29']
  );
  assert.equal(dateInRecurringRange('2024-02-29', '2024-02-29', '2024-02-29'), true);
});

test('recurring February 29 does not move to March 1 in non-leap years', () => {
  assert.deepEqual(
    expandRecurringToWindow('2024-02-29', '2024-02-29', '2025-02-01', '2025-03-02'),
    []
  );
  assert.equal(dateInRecurringRange('2025-03-01', '2024-02-29', '2024-02-29'), false);
});

test('a February 29 through March 1 range retains real dates only', () => {
  assert.deepEqual(
    expandRecurringToWindow('2024-02-29', '2024-03-01', '2024-02-28', '2025-03-02'),
    ['2024-02-29', '2024-03-01', '2025-03-01']
  );
});

test('ordinary same-year recurring ranges remain inclusive', () => {
  assert.deepEqual(
    expandRecurringToWindow('2020-08-12', '2020-08-13', '2026-08-01', '2026-08-31'),
    ['2026-08-12', '2026-08-13']
  );
});

test('cross-year recurring ranges retain both calendar-year segments', () => {
  assert.deepEqual(
    expandRecurringToWindow('2020-12-30', '2021-01-02', '2026-12-29', '2027-01-03'),
    ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02']
  );
  assert.equal(dateInRecurringRange('2027-01-01', '2020-12-30', '2021-01-02'), true);
});

test('invalid recurring template month/day values produce no dates', () => {
  assert.deepEqual(
    expandRecurringToWindow('2024-04-31', '2024-04-31', '2026-04-01', '2026-05-02'),
    []
  );
});
