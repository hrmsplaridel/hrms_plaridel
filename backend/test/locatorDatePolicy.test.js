const test = require('node:test');
const assert = require('node:assert/strict');

const {
  currentHrmsDate,
  evaluateEmployeeLocatorDateWindow,
  evaluateLocatorEmployeeCorrectionWindow,
  evaluateLocatorReturnWindow,
  normalizeCorrectionReason,
} = require('../src/services/locatorDatePolicy');

const NOW = new Date('2026-08-11T02:00:00.000Z'); // 10:00 AM Manila

test('employee locator filing allows today and future dates but blocks past dates', () => {
  assert.equal(currentHrmsDate(NOW), '2026-08-11');
  assert.equal(
    evaluateEmployeeLocatorDateWindow({ slipDate: '2026-08-10', now: NOW })
      .code,
    'locator_past_date_not_allowed'
  );
  assert.equal(
    evaluateEmployeeLocatorDateWindow({ slipDate: '2026-08-11', now: NOW }).ok,
    true
  );
  assert.equal(
    evaluateEmployeeLocatorDateWindow({ slipDate: '2026-08-12', now: NOW }).ok,
    true
  );
});

test('official locator date follows Manila across the UTC date boundary', () => {
  assert.equal(
    currentHrmsDate(new Date('2026-08-10T16:30:00.000Z')),
    '2026-08-11'
  );
});

test('past locator requests cannot enter the employee correction workflow', () => {
  assert.equal(
    evaluateLocatorReturnWindow({ slipDate: '2026-08-10', now: NOW }).code,
    'locator_past_date_return_not_allowed'
  );
  assert.equal(
    evaluateLocatorReturnWindow({ slipDate: '2026-08-11', now: NOW }).ok,
    true
  );
});

test('legacy returned requests cannot move a past locator date forward', () => {
  assert.equal(
    evaluateLocatorEmployeeCorrectionWindow({
      slipDate: '2026-08-10',
      now: NOW,
    }).code,
    'locator_past_date_correction_not_allowed'
  );
  assert.equal(
    evaluateLocatorEmployeeCorrectionWindow({
      slipDate: '2026-08-11',
      now: NOW,
    }).ok,
    true
  );
});

test('HR correction reasons remain validated independently of approval time', () => {
  assert.equal(normalizeCorrectionReason('Too short'), null);
  assert.equal(
    normalizeCorrectionReason('Approved paper locator encoded by HR afterward.'),
    'Approved paper locator encoded by HR afterward.'
  );
});
