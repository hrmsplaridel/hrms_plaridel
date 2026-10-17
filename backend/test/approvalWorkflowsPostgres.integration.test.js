'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {Client}=require('pg');
const engine=require('../src/services/approvalWorkflows');
const url=process.env.APPROVAL_WORKFLOWS_TEST_DATABASE_URL;
test('migration and versioned workflows preserve history and execute all configured steps in PostgreSQL',{skip:!url},async()=>{
  const db=new Client({connectionString:url});await db.connect();
  try{
    await db.query('BEGIN');
    const schema='workflow_test_'+require('node:crypto').randomBytes(6).toString('hex');
    await db.query(`CREATE SCHEMA ${schema}`);
    await db.query(`SET LOCAL search_path=${schema},pg_catalog`);
    await db.query(`CREATE TABLE users(id uuid PRIMARY KEY,full_name text,role text,is_active boolean,employment_type text);
      CREATE TABLE leave_types(id uuid PRIMARY KEY,approval_route text,mayor_employment_types text[]);
      CREATE TABLE locator_request_types(LIKE leave_types INCLUDING ALL);
      CREATE TABLE leave_requests(signature_revision integer DEFAULT 1,id uuid PRIMARY KEY,employee_id uuid,status text,final_review_route text CHECK(final_review_route IN ('hr','mayor')),
        final_reviewer_user_id uuid);
      CREATE TABLE locator_slips(LIKE leave_requests INCLUDING ALL);
      CREATE FUNCTION snapshot_leave_approval_route() RETURNS trigger AS $$
      BEGIN
        RETURN NEW;
      END; $$ LANGUAGE plpgsql;
      INSERT INTO leave_types VALUES('11111111-1111-4111-8111-111111111111','hr',null);
      INSERT INTO locator_request_types VALUES('22222222-2222-4222-8222-222222222222','mayor_direct',ARRAY['job_order']);
      INSERT INTO leave_requests(id,employee_id,status,final_review_route,final_reviewer_user_id) VALUES('33333333-3333-4333-8333-333333333333',null,'pending_hr','hr',null);`);
    const originalFunction=(await db.query("SELECT pg_get_functiondef('snapshot_leave_approval_route()'::regprocedure) AS body")).rows[0].body;
    await db.query(originalFunction.replaceAll('\n','\r\n'));
    await db.query(`CREATE TABLE docutracker_leave_signatures(leave_request_id uuid,signature_asset_id uuid,signed_by uuid,signer_name_snapshot text,signed_at timestamptz,revision integer)`);
    const sql=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261015_named_approval_workflows.sql'),'utf8')
      .replace(/^BEGIN;\s*$/m,'').replace(/^COMMIT;\s*$/m,'');
    await db.query(sql);await db.query(sql);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM approval_workflows')).rows[0].n,2);
    assert.ok((await db.query('SELECT approval_workflow_id FROM leave_types')).rows[0].approval_workflow_id);
    const legacy=(await db.query('SELECT * FROM leave_requests')).rows[0];
    assert.equal(legacy.workflow_snapshot,null);assert.equal(legacy.status,'pending_hr');
    const old=(await db.query('SELECT * FROM approval_workflows ORDER BY name LIMIT 1')).rows[0];
    const snapshot={id:old.id,name:old.name,version:1,steps:['department','hr','mayor'],current_step:0,decisions:[]};
    await engine.saveWorkflow(db,'leave',legacy.id,snapshot);
    await db.query('UPDATE approval_workflows SET current_version=2 WHERE id=$1',[old.id]);
    await db.query(`INSERT INTO approval_workflow_versions(workflow_id,version,steps) VALUES($1,2,'["hr"]')`,[old.id]);
    const frozen=await engine.loadRequestWorkflow(db,'leave',legacy.id);
    assert.deepEqual(frozen.steps,['department','hr','mayor']);assert.equal(frozen.version,1);
    let next=engine.nextWorkflowStep(frozen,{id:'head'},'approve');
    assert.equal(engine.workflowStatus(next),'pending_hr');
    next=engine.nextWorkflowStep(next,{id:'hr'},'approve');
    assert.equal(engine.workflowStatus(next),'pending_mayor');
    next=engine.nextWorkflowStep(next,{id:'mayor'},'approve');
    assert.equal(engine.workflowStatus(next),'approved');
    assert.match((await db.query("SELECT pg_get_functiondef('snapshot_leave_approval_route()'::regprocedure) AS body")).rows[0].body,/NEW.workflow_snapshot IS NOT NULL/);
  }finally{await db.query('ROLLBACK');await db.end();}
});
