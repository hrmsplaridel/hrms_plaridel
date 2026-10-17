const {normalizeEligibleEmploymentTypes}=require('./leaveEmploymentEligibility');
function normalizeRouting(body){
 const route=body.approval_route||'hr';
 if(!['hr','mayor'].includes(route))throw Object.assign(new Error('Invalid approval routing'),{statusCode:400});
 return {approval_route:route,mayor_employment_types:route==='hr'?null:normalizeEligibleEmploymentTypes(body.mayor_employment_types)};
}
function chooseLeaveRoute(rule,employmentType){
 return rule?.approval_route==='mayor' && (rule.mayor_employment_types==null||rule.mayor_employment_types.includes(employmentType))?'mayor':'hr';
}
async function requestFinalReviewers(db,requestId,fallback){
 if(!requestId)return fallback();
 const row=(await db.query('SELECT final_review_route,final_reviewer_user_id FROM leave_requests WHERE id=$1::uuid',[requestId])).rows[0];
 if(row?.final_review_route!=='mayor')return fallback();
 // The Mayor signs on paper; department approval is the final system decision.
 return [];
}
function requireLeaveFinalRole(req,res,next){
 if(['admin','hr'].includes(req.user?.role)) return next();
 if(req.user?.role!=='mayor' || !req.params?.id && !['/','/pending','/filter-options','/final-reviewer/me'].includes(req.path))
  return res.status(403).json({error:'Final reviewer access required'});
 return (async()=>{
  const db=require('../config/db').pool;
  const mayor=await require('./officialSignatoryService').resolveActiveMayor(db,require('../utils/dateRangeParser').todayInHrmsTimezone());
  if(String(mayor?.employee_id)!==String(req.user.id))return res.status(403).json({error:'Current Mayor access required'});
  if(req.params?.id){
   const snapshot=await require('./approvalWorkflows').loadRequestWorkflow(db,'leave',req.params.id);
   if(!snapshot || require('./approvalWorkflows').stepKind(snapshot.steps[snapshot.current_step])!=='mayor')return res.status(403).json({error:'This request is not awaiting Mayor approval.'});
  }
  return next();
 })().catch(()=>res.status(503).json({error:'Approval authority could not be verified'}));
}
module.exports={normalizeRouting,chooseLeaveRoute,requestFinalReviewers,requireLeaveFinalRole};
