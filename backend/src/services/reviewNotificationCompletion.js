const stages = {
  leave_request: {
    pending_department_head: ['leave_pending_department_head'],
    pending_hr: ['leave_pending_hr', 'leave_forwarded_to_hr'],
    pending_mayor: ['leave_pending_mayor', 'leave_forwarded_to_mayor'],
  },
  locator_slip: {
    pending_department_head: ['locator_pending_department_head'],
    pending_hr: ['locator_pending_hr', 'locator_forwarded_to_hr'],
  },
};

async function completeReviewNotifications(db, referenceType, referenceId, fromStatus, toStatus) {
  const rules = stages[referenceType];
  const stage = fromStatus === 'pending' ? 'pending_hr' : fromStatus;
  if (!rules || fromStatus === toStatus || !rules[stage]) return;
  const next = toStatus === 'pending' ? 'pending_hr' : toStatus;
  const types = rules[next] ? rules[stage] : Object.values(rules).flat();
  await db.query(`UPDATE user_notifications SET read_at = now()
    WHERE reference_type = $1 AND reference_id = $2::uuid AND type = ANY($3::text[]) AND read_at IS NULL`,
    [referenceType, referenceId, types]);
}

// Repair historical or delayed review alerts without touching employee outcomes.
async function reconcileReviewNotifications(db, userId) {
  const terms = [];
  for (const [referenceType, rules] of Object.entries(stages)) {
    const leave = referenceType === 'leave_request';
    const table = leave ? 'leave_requests' : 'locator_slips';
    const history = leave ? 'leave_request_history' : 'locator_slip_history';
    const foreignKey = leave ? 'leave_request_id' : 'locator_slip_id';
    const timestamp = leave ? 'acted_at' : 'created_at';
    for (const [stage, types] of Object.entries(rules)) {
      const statuses = stage === 'pending_hr' ? "'pending', 'pending_hr'" : `'${stage}'`;
      terms.push(`(n.reference_type = '${referenceType}' AND n.type IN (${types.map(t => `'${t}'`).join(', ')})
        AND EXISTS (SELECT 1 FROM ${table} r WHERE r.id = n.reference_id AND (
          r.status NOT IN (${statuses}) OR EXISTS (SELECT 1 FROM ${history} h
            WHERE h.${foreignKey} = r.id AND h.from_status IN (${statuses})
              AND h.to_status NOT IN (${statuses}) AND h.${timestamp} > n.created_at))))`);
    }
  }
  return db.query(`UPDATE user_notifications n SET read_at = now()
    WHERE n.user_id = $1::uuid AND n.read_at IS NULL AND (${terms.join(' OR ')}) RETURNING n.id`, [userId]);
}
module.exports = {completeReviewNotifications, reconcileReviewNotifications};
