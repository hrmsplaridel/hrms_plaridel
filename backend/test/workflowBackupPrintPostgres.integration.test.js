'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomBytes}=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const {Client}=require('pg');

test('backup print migration applies twice, validates policies and leaves request snapshots unchanged in isolated PostgreSQL',
  {skip:!process.env.WORKFLOW_BACKUP_PRINT_TEST_DATABASE_URL},async()=>{
    const target=new URL(process.env.WORKFLOW_BACKUP_PRINT_TEST_DATABASE_URL);
    assert.ok(['localhost','127.0.0.1'].includes(target.hostname)&&target.port==='5433','Explicit local PostgreSQL test server required');
    const schema=`workflow_backup_print_${randomBytes(6).toString('hex')}`;
    const db=new Client({connectionString:target.toString()});
    await db.connect();
    try {
      await db.query(`CREATE SCHEMA ${schema}; SET search_path TO ${schema};
        CREATE TABLE approval_workflow_versions(version integer PRIMARY KEY);
        INSERT INTO approval_workflow_versions VALUES(1);
        CREATE TABLE leave_requests(workflow_snapshot jsonb);
        CREATE TABLE locator_slips(workflow_snapshot jsonb);
        INSERT INTO leave_requests VALUES(' {"version":1,"decisions":[]} ');
        INSERT INTO locator_slips SELECT * FROM leave_requests;`);
      const migration=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261111_workflow_backup_signatories.sql'),'utf8');
      await db.query(migration);
      await db.query(migration);
      assert.equal((await db.query('SELECT backup_signatory_policy FROM approval_workflow_versions WHERE version=1')).rows[0].backup_signatory_policy,'keep_primary');
      await db.query("INSERT INTO approval_workflow_versions VALUES(2,'actual_reviewer')");
      await assert.rejects(db.query("INSERT INTO approval_workflow_versions VALUES(3,'invalid')"),{code:'23514'});
      for(const table of ['leave_requests','locator_slips']) {
        assert.deepEqual((await db.query(`SELECT workflow_snapshot FROM ${table}`)).rows[0].workflow_snapshot,{version:1,decisions:[]});
      }
    } finally {
      await db.query('ROLLBACK');
      await db.query(`SET search_path TO public; DROP SCHEMA IF EXISTS ${schema} CASCADE`);
      await db.end();
    }
  });
