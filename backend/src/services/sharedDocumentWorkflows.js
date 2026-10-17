'use strict';
function invalid(message){throw Object.assign(new Error(message),{statusCode:400});}
function validateForDocuments(workflow) {
 if(workflow.is_active===false)invalid('Assign linked document types to another workflow before deactivating this one.');
 if(workflow.steps.some(s=>!s || typeof s!=='object' ||
   !['specific_users','department_reviewers','submitter_department_reviewers','final_hr_reviewers','active_mayor'].includes(s.assignee_source)))
   invalid('DocuTracker document workflows must use electronic approval steps. Manual signing is available only for Leave/Locator.');
}
async function publishDocumentVersion(db,documentType,workflow,actorId) {
 validateForDocuments(workflow);
 await require('./approvalWorkflows').assertActiveSelectedReviewers(db,workflow.steps);
 await db.query("SELECT pg_advisory_xact_lock(hashtext('document-workflow:' || $1::text))",[documentType]);
 const version=(await db.query('SELECT COALESCE(MAX(version),0)::int+1 AS next_version FROM docutracker_routing_config_versions WHERE document_type=$1',[documentType])).rows[0].next_version;
 const json=JSON.stringify(workflow.steps);
 await db.query(`INSERT INTO docutracker_routing_config_versions(document_type,version,steps,review_deadline_hours,created_by,shared_workflow_id,shared_workflow_version)
   VALUES($1,$2,$3::jsonb,24,$4::uuid,$5::uuid,$6)`,[documentType,version,json,actorId,workflow.id,workflow.version]);
 await db.query('UPDATE docutracker_routing_configs SET steps=$2::jsonb,updated_at=now() WHERE document_type=$1',[documentType,json]);
 for(const step of workflow.steps) {
  const id=(await db.query(`INSERT INTO docutracker_workflow_steps(document_type,workflow_version,step_order,department_id,assignee_source,label,enabled)
    VALUES($1,$2,$3,$4::uuid,$5,$6,true) RETURNING id`,[documentType,version,step.step_order,step.department_id||null,step.assignee_source,step.label])).rows[0].id;
  if(step.assignee_source==='specific_users')for(const [index,userId] of step.user_ids.entries())
   await db.query(`INSERT INTO docutracker_workflow_step_assignees(step_id,user_id,is_primary,backup_rank,is_enabled,allowed_actions)
     VALUES($1::uuid,$2::uuid,$3,$4,true,$5::text[])`,[id,userId,index===0,index===0?null:index,step.allowed_actions]);
 }
 await db.query(`INSERT INTO approval_workflow_document_types(document_type,workflow_id,workflow_version,docutracker_version)
   VALUES($1,$2::uuid,$3,$4) ON CONFLICT(document_type) DO UPDATE SET workflow_id=excluded.workflow_id,
   workflow_version=excluded.workflow_version,docutracker_version=excluded.docutracker_version,updated_at=now()`,[documentType,workflow.id,workflow.version,version]);
 return version;
}
async function syncLinkedDocumentWorkflows(db,workflow,actorId) {
 const linked=(await db.query('SELECT document_type,workflow_version FROM approval_workflow_document_types WHERE workflow_id=$1::uuid ORDER BY document_type',[workflow.id])).rows;
 if(linked.length)validateForDocuments(workflow);
 for(const row of linked)if(row.workflow_version!==workflow.version) {
  await db.query("SELECT pg_advisory_xact_lock(hashtext('document-workflow:' || $1::text))",[row.document_type]);
  const current=(await db.query('SELECT workflow_id,workflow_version FROM approval_workflow_document_types WHERE document_type=$1',[row.document_type])).rows[0];
  if(current?.workflow_id!==workflow.id)continue;
  await publishDocumentVersion(db,row.document_type,workflow,actorId);
 }
}
module.exports={publishDocumentVersion,syncLinkedDocumentWorkflows,validateForDocuments};
