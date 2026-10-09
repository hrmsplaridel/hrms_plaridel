const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {Client}=require('pg');
const {randomUUID}=require('node:crypto');
test('JO/COS default credit and protected leave exclusions preserve balances and legacy access',
  {skip:!process.env.JO_COS_TEST_DATABASE_URL},async()=>{
    const db=new Client({connectionString:process.env.JO_COS_TEST_DATABASE_URL});await db.connect();
    const schema=`jo_cos_test_${randomUUID().replaceAll('-','')}`;
    try{
      await db.query(`CREATE SCHEMA ${schema}; SET search_path TO ${schema},public`);
      await db.query(`CREATE TEMP TABLE users(id int, employment_type text,
        leave_credit_eligible boolean DEFAULT true, leave_credit_eligible_until date,updated_at timestamptz DEFAULT now());
        CREATE TEMP TABLE leave_types(name text,is_system boolean,eligible_employment_types text[],updated_at timestamptz DEFAULT now());
        CREATE TEMP TABLE leave_balances(earned_days numeric,used_days numeric);
        INSERT INTO users(id,employment_type) VALUES(1,'job_order'),(2,'contract_of_service'),(3,'regular');
        INSERT INTO leave_types VALUES('vacationLeave',true,NULL,now()),('custom',false,NULL,now());
        INSERT INTO leave_balances VALUES(10,2);`);
      const sql=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261010_jo_cos_leave_defaults.sql'),'utf8');
      await db.query(sql);
      assert.deepEqual((await db.query('SELECT leave_credit_eligible FROM users ORDER BY id')).rows.map(r=>r.leave_credit_eligible),[false,false,true]);
      const protectedTypes=(await db.query("SELECT eligible_employment_types FROM leave_types WHERE is_system=true")).rows[0].eligible_employment_types;
      assert.ok(protectedTypes.includes('regular'));
      assert.equal(protectedTypes.includes('job_order'),false);
      assert.equal(protectedTypes.includes('contract_of_service'),false);
      assert.equal((await db.query("SELECT eligible_employment_types FROM leave_types WHERE name='custom'")).rows[0].eligible_employment_types,null);
      assert.deepEqual((await db.query('SELECT earned_days,used_days FROM leave_balances')).rows,[{earned_days:'10',used_days:'2'}]);
      await db.query("INSERT INTO users(id,employment_type) VALUES(4,'job_order'),(5,'contract_of_service'),(6,'permanent')");
      assert.deepEqual((await db.query('SELECT leave_credit_eligible FROM users WHERE id>=4 ORDER BY id')).rows.map(r=>r.leave_credit_eligible),[false,false,true]);
      await db.query("UPDATE users SET employment_type='contract_of_service' WHERE id=6");
      assert.equal((await db.query('SELECT leave_credit_eligible FROM users WHERE id=6')).rows[0].leave_credit_eligible,false);
      await db.query('UPDATE users SET leave_credit_eligible=true WHERE id=4');
      await db.query(sql);
      assert.equal((await db.query('SELECT leave_credit_eligible FROM users WHERE id=4')).rows[0].leave_credit_eligible,true);
    }finally{await db.query('ROLLBACK');await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);await db.end();}
  });
