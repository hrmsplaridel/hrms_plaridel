'use strict';
const {getDepartmentReviewSnapshot}=require('./departmentHeadService');
const {assertLeaveSubmissionReviewer}=require('./leaveFinalReviewerService');
const {prepareWorkflow}=require('./approvalWorkflows');
async function getLeaveSubmissionAvailability(db,employeeId) {
  const rules=(await db.query('SELECT * FROM leave_types WHERE is_active=true ORDER BY name,id')).rows;
  const profile=(await db.query('SELECT employment_type FROM users WHERE id=$1::uuid',[employeeId])).rows[0];
  const review=await getDepartmentReviewSnapshot(db,employeeId);
  const types=[];
  for(const rule of rules) {
    if(rule.employee_can_file===false || rule.admin_only===true ||
      rule.eligible_employment_types && !rule.eligible_employment_types.includes(profile?.employment_type))continue;
    try {
      if(rule.approval_workflow_id)await prepareWorkflow(db,'leave',rule,employeeId,review);
      else await assertLeaveSubmissionReviewer(db,employeeId,'leave',rule,review);
      types.push({id:rule.id,name:rule.name,can_submit:true});
    }catch(error){
      if(error.statusCode!==409)throw error;
      types.push({id:rule.id,name:rule.name,can_submit:false,reason:error.message});
    }
  }
  const canSubmit=types.some(type=>type.can_submit);
  return {can_submit:canSubmit,types,...(!canSubmit?{reason:types[0]?.reason || 'No leave type has an available approval workflow. Contact HR.'}:{})};
}
module.exports={getLeaveSubmissionAvailability};
