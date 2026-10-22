'use strict';
const engine=require('./approvalWorkflows');
const {insertNotificationForUsers}=require('./notificationService');
const {notifyMissingFinalReviewer}=require('./approvalConfigurationNotifications');

// Shared approval alerts are built from the committed request and the same
// resolver as the inbox. Callers cannot accidentally label the next stage with
// stale filing arguments or notify a legacy role-based reviewer list.
async function notifySharedWorkflowReview(db,kind,requestId) {
 const snapshot=await engine.loadRequestWorkflow(db,kind,requestId);
 if(!engine.isShared(snapshot))return false;
 const leave=kind==='leave';
 const row=(await db.query(`SELECT r.*,u.full_name AS employee_name,
   ${leave?'r.start_date::text AS start_date_text,r.end_date::text AS end_date_text,lt.name AS leave_type_name':'r.slip_date::text AS slip_date_text'}
   FROM ${engine.tableFor(kind)} r JOIN users u ON u.id=${leave?'COALESCE(r.employee_id,r.user_id)':'r.employee_id'}
   ${leave?'LEFT JOIN leave_types lt ON lt.id=r.leave_type_id':''}
   WHERE r.id=$1::uuid`,[requestId])).rows[0];
 if(!row||!['pending_hr','pending_mayor'].includes(row.status))return true;
 const saved=row.workflow_snapshot||snapshot;
 if(saved.outcome||saved.current_step>=saved.steps.length)return true;
 const applicant=row.employee_id||row.user_id;
 const ids=[...new Set((await engine.resolveWorkflowReviewers(db,kind,{...row,workflow_snapshot:saved}))
   .map(r=>String(r.id)).filter(id=>id!==String(applicant)))];
 if(!ids.length){await notifyMissingFinalReviewer(db,kind,requestId);return true;}
 const who=row.employee_official_snapshot?.employee_name||row.employee_name||'An employee';
 const type=leave?(row.details?.leave_type_display_name||row.details?.leaveTypeDisplayName||row.leave_type_name||'Leave')
   :(row.request_type_label_snapshot||row.request_type||'Locator');
 const when=leave?`${row.start_date_text} – ${row.end_date_text}`:row.slip_date_text;
 const segments=leave?'':[['am_in','AM IN'],['am_out','AM OUT'],['pm_in','PM IN'],['pm_out','PM OUT']]
   .filter(([key])=>row[key]===true).map(([,label])=>label).join(', ');
 const module=leave?'Leave':'Locator';
 await insertNotificationForUsers(db,ids,{
   category:kind,type:`${kind}_pending_${row.status==='pending_mayor'?'mayor':'hr'}`,
   title:`${module} request needs your approval`,
   body:`${who} submitted ${type} (${when})${segments?` (${segments})`:''}. Open ${module} approvals to review ${engine.stepLabel(saved.steps[saved.current_step])}.`,
   referenceType:leave?'leave_request':'locator_slip',referenceId:requestId,
   metadata:{employee_id:applicant,workflow_approval:true,workflow_step:saved.current_step,
     workflow_version:saved.version,signature_revision:row.signature_revision,...(leave?{leave_type:type}:{})},
 });
 return true;
}
module.exports={notifySharedWorkflowReview};
