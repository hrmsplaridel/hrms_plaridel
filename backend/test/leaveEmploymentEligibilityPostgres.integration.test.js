const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {Client}=require('pg');
test('eligibility migration preserves unconfigured rules and validates restricted lists',
  {skip:!process.env.LEAVE_EMPLOYMENT_TEST_DATABASE_URL},async()=>{
    const db=new Client({connectionString:process.env.LEAVE_EMPLOYMENT_TEST_DATABASE_URL});await db.connect();
    try{
      await db.query('CREATE TEMP TABLE leave_types(id int); INSERT INTO leave_types VALUES(1)');
      const sql=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261010_leave_type_employment_eligibility.sql'),'utf8');
      await db.query(sql);
      assert.equal((await db.query('SELECT eligible_employment_types FROM leave_types')).rows[0].eligible_employment_types,null);
      await db.query("UPDATE leave_types SET eligible_employment_types=ARRAY['permanent','contractual']");
      await db.query(sql);
      assert.deepEqual((await db.query('SELECT eligible_employment_types FROM leave_types')).rows[0].eligible_employment_types,['permanent','contractual']);
      for(const values of [[],['unknown'],[null]]) {
        await assert.rejects(db.query('UPDATE leave_types SET eligible_employment_types=$1::text[]',[values]),e=>e.code==='23514');
      }
    }finally{await db.end();}
  });
