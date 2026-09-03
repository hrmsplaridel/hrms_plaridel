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

function buildAnnualEntitlementYearSummary({
  year,
  limitDays,
  approvedDays = 0,
  pendingDays = 0,
  requestedDays = 0,
  requestedCountedDates = [],
}) {
  const limit = Number(limitDays) || 0;
  const approved = Number(approvedDays) || 0;
  const pending = Number(pendingDays) || 0;
  const requested = Number(requestedDays) || 0;
  const used = approved + pending;
  const remainingBeforeRequest = Math.max(0, limit - used);
  return {
    year: Number(year),
    limit_days: limit,
    approved_days: approved,
    pending_days: pending,
    used_days: used,
    requested_days: requested,
    requested_counted_dates: Array.isArray(requestedCountedDates)
      ? [...requestedCountedDates]
      : [],
    remaining_before_request: remainingBeforeRequest,
    remaining_after_request: Math.max(0, remainingBeforeRequest - requested),
    allowed: used + requested <= limit + 0.0001,
  };
}

function countedDatesForCalendarYear(countedDates, year) {
  if (!Array.isArray(countedDates)) return [];
  const prefix = `${Number(year)}-`;
  return countedDates.filter((date) => String(date || '').startsWith(prefix));
}

module.exports = {
  ENTITLEMENT_BASES,
  SYSTEM_ENTITLEMENT_BASIS,
  VALID_ENTITLEMENT_BASES,
  defaultEntitlementBasisForLeaveType,
  normalizeEntitlementBasis,
  buildAnnualEntitlementYearSummary,
  countedDatesForCalendarYear,
};
