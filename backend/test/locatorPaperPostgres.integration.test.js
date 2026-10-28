'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {Client}=require('pg'),fs=require('fs'),path=require('path');
const id=n=>`99999999-9999-4999-8999-${String(n).padStart(12,'0')}`;
test('approved paper Locator persists evidence and frozen signatures, prevents duplicate coverage, and remains distinct from electronic approval',
 {skip:!process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL},async()=>{
 const url=new URL(process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL);assert.match(url.pathname,/^\/hrms_workflow_audit_[a-f0-9]{16}$/);
 process.env.DATABASE_URL=url.toString();
 const db=new Client({connectionString:url.toString()});await db.connect();
 try{
  await db.query(fs.readFileSync(path.resolve(__dirname,'../scripts/init-schema.sql'),'utf8'));
  const migration=fs.readFileSync(path.resolve(__dirname,'../scripts/migrations/dtr/20261028_locator_approved_paper_recording.sql'),'utf8');
  await db.query(migration);await db.query(migration);
  await db.query("UPDATE users SET is_active=false WHERE role='mayor'");
  for(const [n,role] of [[1,'hr'],[2,'employee'],[3,'mayor'],[4,'supervisor']])
   await db.query("INSERT INTO users(id,email,password_hash,full_name,role,employment_type,date_hired) VALUES($1,$2,'test-only',$3,$4,'permanent','2025-01-01')",[id(n),`paper-locator-${n}@test.local`,`Paper Person ${n}`,role]);
  await db.query("INSERT INTO departments(id,name) VALUES($1,'Paper Locator Audit')",[id(10)]);
  await db.query("INSERT INTO shifts(id,name,start_time,end_time,working_days) VALUES($1,'Paper Shift','08:00','17:00',ARRAY[1,2,3,4,5])",[id(11)]);
  for(let n=1;n<=4;n++)await db.query("INSERT INTO assignments(employee_id,department_id,shift_id,effective_from) VALUES($1,$2,$3,'2025-01-01')",[id(n),id(10),id(11)]);
  await db.query("INSERT INTO users(id,email,password_hash,full_name,role,employee_number,leave_credit_eligible,date_hired) VALUES($1,'system-paper@test.local','test-only','System Administrator','super_admin',NULL,false,'2025-01-01')",[id(6)]);
  await db.query("INSERT INTO users(id,email,password_hash,full_name,role,employment_type,date_hired) VALUES($1,'admin-employee-paper@test.local','test-only','Admin Employee','admin','permanent','2025-01-01')",[id(7)]);
  for(const n of [6,7])await db.query("INSERT INTO assignments(employee_id,department_id,shift_id,effective_from) VALUES($1,$2,$3,'2025-01-01')",[id(n),id(10),id(11)]);
  // Discover the employee first; validate the original slip date after selection.
  await db.query("INSERT INTO users(id,email,password_hash,full_name,role,date_hired) VALUES($1,'historical-paper@test.local','test-only','Historical Employee','employee','2025-01-01')",[id(5)]);
  await db.query("INSERT INTO assignments(employee_id,department_id,shift_id,effective_from,effective_to) VALUES($1,$2,$3,'2025-01-01','2026-09-30')",[id(5),id(10),id(11)]);
  const directory=require('../src/modules/locator/controllers/staffFiling.controller')({pool:db,
   parseLocatorDateOnly:require('../src/services/locatorFilingRules').parseLocatorDateOnly,
   validateStaffBatch:require('../src/services/locatorStaffFiling').validateStaffBatch});
  const response=()=>({statusCode:200,status(code){this.statusCode=code;return this;},json(body){this.body=body;return this;}});
  const all=response();
  await directory.listFilingEmployees({user:{id:id(1)},query:{paper:'true',search:'Historical'}},all);
  assert.equal(all.statusCode,200);assert.equal(all.body.employees[0].id,id(5));
  const dated=response();
  await directory.listFilingEmployees({user:{id:id(1)},query:{slip_date:'2026-10-28',employee_ids:JSON.stringify([id(5)])}},dated);
  assert.equal(dated.body.employees.length,0,'Current-date availability does not determine who appears in the paper picker');
  for(const query of [{paper:'true'},{paper:'true',search:'System Administrator'},
    {slip_date:'2026-09-10',employee_ids:JSON.stringify([id(6),id(7)])}]){
   const picker=response();
   await directory.listFilingEmployees({user:{id:id(1)},query},picker);
   assert.equal(picker.statusCode,200);
   assert.equal(picker.body.employees.some(e=>e.id===id(6)),false,'System Admin is never an employee choice, even with an assignment');
   if(!query.search)assert.equal(picker.body.employees.some(e=>e.id===id(7)),true,'Admin accounts belonging to employees remain available');
   else assert.equal(picker.body.total,0,'Excluded system accounts do not inflate the total');
  }
  await db.query("INSERT INTO primary_reviewer_designations(scope_key,department_id,employee_id,effective_from) VALUES('final_hr',NULL,$1,'2025-01-01'),('department:'||$2::text,$2::uuid,$3::uuid,'2025-01-01')",[id(1),id(10),id(4)]);
  const steps=[{label:'Department',assignee_source:'submitter_department_reviewers',step_order:1},{label:'Manual Mayor',assignee_source:'manual_mayor',step_order:2}];
  await db.query("INSERT INTO approval_workflows(id,name) VALUES($1,'Paper route')",[id(12)]);
  await db.query("INSERT INTO approval_workflow_versions(workflow_id,version,steps) VALUES($1,1,$2)",[id(12),JSON.stringify(steps)]);
  await db.query("UPDATE locator_request_types SET approval_workflow_id=$1 WHERE code='locator'",[id(12)]);
  const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
  for(const n of [2,3])await db.query("INSERT INTO docutracker_signature_assets(id,owner_user_id,image_bytes,mime_type,source_type,is_saved) VALUES($1,$2,$3,'image/png','uploaded',true)",[id(20+n),id(n),bytes]);
  const filing=require('../src/services/locatorFilingRules');
  const deps={pool:{connect:async()=>({query:(...args)=>db.query(...args),release(){}})},
   ...require('../src/modules/locator/repositories/types')({}),todayInHrmsTimezone:()=> '2026-10-28',
   validateLocatorWorkingDayForEmployee:filing.validateLocatorWorkingDayForEmployee,resolveLocatorShiftCoverage:filing.resolveLocatorShiftCoverage,
   findLocatorRequestConflicts:require('../src/services/locatorConflictPolicy').findLocatorRequestConflicts,
   captureLocatorTypeSnapshot:require('../src/services/locatorTypeSnapshot').captureLocatorTypeSnapshot,
   normalizeLocatorFieldSchema:require('../src/services/locatorCustomFields').normalizeLocatorFieldSchema,
   locatorDetailValues:require('../src/services/locatorCustomFields').locatorDetailValues,
   recordLocatorWorkflowEvent:require('../src/services/locatorWorkflowHistory').recordLocatorWorkflowEvent};
  const service=require('../src/modules/locator/services/paperRecording')(deps);
  const input={actor:{id:id(1),role:'hr'},employeeId:id(2),slipDate:'2026-09-10',requestType:'locator',office:'Municipal Hall',reason:'Signed paper record',
   slots:{amIn:true,amOut:false,pmIn:false,pmOut:false},attachment:{path:'test-signed.pdf',name:'signed.pdf',mimeType:'application/pdf'},
   paperApproval:{original_filing_date:'2026-09-01',approval_date:'2026-09-02',final_approver:{user_id:id(3),name:'Client supplied name',position_title:'Municipal Mayor'},confirmed_complete:true,confirmed_not_recorded:true}};
  await assert.rejects(service.recordPaperLocator({...input,employeeId:id(6)}),{statusCode:400},'A direct API submission cannot record paper attendance for a system account');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM locator_slips WHERE employee_id=$1',[id(6)])).rows[0].n,0);
  const row=await service.recordPaperLocator(input);
  assert.equal(row.status,'approved');assert.equal(row.hr_reviewer_id,null);assert.equal(row.workflow_snapshot,null);
  assert.equal(row.paper_approval_record.encoded_by,id(1));assert.equal(row.paper_approval_record.final_approver.name,'Paper Person 3');
  assert.equal(row.paper_approval_record.applicant.signature.signature_asset_id,id(22));
  assert.equal(row.paper_approval_record.final_approver.signature.signature_asset_id,id(23));
  assert.equal((await db.query('SELECT count(*)::int AS n FROM docutracker_locator_signatures WHERE locator_slip_id=$1',[row.id])).rows[0].n,0);
  const history=(await db.query('SELECT * FROM locator_slip_history WHERE locator_slip_id=$1',[row.id])).rows;
  assert.equal(history.length,1);assert.equal(history[0].action,'paper_approved_recorded');assert.equal(history[0].actor_id,id(1));
  assert.equal(history[0].metadata.paper_approval_record.applicant.signature.signature_image_base64,undefined);
  assert.equal(require('../src/services/locatorCoverage').normalizeLocatorCoverage(row).am_in,true);
  await assert.rejects(service.recordPaperLocator(input),{statusCode:409});
  assert.equal((await db.query('SELECT count(*)::int AS n FROM locator_slips')).rows[0].n,1);
  await db.query("INSERT INTO dtr_daily_summary(employee_id,attendance_date,time_in,status) VALUES($1,'2026-09-14','2026-09-14T08:00:00+08:00','present')",[id(2)]);
  await assert.rejects(service.recordPaperLocator({...input,slipDate:'2026-09-14'}),{statusCode:409});
  assert.equal((await db.query("SELECT count(*)::int AS n FROM locator_slips WHERE slip_date='2026-09-14'")).rows[0].n,0,'Paper recording cannot replace an existing DTR punch');
  await db.query("UPDATE docutracker_signature_assets SET is_saved=false,image_bytes=$1 WHERE owner_user_id IN ($2,$3)",[Buffer.from('changed'),id(2),id(3)]);
  const form=await require('../src/services/locatorSignatureService').getLocatorSourceSignatures(db,{id:id(2),role:'employee'},'dtr','locator_slips',row.id);
  assert.equal(form.print_signatories.applicant.signature_image_base64,bytes.toString('base64'));
  assert.equal(form.print_signatories.hr_approver.signature_image_base64,bytes.toString('base64'));
  // A new manual-only paper record works without saved ink or current review configuration.
  await db.query("INSERT INTO leave_attendance_deductions(user_id,service_month,posted_at) VALUES($1,'2026-09-01',now())",[id(2)]);
  const manual=await service.recordPaperLocator({...input,slipDate:'2026-09-11',paperApproval:{...input.paperApproval,final_approver:{name:'Former official',position_title:'Head of Office'}}});
  assert.equal(manual.month_end_reconciliation_required,true,'Previously posted attendance is flagged for reconciliation, not deducted again');
  assert.equal(manual.paper_approval_record.applicant.signature,null);assert.equal(manual.paper_approval_record.final_approver.signature,undefined);
  const publicRecord=require('../src/modules/leave/services/paperSignatures').publicPaperRecord(row.paper_approval_record);
  assert.equal(publicRecord.final_approver.signature.signature_image_base64,undefined);
  console.log('Paper Locator: past dates, original authority, frozen employee/Mayor signatures, duplicate protection and authorized printing verified.');
 }finally{await db.end();}
});
