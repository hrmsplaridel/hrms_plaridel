'use strict';

const {todayInHrmsTimezone} = require('../utils/dateRangeParser');
const {normalizePrintPolicy} = require('./workflowPrintPolicy');
const STEP_LABELS = {department:'Department Review', hr:'HR Review', mayor:'Mayor Approval', manual_mayor:'Manual Mayor Signing'};
const STATUS = {department:'pending_department_head', hr:'pending_hr', mayor:'pending_mayor'};
function stepKind(step) {
  if(!step)return null;
  if(typeof step==='string')return step;
  return step?.assignee_source==='active_mayor'?'mayor':step?.assignee_source==='manual_mayor'?'manual_mayor':'hr';
}
function stepLabel(step) {return typeof step==='string'?STEP_LABELS[step]:step?.label;}
function isShared(snapshot) {return snapshot?.steps?.some(step=>typeof step==='object' && step!==null)===true;}
function isDepartmentOnlyWorkflow(snapshot) {
  return snapshot?.steps?.length===1 &&
    ['submitter_department_reviewers','department_reviewers'].includes(snapshot.steps[0]?.assignee_source);
}
function workflowRoute(snapshot) {return snapshot.steps.some(s=>stepKind(s)==='mayor')?'mayor_direct':snapshot.steps.some(s=>stepKind(s)==='manual_mayor')?'mayor':'hr';}
function legacyStep(step,index) {
  return {step_order:index+1,label:STEP_LABELS[step],assignee_type:'user',
    assignee_source:{department:'submitter_department_reviewers',hr:'final_hr_reviewers',mayor:'active_mayor',manual_mayor:'manual_mayor'}[step],
    user_ids:[],requires_signature:true,allowed_actions:['approve','return','reject'],enabled:true};
}
function normalizeSharedSteps(steps) {
  if(!steps.length || steps.length>20)throw error('Choose between 1 and 20 approval steps.');
  return steps.map((input,index)=>{
    const step=typeof input==='string'?legacyStep(input,index):input;
    if(!step || step.step_order!==index+1 || !String(step.label||'').trim() || String(step.label).length>100 || step.enabled===false)
      throw error('Each approval step needs a name and consecutive step order.');
    const source=step.assignee_source;
    if(!['specific_users','submitter_department_reviewers','department_reviewers','final_hr_reviewers','active_mayor','manual_mayor'].includes(source))throw error('Choose a valid approver source.');
    const ids=step.user_ids || [];
    if(!Array.isArray(ids) || source==='specific_users' && (!ids.length || ids.length>6 || new Set(ids).size!==ids.length || ids.some(id=>!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(id))))throw error('Choose a primary reviewer and up to five different backups.');
    if(source==='department_reviewers' && !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(step.department_id||''))throw error('Select a department for this step.');
    if(source==='manual_mayor' && (index!==steps.length-1 || index===0))throw error('Manual signing must follow a system approval and go last.');
    const actions=step.allowed_actions || ['approve','return','reject'];
    if(!Array.isArray(actions) || !actions.includes('approve') || actions.some(a=>!['approve','return','reject'].includes(a)))throw error('Approval steps must allow approval; return and reject are optional.');
    return {step_order:index+1,label:String(step.label).trim(),assignee_type:'user',assignee_source:source,
      department_id:source==='department_reviewers'?step.department_id:null,user_ids:source==='specific_users'?[...ids]:[],
      enabled:true,requires_signature:true,allowed_actions:[...new Set(actions)]};
  });
}
function error(message, statusCode = 400) { return Object.assign(new Error(message), {statusCode}); }
function hasDistinctReviewers(groups) {
  const assigned=new Map();
  function match(index,visited) {
    for(const id of groups[index]) {
      if(visited.has(id))continue;
      visited.add(id);
      if(!assigned.has(id) || match(assigned.get(id),visited)) {
        assigned.set(id,index);return true;
      }
    }
    return false;
  }
  return groups.every((_,index)=>match(index,new Set()));
}
function normalizeWorkflow(body = {}) {
  const name = String(body.name || '').trim();
  const steps = body.steps;
  const self_filing_signatory_policy = normalizePrintPolicy(body.self_filing_signatory_policy);
  if (!name || name.length > 100) throw error('Enter a workflow name of up to 100 characters.');
  if(Array.isArray(steps) && steps.some(s=>s && typeof s==='object'))return {name,steps:normalizeSharedSteps(steps),is_active:body.is_active!==false,self_filing_signatory_policy};
  if (!Array.isArray(steps) || !steps.length || steps.length > 3 ||
      steps.some(s => !Object.hasOwn(STEP_LABELS,s)) || new Set(steps).size !== steps.length ||
      steps.includes('department') && steps[0] !== 'department' ||
      steps.includes('mayor') && steps.at(-1) !== 'mayor' ||
      steps.includes('manual_mayor') && (steps.at(-1) !== 'manual_mayor' || steps.length < 2) ||
      steps.includes('mayor') && steps.includes('manual_mayor')) {
    throw error('Choose unique approval steps. Department review goes first; Mayor approval or manual signing goes last.');
  }
  return {name, steps:[...steps], is_active:body.is_active !== false,self_filing_signatory_policy};
}
function workflowStatus(snapshot) {
  if (snapshot.outcome) return snapshot.outcome;
  return STATUS[stepKind(snapshot.steps[snapshot.current_step])] || 'approved';
}
function nextWorkflowStep(snapshot, actor, action) {
  if (!['approve','reject','return'].includes(action)) throw error('Invalid workflow action.');
  const current=snapshot.steps[snapshot.current_step];
  if (snapshot.outcome || !STATUS[stepKind(current)]) throw error('This review cycle is complete.',409);
  if(typeof current==='object' && !current.allowed_actions.includes(action))throw error('This action is not allowed for this workflow step.',403);
  if ((snapshot.decisions || []).some(d => d.actor_id === actor.id && d.action === 'approve' || d.actor_id === actor.id && d.action == null)) {
    throw error('A different reviewer must approve each workflow step.',403);
  }
  const next = structuredClone(snapshot);
  next.decisions = [...(next.decisions || []), {step:next.current_step, actor_id:actor.id, action, acted_at:new Date().toISOString()}];
  if (action !== 'approve') next.outcome = action === 'return' ? 'returned' :
    stepKind(current) === 'department' ? 'rejected_by_department_head' : stepKind(current) === 'mayor' ? 'rejected' : 'rejected_by_hr';
  else {
    next.current_step++;
    if (stepKind(next.steps[next.current_step]) === 'manual_mayor') {
      next.manual_signing_required = true;
      next.current_step++;
    }
  }
  return next;
}
function tableFor(kind) {
  if (!['leave','locator'].includes(kind)) throw error('Invalid request module.');
  return kind === 'leave' ? 'leave_requests' : 'locator_slips';
}
async function loadRequestWorkflow(db, kind, id) {
  return (await db.query(`SELECT workflow_snapshot FROM ${tableFor(kind)} WHERE id=$1::uuid`,[id])).rows[0]?.workflow_snapshot || null;
}
async function isCurrentMayor(db,user) {
  if(user?.role!=='mayor' || !user.id)return false;
  const mayor=await require('./officialSignatoryService').resolveActiveMayor(db,todayInHrmsTimezone());
  return String(mayor?.employee_id)===String(user.id);
}
async function resolveWorkflowReviewers(db, kind, row, dependencies = {}) {
  const snapshot = row.workflow_snapshot;
  const index=snapshot.current_step < snapshot.steps.length ? snapshot.current_step :
    snapshot.steps.findLastIndex(step=>Object.hasOwn(STATUS,stepKind(step)));
  const step = snapshot.steps[index];
  const applicant = row.employee_id || row.user_id;
  const excluded = new Set([String(applicant), ...(snapshot.decisions || [])
    .filter(d => d.step !== index && (d.action === 'approve' || !d.action)).map(d => String(d.actor_id))]);
  let reviewers = [];
  if(typeof step==='object' && ['specific_users','submitter_department_reviewers','department_reviewers'].includes(step.assignee_source)) {
    let ids;
    try {ids=await require('./docutrackerWorkflowService').resolveStepAssignees(db,{stepConfig:step,submitterUserId:applicant});}
    catch(e) {if(e.code==='VALIDATION')throw error(e.message,409);throw e;}
    reviewers=(await db.query(`SELECT id,full_name AS name,role FROM users WHERE id=ANY($1::uuid[])
      AND is_active=true AND COALESCE(employment_status,'active')='active'`,[ids])).rows;
    reviewers.sort((a,b)=>ids.indexOf(String(a.id))-ids.indexOf(String(b.id)));
  } else if (step === 'department') {
    const table = kind === 'leave' ? 'leave_request_department_reviewers' : 'locator_slip_department_reviewers';
    const key = kind === 'leave' ? 'leave_request_id' : 'locator_slip_id';
    reviewers = (await db.query(`SELECT u.id, u.full_name AS name FROM ${table} r
      JOIN users u ON u.id=r.reviewer_id WHERE r.${key}=$1::uuid AND u.is_active=true`,[row.id])).rows;
  } else if (stepKind(step) === 'hr') {
    const resolve = dependencies.final || require('./leaveFinalReviewerService').resolveFinalLeaveReviewerConfiguration;
    const config = await resolve(db);
    reviewers = config.reviewers.filter(r => r.role !== 'admin' || r[`${kind}_allowed`] === true);
  } else if (stepKind(step) === 'mayor') {
    const resolve = dependencies.mayor || require('./officialSignatoryService').resolveActiveMayor;
    const mayor = await resolve(db,todayInHrmsTimezone());
    if (mayor) reviewers = [{id:mayor.employee_id,name:mayor.name}];
  }
  return reviewers.filter(r => !excluded.has(String(r.id)));
}
async function prepareWorkflow(db, kind, rule, applicantId, reviewSnapshot) {
  if (!rule?.approval_workflow_id && !rule?.approval_workflow_snapshot) return null;
  const saved=rule.approval_workflow_snapshot;
  const workflow = saved ? {...saved,is_active:true} : (await db.query(`SELECT w.id,w.name,w.is_active,v.version,v.steps,v.self_filing_signatory_policy
    FROM approval_workflows w JOIN approval_workflow_versions v ON v.workflow_id=w.id AND v.version=w.current_version
    WHERE w.id=$1::uuid`,[rule.approval_workflow_id])).rows[0];
  if (!workflow?.is_active) throw error('The selected approval workflow is inactive or unavailable. Contact HR.',409);
  let steps = workflow.steps;
  const configuredSteps=[...steps];
  if(rule.authorized_staff_auto_approval && !isShared({steps}) && steps.at(-1)==='hr')steps=['hr'];
  const snapshot = {id:workflow.id,name:workflow.name,version:workflow.version,steps:[...steps],current_step:0,decisions:[],
    self_filing_signatory_policy:normalizePrintPolicy(workflow.self_filing_signatory_policy)};
  if(rule.authorized_staff_auto_approval && steps.length===1 && steps[0]==='hr')snapshot.staff_auto_approval={configured_steps:configuredSteps};
  const candidates=[];
  for (let i=0;i<steps.length;i++) {
    const step=steps[i];
    if (stepKind(step)==='manual_mayor') {
      const mayor=await require('./officialSignatoryService').resolveActiveMayor(db,todayInHrmsTimezone());
      if(!mayor || String(mayor.employee_id)===String(applicantId))throw error('Configure an eligible active Mayor for manual signing.',409);
      continue;
    }
    let reviewers;
    if (step==='department') reviewers=[...new Set([reviewSnapshot?.departmentHeadUserId,
      ...(reviewSnapshot?.reviewerUserIds || [])].filter(Boolean))].map(id=>({id}));
    else reviewers=await resolveWorkflowReviewers(db,kind,{employee_id:applicantId,workflow_snapshot:{...snapshot,current_step:i}});
    const ids=[...new Set(reviewers.map(r=>String(r.id)).filter(id=>id!==String(applicantId)))];
    if (!ids.length) throw error(`No eligible ${stepLabel(step)} reviewer is available. Configure reviewer assignments before filing.`,409);
    candidates.push(ids);
  }
  if (!hasDistinctReviewers(candidates)) throw error('Configure a different eligible reviewer for each approval step.',409);
  return snapshot;
}
async function saveWorkflow(db,kind,id,snapshot) {
  if (!snapshot) return;
  const decision=snapshot.decisions?.at(-1);
  if(decision?.action==='approve' && !decision.signature) {
    const signatureTable=kind==='leave'?'docutracker_leave_signatures':'docutracker_locator_signatures';
    const foreignKey=kind==='leave'?'leave_request_id':'locator_slip_id';
    const signature=(await db.query(`SELECT s.signature_asset_id,s.signed_by,s.signer_name_snapshot,s.signed_at,s.revision
      FROM ${signatureTable} s JOIN ${tableFor(kind)} r ON r.id=s.${foreignKey}
      WHERE r.id=$1::uuid AND s.revision=r.signature_revision AND s.signed_by=$2::uuid
      ORDER BY s.signed_at DESC LIMIT 1`,[id,decision.actor_id])).rows[0];
    if(signature) {
      decision.signature=signature;
      if(isShared(snapshot) || snapshot.self_filing_signatory_policy==='actual_reviewer')decision.reviewer=await reviewerProfile(db,decision.actor_id);
    }
  }
  await db.query(`UPDATE ${tableFor(kind)} SET workflow_snapshot=$2::jsonb WHERE id=$1::uuid`,[id,JSON.stringify(snapshot)]);
  if (isShared(snapshot)) await require('./reviewNotificationCompletion').completeWorkflowReviewNotifications(db,kind,id,snapshot);
}
async function reviewerProfile(db,userId) {
 return (await db.query(`SELECT u.id AS employee_id,u.full_name AS name,u.role,p.name AS position_title
   FROM users u LEFT JOIN LATERAL (SELECT a.position_id FROM assignments a WHERE a.employee_id=u.id
     AND (a.is_active IS NULL OR a.is_active=true)
     AND a.effective_from<=$2::date AND (a.effective_to IS NULL OR a.effective_to>=$2::date)
     ORDER BY a.effective_from DESC,a.created_at DESC LIMIT 1) a ON true
   LEFT JOIN positions p ON p.id=a.position_id WHERE u.id=$1::uuid`,[userId,todayInHrmsTimezone()])).rows[0] || null;
}
async function printOfficials(db,kind,row) {
 const snapshot=row.workflow_snapshot;
 if(!isShared(snapshot))return null;
 const indices=snapshot.steps.map((s,i)=>stepKind(s)!=='manual_mayor'?i:null).filter(i=>i!==null);
 async function official(index) {
  const decision=snapshot.decisions?.find(d=>d.step===index && d.action==='approve');
  if(decision?.reviewer)return {...decision.reviewer,id:decision.actor_id};
  const reviewers=decision?[{id:decision.actor_id}]:await resolveWorkflowReviewers(db,kind,{...row,workflow_snapshot:{...snapshot,current_step:index}});
  if(!reviewers[0])return {id:null,name:'',position_title:''};
  const profile=await reviewerProfile(db,reviewers[0].id);
  return {...profile,id:reviewers[0].id,name:decision?.signature?.signer_name_snapshot||profile?.name||reviewers[0].name||''};
 }
 const first=indices[0],last=indices.at(-1);
 if(isDepartmentOnlyWorkflow(snapshot)) {
  return {department_head:await official(first),hr_approver:{id:null,name:'',position_title:''}};
 }
 if(stepKind(snapshot.steps.at(-1))==='manual_mayor') {
  const mayor=row.status==='approved' && row.approving_authority_snapshot?.name?row.approving_authority_snapshot:
    row.print_signatories?.hr_approver || await require('./officialSignatoryService').resolveActiveMayor(db,todayInHrmsTimezone());
  return {department_head:await official(first),hr_approver:{...mayor,id:mayor?.id || mayor?.employee_id || null}};
 }
 return {department_head:first!==last?await official(first):{id:null,name:'',position_title:''},hr_approver:await official(last)};
}
// Completed steps keep immutable signature snapshots. The shared signing slot
// may still contain their ink until the next reviewer signs; do not present it
// as the current step's signature.
function currentStepSignature(row,signature) {
 const snapshot=row.workflow_snapshot;
 if(!signature || !isShared(snapshot) || snapshot.outcome ||
   !['pending','pending_hr','pending_mayor'].includes(row.status))return signature;
 const belongsToCompletedStep=snapshot.decisions?.some(d=>d.action==='approve' &&
   d.step!==snapshot.current_step && String(d.actor_id)===String(signature.signed_by));
 return belongsToCompletedStep?null:signature;
}
async function decisionSignatures(db,row) {
 const snapshot=row.workflow_snapshot;
 if(!isShared(snapshot) || !['pending','pending_hr','pending_mayor','pending_department_head','approved'].includes(row.status))return [];
 const decisions=(snapshot.decisions||[]).filter(d=>d.action==='approve' && d.signature?.revision===row.signature_revision);
 if(!decisions.length)return [];
 const assets=(await db.query(`SELECT id,owner_user_id,mime_type,encode(image_bytes,'base64') AS signature_image_base64
   FROM docutracker_signature_assets WHERE id=ANY($1::uuid[])`,[decisions.map(d=>d.signature.signature_asset_id)])).rows;
 return decisions.flatMap(d=>{
  const asset=assets.find(a=>String(a.id)===String(d.signature.signature_asset_id) && String(a.owner_user_id)===String(d.actor_id));
  return asset?[{...d.signature,...asset,id:null,slot_key:`workflow_step_${d.step+1}`,label:stepLabel(snapshot.steps[d.step]),
    signed_by:d.actor_id,assigned_signer_id:d.actor_id,signer_name_snapshot:d.signature.signer_name_snapshot,can_sign:false,can_assign:false}]:[];
 });
}
async function initialWorkflow(db,kind,id,prepared) {
  if (!prepared) return null;
  const previous=await loadRequestWorkflow(db,kind,id);
  const snapshot=previous ? {...prepared,
    cycles:[...(previous.cycles || []),{workflow_id:previous.id,version:previous.version,steps:previous.steps,
      self_filing_signatory_policy:previous.self_filing_signatory_policy ?? 'mayor',
      decisions:previous.decisions || [],outcome:previous.outcome || null}]} : prepared;
  const route=workflowRoute(snapshot);
  const mayor=route!=='hr'?await require('./officialSignatoryService').resolveActiveMayor(db,todayInHrmsTimezone()):null;
  await db.query(`UPDATE ${tableFor(kind)} SET workflow_snapshot=$2::jsonb, status=$3,
    final_review_route=$4,final_reviewer_user_id=$5::uuid WHERE id=$1::uuid`,
    [id,JSON.stringify(snapshot),workflowStatus(snapshot),route,mayor?.employee_id || null]);
  return snapshot;
}
async function selectedWorkflowId(db,value) {
  if (value==null) return null;
  if(!/^[a-f0-9-]{36}$/i.test(String(value))) throw error('Select a valid approval workflow.');
  const row=(await db.query('SELECT id FROM approval_workflows WHERE id=$1::uuid AND is_active=true',[value])).rows[0];
  if(!row) throw error('Select an active approval workflow.');
  return row.id;
}
async function assertActiveSelectedReviewers(db,steps) {
 const ids=[...new Set(steps.flatMap(step=>typeof step==='object' && step.assignee_source==='specific_users'?step.user_ids:[]))];
 if(!ids.length)return;
 const active=(await db.query("SELECT id FROM users WHERE id=ANY($1::uuid[]) AND is_active=true AND COALESCE(employment_status,'active')='active'",[ids])).rows;
 if(active.length!==ids.length)throw error('Choose an active reviewer for every primary and backup assignment.');
}
async function workflowDecision(db,kind,id,actorId,action,expected=null) {
  if(!await loadRequestWorkflow(db,kind,id))return null;
  const row=(await db.query(`SELECT * FROM ${tableFor(kind)} WHERE id=$1::uuid FOR UPDATE`,[id])).rows[0];
  if (!row?.workflow_snapshot) return null;
  const snapshot=row.workflow_snapshot;
  if(expected && (expected.step!==snapshot.current_step || expected.revision!==row.signature_revision))throw error('This request changed. Refresh before reviewing.',409);
  if (workflowStatus(snapshot)!==row.status) throw error('This workflow step is no longer pending.',409);
  const reviewers=await resolveWorkflowReviewers(db,kind,row);
  if (!reviewers.some(r=>String(r.id)===String(actorId))) throw error('Only an eligible reviewer for the current workflow step can act.',403);
  const next=nextWorkflowStep(snapshot,{id:actorId},action);
  if(kind==='locator' && action==='return')next.outcome='returned_for_correction';
  if(kind==='locator' && action==='reject' && stepKind(snapshot.steps[snapshot.current_step])!=='department')next.outcome='rejected_by_hr';
  if (action==='approve' && workflowStatus(next)!=='approved') {
    const remaining=[];
    for(let index=next.current_step;index<next.steps.length;index++) {
      if(stepKind(next.steps[index])==='manual_mayor')continue;
      const available=await resolveWorkflowReviewers(db,kind,{...row,workflow_snapshot:{...next,current_step:index}});
      remaining.push(available.map(r=>String(r.id)));
    }
    if (!hasDistinctReviewers(remaining)) throw error('No different eligible reviewer is available for the remaining approval steps. Contact HR.',409);
  }
  return {snapshot:next,status:workflowStatus(next),step:snapshot.steps[snapshot.current_step]};
}
module.exports={normalizeWorkflow,workflowStatus,nextWorkflowStep,resolveWorkflowReviewers,prepareWorkflow,saveWorkflow,
  initialWorkflow,selectedWorkflowId,loadRequestWorkflow,workflowDecision,tableFor,isCurrentMayor,STEP_LABELS,
    stepKind,stepLabel,isShared,isDepartmentOnlyWorkflow,workflowRoute,legacyStep,normalizeSharedSteps,reviewerProfile,printOfficials,assertActiveSelectedReviewers,decisionSignatures,currentStepSignature};
