const APPROVAL_DAY_TOLERANCE = 0.0001;

function allocationError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function parseApprovalDays(rawValue, fieldLabel) {
  if (rawValue == null || String(rawValue).trim() === '') {
    throw allocationError(`${fieldLabel} is required.`);
  }

  const value = Number(rawValue);
  if (!Number.isFinite(value)) {
    throw allocationError(`${fieldLabel} must be a valid number.`);
  }
  if (value < 0) {
    throw allocationError(`${fieldLabel} cannot be negative.`);
  }

  const rounded = Math.round(value * 100) / 100;
  if (Math.abs(value - rounded) > APPROVAL_DAY_TOLERANCE) {
    throw allocationError(`${fieldLabel} can have at most 2 decimal places.`);
  }
  return rounded;
}

function resolveApprovalAllocation({
  requestedDays,
  approvedDaysWithPay,
  approvedDaysWithoutPay,
}) {
  const requested = Number(requestedDays);
  if (!Number.isFinite(requested) || requested <= 0) {
    throw allocationError('The leave request must have a valid number of requested days.');
  }

  const withPay = parseApprovalDays(approvedDaysWithPay, 'Approved days with pay');
  const withoutPay = parseApprovalDays(
    approvedDaysWithoutPay,
    'Approved days without pay'
  );
  const allocated = withPay + withoutPay;

  if (Math.abs(allocated - requested) > APPROVAL_DAY_TOLERANCE) {
    throw allocationError(
      `Approved days with pay plus days without pay must equal the ${requested} requested day(s).`
    );
  }

  return {
    requestedDays: requested,
    approvedDaysWithPay: withPay,
    approvedDaysWithoutPay: withoutPay,
    usedDaysToDeduct: withPay,
  };
}

function approvedPaidDaysForRevoke({ requestedDays, approvedDaysWithPay }) {
  const storedPaidDays = Number(approvedDaysWithPay);
  if (
    approvedDaysWithPay != null &&
    approvedDaysWithPay !== '' &&
    Number.isFinite(storedPaidDays) &&
    storedPaidDays >= 0
  ) {
    return storedPaidDays;
  }

  const legacyRequestedDays = Number(requestedDays);
  return Number.isFinite(legacyRequestedDays) && legacyRequestedDays > 0
    ? legacyRequestedDays
    : 0;
}

module.exports = {
  APPROVAL_DAY_TOLERANCE,
  approvedPaidDaysForRevoke,
  resolveApprovalAllocation,
};
