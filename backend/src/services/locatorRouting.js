const {normalizeEligibleEmploymentTypes}=require('./leaveEmploymentEligibility');
const {resolveActiveMayor}=require('./officialSignatoryService');
const {todayInHrmsTimezone}=require('../utils/dateRangeParser');
function error(message){return Object.assign(new Error(message),{statusCode:409});}
function normalizeLocatorRouting(body={},existing={}) {
 const route=body.approval_route ?? existing.approval_route ?? 'hr';
 if(!['hr','mayor','mayor_direct'].includes(route))throw Object.assign(error('Invalid locator approval route'),{statusCode:400});
 if(route!=='hr' && (body.auto_approve_admin ?? existing.auto_approve_admin)===true)
   throw Object.assign(error('HR auto approval cannot be enabled for Mayor routing'),{statusCode:400});
 return {approval_route:route,mayor_employment_types:route==='hr'?null:normalizeEligibleEmploymentTypes(body.mayor_employment_types===undefined?existing.mayor_employment_types:body.mayor_employment_types)};
}
function chooseLocatorRoute(rule,type) {
 return rule?.approval_route && rule.approval_route!=='hr' &&
   (rule.mayor_employment_types==null || rule.mayor_employment_types.includes(type))?rule.approval_route:'hr';
}
async function resolveLocatorRouting(db,applicantId,rule,headId,reviewSnapshot=null) {
 if(rule?.approval_workflow_id || rule?.approval_workflow_snapshot) {
  const engine=require('./approvalWorkflows');
  const snapshot=await engine.prepareWorkflow(db,'locator',rule,applicantId,reviewSnapshot || {departmentHeadUserId:headId,reviewerUserIds:headId?[headId]:[]});
  const route=engine.workflowRoute(snapshot);
  const mayor=route!=='hr'?await resolveActiveMayor(db,todayInHrmsTimezone()):null;
  return {route,mayorId:mayor?.employee_id||null,status:engine.workflowStatus(snapshot),workflow:snapshot};
 }
 if(!rule?.approval_route || rule.approval_route==='hr')return {route:'hr',mayorId:null,status:headId?'pending_department_head':'pending_hr'};
 const profile=(await db.query('SELECT employment_type FROM users WHERE id=$1::uuid',[applicantId])).rows[0];
 const route=chooseLocatorRoute(rule,profile?.employment_type);
 if(route==='hr')return {route,mayorId:null,status:headId?'pending_department_head':'pending_hr'};
 const mayor=await resolveActiveMayor(db,todayInHrmsTimezone());
 if(!mayor || String(mayor.employee_id)===String(applicantId))throw error('No eligible active Mayor is configured. Contact HR before submitting.');
 if(route==='mayor'&&!headId)throw error('A department reviewer is required for manual Mayor signing.');
 return {route,mayorId:mayor.employee_id,status:route==='mayor_direct'?'pending_mayor':'pending_department_head'};
}
async function locatorFinalReviewers(db,requestId,fallback) {
 if(!requestId)return fallback();
 const row=(await db.query('SELECT final_review_route FROM locator_slips WHERE id=$1::uuid',[requestId])).rows[0];
 if(row?.final_review_route==='mayor')return [];
 if(row?.final_review_route==='mayor_direct') {
   const mayor=await resolveActiveMayor(db,todayInHrmsTimezone());
   return mayor?[{id:mayor.employee_id,name:mayor.name}]:[];
 }
 return fallback();
}
function requireLocatorFinalRole(req,res,next) {
 return ['admin','hr','mayor'].includes(req.user?.role)?next():res.status(403).json({error:'Final reviewer access required'});
}
module.exports={normalizeLocatorRouting,chooseLocatorRoute,resolveLocatorRouting,locatorFinalReviewers,requireLocatorFinalRole};
