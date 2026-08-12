const LOCATOR_REVOKE_WINDOW_DAYS = 3;
const LOCATOR_REVOKE_WINDOW_MS =
  LOCATOR_REVOKE_WINDOW_DAYS * 24 * 60 * 60 * 1000;

function normalizeLocatorRevocationReason(value) {
  const reason = String(value || '').trim();
  return reason.length >= 10 && reason.length <= 1000 ? reason : null;
}

function evaluateLocatorRevocation({
  status,
  approvedAt,
  reason,
  now = new Date(),
}) {
  if (status !== 'approved') {
    return {
      ok: false,
      statusCode: 409,
      code: 'locator_not_approved',
      error: `Cannot revoke a locator request with status '${status}'. Only approved requests can be revoked.`,
    };
  }

  const revocationReason = normalizeLocatorRevocationReason(reason);
  if (!revocationReason) {
    return {
      ok: false,
      statusCode: 400,
      code: 'locator_revocation_reason_required',
      error: 'A revocation reason between 10 and 1000 characters is required.',
    };
  }

  const approvedDate = approvedAt ? new Date(approvedAt) : null;
  if (!approvedDate || Number.isNaN(approvedDate.getTime())) {
    return {
      ok: false,
      statusCode: 409,
      code: 'locator_approval_time_missing',
      error:
        'Cannot determine the HR approval time for this locator request.',
    };
  }

  const deadline = new Date(approvedDate.getTime() + LOCATOR_REVOKE_WINDOW_MS);
  if (now.getTime() > deadline.getTime()) {
    return {
      ok: false,
      statusCode: 409,
      code: 'locator_revoke_window_expired',
      error: `The revoke period has expired. Locator approval can only be revoked within ${LOCATOR_REVOKE_WINDOW_DAYS} days after HR approval.`,
      deadline,
    };
  }

  return { ok: true, revocationReason, deadline };
}

module.exports = {
  LOCATOR_REVOKE_WINDOW_DAYS,
  LOCATOR_REVOKE_WINDOW_MS,
  evaluateLocatorRevocation,
  normalizeLocatorRevocationReason,
};
