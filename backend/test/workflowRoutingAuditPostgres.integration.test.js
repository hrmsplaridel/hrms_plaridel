'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {Client}=require('pg');
const engine=require('../src/services/approvalWorkflows');
const {selfFilingOfficial}=require('../src/services/workflowPrintPolicy');
const {listInbox}=require('../src/services/sharedWorkflowInbox');
const id=n=>`22222222-2222-4222-8222-${String(n).padStart(12,'0')}`;

test('configured primary/backups, custom steps, Mayor and manual routes execute for Leave and Locator in isolated PostgreSQL',
 {skip:!process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL},async()=>{
 const db=new Client({connectionString:process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL});await db.connect();
 try{
  await db.query('BEGIN');
  await db.query(`CREATE TEMP TABLE users(id uuid PRIMARY KEY,full_name text,email text,role text,is_active boolean DEFAULT true,
    employment_status text DEFAULT 'active',employment_type text DEFAULT 'permanent',date_hired date,separation_date date,created_at timestamptz DEFAULT now());
   CREATE TEMP TABLE departments(id uuid PRIMARY KEY,name text);
   CREATE TEMP TABLE positions(id uuid PRIMARY KEY,name text);
   CREATE TEMP TABLE assignments(id uuid DEFAULT gen_random_uuid(),employee_id uuid,department_id uuid,position_id uuid,
    effective_from date DEFAULT '2026-01-01',effective_to date,is_active boolean DEFAULT true,created_at timestamptz DEFAULT now());
   CREATE TEMP TABLE primary_reviewer_designations(id uuid DEFAULT gen_random_uuid(),scope_key text,department_id uuid,employee_id uuid,
    position_title_snapshot text,effective_from date DEFAULT '2026-01-01',effective_to date,is_active boolean DEFAULT true);
   CREATE TEMP TABLE department_reviewer_backups(id uuid DEFAULT gen_random_uuid(),department_id uuid,employee_id uuid,backup_rank integer,
    effective_from date DEFAULT '2026-01-01',effective_to date,is_active boolean DEFAULT true,created_at timestamptz DEFAULT now());
   CREATE TEMP TABLE leave_final_reviewer_backups(employee_id uuid,backup_rank integer,effective_from date DEFAULT '2026-01-01',effective_to date,is_active boolean DEFAULT true);
   CREATE TEMP TABLE dtr_admin_access(admin_user_id uuid,leave_allowed boolean,locator_allowed boolean);
   CREATE TEMP TABLE approval_workflows(id uuid PRIMARY KEY,name text,current_version integer,is_active boolean DEFAULT true);
   CREATE TEMP TABLE approval_workflow_versions(workflow_id uuid,version integer,steps jsonb,employment_types text[],
    self_filing_signatory_policy text DEFAULT 'mayor');
   CREATE TEMP TABLE leave_types(id uuid PRIMARY KEY,name text);
   CREATE TEMP TABLE leave_requests(id uuid PRIMARY KEY,user_id uuid,employee_id uuid,status text,workflow_snapshot jsonb,signature_revision integer DEFAULT 1,
    final_review_route text,final_reviewer_user_id uuid,department_id uuid,leave_type_id uuid,start_date date,end_date date,created_at timestamptz DEFAULT now(),discarded_at timestamptz);
   CREATE TEMP TABLE locator_slips(LIKE leave_requests INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
   ALTER TABLE locator_slips ADD COLUMN slip_date date;
   CREATE TEMP TABLE docutracker_signature_assets(id uuid,owner_user_id uuid,mime_type text,image_bytes bytea);
   CREATE TEMP TABLE docutracker_leave_signatures(leave_request_id uuid,revision integer,signature_asset_id uuid,signed_by uuid,signer_name_snapshot text,signed_at timestamptz DEFAULT now());
   CREATE TEMP TABLE docutracker_locator_signatures(locator_slip_id uuid,revision integer,signature_asset_id uuid,signed_by uuid,signer_name_snapshot text,signed_at timestamptz DEFAULT now());
   CREATE TEMP TABLE user_notifications(id uuid,reference_type text,reference_id uuid,metadata jsonb,read_at timestamptz,created_at timestamptz);`);
  for(let n=1;n<=9;n++)await db.query('INSERT INTO users(id,full_name,email,role) VALUES($1,$2,$3,$4)',[id(n),`Person ${n}`,`person${n}@test.local`,n===8?'mayor':[6,7].includes(n)?'hr':'employee']);
  await db.query("INSERT INTO departments VALUES($1,'Accounting') ON CONFLICT DO NOTHING",[id(20)]);
  await db.query("INSERT INTO positions VALUES($1,'Officer') ON CONFLICT DO NOTHING",[id(21)]);
  for(let n=1;n<=8;n++)await db.query('INSERT INTO assignments(employee_id,department_id,position_id) VALUES($1,$2,$3)',[id(n),id(20),id(21)]);
  await db.query("INSERT INTO primary_reviewer_designations(scope_key,department_id,employee_id) VALUES('department:'||$1::text,$1::uuid,$2::uuid),('final_hr',NULL,$3::uuid)",[id(20),id(2),id(6)]);
  await db.query('INSERT INTO department_reviewer_backups(department_id,employee_id,backup_rank) VALUES($1,$2,1)',[id(20),id(3)]);
  await db.query('INSERT INTO leave_final_reviewer_backups(employee_id,backup_rank) VALUES($1,1)',[id(7)]);
  const step=(source,label,user_ids=[])=>({label,assignee_source:source,user_ids,assignee_type:'user',requires_signature:true,allowed_actions:['approve','return','reject']});
  const department=step('submitter_department_reviewers','Department Review'),hr=step('final_hr_reviewers','Final HR Review');
  const finance=step('specific_users','Finance Review',[id(4),id(5)]),mayor=step('active_mayor','Mayor Approval'),manual=step('manual_mayor','Manual Mayor Signing');
  const routes=[[department],[department,hr],[department,finance,hr,mayor],[finance],[department,hr,manual]];
  const policies=['mayor','blank','actual_reviewer'];
  const policyIndependentRoutes=new Map();
  let sequence=100;
  let checked=0;
  for(const kind of ['leave','locator'])for(const policy of policies)for(const ownership of ['neither','department','hr','both'])for(const useBackup of [false,true])for(const route of routes){
   const ownsDepartment=['department','both'].includes(ownership),ownsHr=['hr','both'].includes(ownership);
   await db.query("UPDATE primary_reviewer_designations SET employee_id=CASE WHEN scope_key='final_hr' THEN $2::uuid ELSE $1::uuid END",[ownsDepartment?id(1):id(2),ownsHr?id(1):id(6)]);
   const request=id(sequence++),workflow=id(sequence++);
   const steps=route.map((s,i)=>({...s,step_order:i+1}));
   await db.query("INSERT INTO approval_workflows(id,name,current_version) VALUES($1,'Audit route',1)",[workflow]);
   await db.query('INSERT INTO approval_workflow_versions(workflow_id,version,steps,employment_types,self_filing_signatory_policy) VALUES($1,1,$2,NULL,$3)',[workflow,JSON.stringify(steps),policy]);
   await db.query(`INSERT INTO ${engine.tableFor(kind)}(id,employee_id,user_id,status,department_id) VALUES($1,$2,$2,'draft',$3)`,[request,id(1),id(20)]);
   const prepared=await engine.prepareWorkflow(db,kind,{approval_workflow_id:workflow},id(1));
   assert.equal(prepared.self_filing_signatory_policy,policy);
   await engine.initialWorkflow(db,kind,request,prepared);
   const mayorProfile=await require('../src/services/officialSignatoryService').resolveActiveMayor(db,require('../src/utils/dateRangeParser').todayInHrmsTimezone());
   for(const role of ['department','hr'])if(role==='department'?ownsDepartment:ownsHr){
    const before=await selfFilingOfficial(db,{employee_id:id(1),workflow_snapshot:prepared},role,mayorProfile);
    assert.equal(before.id || before.employee_id || null,policy==='mayor'?id(8):null,'Actual reviewer stays blank until that role approves');
   }
   for(let stage=0;stage<steps.length;stage++){
    if(steps[stage].assignee_source==='manual_mayor')continue;
    const row=(await db.query(`SELECT * FROM ${engine.tableFor(kind)} WHERE id=$1`,[request])).rows[0];
    const expected=steps[stage].assignee_source==='submitter_department_reviewers'?(ownsDepartment?[id(3)]:[id(2),id(3)]):steps[stage].assignee_source==='final_hr_reviewers'?(ownsHr?[id(7)]:[id(6),id(7)]):steps[stage].assignee_source==='active_mayor'?[id(8)]:[id(4),id(5)];
    const resolved=await engine.resolveWorkflowReviewers(db,kind,row);
    assert.deepEqual(resolved.map(r=>r.id),expected);
    for(const who of [...expected,id(9),id(1)])assert.equal((await listInbox(db,{id:who})).some(r=>r.id===request),expected.includes(who));
    await assert.rejects(engine.workflowDecision(db,kind,request,id(9),'approve',{step:stage,revision:1}),{statusCode:403});
    const actor=useBackup&&expected.length>1?expected[1]:expected[0];
    await assert.rejects(engine.workflowDecision(db,kind,request,id(1),'approve',{step:stage,revision:1}),{statusCode:403},'Applicant cannot approve their own request');
    const decision=await engine.workflowDecision(db,kind,request,actor,'approve',{step:stage,revision:1});
    const asset=id(sequence++);
    await db.query("INSERT INTO docutracker_signature_assets VALUES($1,$2,'image/png',$3)",[asset,actor,Buffer.from(`ink ${actor}`)]);
    await db.query(`INSERT INTO ${kind==='leave'?'docutracker_leave_signatures':'docutracker_locator_signatures'}(${kind==='leave'?'leave_request_id':'locator_slip_id'},revision,signature_asset_id,signed_by,signer_name_snapshot) VALUES($1,1,$2,$3,$4)`,[request,asset,actor,`Person ${actor.slice(-1)}`]);
    await engine.saveWorkflow(db,kind,request,decision.snapshot);
    await db.query(`UPDATE ${engine.tableFor(kind)} SET status=$2 WHERE id=$1`,[request,decision.status]);
   }
   const saved=(await db.query(`SELECT * FROM ${engine.tableFor(kind)} WHERE id=$1`,[request])).rows[0];
   assert.equal(saved.status,'approved');assert.equal(saved.workflow_snapshot.version,1);
   const routingKey=JSON.stringify([kind,ownership,useBackup,steps.map(s=>s.assignee_source)]);
   const actors=saved.workflow_snapshot.decisions.map(d=>d.actor_id);
   if(policyIndependentRoutes.has(routingKey))assert.deepEqual(actors,policyIndependentRoutes.get(routingKey),'Printed signatory policy must not change approval routing');
   else policyIndependentRoutes.set(routingKey,actors);
   const signatures=await engine.decisionSignatures(db,saved);
   assert.equal(signatures.length,steps.filter(s=>s.assignee_source!=='manual_mayor').length);
   assert.ok(signatures.every(s=>Buffer.from(s.signature_image_base64,'base64').toString()===`ink ${s.signed_by}`));
   const officials=await engine.printOfficials(db,kind,saved);
   assert.equal(officials.hr_approver.id,engine.isDepartmentOnlyWorkflow(saved.workflow_snapshot)?null:steps.at(-1).assignee_source==='manual_mayor'?id(8):saved.workflow_snapshot.decisions.at(-1).actor_id);
   if(engine.isDepartmentOnlyWorkflow(saved.workflow_snapshot))assert.equal(officials.department_head.id,actors.at(-1));
   if(steps.at(-1).assignee_source==='manual_mayor'){
    assert.equal(saved.workflow_snapshot.manual_signing_required,true);
    assert.ok(!signatures.some(signature=>signature.signed_by===id(8)),'Manual signing must not create an electronic Mayor signature');
   }
   for(const role of ['department','hr'])if(role==='department'?ownsDepartment:ownsHr){
    const official=await selfFilingOfficial(db,saved,role,mayorProfile);
    const explicit=role==='department'?steps.findIndex(s=>s.assignee_source==='submitter_department_reviewers'):steps.findLastIndex(s=>s.assignee_source==='final_hr_reviewers');
    const stage=explicit>=0?explicit:role==='department'?steps.findIndex(s=>s.assignee_source==='specific_users'):steps.findLastIndex(s=>s.assignee_source==='specific_users');
    const actor=saved.workflow_snapshot.decisions.find(d=>d.step===stage)?.actor_id;
    assert.equal(official.id || official.employee_id || null,policy==='mayor'?id(8):policy==='actual_reviewer'?actor || null:null,`${kind}/${ownership}/${policy}: correct printed ${role} identity`);
   }
   const nextPolicy=policies[(policies.indexOf(policy)+1)%policies.length];
   await db.query('INSERT INTO approval_workflow_versions(workflow_id,version,steps,self_filing_signatory_policy) VALUES($1,2,$2,$3)',[workflow,JSON.stringify(steps),nextPolicy]);
   await db.query('UPDATE approval_workflows SET current_version=2 WHERE id=$1',[workflow]);
   const next=await engine.prepareWorkflow(db,kind,{approval_workflow_id:workflow},id(1));
   assert.equal(next.self_filing_signatory_policy,nextPolicy,'New filings use the newly published policy');
   const resubmitted=await engine.prepareWorkflow(db,kind,{approval_workflow_snapshot:saved.workflow_snapshot},id(1));
   assert.equal(resubmitted.version,1);
   assert.equal(resubmitted.self_filing_signatory_policy,policy,'Existing filings and corrections retain their saved policy');
   checked++;
  }
  assert.equal(checked,240,'Both modules cover all three policies, all applicant roles, primary/backup approvals and five routes');
  await db.query("UPDATE primary_reviewer_designations SET employee_id=$1 WHERE scope_key LIKE 'department:%'",[id(1)]);
  assert.deepEqual((await engine.resolveWorkflowReviewers(db,'leave',{employee_id:id(1),workflow_snapshot:{steps:[department],current_step:0,decisions:[]}})).map(r=>r.id),[id(3)],'Applicant-primary falls back to the eligible department backup');
 }finally{await db.query('ROLLBACK');await db.end();}
});
