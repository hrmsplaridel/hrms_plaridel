const test = require('node:test');
const assert = require('node:assert/strict');

const {
  calculateApprovalCreditHeadroom,
  calculateCreditReservation,
} = require('../src/services/leaveCreditReservation');

test('reserves all requested days when enough credits are available', () => {
  assert.deepEqual(
    calculateCreditReservation({ requestedDays: 3, availableDays: 5 }),
    {
      requestedDays: 3,
      reservedDays: 3,
      potentialWithoutPayDays: 0,
    }
  );
});

test('reserves available credits and leaves the shortage for unpaid allocation', () => {
  assert.deepEqual(
    calculateCreditReservation({ requestedDays: 3, availableDays: 1 }),
    {
      requestedDays: 3,
      reservedDays: 1,
      potentialWithoutPayDays: 2,
    }
  );
});

test('allows filing with no credits without creating a negative reservation', () => {
  assert.deepEqual(
    calculateCreditReservation({ requestedDays: 2, availableDays: 0 }),
    {
      requestedDays: 2,
      reservedDays: 0,
      potentialWithoutPayDays: 2,
    }
  );
});

test('approval headroom includes this request reservation but excludes other pending requests', () => {
  assert.equal(
    calculateApprovalCreditHeadroom({
      remainingDays: 5,
      pendingDays: 4,
      reservedCreditDays: 2,
    }),
    3
  );
});
