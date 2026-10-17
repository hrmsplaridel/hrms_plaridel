'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {Client}=require('pg');
const engine=require('../src/services/approvalWorkflows');
const {syncLinkedDocumentWorkflows,publishDocumentVersion}=require('../src/services/sharedDocumentWorkflows');
const url=process.env.APPROVAL_WORKFLOWS_TEST_DATABASE_URL;
test('shared migration, DocuTracker version pinning, employee backups and inbox execute in isolated PostgreSQL',{skip:!url},async()=>{
 const db=new Client({connectionString:url});await db.connect();
 const id=n=>`11111111-1111-4111-8111-${String(n).padStart(12,'0')}`;
 try {
  await db.query('BEGIN');
  const schema='shared_workflow_test_'+require('node:crypto').randomBytes(6).toString('hex');
  await db.query(`CREATE SCHEMA ${schema}; SET LOCAL search_path=${schema},pg_catalog`);
  for(const table of ['approval_workflows','approval_workflow_versions','docutracker_document_types','docutracker_routing_config_versions','docutracker_workflow_steps','docutracker_workflow_step_assignees'])
    await db.query(`CREATE TABLE ${table}(LIKE public.${table} INCLUDING ALL)`);
  await db.query(`CREATE TABLE users(id uuid PRIMARY KEY,full_name text,role text,is_active boolean,employment_status text,employment_type text);
    CREATE TABLE assignments(employee_id uuid,position_id uuid,effective_from date,effective_to date,created_at timestamptz,is_active boolean DEFAULT true);
    CREATE TABLE positions(id uuid,name text);
    CREATE TABLE docutracker_routing_configs(document_type text PRIMARY KEY,steps jsonb,updated_at timestamptz);
    CREATE TABLE leave_requests(id uuid PRIMARY KEY,employee_id uuid,user_id uuid,status text,signature_revision int,
      workflow_snapshot jsonb,final_review_route text,final_reviewer_user_id uuid,created_at timestamptz DEFAULT now(),
      start_date date,number_of_days numeric,reason text,details jsonb,attachment_name text,leave_type_id uuid);
    ALTER TABLE leave_requests ADD COLUMN discarded_at timestamptz;
    CREATE TABLE locator_slips(LIKE leave_requests INCLUDING ALL);
    ALTER TABLE locator_slips ADD COLUMN slip_date date;
      ALTER TABLE locator_slips ADD COLUMN department_id uuid;
      CREATE TABLE departments(id uuid PRIMARY KEY,name text);
      CREATE TABLE leave_types(id uuid PRIMARY KEY,name text);
    CREATE TABLE docutracker_leave_signatures(leave_request_id uuid,revision int,signature_asset_id uuid,signed_by uuid,signer_name_snapshot text,signed_at timestamptz);
    CREATE TABLE docutracker_signature_assets(id uuid,owner_user_id uuid,mime_type text,image_bytes bytea);
    CREATE TABLE user_notifications(id uuid,reference_type text,reference_id uuid,read_at timestamptz,metadata jsonb,created_at timestamptz);
    INSERT INTO docutracker_document_types(document_type,display_name) VALUES('memo','Memo');`);
  const migration=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261016_shared_workflow_assignments.sql'),'utf8').replace(/^BEGIN;\s*$/m,'').replace(/^COMMIT;\s*$/m,'');
  await db.query(migration);await db.query(migration);
  for(let n=1;n<=7;n++)await db.query("INSERT INTO users VALUES($1,$2,'employee',true,'active','permanent')",[id(n),`Reviewer ${n}`]);
  await db.query("INSERT INTO positions VALUES($1,'Administrative Assistant')",[id(20)]);
  await db.query("INSERT INTO assignments(employee_id,position_id,effective_from) VALUES($1,$2,'2026-01-01')",[id(6),id(20)]);
  const steps=Array.from({length:4},(_,index)=>({step_order:index+1,label:`Approval ${index+1}`,assignee_type:'user',assignee_source:'specific_users',
    user_ids:[id(index+1),id(6)],requires_signature:true,allowed_actions:['approve','return','reject'],enabled:true}));
  const workflow=(await db.query("INSERT INTO approval_workflows(name) VALUES('Shared test') RETURNING *")).rows[0];
  await db.query('INSERT INTO approval_workflow_versions(workflow_id,version,steps) VALUES($1,1,$2)',[workflow.id,JSON.stringify(steps)]);
  const native=await publishDocumentVersion(db,'memo',{...workflow,version:1,steps},id(1));
  const previous=(await db.query('SELECT steps FROM docutracker_routing_config_versions WHERE document_type=$1 AND version=$2',['memo',native])).rows[0].steps;
  await db.query("INSERT INTO leave_requests(id,employee_id,status,signature_revision) VALUES($1,$2,'draft',1)",[id(8),id(7)]);
  const prepared=await engine.prepareWorkflow(db,'leave',{approval_workflow_id:workflow.id},id(7),null);
  await engine.initialWorkflow(db,'leave',id(8),prepared);
  const inbox=await require('../src/services/sharedWorkflowInbox').listInbox(db,{id:id(6),role:'employee'});
  assert.equal(inbox.length,1);assert.equal(inbox[0].step_label,'Approval 1');
  await db.query('UPDATE approval_workflows SET current_version=2 WHERE id=$1',[workflow.id]);
  const edited=steps.map(s=>({...s,label:'New '+s.label}));
  await db.query('INSERT INTO approval_workflow_versions(workflow_id,version,steps) VALUES($1,2,$2)',[workflow.id,JSON.stringify(edited)]);
  await syncLinkedDocumentWorkflows(db,{...workflow,version:2,steps:edited},id(1));
  assert.deepEqual((await db.query('SELECT steps FROM docutracker_routing_config_versions WHERE document_type=$1 AND version=$2',['memo',native])).rows[0].steps,previous);
  assert.equal((await db.query('SELECT workflow_version FROM approval_workflow_document_types')).rows[0].workflow_version,2);
  for(let i=0;i<4;i++) {
    const actor=i===0?id(6):id(i+1);
    const decision=await engine.workflowDecision(db,'leave',id(8),actor,'approve',{step:i,revision:1});
    assert.equal(decision.status,i===3?'approved':'pending_hr');
    await db.query("INSERT INTO docutracker_signature_assets VALUES($1,$2,'image/png',$3)",[id(60+i),actor,Buffer.from(`ink ${i}`)]);
    await db.query('INSERT INTO docutracker_leave_signatures VALUES($1,1,$2,$3,$4,now())',[id(8),id(60+i),actor,`Reviewer ${i===0?6:i+1}`]);
    await engine.saveWorkflow(db,'leave',id(8),decision.snapshot);
    await db.query('UPDATE leave_requests SET status=$2 WHERE id=$1',[id(8),decision.status]);
  }
  const saved=await engine.loadRequestWorkflow(db,'leave',id(8));
  assert.equal(saved.version,1);assert.equal(saved.decisions.length,4);assert.equal(saved.steps[0].label,'Approval 1');
  assert.equal(saved.decisions[0].reviewer.name,'Reviewer 6');
  assert.equal(saved.decisions[0].reviewer.position_title,'Administrative Assistant');
  const completed=(await db.query('SELECT * FROM leave_requests WHERE id=$1',[id(8)])).rows[0];
  assert.equal((await engine.decisionSignatures(db,completed)).length,4);
 }finally {await db.query('ROLLBACK');await db.end();}
});
