const {completeReviewNotifications} = require('./reviewNotificationCompletion');
const LOCATOR_HISTORY_ACTION_TITLES = Object.freeze({
  submitted: 'Submitted',
  paper_approved_recorded: 'Approved Paper Locator Recorded',
  retroactive_correction_recorded: 'Retroactive Correction Recorded',
  cancelled: 'Cancelled',
  resubmitted: 'Corrected and Resubmitted',
  department_head_approved: 'Approved by Department Head',
  department_head_rejected: 'Rejected by Department Head',
  department_head_returned: 'Returned by Department Head',
  hr_returned: 'Returned by HR',
  hr_approved: 'Approved by HR',
  mayor_approved: 'Approved by Mayor',
  mayor_rejected: 'Rejected by Mayor',
  mayor_returned: 'Returned by Mayor',
  mayor_reassigned: 'Reassigned to Current Mayor',
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
  await completeReviewNotifications(client, 'locator_slip', locatorSlipId, fromStatus, toStatus);
  return result.rows[0] || null;
}

function savedWorkflowEventTitle(row) {
  const outcome = /^(?:department_head|hr|mayor)_(approved|rejected|returned)$/.exec(row.action || '')?.[1];
  if (!outcome) return locatorHistoryTitle(row.action);
  const title = {approved:'Approved', rejected:'Rejected', returned:'Returned'}[outcome];
  const action = {approved:'approve', rejected:'reject', returned:'return'}[outcome];
  const snapshot = row.workflow_snapshot;
  if (!Array.isArray(snapshot?.steps)) {
    return row.action.startsWith('hr_') && row.actor_role &&
      !['hr','admin','super_admin'].includes(row.actor_role) ? title : locatorHistoryTitle(row.action);
  }
  const labels = new Set();
  for (const cycle of [snapshot, ...(snapshot.cycles || [])]) {
    for (const decision of cycle.decisions || []) {
      if (!row.actor_id || decision.actor_id !== row.actor_id ||
          (decision.action || 'approve') !== action) continue;
      const step = cycle.steps?.[decision.step];
      const label = typeof step === 'string'
        ? {department:'Department Review', hr:'HR Review', mayor:'Mayor Approval'}[step]
        : step?.label?.trim();
      if (label) labels.add(label);
    }
  }
  return labels.size === 1 ? `${[...labels][0]} · ${title}` : title;
}

function mapLocatorWorkflowEvent(row) {
  return {
    id: row.id,
    locator_slip_id: row.locator_slip_id,
    action: row.action,
    title: savedWorkflowEventTitle(row),
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
    `SELECT history.*, slip.workflow_snapshot
     FROM locator_slip_history history
     JOIN locator_slips slip ON slip.id = history.locator_slip_id
     WHERE history.locator_slip_id = $1::uuid
     ORDER BY history.created_at ASC, history.id ASC`,
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
