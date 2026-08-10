const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ENTITLEMENT_BASES,
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
