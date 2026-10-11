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
 return ['admin','hr'].includes(req.user?.role)?next():res.status(403).json({error:'Final reviewer access required'});
}
module.exports={normalizeRouting,chooseLeaveRoute,requestFinalReviewers,requireLeaveFinalRole};
