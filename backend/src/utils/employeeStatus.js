const EMPLOYMENT_STATUSES = new Set([
  'active',
  'inactive',
  'resigned',
  'retired',
  'terminated',
  'deceased',
  'contract_expired',
]);

function normalizeEmploymentStatus(value) {
  return typeof value === 'string' && EMPLOYMENT_STATUSES.has(value)
    ? value
    : 'active';
}

function accountIsActiveForEmploymentStatus(employmentStatus) {
  return normalizeEmploymentStatus(employmentStatus) === 'active';
}

function leaveCreditEligibleForEmploymentStatus(
  employmentStatus,
  requestedEligibility
) {
  return (
    normalizeEmploymentStatus(employmentStatus) === 'active' &&
    requestedEligibility !== false
  );
}

module.exports = {
  normalizeEmploymentStatus,
  accountIsActiveForEmploymentStatus,
  leaveCreditEligibleForEmploymentStatus,
};
