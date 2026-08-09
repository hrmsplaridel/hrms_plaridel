const ENTITLEMENT_BASES = Object.freeze({
  ACCRUAL: 'accrual',
  ANNUAL: 'annual',
  PER_EVENT: 'per_event',
  PER_REQUEST: 'per_request',
  COMPLIANCE: 'compliance',
});

const VALID_ENTITLEMENT_BASES = new Set(Object.values(ENTITLEMENT_BASES));

const SYSTEM_ENTITLEMENT_BASIS = Object.freeze({
  vacationLeave: ENTITLEMENT_BASES.ACCRUAL,
  sickLeave: ENTITLEMENT_BASES.ACCRUAL,
  mandatoryForcedLeave: ENTITLEMENT_BASES.COMPLIANCE,
  specialPrivilegeLeave: ENTITLEMENT_BASES.ANNUAL,
  soloParentLeave: ENTITLEMENT_BASES.ANNUAL,
  tenDayVawcLeave: ENTITLEMENT_BASES.ANNUAL,
  maternityLeave: ENTITLEMENT_BASES.PER_EVENT,
  paternityLeave: ENTITLEMENT_BASES.PER_EVENT,
  rehabilitationPrivilege: ENTITLEMENT_BASES.PER_EVENT,
  specialLeaveBenefitsForWomen: ENTITLEMENT_BASES.PER_EVENT,
  specialEmergencyCalamityLeave: ENTITLEMENT_BASES.PER_EVENT,
  adoptionLeave: ENTITLEMENT_BASES.PER_EVENT,
  studyLeave: ENTITLEMENT_BASES.PER_REQUEST,
  others: ENTITLEMENT_BASES.PER_REQUEST,
});

function defaultEntitlementBasisForLeaveType(leaveTypeName) {
  const name = String(leaveTypeName || '').trim();
  return SYSTEM_ENTITLEMENT_BASIS[name] || ENTITLEMENT_BASES.PER_REQUEST;
}

function normalizeEntitlementBasis(value, leaveTypeName) {
  const normalized = String(value || '').trim().toLowerCase();
  return VALID_ENTITLEMENT_BASES.has(normalized)
    ? normalized
    : defaultEntitlementBasisForLeaveType(leaveTypeName);
}

module.exports = {
  ENTITLEMENT_BASES,
  SYSTEM_ENTITLEMENT_BASIS,
  VALID_ENTITLEMENT_BASES,
  defaultEntitlementBasisForLeaveType,
  normalizeEntitlementBasis,
};
