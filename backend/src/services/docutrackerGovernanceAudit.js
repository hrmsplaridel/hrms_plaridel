async function writeGovernanceAudit(client, {
  actorId,
  eventType,
  entityType,
  entityId = null,
  documentType = null,
  workflowVersion = null,
  targetUserId = null,
  targetRoleId = null,
  beforeState = null,
  afterState = null,
  reason = null,
}) {
  if (!actorId || !eventType || !entityType) return;
  await client.query(
    `INSERT INTO docutracker_governance_audit
       (actor_id, event_type, entity_type, entity_id, document_type,
        workflow_version, target_user_id, target_role_id, before_state,
        after_state, reason)
     VALUES ($1::uuid, $2, $3, $4, $5, $6, $7::uuid, $8, $9::jsonb, $10::jsonb, $11)`,
    [
      actorId,
      eventType,
      entityType,
      entityId,
      documentType,
      workflowVersion,
      targetUserId,
      targetRoleId,
      beforeState == null ? null : JSON.stringify(beforeState),
      afterState == null ? null : JSON.stringify(afterState),
      reason,
    ]
  );
}

module.exports = { writeGovernanceAudit };
