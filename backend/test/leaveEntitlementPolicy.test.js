const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ENTITLEMENT_BASES,
  buildAnnualEntitlementYearSummary,
  countedDatesForCalendarYear,
  defaultEntitlementBasisForLeaveType,
  normalizeEntitlementBasis,
} = require('../src/services/leaveEntitlementPolicy');

test('only genuine standard annual entitlements use the annual basis', () => {
  const annualTypes = [
    'specialPrivilegeLeave',
    'soloParentLeave',
    'tenDayVawcLeave',
  ];
  const eventTypes = [
    'maternityLeave',
    'paternityLeave',
    'rehabilitationPrivilege',
    'specialLeaveBenefitsForWomen',
    'specialEmergencyCalamityLeave',
    'adoptionLeave',
  ];

  for (const leaveType of annualTypes) {
    assert.equal(
      defaultEntitlementBasisForLeaveType(leaveType),
      ENTITLEMENT_BASES.ANNUAL,
    );
  }
  for (const leaveType of eventTypes) {
    assert.equal(
      defaultEntitlementBasisForLeaveType(leaveType),
      ENTITLEMENT_BASES.PER_EVENT,
    );
  }
});

test('annual preview counts approved and pending usage before the request', () => {
  const allowed = buildAnnualEntitlementYearSummary({
    year: 2026,
    limitDays: 7,
    approvedDays: 3,
    pendingDays: 2,
    requestedDays: 2,
    requestedCountedDates: ['2026-12-28', '2026-12-29'],
  });
  assert.equal(allowed.used_days, 5);
  assert.equal(allowed.remaining_before_request, 2);
  assert.equal(allowed.remaining_after_request, 0);
  assert.equal(allowed.allowed, true);

  const rejected = buildAnnualEntitlementYearSummary({
    year: 2026,
    limitDays: 7,
    approvedDays: 3,
    pendingDays: 2,
    requestedDays: 3,
  });
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.remaining_before_request, 2);
});

test('server-counted dates are split by calendar year', () => {
  const dates = ['2026-12-30', '2026-12-31', '2027-01-04'];
  assert.deepEqual(countedDatesForCalendarYear(dates, 2026), [
    '2026-12-30',
    '2026-12-31',
  ]);
  assert.deepEqual(countedDatesForCalendarYear(dates, 2027), ['2027-01-04']);
});

test('VL and SL are accrual balances while Mandatory Leave is compliance', () => {
  assert.equal(
    defaultEntitlementBasisForLeaveType('vacationLeave'),
    ENTITLEMENT_BASES.ACCRUAL,
  );
  assert.equal(
    defaultEntitlementBasisForLeaveType('sickLeave'),
    ENTITLEMENT_BASES.ACCRUAL,
  );
  assert.equal(
    defaultEntitlementBasisForLeaveType('mandatoryForcedLeave'),
    ENTITLEMENT_BASES.COMPLIANCE,
  );
  assert.equal(
    defaultEntitlementBasisForLeaveType('studyLeave'),
    ENTITLEMENT_BASES.PER_REQUEST,
  );
});

test('custom entitlement basis accepts valid configuration and rejects drift', () => {
  assert.equal(
    normalizeEntitlementBasis('annual', 'bereavementLeave'),
    ENTITLEMENT_BASES.ANNUAL,
  );
  assert.equal(
    normalizeEntitlementBasis('invalid', 'bereavementLeave'),
    ENTITLEMENT_BASES.PER_REQUEST,
  );
  assert.equal(
    normalizeEntitlementBasis(null, 'maternityLeave'),
    ENTITLEMENT_BASES.PER_EVENT,
  );
});
