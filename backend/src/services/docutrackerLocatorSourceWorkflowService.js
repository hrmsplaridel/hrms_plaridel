'use strict';

const engine = require('./approvalWorkflows');
const inbox = require('./sharedWorkflowInbox');
const {memoizedReads} = require('./workflowInboxPaging');
const {canReadLocatorAsMayor} = require('./locatorMayorAccess');
const {resolveEligibleFinalReviewers} = require('./leaveFinalReviewerService');
const {listLocatorWorkflowEvents} = require('./locatorWorkflowHistory');

const PENDING = new Set(['pending','pending_department_head','pending_hr','pending_mayor']);
const same = (a,b) => Boolean(a && b) && String(a) === String(b);

// Deliberately select metadata only. Original attachments and signature ink use
// their existing authorized endpoints, never the merged document-list payload.
const SELECT = `SELECT ls.id,ls.employee_id,ls.department_id,ls.status,ls.workflow_snapshot,
  ls.assigned_department_head_id,ls.dept_head_reviewer_id,ls.hr_reviewer_id,ls.final_review_route,
  ls.slip_date::text AS slip_date_text,ls.request_type,ls.request_type_label_snapshot,
  ls.office,ls.reason,ls.am_in,ls.am_out,ls.pm_in,ls.pm_out,ls.attachment_name,
  ls.created_at,ls.updated_at,ls.paper_approval_record,u.full_name AS employee_name,
  t.label AS request_type_label,
  EXISTS(SELECT 1 FROM locator_slip_department_reviewers r
    WHERE r.locator_slip_id=ls.id AND r.reviewer_id=$1::uuid) AS viewer_is_department_reviewer,
  EXISTS(SELECT 1 FROM locator_slip_history h
    WHERE h.locator_slip_id=ls.id AND h.actor_id=$1::uuid) AS viewer_participated
  FROM locator_slips ls JOIN users u ON u.id=ls.employee_id
  LEFT JOIN locator_request_types t ON t.code=ls.request_type`;

async function access(db,row,user,dependencies={}) {
  if (!row || !user?.id) return {read:false,review:false};
  const owner = same(row.employee_id,user.id);
  if (owner) return {read:true,review:false};
  if (!PENDING.has(row.status) && ['hr','admin'].includes(user.role)) return {read:true,review:false};
  const shared = engine.isShared(row.workflow_snapshot);
  const assigned = shared && await (dependencies.sharedRead || inbox.canRead)(db,'locator',row,user);
  const pending = PENDING.has(row.status);
  if (shared && pending && !assigned) return {read:false,review:false};
  const mayor = await (dependencies.mayorRead || canReadLocatorAsMayor)(db,user,row.final_review_route);
  const read = owner || assigned || ['hr','admin'].includes(user.role) || mayor ||
    same(row.assigned_department_head_id,user.id) || same(row.dept_head_reviewer_id,user.id) ||
    row.viewer_is_department_reviewer === true;
  if (!read || owner || !pending || row.paper_approval_record) return {read,review:false};
  let reviewers;
  if (shared) reviewers = await (dependencies.reviewers || inbox.reviewersForRead)(db,'locator',row);
  else if (row.status === 'pending_department_head') return {read,review:
    same(row.assigned_department_head_id,user.id) || row.viewer_is_department_reviewer === true};
  else if (row.final_review_route === 'mayor_direct') return {read,review:mayor};
  else reviewers = await (dependencies.finalReviewers || resolveEligibleFinalReviewers)(db,row.employee_id,'locator',row.id);
  return {read,review:reviewers.some(r => same(r.id,user.id))};
}

async function listLocatorSourceRows(pool,user) {
  const db = memoizedReads(pool);
  const result = await db.query(`${SELECT}
    WHERE ls.employee_id=$1::uuid OR $2::text IN ('hr','admin','mayor')
      OR ls.workflow_snapshot IS NOT NULL
      OR ls.assigned_department_head_id=$1::uuid OR ls.dept_head_reviewer_id=$1::uuid OR ls.hr_reviewer_id=$1::uuid
      OR EXISTS(SELECT 1 FROM locator_slip_department_reviewers r WHERE r.locator_slip_id=ls.id AND r.reviewer_id=$1::uuid)
      OR EXISTS(SELECT 1 FROM locator_slip_history h WHERE h.locator_slip_id=ls.id AND h.actor_id=$1::uuid)`,[user.id,user.role]);
  const rows=[];
  for (const row of result.rows) {
    const allowed = await access(db,row,user);
    if (!allowed.read) continue;
    const label = row.request_type_label_snapshot || row.request_type_label || 'Locator';
    rows.push({source_module:'dtr',source_table:'locator_slips',source_record_id:String(row.id),
      source_title:`${label} · ${row.slip_date_text}`,description:row.reason || row.office || 'Locator request',
      source_status:row.status,source_owner_id:row.employee_id,created_by:row.employee_id,creator_name:row.employee_name,
      created_at:row.created_at,updated_at:row.updated_at,viewer_can_review:allowed.review,
      viewer_participated_in_source:row.viewer_participated === true || same(row.dept_head_reviewer_id,user.id) || same(row.hr_reviewer_id,user.id)});
  }
  return rows;
}

function mappedStatus(status) {
  return require('./docutrackerWorkflowService').mapSourceStatusToDocuTracker('dtr',status,'locator_slips');
}

async function getLocatorSourceWorkflow(pool,user,id,dependencies={}) {
  if (!user?.id || !/^[0-9a-f-]{36}$/i.test(id || '')) return null;
  const db=memoizedReads(pool);
  const row=(await db.query(`${SELECT} WHERE ls.id=$2::uuid`,[user.id,id])).rows[0];
  if (!(await access(db,row,user,dependencies)).read) return null;
  const history=await (dependencies.history || listLocatorWorkflowEvents)(db,id);
  let snapshot=row.workflow_snapshot;
  if (!snapshot?.steps?.length) {
    const department=row.assigned_department_head_id || row.dept_head_reviewer_id || history.some(h=>h.action.startsWith('department_head_'));
    const steps=[...(department?['department']:[]),row.final_review_route==='mayor_direct'?'mayor':'hr'];
    snapshot={steps,current_step:row.status==='pending_department_head'?0:steps.length-1,decisions:[]};
  }
  const terminal=!PENDING.has(row.status) && row.status!=='returned_for_correction';
  const steps=[];
  if (row.paper_approval_record) {
    const person=row.paper_approval_record.final_approver;
    steps.push({step_order:1,label:'Original paper approval',indicator:{kind:row.status==='approved'?'approved':'cancelled',label:row.status.toUpperCase()},
      reviewers:person?[{id:person.user_id,name:person.name,role:'actual_reviewer'}]:[]});
  } else for (let i=0;i<snapshot.steps.length;i++) {
    const step=snapshot.steps[i],kind=engine.stepKind(step);
    const decision=(snapshot.decisions||[]).findLast(d=>d.step===i);
    const legacyPrefix={department:'department_head_',hr:'hr_',mayor:'mayor_'}[kind];
    const legacy=!engine.isShared(snapshot) && legacyPrefix?history.findLast(h=>h.action.startsWith(legacyPrefix) && /_(approved|rejected|returned)$/.test(h.action)):null;
    const actor=decision?.actor_id || legacy?.actor_id;
    const current=i===snapshot.current_step;
    const action=decision?.action || (decision?'approve':legacy?.action.split('_').at(-1));
    let state=['approve','approved'].includes(action)?'approved':['reject','rejected'].includes(action)?'rejected':['return','returned'].includes(action)?'returned':
      kind==='manual_mayor' && row.status==='approved'?'unrecorded':current && !terminal?'current':'upcoming';
    if (current && row.status==='returned_for_correction') state='returned';
    if (current && row.status==='revoked') state='cancelled';
    if (!decision && !legacy && terminal && row.status==='approved' && kind!=='manual_mayor') state=engine.isShared(snapshot)?'unrecorded':'approved';
    let reviewers=[];
    if (actor) reviewers=[{id:actor,name:decision?.signature?.signer_name_snapshot || history.findLast(h=>same(h.actor_id,actor))?.actor_name || 'Reviewer',role:'actual_reviewer'}];
    else if (!terminal && kind!=='manual_mayor') reviewers=await (dependencies.reviewers || inbox.reviewersForRead)(db,'locator',{...row,workflow_snapshot:{...snapshot,current_step:i}});
    steps.push({step_order:i+1,label:engine.stepLabel(step),indicator:{kind:state,label:state==='unrecorded'?kind==='manual_mayor'?'MANUAL SIGNING':'NOT RECORDED':state.toUpperCase()},reviewers});
  }
  return {source_status:row.status,status:mappedStatus(row.status),
    current_step:terminal || row.paper_approval_record || snapshot.current_step>=snapshot.steps.length?null:snapshot.current_step+1,
    workflow_name:snapshot.name,workflow_version:snapshot.version,steps,
    request_data:{id:row.id,employee_name:row.employee_name,slip_date:row.slip_date_text,uses_shared_workflow:engine.isShared(row.workflow_snapshot),
      request_type_label:row.request_type_label_snapshot || row.request_type_label,office:row.office,reason:row.reason,
      am_in:row.am_in,am_out:row.am_out,pm_in:row.pm_in,pm_out:row.pm_out,attachment_name:row.attachment_name},
    history:history.map(h=>({id:h.id,document_id:`source:dtr:${id}`,action:h.title || h.action,
      actor_id:h.actor_id,actor_name:h.actor_name,from_status:h.from_status?mappedStatus(h.from_status):null,
      to_status:h.to_status?mappedStatus(h.to_status):null,remarks:h.remarks,created_at:h.created_at})),
  };
}

module.exports={listLocatorSourceRows,getLocatorSourceWorkflow,locatorSourceAccess:access};
