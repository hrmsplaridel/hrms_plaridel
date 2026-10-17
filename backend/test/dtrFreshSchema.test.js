'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {randomBytes}=require('node:crypto');
const {Client}=require('pg');
const root=path.resolve(__dirname,'..');
const schemaFile=path.join(root,'scripts/init-schema.sql');
const schema=fs.readFileSync(schemaFile,'utf8');
const reflectedMigrations=[
 '20261013_locator_approval_routing.sql','20261013_locator_custom_fields.sql',
 '20261013_locator_print_layouts.sql','20261013_leave_print_layouts.sql',
 '20261015_leave_signature_revisions.sql','20261015_named_approval_workflows.sql',
 '20261016_shared_workflow_assignments.sql',
];

test('the seven DTR upgrades are reflected directly without their initializer includes',()=>{
 for(const file of reflectedMigrations){
  assert.ok(fs.existsSync(path.join(root,'scripts/migrations/dtr',file)),`${file} remains available for upgrades`);
  assert.equal(schema.includes(`\\ir migrations/dtr/${file}`),false,`${file} must not be required by the fresh initializer`);
 }
});

test('the complete fresh initializer runs as SQL without psql commands or other files',()=>{
 assert.doesNotMatch(schema,/^\s*\\/m,'pgAdmin Query Tool accepts SQL, not psql commands');
 const fields={
  users:['auth_version'],audit_logs:['actor_snapshot','target_snapshot'],
  auth_password_reset_otps:['assistance_request_id'],
  recruitment_applications:['step2_gate_required','step4_gate_required','step5_gate_required','required_form_review_log','wes_status','tat_status','csc_approval_status'],
  bi_form_entries:['application_id'],ojt_work_immersion_evaluation_entries:['application_id'],
 };
 for(const [table,columns] of Object.entries(fields)){
  const body=schema.match(new RegExp(`CREATE TABLE IF NOT EXISTS ${table}\\s*\\(([\\s\\S]*?)\\n\\);`,'i'))?.[1];
  assert.ok(body,`${table} is defined`);
  for(const field of columns)assert.match(body,new RegExp(`^\\s*${field}\\s+`,'mi'),`${table}.${field} is declared directly`);
 }
 assert.match(schema,/CREATE TABLE IF NOT EXISTS password_reset_requests\s*\(/i);
 assert.match(schema,/CREATE OR REPLACE FUNCTION (?:public\.)?rsp_storage_path_allowed\s*\(/i);
});

test('DTR table definitions declare the current workflow, signature, field and layout columns',()=>{
 const columns={
  leave_types:['approval_workflow_id'],leave_requests:['workflow_snapshot','signature_revision'],
  locator_request_types:['approval_workflow_id','employee_detail_schema'],
  locator_slips:['workflow_snapshot','employee_detail_schema_snapshot','additional_details'],
  docutracker_leave_signatures:['revision'],leave_print_template_versions:['print_layout'],
  locator_print_template_versions:['print_layout'],
  docutracker_routing_config_versions:['shared_workflow_id','shared_workflow_version'],
 };
 for(const [table,fields] of Object.entries(columns)){
  const definition=schema.match(new RegExp(`CREATE TABLE IF NOT EXISTS ${table}\\s*\\(([\\s\\S]*?)\\n\\);`,'i'));
  assert.ok(definition,`${table} is defined`);
  for(const field of fields)assert.ok(new RegExp(`^\\s*${field}\\s+`,'mi').test(definition[1]),`${table}.${field} must be declared on its table`);
 }
 for(const table of ['approval_workflows','approval_workflow_versions','approval_workflow_document_types']){
  assert.ok(new RegExp(`CREATE TABLE IF NOT EXISTS ${table}\\s*\\(`).test(schema),`${table} is defined`);
 }
});

test('fresh DTR installation resolves configured reviewers and preserves current form/signature rules',
 {skip:!process.env.DTR_FRESH_SCHEMA_TEST_DATABASE_URL,timeout:120000},async()=>{
 const url=new URL(process.env.DTR_FRESH_SCHEMA_TEST_DATABASE_URL);
 assert.ok(['localhost','127.0.0.1'].includes(url.hostname)&&url.port==='5433','Use the explicitly selected local PostgreSQL server on port 5433');
 const name=`hrms_dtr_fresh_${process.pid}_${randomBytes(5).toString('hex')}`;
 const maintenanceUrl=new URL(url);maintenanceUrl.pathname='/postgres';
 const maintenance=new Client({connectionString:maintenanceUrl.toString()});
 let created=false,db;
 try{
  await maintenance.connect();await maintenance.query(`CREATE DATABASE "${name}" TEMPLATE template0`);created=true;
  const target=new URL(url);target.pathname=`/${name}`;
  db=new Client({connectionString:target.toString()});await db.connect();
  // Send the complete file as SQL, just like pgAdmin Query Tool: no psql includes.
  await db.query(schema);
  const reset=(await db.query("INSERT INTO users(email,password_hash,full_name) VALUES('reset@test.invalid','test-hash','Reset User') RETURNING id")).rows[0];
  const assistance=(await db.query('INSERT INTO password_reset_requests(user_id) VALUES($1) RETURNING id',[reset.id])).rows[0];
  await db.query("INSERT INTO auth_password_reset_otps(user_id,code_hash,expires_at,assistance_request_id) VALUES($1,'test',now()+interval '5 minutes',$2)",[reset.id,assistance.id]);
  const audit=(await db.query("INSERT INTO audit_logs(user_id,entity_id,entity_type,action) VALUES($1,$1,'auth','test') RETURNING actor_snapshot,target_snapshot",[reset.id])).rows[0];
  assert.equal(audit.actor_snapshot.name,'Reset User');assert.equal(audit.target_snapshot.name,'Reset User');
  const application=(await db.query("INSERT INTO recruitment_applications(full_name,email,attachment_path) VALUES('Applicant','recruit@test.invalid','test/resume.pdf') RETURNING *")).rows[0];
  assert.equal(application.step2_gate_required,false);assert.equal(application.step4_gate_required,false);assert.equal(application.step5_gate_required,false);
  assert.equal((await db.query("SELECT rsp_storage_path_allowed('test/resume.pdf') AS allowed")).rows[0].allowed,true);
  assert.equal((await db.query("SELECT rsp_storage_path_allowed('unrelated/file.pdf') AS allowed")).rows[0].allowed,false);
  const constraints=(await db.query("SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conname IN ('approval_workflow_versions_steps_check','docutracker_workflow_steps_assignee_source_check','docutracker_leave_signatures_request_revision_slot_unique')")).rows;
  assert.match(constraints.find(c=>c.conname==='approval_workflow_versions_steps_check').definition,/20/);
  assert.match(constraints.find(c=>c.conname==='docutracker_workflow_steps_assignee_source_check').definition,/final_hr_reviewers.*active_mayor/);
  assert.ok(constraints.some(c=>c.conname==='docutracker_leave_signatures_request_revision_slot_unique'));
  assert.equal((await db.query("SELECT count(*)::int AS n FROM pg_constraint WHERE conname='docutracker_leave_signatures_request_slot_unique'")).rows[0].n,0);
  for(const table of ['leave_types','locator_request_types']){
   assert.equal((await db.query(`SELECT count(*)::int AS n FROM ${table} WHERE approval_workflow_id IS NULL`)).rows[0].n,0);
  }
  const applicant=(await db.query("INSERT INTO users(email,password_hash,full_name) VALUES('fresh-applicant@test.invalid','test-hash','Fresh Applicant') RETURNING id")).rows[0].id;
  const reviewer=(await db.query("INSERT INTO users(email,password_hash,full_name) VALUES('fresh-reviewer@test.invalid','test-hash','Fresh Reviewer') RETURNING id")).rows[0].id;
  const snapshot={name:'Configured fresh route',version:1,current_step:0,decisions:[],steps:[
   {label:'Specific review',assignee_source:'specific_users',user_ids:[reviewer],allowed_actions:['approve']},
   {label:'Mayor review',assignee_source:'active_mayor',user_ids:[],allowed_actions:['approve']},
  ]};
  const leave=(await db.query(`INSERT INTO leave_requests(employee_id,user_id,leave_type_id,start_date,end_date,total_days,number_of_days,reason,status,workflow_snapshot)
   SELECT $1,$1,id,CURRENT_DATE,CURRENT_DATE,1,1,'Original','pending_hr',$2::jsonb FROM leave_types WHERE name='vacationLeave' RETURNING *`,[applicant,JSON.stringify(snapshot)])).rows[0];
  assert.ok(leave.print_template_version_id);assert.equal(leave.signature_revision,1);
  const engine=require('../src/services/approvalWorkflows');
  assert.deepEqual((await engine.resolveWorkflowReviewers(db,'leave',leave)).map(r=>r.id),[reviewer]);
  assert.equal((await db.query("UPDATE leave_requests SET reason='Edited' WHERE id=$1 RETURNING signature_revision",[leave.id])).rows[0].signature_revision,2);
  assert.equal((await db.query("UPDATE leave_requests SET status='pending_mayor' WHERE id=$1 RETURNING signature_revision",[leave.id])).rows[0].signature_revision,2);
  const asset=(await db.query(`INSERT INTO docutracker_signature_assets(owner_user_id,image_bytes,mime_type,source_type)
   VALUES($1,decode('00','hex'),'image/png','drawn') RETURNING id`,[applicant])).rows[0].id;
  for(const revision of [1,2])await db.query(`INSERT INTO docutracker_leave_signatures
   (leave_request_id,revision,slot_key,assigned_signer_id,signature_asset_id,signed_by,signer_name_snapshot)
   VALUES($1,$2,'applicant',$3,$4,$3,'Fresh Applicant')`,[leave.id,revision,applicant,asset]);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM docutracker_leave_signatures WHERE leave_request_id=$1',[leave.id])).rows[0].n,2,'Archived and current confirmations coexist');
  const locator=(await db.query(`INSERT INTO locator_slips(employee_id,slip_date,office,reason,am_in,status,workflow_snapshot)
   VALUES($1,CURRENT_DATE,'Destination','Visit',true,'pending_hr',$2::jsonb) RETURNING *`,[applicant,JSON.stringify(snapshot)])).rows[0];
  assert.ok(locator.print_template_version_id);
  assert.deepEqual((await engine.resolveWorkflowReviewers(db,'locator',locator)).map(r=>r.id),[reviewer]);
  assert.equal((await db.query("UPDATE locator_slips SET office='Other destination' WHERE id=$1 RETURNING signature_revision",[locator.id])).rows[0].signature_revision,2);
 }finally{
  if(db){await db.query('ROLLBACK');await db.end();}
  if(created){assert.match(name,/^hrms_dtr_fresh_\d+_[a-f0-9]{10}$/);await maintenance.query(`DROP DATABASE "${name}"`);}
  await maintenance.end();
 }
});
