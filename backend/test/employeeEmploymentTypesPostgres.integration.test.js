const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {Client}=require('pg');
test('employment type migration preserves legacy rows and accepts seven distinct types',
  {skip:!process.env.EMPLOYMENT_TYPES_TEST_DATABASE_URL},async()=>{
    const db=new Client({connectionString:process.env.EMPLOYMENT_TYPES_TEST_DATABASE_URL});
    await db.connect();
    try{
      await db.query(`CREATE TEMP TABLE users(employment_type text
        CONSTRAINT users_employment_type_check CHECK(employment_type IN ('regular','casual','contractual','job_order')));
        INSERT INTO users VALUES('regular'),('contractual'),(NULL);`);
      const migration=fs.readFileSync(path.join(__dirname,'../scripts/migrations/20261009_employee_employment_types.sql'),'utf8');
      await db.query(migration);
      await db.query(migration);
      for(const type of ['permanent','temporary','casual','contractual','coterminous','job_order','contract_of_service']) {
        await db.query('INSERT INTO users VALUES($1)',[type]);
      }
      await assert.rejects(db.query("INSERT INTO users VALUES('unknown')"),e=>e.code==='23514');
      const result=await db.query('SELECT employment_type FROM users');
      assert.equal(result.rows.length,10);
      assert.equal(result.rows[0].employment_type,'regular');
      assert.equal(result.rows[1].employment_type,'contractual');
      assert.equal(result.rows[2].employment_type,null);
    }finally{await db.end();}
  });
