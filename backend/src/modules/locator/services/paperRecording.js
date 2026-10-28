'use strict';
const {publicPaperRecord}=require('../../leave/services/paperSignatures');
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function fail(code,message){throw Object.assign(new Error(message),{statusCode:code});}
function date(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value+'T00:00:00Z'))||new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)fail(400,'Enter valid original filing and paper approval dates.');return value;}
function person(value,required=false){
 const name=String(value?.name||'').trim(),position_title=String(value?.position_title||'').trim();
 if(!required&&!name&&!position_title)return null;
 if(!name||!position_title||name.length>200||position_title.length>200)fail(400,'Enter each paper official’s name and position (up to 200 characters).');
 if(value?.user_id&&!UUID.test(value.user_id))fail(400,'Select a valid signatory account.');
 return {name,position_title,...(value?.user_id?{user_id:value.user_id}:{})};
}
module.exports=function createPaperRecording(deps){
 const profile=deps.findAssignmentProfileByUserIdAtDate||require('../../leave/services/signatories')({}).findAssignmentProfileByUserIdAtDate;
 const today=deps.todayInHrmsTimezone||require('../../../utils/dateRangeParser').todayInHrmsTimezone;
 const suggest=deps.suggestPaperSignatories||require('../../leave/services/paperSignatories')({
  findAssignmentProfileByUserIdAtDate:profile,todayInHrmsTimezone:today,
  resolveDepartmentReviewers:require('../../../services/departmentReviewerService').resolveDepartmentReviewers,
  resolveFinalLeaveReviewerConfiguration:require('../../../services/leaveFinalReviewerService').resolveFinalLeaveReviewerConfiguration,
  resolveActiveMayor:require('../../../services/officialSignatoryService').resolveActiveMayor,
  resolveOfficialSignatory:async()=>null,
  getLeaveTypeDefinition:async(db,code)=>{
   const type=await deps.getLocatorTypeByCode(db,code,{activeOnly:true});
   return type?{...type,admin_can_file:true,allow_approved_paper_filing:true,approval_route:type.approval_route==='mayor_direct'?'mayor':type.approval_route}:null;
  },
 }).suggestPaperSignatories;
 const {snapshotPaperSignatures}=require('../../leave/services/paperSignatures')({suggestPaperSignatories:suggest});
 async function recordPaperLocator({actor,employeeId,slipDate,requestType,office,reason,slots,attachment,paperApproval,additionalDetails,fullShift=false}){
  if(!actor?.id||!['admin','hr'].includes(actor.role))fail(403,'Authorized HR encoder access is required.');
  if(!UUID.test(employeeId||'')||employeeId.toLowerCase()===actor.id.toLowerCase())fail(400,'Select another employee for the approved paper record.');
  if(!attachment?.path)fail(400,'Upload the fully signed original paper locator and supporting documents.');
  date(slipDate);
  let data=paperApproval;if(typeof data==='string'){try{data=JSON.parse(data);}catch(_){fail(400,'Invalid paper approval details.');}}
  if(!data||data.confirmed_complete!==true||data.confirmed_not_recorded!==true)fail(400,'Verify the signed original is complete and this locator has not already been recorded.');
  const filed=date(data.original_filing_date),approved=date(data.approval_date);
  if(filed>approved||approved>today())fail(400,'Original filing must be on or before approval, and approval cannot be in the future.');
  const final=person(data.final_approver,true),department=person(data.department_reviewer);
  const extra=String(data.additional_approvers||'').trim();if(extra.length>2000)fail(400,'Additional approval details must be 2000 characters or less.');
  const db=await deps.pool.connect();
  try{
   await db.query('BEGIN');
   const encoder=(await db.query("SELECT id,full_name,role FROM users WHERE id=$1::uuid AND is_active=true",[actor.id])).rows[0];
   if(!encoder||!['hr','admin'].includes(encoder.role))fail(403,'An active HR encoder account is required.');
   const employee=(await db.query(`SELECT id,full_name FROM users WHERE id=$1::uuid AND is_active=true AND role <> 'super_admin'
     AND COALESCE(employment_status,'active')='active' AND (date_hired IS NULL OR date_hired<=$2::date)
     AND (separation_date IS NULL OR separation_date>=$2::date)`,[employeeId,slipDate])).rows[0];
   if(!employee)fail(400,'Employee is unavailable on the locator date.');
   const type=await deps.getLocatorTypeByCode(db,requestType,{activeOnly:true});if(!type)fail(400,'Select an active locator type.');
   if(fullShift){
    const coverage=await deps.resolveLocatorShiftCoverage(db,employeeId,require('../../../services/locatorFilingRules').parseLocatorDateOnly(slipDate));
    if(!coverage.can_file)fail(400,coverage.error);
    slots={amIn:true,amOut:!coverage.single_session,pmIn:!coverage.single_session,pmOut:true};
   }
   const fields=require('../../../services/locatorFilingRules').validateLocatorRequiredFields({slipDate,requestType,office,reason,slots});
   if(!fields.valid)fail(400,fields.error);
   const working=await deps.validateLocatorWorkingDayForEmployee(db,employeeId,require('../../../services/locatorFilingRules').parseLocatorDateOnly(slipDate),slots);
   if(!working.ok)fail(400,working.error);
   const conflict=await deps.findLocatorRequestConflicts(db,{employeeId,slipDate,slots,phase:'submission'});
   if(!conflict.ok)fail(409,conflict.message||'This locator is already recorded or conflicts with attendance or leave.');
   const assignment=await profile(db,employeeId,slipDate);
   const record=await snapshotPaperSignatures(db,{actor,employeeId,leaveType:requestType,paperRecord:{version:1,source:'approved_paper',
    original_filing_date:filed,approval_date:approved,applicant:{user_id:employee.id,name:employee.full_name,position_title:assignment?.position_title||''},
    final_approver:final,department_reviewer:department,additional_approvers:extra,
    confirmed_complete:true,confirmed_not_recorded:true,encoded_by:actor.id,encoded_by_name:encoder.full_name,encoded_at:new Date().toISOString()}});
   let reconciliation=false;
   if((await db.query("SELECT to_regclass('public.leave_attendance_deductions') AS table_name")).rows[0]?.table_name)
    reconciliation=(await db.query("SELECT 1 FROM leave_attendance_deductions WHERE user_id=$1::uuid AND service_month=date_trunc('month',$2::date)::date LIMIT 1",[employeeId,slipDate])).rows.length>0;
   const meta=deps.captureLocatorTypeSnapshot(type);
   const schema=deps.normalizeLocatorFieldSchema(type.employee_detail_schema);
   let details;try{details=deps.locatorDetailValues(additionalDetails,schema);}catch(error){fail(400,error.message);}
   const roles={applicant:record.applicant,department_head:record.department_reviewer,hr_approver:record.final_approver};
   const payload={employee_id:employeeId,department_id:assignment?.department_id||null,slip_date:slipDate,
    am_in:slots.amIn,am_out:slots.amOut,pm_in:slots.pmIn,pm_out:slots.pmOut,request_type:requestType,office:office.trim(),reason:reason.trim(),
    request_type_label_snapshot:meta.label,request_type_short_label_snapshot:meta.shortLabel,
    request_type_location_label_snapshot:meta.locationLabel,request_type_location_hint_snapshot:meta.locationHint,
    request_type_dtr_slot_label_snapshot:meta.dtrSlotLabel,request_type_dtr_print_label_snapshot:meta.dtrPrintLabel,
    request_type_requires_attachment_snapshot:true,request_type_coverage_mode_snapshot:meta.coverageMode,request_type_snapshot_at:new Date().toISOString(),
    employee_detail_schema_snapshot:schema,additional_details:details,attachment_path:attachment.path,attachment_name:attachment.name,
    attachment_mime_type:attachment.mimeType,attachment_uploaded_at:new Date().toISOString(),status:'approved',hr_reviewer_id:null,
    hr_reviewed_at:approved+'T00:00:00+08:00',final_review_route:'hr',workflow_snapshot:null,paper_approval_record:record,
    month_end_reconciliation_required:reconciliation,
    print_signatories:Object.fromEntries(Object.entries(roles).map(([key,p])=>[key,{id:p?.user_id||null,name:p?.name||'',position_title:p?.position_title||''}]))};
   const columns=Object.keys(payload).join(',');
   const saved=(await db.query(`INSERT INTO locator_slips (${columns}) SELECT ${columns} FROM jsonb_populate_record(NULL::locator_slips,$1::jsonb) RETURNING *`,[JSON.stringify(payload)])).rows[0];
   await deps.recordLocatorWorkflowEvent(db,{locatorSlipId:saved.id,action:'paper_approved_recorded',fromStatus:null,toStatus:'approved',actorId:actor.id,actorRole:actor.role,
    remarks:'Approved paper locator recorded by HR.',metadata:{paper_approval_record:publicPaperRecord(record),reconciliation_required:reconciliation}});
   await db.query('COMMIT');return saved;
  }catch(error){try{await db.query('ROLLBACK');}catch(_){}throw error;}finally{db.release();}
 }
 return {recordPaperLocator,suggestLocatorPaperSignatories:(db,options)=>suggest(db,{...options,leaveType:options.requestType})};
};
