const test = require('node:test');
const assert = require('node:assert/strict');
const { serviceEligibility, assertLeaveServiceEligibility } = require('../src/services/leaveServiceEligibility');

test('minimum service is optional and does not require a hire date when disabled', () => {
  assert.equal(serviceEligibility({}, null, '2026-10-01').eligible, true);
});

test('six calendar months are measured at the first requested leave date', () => {
  const rule = { minimum_service_months: 6 };
  assert.deepEqual(serviceEligibility(rule, '2026-04-18', '2026-10-17'), {
    eligible: false, minimum_service_months: 6, eligible_from: '2026-10-18',
    message: 'This leave type requires 6 month(s) of service. You become eligible on 2026-10-18.',
  });
  assert.equal(serviceEligibility(rule, '2026-04-18', '2026-10-18').eligible, true);
});

test('month-end anniversaries clamp to the last valid calendar date', () => {
  assert.equal(serviceEligibility({ minimum_service_months: 6 }, '2025-08-31', '2026-02-28').eligible_from, '2026-02-28');
  assert.equal(serviceEligibility({ minimum_service_months: 12 }, '2024-02-29', '2025-02-28').eligible, true);
});

test('missing or invalid hire dates cannot bypass a configured service requirement', () => {
  for (const hireDate of [null, '', '2026-02-30']) {
    const result = serviceEligibility({ minimum_service_months: 6 }, hireDate, '2026-10-18');
    assert.equal(result.eligible, false);
    assert.match(result.message, /hire date.*HR/i);
  }
});

test('backend rejects ineligible service and accepts eligible service', async () => {
  const queries = [];
  const db = { query: async (sql, params) => { queries.push({sql, params}); return {rows:[{date_hired:'2026-04-18'}]}; } };
  await assert.rejects(assertLeaveServiceEligibility(db, {minimum_service_months:6}, 'employee', '2026-10-17'), /eligible on 2026-10-18/);
  await assert.doesNotReject(assertLeaveServiceEligibility(db, {minimum_service_months:6}, 'employee', '2026-10-18'));
  await assertLeaveServiceEligibility(db, {}, 'employee', '2026-10-18');
  assert.equal(queries.length, 2);
});
