'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {Client}=require('pg');const fs=require('node:fs');const path=require('node:path');
const id=n=>`88888888-8888-4888-8888-${String(n).padStart(12,'0')}`;
test('approved paper Leave recording retains original approvals and updates accounting once in PostgreSQL',
 {skip:!process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL},async()=>{
 const url=new URL(process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL);
 assert.match(url.pathname,/^\/hrms_workflow_audit_[a-f0-9]{16}$/);
 process.env.DATABASE_URL=url.toString();
 const db=new Client({connectionString:url.toString()});await db.connect();
 try {
  await db.query(fs.readFileSync(path.join(__dirname,'../scripts/init-schema.sql'),'utf8'));
  const freshBuiltins=(await db.query('SELECT name,allow_approved_paper_filing FROM leave_types WHERE is_system=true')).rows;
  assert.equal(freshBuiltins.length,14);
  assert.ok(freshBuiltins.every(row=>row.allow_approved_paper_filing===true),'Fresh built-in CSC types should allow paper recording by default');
  const autoApprovalColumns = (await db.query(`SELECT table_name FROM information_schema.columns
    WHERE table_schema='public' AND column_name='auto_approve_admin'
      AND table_name IN ('leave_types','locator_request_types') ORDER BY table_name`)).rows;
  assert.deepEqual(autoApprovalColumns, [{table_name:'locator_request_types'}], 'Only Locator retains digital staff auto-approval');
  const defaultMigration=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261026_leave_builtin_paper_defaults.sql'),'utf8');
  await db.query("UPDATE leave_types SET allow_approved_paper_filing=false,updated_at='2026-10-01' WHERE name='vacationLeave'");
  await db.query("UPDATE leave_types SET allow_approved_paper_filing=false,updated_at='2026-10-26 12:00:00+08' WHERE name='sickLeave'");
  await db.query("UPDATE leave_types SET allow_approved_paper_filing=false,admin_can_file=false,updated_at='2026-10-01' WHERE name='studyLeave'");
  await db.query("INSERT INTO leave_types(name,description,is_system,updated_at) VALUES('customDefaultLeave','Custom default test',true,'2026-10-01')");
  await db.query(defaultMigration);
  const settings=async()=>Object.fromEntries((await db.query("SELECT name,allow_approved_paper_filing FROM leave_types WHERE name IN ('vacationLeave','sickLeave','studyLeave','customDefaultLeave') ORDER BY name")).rows.map(row=>[row.name,row.allow_approved_paper_filing]));
  assert.deepEqual(await settings(),{customDefaultLeave:false,sickLeave:false,studyLeave:false,vacationLeave:true});
  // Simulate the supported settings API saving a disabled override, then replay.
  await db.query("UPDATE leave_types SET allow_approved_paper_filing=false,updated_at=now() WHERE name='vacationLeave'");
  await db.query(defaultMigration);
  assert.equal((await settings()).vacationLeave,false,'Migration replay must preserve a saved disabled choice');
  async function initializeCompatibility() {
    await new Promise((resolve,reject)=>require('../src/modules/leave/infrastructure/initialize')({
      SYSTEM_LEAVE_TYPE_NAMES:Object.keys(require('../src/routes/leaveTypeRules').LEAVE_TYPE_RULES),
      initLeaveAttachmentAccessLog(){},initLeaveBalanceLedger(){},initLeaveRequestHistory(){},
      pool:{query:async(sql,params)=>{
        try {const result=await db.query(sql,params);if(sql.includes('CREATE INDEX IF NOT EXISTS idx_leave_balance_deduction_history_user_applied'))resolve();return result;}
        catch(error){reject(error);throw error;}
      }},
    }));
  }
  await db.query("UPDATE leave_types SET allow_approved_paper_filing=false,updated_at='2026-10-01' WHERE name='mandatoryForcedLeave'");
  await initializeCompatibility();
  assert.equal((await db.query("SELECT allow_approved_paper_filing FROM leave_types WHERE name='mandatoryForcedLeave'")).rows[0].allow_approved_paper_filing,true,'Startup enables only untouched legacy built-in defaults');
  await initializeCompatibility();
  assert.deepEqual(await settings(),{customDefaultLeave:false,sickLeave:false,studyLeave:false,vacationLeave:false},'Restarts preserve explicit choices and never enable custom types');
  // The disposable initializer seeds an active Mayor; replace only that test fixture.
  await db.query("UPDATE users SET is_active=false WHERE role='mayor'");
  for(const [n,role] of [[1,'hr'],[2,'employee'],[3,'supervisor'],[4,'hr'],[5,'mayor']]) {
   await db.query(`INSERT INTO users(id,email,password_hash,full_name,role,employment_type,date_hired,sex)
    VALUES($1,$2,'test-only','Staff Test '||$3,$4,'permanent','2025-01-01','Male')`,[id(n),`staff${n}@test.local`,String(n),role]);
  }
  await db.query("INSERT INTO departments(id,name) VALUES($1,'Staff Audit')",[id(20)]);
  await db.query("INSERT INTO shifts(id,name,start_time,end_time) VALUES($1,'Audit Shift','08:00','17:00')",[id(21)]);
  for(let n=1;n<=5;n++)await db.query("INSERT INTO assignments(employee_id,department_id,shift_id,effective_from) VALUES($1,$2,$3,'2025-01-01')",[id(n),id(20),id(21)]);
  await db.query(`INSERT INTO primary_reviewer_designations(scope_key,department_id,employee_id,effective_from)
    VALUES('final_hr',NULL,$1,'2025-01-01'),('department:'||$2::text,$2::uuid,$3::uuid,'2025-01-01')`,[id(1),id(20),id(3)]);
  const step=(source,index)=>({step_order:index+1,label:source,assignee_source:source,user_ids:source==='specific_users'?[id(3)]:[],requires_signature:true,allowed_actions:['approve','return','reject']});
  await db.query("INSERT INTO approval_workflows(id,name) VALUES($1,'Paper Audit Route')",[id(30)]);
  await db.query("INSERT INTO approval_workflow_versions(workflow_id,version,steps,self_filing_signatory_policy) VALUES($1,1,$2,'blank')",[id(30),JSON.stringify(['submitter_department_reviewers','final_hr_reviewers'].map(step))]);
  await db.query(`INSERT INTO leave_types(id,name,display_name,admin_can_file,employee_can_file,allow_approved_paper_filing,balance_ledger_type,approval_workflow_id)
    VALUES($1,'staffAuditLeave','Staff Audit Leave',true,true,true,'vacationLeave',$2)`,[id(40),id(30)]);
  await db.query("INSERT INTO leave_balances(user_id,leave_type,earned_days) VALUES($1,'vacationLeave',20)",[id(2)]);
  const deps=require('../src/modules/leave/dependencies').loadLeaveDependencies();
  const pool={query:(...args)=>db.query(...args),connect:async()=>({query:(...args)=>db.query(...args),release(){}})};
  const runtime={...deps,pool,notifySafe:()=>{}};
  for(const file of ['services/events','services/signatories','policies/dates','policies/leaveTypes','policies/requestDetails',
   'repositories/leaveRequests','infrastructure/attachments','controllers/typeErrors','services/workingDays','serializers/leaveTypes',
   'serializers/leaveRequests','use-cases/leaveCredits','repositories/reviewQueries','services/annualEntitlements','repositories/leaveTypes',
   'use-cases/finalizeApproval','use-cases/staffFiling'])Object.assign(runtime,require('../src/modules/leave/'+file)(runtime));
  runtime.notifySafe=()=>{};runtime.broadcastLeaveUpdated=()=>{};runtime.broadcastDtrLeaveRefresh=()=>{};
  const typeControllers=require('../src/modules/leave/controllers/types.controller')(runtime);
  const vacationId=(await db.query("SELECT id FROM leave_types WHERE name='vacationLeave'")).rows[0].id;
  const disabledSetting={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
  await typeControllers.updateType({params:{id:vacationId},body:{allow_approved_paper_filing:false}},disabledSetting);
  assert.equal(disabledSetting.code,200);
  assert.equal(disabledSetting.body.allow_approved_paper_filing,false);
  await initializeCompatibility();
  assert.equal((await settings()).vacationLeave,false);
  await db.query("INSERT INTO leave_final_reviewer_backups(employee_id,backup_rank,effective_from) VALUES($1,1,'2025-01-01')",[id(4)]);
  await db.query("INSERT INTO department_reviewer_backups(department_id,employee_id,backup_rank,effective_from) VALUES($1,$2,1,'2025-01-01')",[id(20),id(1)]);
  const signatureBytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
  await db.query("INSERT INTO docutracker_signature_assets(id,owner_user_id,image_bytes,mime_type,source_type,is_saved) VALUES($1,$2,$3,'image/png','uploaded',true),($4,$5,$3,'image/png','uploaded',true)",[id(50),id(1),signatureBytes,id(51),id(3)]);
  await db.query("INSERT INTO docutracker_signature_assets(id,owner_user_id,image_bytes,mime_type,source_type,is_saved) VALUES($1,$2,$3,'image/png','uploaded',true)",[id(52),id(5),signatureBytes]);
  await db.query("INSERT INTO docutracker_signature_assets(id,owner_user_id,image_bytes,mime_type,source_type,is_saved) VALUES($1,$2,$3,'image/png','uploaded',true)",[id(53),id(2),signatureBytes]);
  const suggest=require('../src/modules/leave/services/paperSignatories')(runtime).suggestPaperSignatories;
  const suggested=await suggest(db,{employeeId:id(2),leaveType:'staffAuditLeave',filingDate:'2026-09-01',approvalDate:'2026-09-02'});
  assert.deepEqual(suggested.final_approver.map(person=>person.user_id),[id(1),id(4)]);
  assert.deepEqual(suggested.department_reviewer.map(person=>person.user_id),[id(3),id(1)]);
  assert.equal(suggested.certification_officer[0].user_id,id(1),'Unconfigured standalone certifier falls back to the dated primary HR designation');
  assert.equal(suggested.effective_date,'2026-09-02');
  assert.equal(suggested.final_approver[0].has_saved_signature,true);
  assert.equal(suggested.final_approver[1].has_saved_signature,false);
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM leave_requests')).rows[0].n),0,'Suggestions must not create a routed request');
  const upload=require('../src/modules/leave/controllers/submitWithAttachment.controller')(runtime).submitWithAttachment;
  const submitSelf=require('../src/modules/leave/controllers/submit.controller')(runtime).submitLeave;
  const cleanup=[];
  const paper={original_filing_date:'2026-09-01',approval_date:'2026-09-02',final_approver:{name:'Paper Approving Official',position_title:'Original Mayor'},confirmed_complete:true,confirmed_not_recorded:true};
  const balance=async()=>(await db.query("SELECT used_days,pending_days FROM leave_balances WHERE user_id=$1 AND leave_type='vacationLeave'",[id(2)])).rows[0];
  const count=async()=>Number((await db.query('SELECT count(*) AS n FROM leave_requests')).rows[0].n);
  async function record(start,end,{paid=2,unpaid=0,data=paper,actor=4,withFile=true}={}){
   const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
   await upload({user:{id:id(actor),role:actor===2?'employee':'hr'},file:withFile?{buffer:Buffer.from('%PDF-1.4 approved paper packet'),originalname:'signed.pdf',mimetype:'application/pdf'}:null,
    body:{leave_type:'staffAuditLeave',start_date:start,end_date:end,reason:'Approved paper record',paper_approval:JSON.stringify(data),approved_days_with_pay:paid,approved_days_without_pay:unpaid}},res,id(2));
   if(res.body?.id){const row=(await db.query('SELECT attachment_path FROM leave_requests WHERE id=$1',[res.body.id])).rows[0];cleanup.push(row.attachment_path);}
   return res;
  }
  try {
   const routes=[['submitter_department_reviewers'],['submitter_department_reviewers','final_hr_reviewers'],['submitter_department_reviewers','final_hr_reviewers','active_mayor'],['specific_users','final_hr_reviewers'],['submitter_department_reviewers','manual_mayor']];
   const dates=[['2026-09-10','2026-09-11'],['2026-09-14','2026-09-15'],['2026-09-16','2026-09-17'],['2026-09-21','2026-09-22'],['2026-09-23','2026-09-24']];
   for(let i=0;i<routes.length;i++){
    await db.query('UPDATE approval_workflow_versions SET steps=$2 WHERE workflow_id=$1',[id(30),JSON.stringify(routes[i].map(step))]);
    const selectedPaper={...paper,final_approver:{user_id:id(1),name:'Client label','position_title':'HR Director'},certification_officer:{user_id:id(1),name:'Client label',position_title:'HR Director'},department_reviewer:{user_id:id(3),name:'Client label',position_title:'Department Head'}};
    const result=await record(...dates[i],{data:i===1?selectedPaper:i===2?{...selectedPaper,final_approver:{user_id:id(5),name:'Client Mayor label',position_title:'Mayor'}}:paper});assert.equal(result.code,201,JSON.stringify(result.body));assert.equal(result.body.status,'approved');
    const saved=(await db.query('SELECT * FROM leave_requests WHERE id=$1',[result.body.id])).rows[0];
    assert.equal(saved.workflow_snapshot,null);assert.equal(saved.reviewer_id,null);assert.equal(saved.approved_by,null);
    assert.equal(saved.paper_approval_record.encoded_by,id(4),'Encoder need not be the final HR reviewer');
    assert.equal(saved.paper_approval_record.approval_date,'2026-09-02');
    assert.equal(saved.paper_approval_record.applicant.user_id,id(2));
    if(i<2){
      assert.equal(saved.paper_approval_record.applicant.signature.signature_asset_id,id(53));
      assert.equal(saved.paper_approval_record.applicant.signature.owner_user_id,id(2));
      assert.equal(saved.paper_approval_record.applicant.signature.applied_by,id(4));
      assert.equal(result.body.paper_approval_record.applicant.signature.signature_image_base64,undefined);
    } else assert.equal(saved.paper_approval_record.applicant.signature,null,'No saved applicant asset leaves a blank signature line');
    assert.equal(saved.approved_at.toISOString(),'2026-09-01T16:00:00.000Z');
    assert.equal(result.body.date_filed,'2026-09-01');assert.equal(saved.approving_authority_snapshot.name,i===1?'Staff Test 1':i===2?'Staff Test 5':paper.final_approver.name);
    const signatures=await db.query('SELECT * FROM docutracker_leave_signatures WHERE leave_request_id=$1',[saved.id]);assert.equal(signatures.rows.length,0);
    const history=(await db.query('SELECT * FROM leave_request_history WHERE leave_request_id=$1',[saved.id])).rows;
    assert.equal(history.length,1);assert.equal(history[0].action,'paper_approved_recorded');assert.equal(history[0].acted_by,id(4));
    assert.equal(history[0].metadata_json.paper_approval_record.applicant.signature?.signature_image_base64,undefined);
    if(i===2){
      assert.equal(saved.paper_approval_record.final_approver.signature.owner_user_id,id(5));
      assert.equal(saved.paper_approval_record.final_approver.signature.signature_asset_id,id(52),'Mayor dropdown uses the Mayor’s saved signature');
      const mayorCopy=require('../src/modules/leave/services/paperSignatures').paperSignaturePayload(saved.paper_approval_record);
      assert.equal(mayorCopy.final_approver.signed_by,id(5));
      assert.equal(mayorCopy.final_approver.signature_image_base64,signatureBytes.toString('base64'));
    }
    if(i===1){
      const snapshot=saved.paper_approval_record.final_approver.signature;
      assert.equal(snapshot.signature_asset_id,id(50));assert.equal(snapshot.signature_image_base64,signatureBytes.toString('base64'));
      assert.equal(snapshot.applied_by,id(4));
      assert.equal(result.body.paper_approval_record.final_approver.signature.signature_image_base64,undefined,'Queues do not include signature image bytes');
      assert.equal(history[0].metadata_json.paper_approval_record.final_approver.signature.signature_image_base64,undefined,'History records asset provenance without duplicating image bytes');
      await db.query("UPDATE docutracker_signature_assets SET image_bytes=$2,is_saved=false WHERE id=$1",[id(50),Buffer.from('replacement signature')]);
      await db.query("UPDATE docutracker_signature_assets SET image_bytes=$2,is_saved=false WHERE id=$1",[id(53),Buffer.from('replacement employee signature')]);
      const signatories={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
      await require('../src/modules/leave/controllers/signatories.controller')(runtime).getSignatories({user:{id:id(4),role:'hr'},query:{employee_id:id(2),leave_request_id:saved.id}},signatories);
      assert.equal(signatories.code,200);
      assert.equal(signatories.body.paper_signatures.final_approver.signature_image_base64,signatureBytes.toString('base64'),'Generated copy retains the original stored signature after the asset is changed');
      assert.equal(signatories.body.paper_signatures.certification_officer.signed_by,id(1));
      assert.equal(signatories.body.paper_signatures.department_reviewer.signed_by,id(3));
      assert.equal(signatories.body.paper_signatures.applicant.signed_by,id(2));
      assert.equal(signatories.body.paper_signatures.applicant.slot_key,'applicant');
      assert.equal(signatories.body.paper_signatures.applicant.signature_image_base64,signatureBytes.toString('base64'),'Applicant copy stays frozen after changing or removing the saved asset');
    }

   }
   let current=await balance();assert.equal(Number(current.used_days),10);assert.equal(Number(current.pending_days),0);
   const before=await count();
   for(const result of [await record(...dates[0]),await record('2026-09-28','2026-09-29',{withFile:false}),
    await record('2026-09-28','2026-09-29',{data:{...paper,confirmed_complete:false}}),
    await record('2026-09-28','2026-09-29',{actor:2}),await record('2026-09-28','2026-09-29',{paid:0,unpaid:0})])assert.ok(result.code>=400,JSON.stringify(result.body));
   assert.equal(await count(),before);assert.deepEqual(await balance(),current);
   const unpaid=await record('2026-09-28','2026-09-29',{paid:0,unpaid:2});assert.equal(unpaid.code,201,JSON.stringify(unpaid.body));
   assert.deepEqual(await balance(),current,'Unpaid paper leave does not consume credits');
   await db.query("UPDATE leave_types SET approval_workflow_id=NULL,balance_ledger_type='none' WHERE id=$1",[id(40)]);
   const noncredit=await record('2026-09-30','2026-10-01');assert.equal(noncredit.code,201,JSON.stringify(noncredit.body));assert.deepEqual(await balance(),current);
   await db.query("UPDATE leave_types SET balance_ledger_type='vacationLeave',allow_approved_paper_filing=false WHERE id=$1",[id(40)]);
   const disabled=await record('2026-10-05','2026-10-06');assert.equal(disabled.code,403);
   // An employee cannot activate paper recording by posting its fields to the self-service endpoint.
   const self={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
   await submitSelf({user:{id:id(2),role:'employee'},body:{leave_type:'staffAuditLeave',start_date:'2026-10-07',end_date:'2026-10-08',paper_approval:paper,allow_approved_paper_filing:true}},self);
   assert.equal(self.code,201,JSON.stringify(self.body));assert.notEqual(self.body.status,'approved');assert.equal(self.body.paper_approval_record,null);
   await db.query('UPDATE leave_types SET allow_approved_paper_filing=true WHERE id=$1',[id(40)]);
   await db.query("UPDATE leave_balances SET earned_days=used_days WHERE user_id=$1 AND leave_type='vacationLeave'",[id(2)]);
   const beforeFailure=await count();const insufficient=await record('2026-10-12','2026-10-13');assert.equal(insufficient.code,400);assert.match(insufficient.body.error,/insufficient/i);assert.equal(await count(),beforeFailure);
   const provenance=(await db.query('SELECT id,paper_approval_record FROM leave_requests ORDER BY id')).rows;
   await db.query('UPDATE leave_types SET allow_approved_paper_filing=false WHERE id=$1',[id(40)]);
   const migration=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261026_leave_approved_paper_recording.sql'),'utf8');
   await db.query(migration);await db.query(migration);
   assert.deepEqual((await db.query('SELECT id,paper_approval_record FROM leave_requests ORDER BY id')).rows,provenance);
   assert.equal((await db.query('SELECT allow_approved_paper_filing FROM leave_types WHERE id=$1',[id(40)])).rows[0].allow_approved_paper_filing,false,'Migration replay must not re-enable a permission');
   console.log('Verified paper recording for department, HR, Mayor, custom, manual and legacy routes; selected stored signature copies; single accounting transaction; employee routing unchanged.');
  }finally{for(const name of cleanup)runtime.cleanupStoredLeaveAttachment(name);}
 }finally{await db.end();await require('../src/config/db').pool.end();}
});
