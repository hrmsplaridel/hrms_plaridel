const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');

test('custom wallet migration, accrual, cap, repeat runs and credit lifecycle in PostgreSQL',{
 skip:process.env.CUSTOM_LEAVE_DB_TEST !== '1',
},async()=>{
 require('dotenv').config({path:path.join(__dirname,'../.env')});
 const url=new URL(process.env.DATABASE_URL);
 assert.ok(['localhost','127.0.0.1','[::1]'].includes(url.hostname),'Local test database only');
 const {Pool}=require('pg');
 const {buildPoolOptions}=require('../src/config/databasePoolOptions');
 const pool=new Pool(buildPoolOptions()), db=await pool.connect();
 const schema=`custom_leave_test_${randomUUID().replaceAll('-','')}`;
 try {
  await db.query('BEGIN');
  await db.query(`CREATE SCHEMA "${schema}"; SET LOCAL search_path TO "${schema}", public`);
  await db.query(`CREATE TABLE users(id uuid PRIMARY KEY,full_name text,role text DEFAULT 'employee',
    date_hired date,sex text,employment_type text,employment_status text DEFAULT 'active',
    separation_date date,leave_credit_eligible boolean DEFAULT true,leave_credit_eligible_until date);
    CREATE TABLE approval_workflows(id uuid PRIMARY KEY);
    CREATE TABLE assignments(employee_id uuid,effective_from date,effective_to date);
    CREATE TABLE leave_requests(id uuid PRIMARY KEY,reserved_credit_days numeric,updated_at timestamptz);
    CREATE TABLE leave_opening_balance_setups(user_id uuid,cutoff_date date);`);
  const init=fs.readFileSync(path.join(__dirname,'../scripts/init-schema.sql'),'utf8');
  for(const table of ['leave_types','leave_balances']) {
    const from=init.indexOf(`CREATE TABLE IF NOT EXISTS ${table} (`);
    const to=init.indexOf('\n);',from)+4;
    assert.ok(from>=0 && to>from);
    await db.query(init.slice(from,to));
  }
  // Simulate an existing installation, then execute the actual migration.
  await db.query(`ALTER TABLE leave_types DROP CONSTRAINT chk_custom_leave_accrual;
    ALTER TABLE leave_types DROP COLUMN accrual_start_date;
    ALTER TABLE leave_balances ADD CONSTRAINT chk_leave_balances_leave_type
      CHECK(leave_type IN ('vacationLeave','sickLeave'));`);
  const migration=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261112_custom_leave_balances.sql'),'utf8')
    .replace(/^BEGIN;\s*$/m,'').replace(/^COMMIT;\s*$/m,'');
  await db.query(migration);
  const user=randomUUID(),jo=randomUUID(),restricted=randomUUID();
  for(const [id,employment,sex] of [[user,'permanent','female'],[jo,'job_order','female'],[restricted,'permanent','male']]) {
    await db.query(`INSERT INTO users(id,full_name,date_hired,sex,employment_type) VALUES($1,'Synthetic credit test','2020-01-01',$3,$2)`,[id,employment,sex]);
    await db.query(`INSERT INTO assignments VALUES($1,'2020-01-01',NULL)`,[id]);
  }
  await db.query(`INSERT INTO leave_types(name,display_name,is_system,balance_ledger_type,entitlement_basis,accrues_monthly,accrual_monthly_rate)
    VALUES('vacationLeave','Vacation Leave',true,'vacationLeave','accrual',true,1.25),
          ('sickLeave','Sick Leave',true,'sickLeave','accrual',true,1.25);
    INSERT INTO leave_types(name,display_name,balance_ledger_type,entitlement_basis,accrues_monthly,accrual_monthly_rate,accrual_start_date,accrual_annual_cap,sex_eligibility,eligible_employment_types)
    VALUES('wellness','Wellness Leave','ownBalance','accrual',true,1.25,'2026-09-01',2,'female',ARRAY['permanent']);`);
  const adapter={query:(...args)=>db.query(...args),connect:async()=>({
    query:(sql,params)=>db.query(sql==='BEGIN'?'SAVEPOINT accrual_job':sql==='COMMIT'?'RELEASE SAVEPOINT accrual_job':sql==='ROLLBACK'?'ROLLBACK TO SAVEPOINT accrual_job':sql,params),release(){}
  })};
  const {runLeaveMonthlyAccrual}=require('../src/services/leaveMonthlyAccrual');
  const {loadLeaveDependencies}=require('../src/modules/leave/dependencies');
  const deps=loadLeaveDependencies();
  const policies=require('../src/modules/leave/policies/leaveTypes')(deps);
  const serialize=require('../src/modules/leave/serializers/leaveTypes')({...deps,...policies}).leaveTypeRowToApi;
  const savedType=(await db.query("SELECT * FROM leave_types WHERE name='wellness'")).rows[0];
  assert.equal(serialize(savedType).accrual_start_date,'2026-09-01','PostgreSQL DATE must retain its calendar day');
  const run=(targetMonth)=>runLeaveMonthlyAccrual(adapter,{targetMonth,maxCatchUpMonths:120,now:'2027-03-01'});
  const balance=async()=> (await db.query(`SELECT * FROM leave_balances WHERE user_id=$1 AND leave_type='wellness'`,[user])).rows[0];
  await run('2026-08');assert.equal(Number((await balance())?.earned_days || 0),0);
  await run('2026-10');assert.equal(Number((await balance()).earned_days),2);
  assert.equal((await db.query(`SELECT count(*)::int AS n FROM leave_monthly_accrual_postings WHERE user_id=$1 AND leave_type='wellness'`,[user])).rows[0].n,2);
  await run('2026-10');assert.equal(Number((await balance()).earned_days),2);
  await db.query(`UPDATE leave_balances SET used_days=1 WHERE user_id=$1 AND leave_type='wellness'`,[user]);
  await run('2026-11');assert.equal(Number((await balance()).earned_days),2,'Annual cap does not replenish after usage');
  await run('2027-01');assert.equal(Number((await balance()).earned_days),3.25,'Annual earning cap resets in January');
  const before=Number((await balance()).earned_days);
  await db.query(`UPDATE leave_types SET accrual_monthly_rate=3 WHERE name='wellness'`);
  await run('2027-01');assert.equal(Number((await balance()).earned_days),before,'Editing rate preserves posted credits');
  assert.equal((await db.query(`SELECT count(*)::int AS n FROM leave_monthly_accrual_postings WHERE user_id=ANY($1::uuid[]) AND leave_type='wellness'`,[[jo,restricted]])).rows[0].n,0);
  const ledger=require('../src/services/leaveBalanceLedger');
  await ledger.applyAdminLeaveBalanceAdjustment(db,{userId:user,leaveType:'wellness',daysChanged:3,remarks:'Verified custom opening allowance',actorKind:'system'});
  const credits=require('../src/modules/leave/use-cases/leaveCredits')({...deps,...policies});
  const request=randomUUID();await db.query('INSERT INTO leave_requests(id) VALUES($1)',[request]);
  await credits.reservePendingLeaveBalance(db,{userId:user,leaveTypeName:'wellness',days:1,leaveRequestId:request});
  assert.equal(Number((await balance()).pending_days),1);
  await credits.releasePendingLeaveBalance(db,{userId:user,leaveTypeName:'wellness',days:1,leaveRequestId:request,action:'leave_cancelled'});
  assert.equal(Number((await balance()).pending_days),0,'Cancellation releases only this wallet');
  await credits.reservePendingLeaveBalance(db,{userId:user,leaveTypeName:'wellness',days:1,leaveRequestId:request});
  await credits.upsertLeaveBalanceDeduction(db,user,'wellness',1,{decrementPendingDays:true,pendingDaysToRelease:1});
  assert.equal(Number((await balance()).used_days),2);assert.equal(Number((await balance()).pending_days),0);
  assert.equal(Number((await balance()).adjusted_days),3);
  await db.query(`UPDATE leave_types SET accrues_monthly=false,accrual_monthly_rate=NULL,accrual_start_date=NULL,accrual_annual_cap=NULL WHERE name='wellness'`);
  await run('2027-02');assert.equal(Number((await balance()).earned_days),before,'Disabling accrual preserves historical awards');
  await db.query('SAVEPOINT invalid_type');
  await db.query(`INSERT INTO leave_balances(user_id,leave_type) VALUES($1,'unregistered')`,[user]);
  await assert.rejects(db.query('SET CONSTRAINTS ALL IMMEDIATE'));
  await db.query('ROLLBACK TO SAVEPOINT invalid_type');
 } finally {
  await db.query('ROLLBACK');db.release();await pool.end();
 }
});
