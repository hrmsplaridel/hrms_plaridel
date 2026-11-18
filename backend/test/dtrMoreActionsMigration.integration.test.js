const test=require('node:test');
const assert=require('node:assert/strict');
const {Client}=require('pg');
const {randomUUID}=require('crypto');
const fs=require('fs');
const path=require('path');
const {dtrActionParents}=require('../src/services/dtrActionPermissions');

test('More actions migration preserves existing access once, defaults new grants off, and preserves later revocations',
  {skip:!process.env.DTR_ACCESS_TEST_DATABASE_URL},async()=>{
  const db=new Client({connectionString:process.env.DTR_ACCESS_TEST_DATABASE_URL});
  const schema=`dtr_actions_test_${randomUUID().replaceAll('-','')}`;
  await db.connect();
  try {
    await db.query('BEGIN');
    await db.query(`CREATE SCHEMA ${schema}; SET LOCAL search_path TO ${schema},public`);
    await db.query(`CREATE TABLE dtr_admin_access(id int PRIMARY KEY,leave_allowed boolean NOT NULL DEFAULT false,
      locator_allowed boolean NOT NULL DEFAULT false,updated_at timestamptz NOT NULL DEFAULT now());
      INSERT INTO dtr_admin_access(id,leave_allowed,locator_allowed) VALUES(1,true,false),(2,false,true),(3,false,false)`);
    // Execute inside the test transaction so rollback removes every fixture.
    const sql=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261118_more_actions_access.sql'),'utf8')
      .replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
    await db.query(sql);
    const rows=(await db.query('SELECT * FROM dtr_admin_access ORDER BY id')).rows;
    for(const row of rows) for(const [field,parent]of Object.entries(dtrActionParents)) assert.equal(row[field],row[parent],field);
    await db.query('UPDATE dtr_admin_access SET leave_balances_allowed=false WHERE id=1');
    await db.query(sql);
    assert.equal((await db.query('SELECT leave_balances_allowed FROM dtr_admin_access WHERE id=1')).rows[0].leave_balances_allowed,false);
    await db.query('INSERT INTO dtr_admin_access(id,leave_allowed,locator_allowed) VALUES(4,true,true)');
    const fresh=(await db.query('SELECT * FROM dtr_admin_access WHERE id=4')).rows[0];
    for(const field of Object.keys(dtrActionParents)) assert.equal(fresh[field],false,field);
  }finally{await db.query('ROLLBACK');await db.end();}
});
