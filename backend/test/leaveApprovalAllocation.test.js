const test = require('node:test');
const assert = require('node:assert/strict');

const {
  approvedPaidDaysForRevoke,
  resolveApprovalAllocation,
} = require('../src/services/leaveApprovalAllocation');

test('approval allocation deducts only with-pay days', () => {
  const allocation = resolveApprovalAllocation({
    requestedDays: 5,
    approvedDaysWithPay: 2,
    approvedDaysWithoutPay: 3,
  });

  assert.deepEqual(allocation, {
    requestedDays: 5,
    approvedDaysWithPay: 2,
    approvedDaysWithoutPay: 3,
    usedDaysToDeduct: 2,
  });
});

test('approval allocation permits a request that is entirely without pay', () => {
  const allocation = resolveApprovalAllocation({
    requestedDays: 3,
    approvedDaysWithPay: 0,
    approvedDaysWithoutPay: 3,
  });

  assert.equal(allocation.usedDaysToDeduct, 0);
});

test('approval allocation rejects missing, negative, and mismatched values', () => {
  assert.throws(
    () => resolveApprovalAllocation({
      requestedDays: 5,
      approvedDaysWithPay: null,
      approvedDaysWithoutPay: 5,
    }),
    /Approved days with pay is required/
  );
  assert.throws(
    () => resolveApprovalAllocation({
      requestedDays: 5,
      approvedDaysWithPay: -1,
      approvedDaysWithoutPay: 6,
    }),
    /cannot be negative/
  );
  assert.throws(
    () => resolveApprovalAllocation({
      requestedDays: 5,
      approvedDaysWithPay: 2,
      approvedDaysWithoutPay: 2,
    }),
    /must equal the 5 requested day/
  );
});

test('revoke restores the stored paid amount and keeps legacy full-day behavior', () => {
  assert.equal(
    approvedPaidDaysForRevoke({ requestedDays: 5, approvedDaysWithPay: 2 }),
    2
  );
  assert.equal(
    approvedPaidDaysForRevoke({ requestedDays: 5, approvedDaysWithPay: null }),
    5
  );
});
