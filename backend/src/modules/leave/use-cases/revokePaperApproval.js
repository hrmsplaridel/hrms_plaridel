'use strict';
const {evaluatePaperRevocation,assertPaperRevocationActor,restorePaperLeaveCredits}=require('../../../services/paperApprovalRevocation');
module.exports=async function revokePaperApproval(db,row,actor,reason,deps) {
  const employeeId=row.user_id||row.employee_id;
  const staff=await assertPaperRevocationActor(db,{actor,employeeId,module:'leave'});
  const policy=evaluatePaperRevocation({status:row.status,paperRecord:row.paper_approval_record,createdAt:row.created_at,reason,windowMs:deps.LEAVE_REVOKE_WINDOW_MS});
  if(!policy.ok)throw Object.assign(new Error(policy.error),{statusCode:policy.statusCode});
  const {restoredDays}=await restorePaperLeaveCredits(db,{requestId:row.id,employeeId,actorId:actor.id,reason:policy.revocationReason,insertLeaveBalanceLedger:deps.insertLeaveBalanceLedger});
  const removed=await deps.removeApprovedLeaveCoverage(db,row.id);
  if(removed===0)await db.query(`DELETE FROM dtr_daily_summary WHERE leave_request_id=$1::uuid
    AND status='on_leave' AND time_in IS NULL AND time_out IS NULL AND break_in IS NULL AND break_out IS NULL`,[row.id]);
  const dateFrom=deps.toIsoDateStr(row.start_date),dateTo=deps.toIsoDateStr(row.end_date);
  const reconciliation=await require('../../../services/dtrMonthEndReconciliation').enqueueEmployeeRangeReconciliation(db,{
    employeeId,dateFrom,dateTo,reason:'paper_leave_approval_revoked',metadata:{leave_request_id:row.id,revoked_by:actor.id},
  });
  const revocation={revoked_by:actor.id,revoked_by_name:staff.full_name,revoked_at:new Date().toISOString(),reason:policy.revocationReason,
    restored_credit_days:restoredDays,reconciliation_required:reconciliation.count>0,reconciliation_months:reconciliation.months};
  // A paper reversal is terminal. It must never reopen an employee-editable request.
  await db.query(`UPDATE leave_requests SET status='cancelled',reviewer_id=$2::uuid,reviewer_remarks=$3::text,
    paper_approval_record=jsonb_set(paper_approval_record,'{revocation}',$4::jsonb,true),updated_at=now() WHERE id=$1::uuid`,
    [row.id,actor.id,policy.revocationReason,JSON.stringify(revocation)]);
  await deps.insertLeaveRequestHistory(db,{leaveRequestId:row.id,action:'revoked',fromStatus:'approved',toStatus:'cancelled',actedBy:actor.id,
    remarks:policy.revocationReason,metadataJson:{approval_source:'approved_paper',...revocation}});
  return {employeeId,dateFrom,dateTo,revocation};
};
