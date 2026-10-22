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

const {annualAllowance} = require('../src/services/leaveEntitlementPolicy');
test('annual allowance keeps existing full entitlement behavior by default', () => {
  assert.equal(annualAllowance({max_days:5}, null, 2026).limit_days, 5);
});
test('October hires get prorated whole days and the full limit in January', () => {
  const rule = {max_days:5, first_year_allowance:'prorated'};
  assert.deepEqual(annualAllowance(rule, '2026-10-01', 2026), {
    limit_days:1, full_limit_days:5, calculated_days:1.25, prorated:true, error_message:null,
  });
  assert.equal(annualAllowance(rule, '2026-10-01', 2027).limit_days,5);
});
test('partial hire months use calendar days including the hire date', () => {
  const result = annualAllowance({max_days:12, first_year_allowance:'prorated'}, '2026-10-16', 2026);
  assert.equal(result.limit_days,2);
  assert.equal(result.calculated_days,2.516);
});
test('January 1 hires get full days; late-year hires may have zero usable days', () => {
  const rule = {max_days:5, first_year_allowance:'prorated'};
  assert.equal(annualAllowance(rule,'2026-01-01',2026).limit_days,5);
  assert.equal(annualAllowance(rule,'2026-12-01',2026).limit_days,0);
  assert.equal(annualAllowance(rule,'2027-01-01',2026).limit_days,0);
});
test('missing hire date cannot grant a full allowance for a prorated type', () => {
  const result = annualAllowance({max_days:5, first_year_allowance:'prorated'}, null, 2026);
  assert.equal(result.limit_days,0);
  assert.match(result.error_message,/hire date.*HR/i);
});
