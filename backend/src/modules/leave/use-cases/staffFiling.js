'use strict';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function fail(statusCode,message){throw Object.assign(new Error(message),{statusCode});}
function person(value,required=false){
 const name=String(value?.name || '').trim(),position_title=String(value?.position_title || '').trim();
 if(!required && !name && !position_title)return null;
 if(!name || !position_title || name.length>200 || position_title.length>200)fail(400,'Enter each paper signatory name and position (up to 200 characters).');
 if(value?.user_id!=null && (typeof value.user_id!=='string'||!UUID.test(value.user_id)))fail(400,'Select a valid signatory account.');
 return {name,position_title,...(value?.user_id?{user_id:value.user_id}: {})};
}
function date(value,label){
 if(typeof value!=='string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value+'T00:00:00Z')) || new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)fail(400,`Enter a valid ${label}.`);
 return value;
}
module.exports=function createStaffFiling(dependencies){
 const {finalizeLeaveApproval,todayInHrmsTimezone}=dependencies;
 const {snapshotPaperSignatures}=require('../services/paperSignatures')(dependencies);
 const today=todayInHrmsTimezone || require('../../../utils/dateRangeParser').todayInHrmsTimezone;
 async function prepareStaffLeave(db,{actor,employeeId,rule,start=null,end=null,paperApproval,hasAttachment=false}){
  if(!actor?.id || !['admin','hr'].includes(actor.role))fail(403,'Authorized HR encoder access is required.');
  if(typeof employeeId!=='string' || !UUID.test(employeeId))fail(400,'Select a valid employee.');
  if(employeeId.toLowerCase()===String(actor.id).toLowerCase())fail(400,'Use My Leave for your own request.');
  if(!rule || rule.is_active===false || rule.admin_can_file===false || rule.allow_approved_paper_filing!==true)fail(403,'Recording approved paper leave is disabled for this leave type.');
  if(!hasAttachment)fail(400,'Upload the fully approved paper form and required supporting documents as one PDF or image.');
  let data=paperApproval;
  if(typeof data==='string'){try{data=JSON.parse(data);}catch(_){fail(400,'Invalid paper approval details.');}}
  if(!data || typeof data!=='object' || Array.isArray(data))fail(400,'Enter the original paper approval details.');
  if(data.confirmed_complete!==true || data.confirmed_not_recorded!==true)fail(400,'Confirm all required paper approvals are complete and this leave has not already been recorded or deducted.');
  const original_filing_date=date(data.original_filing_date,'original filing date');
  const approval_date=date(data.approval_date,'paper approval date');
  if(original_filing_date>approval_date || approval_date>today())fail(400,'Original filing must be on or before approval, and approval cannot be in the future.');
  const final_approver=person(data.final_approver,true);
  const certification_officer=person(data.certification_officer);
  const department_reviewer=person(data.department_reviewer);
  const additional_approvers=String(data.additional_approvers || '').trim();
  if(additional_approvers.length>2000)fail(400,'Additional paper approval details must be 2000 characters or less.');
  const employee=(await db.query(`SELECT id,full_name,employment_type FROM users WHERE id=$1::uuid
    AND is_active=true AND COALESCE(employment_status,'active')='active'
    AND ($2::date IS NULL OR date_hired IS NULL OR date_hired <= $2::date)
    AND ($3::date IS NULL OR separation_date IS NULL OR separation_date >= $3::date)`,[employeeId,start,end])).rows[0];
  if(!employee)fail(400,'Employee is inactive or unavailable during the recorded leave dates.');
  const paperRecord={version:1,source:'approved_paper',original_filing_date,approval_date,final_approver,
    applicant:{user_id:employee.id,name:employee.full_name},
    certification_officer,department_reviewer,additional_approvers,confirmed_complete:true,confirmed_not_recorded:true,encoded_by:actor.id};
  return {rule,paperRecord:await snapshotPaperSignatures(db,{actor,employeeId,leaveType:rule.name,paperRecord})};
 }
 async function completeStaffLeave(db,{actor,row,leaveTypeName,paperRecord,approvedDaysWithPay,approvedDaysWithoutPay,remarks}){
  // This metadata is built by prepareStaffLeave inside the same locked filing transaction.
  if(paperRecord?.source!=='approved_paper' || paperRecord.encoded_by!==actor.id)fail(400,'Validated paper approval details are required.');
  const encoder=(await db.query('SELECT full_name FROM users WHERE id=$1::uuid AND is_active=true',[actor.id])).rows[0];
  if(!encoder)fail(403,'Only an active HR encoder may record paper leave.');
  const record={...paperRecord,encoded_by_name:encoder.full_name};
  const saved=await db.query(`UPDATE leave_requests SET paper_approval_record=$2::jsonb || jsonb_build_object('encoded_at',CURRENT_TIMESTAMP),updated_at=now()
    WHERE id=$1::uuid RETURNING paper_approval_record`,[row.id,JSON.stringify(record)]);
  return (await finalizeLeaveApproval(db,{...row,days:row.number_of_days || row.total_days,leave_type_name:leaveTypeName},
    {id:row.id,reviewerId:actor.id,remarks:remarks || 'Approved paper leave recorded by HR.',paperRecord:saved.rows[0].paper_approval_record,
      approvedDaysWithPayRaw:approvedDaysWithPay,approvedDaysWithoutPayRaw:approvedDaysWithoutPay})).row;
 }
 return {prepareStaffLeave,completeStaffLeave};
};
