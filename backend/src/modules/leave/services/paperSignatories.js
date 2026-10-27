'use strict';
const {resolveOfficialSignatory:defaultCertifier}=require('../../../services/officialSignatoryService');
const {chooseLeaveRoute}=require('../../../services/leaveRouting');
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function fail(statusCode,message){throw Object.assign(new Error(message),{statusCode});}
function validDate(value,label){
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value+'T00:00:00Z'))||new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)fail(400,`Enter a valid ${label} (YYYY-MM-DD).`);
 return value;
}
module.exports=function createPaperSignatories({getLeaveTypeDefinition,findAssignmentProfileByUserIdAtDate,
 resolveDepartmentReviewers,resolveFinalLeaveReviewerConfiguration,resolveActiveMayor,todayInHrmsTimezone,
 resolveOfficialSignatory=defaultCertifier}) {
 async function suggestPaperSignatories(db,{employeeId,leaveType,filingDate,approvalDate}){
  if(typeof employeeId!=='string'||!UUID.test(employeeId))fail(400,'Select a valid employee.');
  if(typeof leaveType!=='string'||!leaveType.trim())fail(400,'Select a leave type.');
  const filed=validDate(filingDate,'original filing date');
  const effective=validDate(approvalDate || filed,'paper approval date');
  if(filed>effective||effective>todayInHrmsTimezone())fail(400,'Original filing must be on or before approval, and approval cannot be in the future.');
  const rule=await getLeaveTypeDefinition(db,leaveType.trim());
  if(!rule||rule.admin_can_file===false||rule.allow_approved_paper_filing!==true)fail(403,'Recording approved paper leave is disabled for this leave type.');
  const employee=(await db.query("SELECT id,employment_type FROM users WHERE id=$1::uuid AND is_active=true AND COALESCE(employment_status,'active')='active'",[employeeId])).rows[0];
  if(!employee)fail(404,'Employee not found or inactive.');
  const employeeProfile=await findAssignmentProfileByUserIdAtDate(db,employeeId,filed);
  const profiles=new Map();
  const signatureAvailability=new Map();
  async function candidate(raw,role,label){
   const userId=raw?.reviewerId||raw?.employee_id||raw?.id;
   if(!userId||String(userId).toLowerCase()===employeeId.toLowerCase())return null;
   if(!profiles.has(userId))profiles.set(userId,await findAssignmentProfileByUserIdAtDate(db,userId,effective));
   const profile=profiles.get(userId);
   const name=raw.reviewerName||raw.name||profile?.full_name;
   if(!name)return null;
   if(!signatureAvailability.has(userId))signatureAvailability.set(userId,(await db.query('SELECT EXISTS (SELECT 1 FROM docutracker_signature_assets WHERE owner_user_id=$1::uuid AND is_saved = true) AS has_saved_signature',[userId])).rows[0]?.has_saved_signature===true);
   return {user_id:userId,name,has_saved_signature:signatureAvailability.get(userId),position_title:raw.position_title||profile?.position_title||'',reviewer_role:role,step_label:label};
  }
  const departmentCache=new Map();
  async function department(departmentId,label){
   if(!departmentId)return [];
   if(!departmentCache.has(departmentId))departmentCache.set(departmentId,await resolveDepartmentReviewers(db,{departmentId,effectiveDate:effective,excludeUserId:employeeId}));
   const config=departmentCache.get(departmentId);
   return (await Promise.all((config.reviewers||[]).map(row=>candidate(row,row.reviewerRole||'backup',label)))).filter(Boolean);
  }
  const hrConfig=await resolveFinalLeaveReviewerConfiguration(db,effective);
  async function hr(label){return (await Promise.all([
   ...(hrConfig.primary?[candidate(hrConfig.primary,'primary',label)]:[]),
   ...(hrConfig.backups||[]).map(row=>candidate(row,'backup',label)),
  ])).filter(Boolean);}
  async function mayor(label){const person=await resolveActiveMayor(db,effective);const result=await candidate(person,'primary',label);return result?[result]:[];}
  async function resolveStep(step){
   const source=typeof step==='string'?({department:'submitter_department_reviewers',hr:'final_hr_reviewers',mayor:'active_mayor',manual_mayor:'manual_mayor'}[step]):step?.assignee_source;
   const label=(typeof step==='object'?step.label:null)||String(step);
   if(source==='submitter_department_reviewers')return department(employeeProfile?.department_id,label);
   if(source==='department_reviewers')return department(step.department_id,label);
   if(source==='final_hr_reviewers')return hr(label);
   if(source==='active_mayor'||source==='manual_mayor')return mayor(label);
   if(source==='specific_users'){
    const ids=[...new Set((step.user_ids||[]).filter(value=>typeof value==='string'&&UUID.test(value)))];
    if(!ids.length)return [];
    const active=(await db.query("SELECT id,full_name AS name FROM users WHERE id=ANY($1::uuid[]) AND is_active=true AND COALESCE(employment_status,'active')='active'",[ids])).rows;
    return (await Promise.all(ids.map((id,index)=>{
     const row=active.find(value=>String(value.id)===String(id));
     return row?candidate(row,index===0?'primary':'backup',label):null;
    }))).filter(Boolean);
   }
   return [];
  }
  let workflow=rule.approval_workflow_snapshot||null;
  if(!workflow&&rule.approval_workflow_id)workflow=(await db.query(`SELECT w.id,w.name,w.is_active,v.steps,v.version
    FROM approval_workflows w JOIN approval_workflow_versions v ON v.workflow_id=w.id AND v.version=w.current_version
    WHERE w.id=$1::uuid`,[rule.approval_workflow_id])).rows[0]||null;
  const warnings=[];
  if(rule.approval_workflow_id&&!workflow)warnings.push('The current workflow is unavailable. Confirm the paper signers using Other signatory.');
  if(workflow?.is_active===false)warnings.push('This workflow is currently inactive. Verify the original paper signers.');
  let final=[];let recommendation=[];
  if(Array.isArray(workflow?.steps)&&workflow.steps.length){
   const groups=[];for(const step of workflow.steps)groups.push(await resolveStep(step));
   final=groups.at(-1);
   recommendation=groups.slice(0,-1).flat();
   // A department-only form may also name that official in its recommendation block.
   if(groups.length===1&&['department','submitter_department_reviewers','department_reviewers'].includes(typeof workflow.steps[0]==='string'?workflow.steps[0]:workflow.steps[0].assignee_source))recommendation=groups[0];
  } else if(!rule.approval_workflow_id) {
   recommendation=await department(employeeProfile?.department_id,'Department review');
   final=chooseLeaveRoute(rule,employee.employment_type)==='mayor'?await mayor('Manual Mayor signing'):await hr('Final HR review');
  }
  const certifier=await resolveOfficialSignatory(db,'leave_credit_certifier',effective);
  const cert=await candidate(certifier||hrConfig.primary,'primary',certifier?'Leave-credit certifier':'Final HR designation');
  function unique(rows){const seen=new Set();return rows.filter(row=>{const key=String(row.user_id);if(seen.has(key))return false;seen.add(key);return true;});}
  return {effective_date:effective,workflow_name:workflow?.name||null,final_approver:unique(final),department_reviewer:unique(recommendation),certification_officer:cert?[cert]:[],warnings};
 }
 return {suggestPaperSignatories};
};
