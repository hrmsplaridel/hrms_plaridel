const ACCESS_OUTCOMES = new Set([
  'allowed',
  'denied',
  'missing_attachment',
  'missing_file',
]);

function sameUser(left, right) {
  const a = String(left || '').trim();
  const b = String(right || '').trim();
  return a.length > 0 && a === b;
}

function resolveLocatorAttachmentAccess({
  role,
  userId,
  ownerUserId,
  requestStatus,
  assignedDepartmentHeadId,
  reviewingDepartmentHeadId,
}) {
  const normalizedRole = String(role || '').trim().toLowerCase();
  if (normalizedRole === 'admin' || normalizedRole === 'hr') {
    return { allowed: true, reason: 'hr_or_admin' };
  }
  if (sameUser(userId, ownerUserId)) {
    return { allowed: true, reason: 'request_owner' };
  }
  if (
    requestStatus === 'pending_department_head' &&
    sameUser(userId, assignedDepartmentHeadId)
  ) {
    return { allowed: true, reason: 'assigned_department_head' };
  }
  if (sameUser(userId, reviewingDepartmentHeadId)) {
    return { allowed: true, reason: 'recorded_department_head_reviewer' };
  }
  return { allowed: false, reason: 'not_authorized' };
}

async function recordLocatorAttachmentAccess(
  dbOrClient,
  {
    locatorSlipId,
    attachmentName = null,
    accessedBy,
    actorRole = null,
    accessReason,
    accessOutcome,
    ipAddress = null,
    userAgent = null,
  }
) {
  if (!ACCESS_OUTCOMES.has(accessOutcome)) {
    throw new Error(`Invalid locator attachment access outcome: ${accessOutcome}`);
  }
  return dbOrClient.query(
    `INSERT INTO locator_attachment_access_logs (
       locator_slip_id,
       attachment_name,
       accessed_by,
       actor_role,
       access_reason,
       access_outcome,
       ip_address,
       user_agent,
       accessed_at
     )
     VALUES ($1::uuid, $2::text, $3::uuid, $4::text, $5::text, $6::text, $7::text, $8::text, now())`,
    [
      locatorSlipId,
      attachmentName,
      accessedBy,
      actorRole ? String(actorRole).slice(0, 100) : null,
      accessReason,
      accessOutcome,
      ipAddress ? String(ipAddress).slice(0, 255) : null,
      userAgent ? String(userAgent).slice(0, 1000) : null,
    ]
  );
}

module.exports = {
  ACCESS_OUTCOMES,
  recordLocatorAttachmentAccess,
  resolveLocatorAttachmentAccess,
};
