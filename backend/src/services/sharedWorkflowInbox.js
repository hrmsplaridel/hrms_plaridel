'use strict';
const engine=require('./approvalWorkflows');
const pagingSupport=require('./workflowInboxPaging');
const {sanitizeEmployeeLeaveDetails,normalizeEmployeeDetailSchema,normalizeEmployeeOfficialSnapshot,customLeaveDetailValues}=require('./leaveRequestDetailsPolicy');
function forbidden(){throw Object.assign(new Error('This workflow request is not assigned to you.'),{statusCode:403});}
async function canRead(db,kind,row,user) {
 if(!engine.isShared(row?.workflow_snapshot))return false;
 const applicant=row.employee_id || row.user_id;
 if(String(applicant)===String(user.id))return true;
 if(row.workflow_snapshot.decisions?.some(d=>String(d.actor_id)===String(user.id)))return true;
 const reviewers=await engine.resolveWorkflowReviewers(db,kind,row);
 return reviewers.some(r=>String(r.id)===String(user.id));
}
// Pending shared requests follow their current assignees and recorded actors,
// even when a legacy endpoint normally permits broader management access.
// null preserves the established policy for completed and pre-workflow records.
async function pendingReadAccess(db,kind,row,user) {
 if(!engine.isShared(row?.workflow_snapshot)||!['pending','pending_department_head','pending_hr','pending_mayor'].includes(row.status))return null;
 return canRead(db,kind,row,user);
}
async function getRequest(db,kind,id,user,{decision=false}={}) {
 const row=(await db.query(`SELECT * FROM ${engine.tableFor(kind)} WHERE id=$1::uuid`,[id])).rows[0];
 if(!await canRead(db,kind,row,user))forbidden();
 if(decision) {
  if(!['pending_hr','pending_mayor'].includes(row.status))throw Object.assign(new Error('This approval cycle is complete.'),{statusCode:409});
  const reviewers=await engine.resolveWorkflowReviewers(db,kind,row);
  if(!reviewers.some(r=>String(r.id)===String(user.id)))forbidden();
 }
 return row;
}
async function listInbox(db,user,options={}) {
 const {includeHistory=false}=options;
 const paging=pagingSupport.optionsFor(options);
 db=pagingSupport.memoizedReads(db);
 const entries=[];
 const sortKeys=new Map();
 const next_cursor={},has_more={};
 for(const kind of paging.kinds) {
  let count=0,last=null;
  has_more[kind]=false;
  next_cursor[kind]=null;
  const table=engine.tableFor(kind),owner=kind==='leave'?'COALESCE(r.employee_id,r.user_id)':'r.employee_id';
  const assignedScope=`(r.status IN ('pending_hr','pending_mayor')
    AND ((r.workflow_snapshot #> ARRAY['steps',r.workflow_snapshot->>'current_step','user_ids']) ? $1::text
      OR (r.workflow_snapshot #>> ARRAY['steps',r.workflow_snapshot->>'current_step','assignee_source'])<>'specific_users'))`;
  const scope=includeHistory?`(${assignedScope} OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(r.workflow_snapshot->'decisions','[]'::jsonb)) decision
    WHERE decision->>'actor_id'=$1::text))`:assignedScope;
  const sql=`SELECT r.*,to_char(r.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS inbox_created_at,u.full_name AS employee_name${kind==='locator'?',r.slip_date::text AS slip_date_text,d.name AS department_name':',lt.name AS leave_type_name'} FROM ${table} r JOIN users u ON u.id=${owner}
    ${kind==='locator'?'LEFT JOIN departments d ON d.id=r.department_id':'LEFT JOIN leave_types lt ON lt.id=r.leave_type_id'}
    WHERE jsonb_typeof(r.workflow_snapshot->'steps'->0)='object'
      AND ${owner}<>$1::uuid
      ${kind==='leave'?'AND r.discarded_at IS NULL':''}
      AND ${scope}`;
  for await(const row of pagingSupport.candidates(db,sql,user.id,paging)) {
   const snapshot=row.workflow_snapshot;
   const pending=!snapshot.outcome&&['pending_hr','pending_mayor'].includes(row.status)&&snapshot.current_step<snapshot.steps.length;
   const reviewers=pending?await engine.resolveWorkflowReviewers(db,kind,row):[];
   const canReview=reviewers.some(r=>String(r.id)===String(user.id));
   const reviewed=snapshot.decisions?.some(d=>String(d.actor_id)===String(user.id));
   if(!canReview&&!(includeHistory&&reviewed))continue;
   if(paging.paginated && count===paging.limit) {
    has_more[kind]=true;
    next_cursor[kind]=pagingSupport.cursorFor(last,kind,includeHistory);
    break;
   }
   count++;
   last=row;
   if(paging.paginated)sortKeys.set(kind+'/'+row.id,{
    rank:['pending_hr','pending_mayor'].includes(row.status)?0:1,
    created:row.inbox_created_at||new Date(row.created_at).toISOString(),
   });
   const step=snapshot.steps[Math.min(snapshot.current_step,snapshot.steps.length-1)];
   const dateOnly=value=>value instanceof Date?value.toISOString().slice(0,10):value?.toString().slice(0,10)||null;
   const leaveSchema=kind==='leave'?normalizeEmployeeDetailSchema(row.employee_detail_schema_snapshot):[];
   const leaveDetails=kind==='leave'?sanitizeEmployeeLeaveDetails(row.details,leaveSchema):{};
   const official=kind==='leave'?normalizeEmployeeOfficialSnapshot(row.employee_official_snapshot):{};
   // Only filing details and official snapshots are exposed; file bytes use the authorized endpoint.
   const requestData={id:row.id,employee_name:row.employee_official_snapshot?.employee_name||row.employee_name,
    status:row.status,created_at:row.created_at,updated_at:row.updated_at,workflow_snapshot:snapshot,date_filed:dateOnly(row.created_at),
    final_review_route:row.final_review_route,attachment_name:row.attachment_name||null,
    ...(kind==='leave'?{...leaveDetails,user_id:row.employee_id||row.user_id,
     approved_at:row.approved_at||null,reviewed_at:row.reviewed_at||null,
     can_revoke_approval:await require('./leaveRevocationAccess').canRevokeSharedLeave(db,row,user),
     start_date:dateOnly(row.start_date),end_date:dateOnly(row.end_date),
     working_days_applied:Number(row.number_of_days??row.total_days??0),
     leave_type:row.leave_type_name||row.leave_type,
     leave_type_display_name:row.details?.leave_type_display_name||row.details?.leaveTypeDisplayName,
     office_department:official.office_department||'',position_title:official.position_title,salary:official.salary,
     date_filed:official.date_filed||dateOnly(row.created_at),reason:row.reason||'',
     employee_detail_schema_snapshot:leaveSchema,custom_details:customLeaveDetailValues(leaveDetails,leaveSchema),
    }:{employee_id:row.employee_id,department_id:row.department_id,department_name:row.department_name||'',
     hr_reviewed_at:row.hr_reviewed_at||null,
     slip_date:dateOnly(row.slip_date_text||row.slip_date),request_type:row.request_type,
     request_type_label:row.request_type_label_snapshot,request_type_short_label:row.request_type_short_label_snapshot,
     request_type_location_label:row.request_type_location_label_snapshot,
     employee_detail_schema_snapshot:row.employee_detail_schema_snapshot||[],additional_details:row.additional_details||{},
     office:row.office||'',reason:row.reason||'',am_in:row.am_in===true,am_out:row.am_out===true,
     pm_in:row.pm_in===true,pm_out:row.pm_out===true})};
   entries.push({id:row.id,kind,employee_name:requestData.employee_name,status:row.status,request_data:requestData,
    workflow_name:snapshot.name,workflow_version:snapshot.version,current_step:snapshot.current_step,
    step_label:engine.stepLabel(step),step_count:snapshot.steps.length,can_review:canReview,allowed_actions:canReview?step.allowed_actions:[],
    signature_revision:row.signature_revision,created_at:row.created_at,
    date:row.start_date || row.slip_date,days:row.number_of_days || row.total_days,
    reason:row.reason || row.remarks || row.purpose || '',office:row.office || '',
    additional_details:kind==='leave'?leaveDetails:row.additional_details || {},
    decisions:(snapshot.decisions||[]).map(d=>({step_label:engine.stepLabel(snapshot.steps[d.step]),action:d.action,reviewer_name:d.signature?.signer_name_snapshot||d.reviewer?.name,acted_at:d.acted_at})),
    detail_schema:row.employee_detail_schema_snapshot || [],
    attachment_name:row.attachment_name || null});
  }
 }
 const items=entries.sort((a,b)=>{
  if(!paging.paginated)return new Date(b.created_at)-new Date(a.created_at);
  const left=sortKeys.get(a.kind+'/'+a.id),right=sortKeys.get(b.kind+'/'+b.id);
  return left.rank-right.rank || right.created.localeCompare(left.created) || b.id.localeCompare(a.id);
 });
 return paging.paginated?{items,has_more,next_cursor,limit:paging.limit}:items;
}
module.exports={canRead,pendingReadAccess,getRequest,listInbox};
