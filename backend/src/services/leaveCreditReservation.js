const CREDIT_DAY_PRECISION = 1000;

function roundCreditDays(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  return Math.round(numeric * CREDIT_DAY_PRECISION) / CREDIT_DAY_PRECISION;
}

function calculateCreditReservation({ requestedDays, availableDays }) {
  const requested = Math.max(0, roundCreditDays(requestedDays));
  const available = Math.max(0, roundCreditDays(availableDays));
  const reservedDays = Math.min(requested, available);

  return {
    requestedDays: requested,
    reservedDays: roundCreditDays(reservedDays),
    potentialWithoutPayDays: roundCreditDays(requested - reservedDays),
  };
}

function calculateApprovalCreditHeadroom({
  remainingDays,
  pendingDays,
  reservedCreditDays,
}) {
  const remaining = roundCreditDays(remainingDays);
  const pending = Math.max(0, roundCreditDays(pendingDays));
  const ownReservation = Math.max(0, roundCreditDays(reservedCreditDays));
  return Math.max(0, roundCreditDays(remaining - pending + ownReservation));
}

module.exports = {
  calculateApprovalCreditHeadroom,
  calculateCreditReservation,
  roundCreditDays,
};
