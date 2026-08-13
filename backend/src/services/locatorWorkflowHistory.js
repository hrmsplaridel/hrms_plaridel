const LOCATOR_HISTORY_ACTION_TITLES = Object.freeze({
  submitted: 'Submitted',
  retroactive_correction_recorded: 'Retroactive Correction Recorded',
  cancelled: 'Cancelled',
  resubmitted: 'Corrected and Resubmitted',
  department_head_approved: 'Approved by Department Head',
  department_head_rejected: 'Rejected by Department Head',
  department_head_returned: 'Returned by Department Head',
  hr_returned: 'Returned by HR',
  hr_approved: 'Approved by HR',
  approval_revoked: 'Approval Revoked',
  hr_rejected: 'Rejected by HR',
  attachment_replaced: 'Supporting Attachment Replaced',
  attachment_removed: 'Supporting Attachment Removed',
});

function normalizeLocatorRejectionReason(value) {
  const reason = (value ?? '').toString().trim();
  if (!reason) {
    return { valid: false, error: 'Rejection reason is required.' };
  }
  if (reason.length > 1000) {
    return {
      valid: false,
      error: 'Rejection reason must be 1000 characters or fewer.',
    };
  }
  return { valid: true, value: reason };
}

function locatorHistoryTitle(action) {
  const normalized = (action || '').toString().trim();
  if (LOCATOR_HISTORY_ACTION_TITLES[normalized]) {
    return LOCATOR_HISTORY_ACTION_TITLES[normalized];
  }
  return normalized
    .split('_')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

async function recordLocatorWorkflowEvent(client, {
  locatorSlipId,
  action,
  fromStatus = null,
  toStatus = null,
  actorId = null,
  actorRole = null,
  actorName = null,
  remarks = null,
  metadata = {},
}) {
  if (!client?.query) {
    throw new TypeError('A database client is required to record locator history.');
  }
  if (!(locatorSlipId || '').toString().trim()) {
    throw new TypeError('locatorSlipId is required to record locator history.');
  }
  if (!(action || '').toString().trim()) {
    throw new TypeError('action is required to record locator history.');
  }

  const result = await client.query(
    `INSERT INTO locator_slip_history (
       locator_slip_id,
       action,
       from_status,
       to_status,
       actor_id,
       actor_name_snapshot,
       actor_role,
       remarks,
       metadata,
       created_at
     ) VALUES (
       $1::uuid,
       $2::text,
       $3::text,
       $4::text,
       $5::uuid,
       COALESCE(NULLIF($6::text, ''), (
         SELECT full_name FROM users WHERE id = $5::uuid
       )),
       $7::text,
       $8::text,
       $9::jsonb,
       now()
     )
     RETURNING *`,
    [
      locatorSlipId,
      action.toString().trim(),
      fromStatus,
      toStatus,
      actorId,
      actorName,
      actorRole,
      remarks,
      JSON.stringify(metadata || {}),
    ]
  );
  return result.rows[0] || null;
}

function mapLocatorWorkflowEvent(row) {
  return {
    id: row.id,
    locator_slip_id: row.locator_slip_id,
    action: row.action,
    title: locatorHistoryTitle(row.action),
    from_status: row.from_status || null,
    to_status: row.to_status || null,
    actor_id: row.actor_id || null,
    actor_name: row.actor_name_snapshot || null,
    actor_role: row.actor_role || null,
    remarks: row.remarks || null,
    metadata: row.metadata || {},
    created_at: row.created_at || null,
  };
}

async function listLocatorWorkflowEvents(client, locatorSlipId) {
  const result = await client.query(
    `SELECT *
     FROM locator_slip_history
     WHERE locator_slip_id = $1::uuid
     ORDER BY created_at ASC, id ASC`,
    [locatorSlipId]
  );
  return result.rows.map(mapLocatorWorkflowEvent);
}

module.exports = {
  LOCATOR_HISTORY_ACTION_TITLES,
  listLocatorWorkflowEvents,
  locatorHistoryTitle,
  mapLocatorWorkflowEvent,
  normalizeLocatorRejectionReason,
  recordLocatorWorkflowEvent,
};
