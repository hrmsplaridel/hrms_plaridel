const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeEmploymentStatus,
  accountIsActiveForEmploymentStatus,
  leaveCreditEligibleForEmploymentStatus,
} = require('../src/utils/employeeStatus');

test('only active employment status enables a newly created account', () => {
  assert.equal(accountIsActiveForEmploymentStatus('active'), true);

  for (const status of [
    'inactive',
    'resigned',
    'retired',
    'terminated',
  ]) {
    assert.equal(accountIsActiveForEmploymentStatus(status), false, status);
  }
});

test('unknown or missing employment status retains the active default', () => {
  assert.equal(normalizeEmploymentStatus(undefined), 'active');
  assert.equal(normalizeEmploymentStatus('unknown'), 'active');
  assert.equal(accountIsActiveForEmploymentStatus(undefined), true);
});

test('leave credits are disabled for every non-active employment status', () => {
  assert.equal(leaveCreditEligibleForEmploymentStatus('active', true), true);
  assert.equal(leaveCreditEligibleForEmploymentStatus('active', false), false);

  for (const status of [
    'inactive',
    'resigned',
    'retired',
    'terminated',
  ]) {
    assert.equal(
      leaveCreditEligibleForEmploymentStatus(status, true),
      false,
      status
    );
  }
});
for (const status of ['deceased', 'contract_expired']) {
  test(`${status} is preserved and disables login and future accrual`, () => {
    assert.equal(normalizeEmploymentStatus(status), status);
    assert.equal(accountIsActiveForEmploymentStatus(status), false);
    assert.equal(leaveCreditEligibleForEmploymentStatus(status, true), false);
  });
}
