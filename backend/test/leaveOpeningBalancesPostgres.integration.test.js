const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
test('PostgreSQL opening setup records exact final credits and cutoff; all test rows roll back',{
 skip:process.env.LEAVE_OPENING_BALANCE_DB_TEST!=='1',
},async()=>{
 require('dotenv').config();
 const {pool}=require('../src/config/db');
 const db=await pool.connect();
 try {
  await db.query('BEGIN');
  const userId=randomUUID(),actorId=randomUUID();
  for(const [id,role] of [[userId,'employee'],[actorId,'hr']])await db.query(`INSERT INTO users(id,employee_number,email,password_hash,full_name,role,employment_type,date_hired)
   VALUES($1,NULL,$2,'not-a-login-credential','Opening balance rollback test',$3,'permanent','2020-01-01')`,[id,`${id}@rollback.invalid`,role]);
  const service=require('../src/services/leaveOpeningBalances');
  const input={userId,actor:{id:actorId,role:'hr'},sick_leave_days:25,vacation_leave_days:30,qualifying_leave_days:3,cutoff_date:'2026-10-31',confirmed:true,reason:'Transactional integration test; rolled back.'};
  const recorded=await service.applyOpeningBalances(db,input,{today:'2026-11-01'});
  assert.equal(recorded.setup.cutoff_date,'2026-10-31');
  assert.equal(Number(recorded.setup.qualifying_leave_days),3);
  const controller=require('../src/modules/leave/controllers/openingBalances.controller')({pool:{query:(...args)=>db.query(...args)},todayInHrmsTimezone:()=> '2026-11-01'});
  const response={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
  await controller.getOpeningBalances({params:{userId}},response);
  assert.equal(response.code,200);assert.equal(response.body.setup.cutoff_date,'2026-10-31');
  const balances=(await db.query('SELECT leave_type,earned_days,used_days,pending_days,adjusted_days,last_accrual_date::text FROM leave_balances WHERE user_id=$1 ORDER BY leave_type',[userId])).rows;
  assert.deepEqual(balances.map(b=>Number(b.earned_days)-Number(b.used_days)+Number(b.adjusted_days)-Number(b.pending_days)),[25,30]);
  assert.deepEqual(balances.map(b=>b.last_accrual_date),['2026-10-01','2026-10-01']);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM leave_balance_ledger WHERE user_id=$1 AND action='opening_balance'",[userId])).rows[0].n,2);
  assert.equal((await service.loadOpeningBalanceCutoffs(db,[userId])).get(userId),'2026-10-31');
  const type=(await db.query("SELECT id FROM leave_types WHERE name='vacationLeave' LIMIT 1")).rows[0];
  assert.ok(type,'Vacation leave must be configured for the integration test');
  for(const [from,to,days] of [['2026-05-04','2026-05-06',3],['2026-11-02','2026-11-03',2]]) {
    await db.query(`INSERT INTO leave_requests(employee_id,user_id,leave_type_id,start_date,end_date,number_of_days,total_days,status)
      VALUES($1,$1,$2,$3,$4,$5,$5,'approved')`,[userId,type.id,from,to,days]);
  }
  const {getYearEndForcedLeaveCompliance}=require('../src/services/leaveYearEndForcedLeave');
  const compliance=await getYearEndForcedLeaveCompliance(db,{year:2026,userId});
  assert.equal(compliance.employees[0].qualifying_leave_days_used,5,'Snapshot replaces pre-cutoff requests and adds only later usage');
  await assert.rejects(service.applyOpeningBalances(db,input,{today:'2026-11-01'}),/already recorded/);
  await db.query('UPDATE leave_opening_balance_setups SET qualifying_leave_days=NULL,usage_reference=NULL,usage_verified_at=NULL,usage_verified_by=NULL WHERE user_id=$1',[userId]);
  const snapshot=JSON.stringify((await db.query('SELECT * FROM leave_balances WHERE user_id=$1 ORDER BY leave_type',[userId])).rows);
  assert.equal((await getYearEndForcedLeaveCompliance(db,{year:2026,userId})).employees[0].status,'needs_history_review');
  await service.verifyOpeningUsage(db,{userId,actor:input.actor,cutoff_date:'2026-10-31',qualifying_leave_days:5,reference:'Verified legacy leave card',confirmed:true});
  assert.equal(JSON.stringify((await db.query('SELECT * FROM leave_balances WHERE user_id=$1 ORDER BY leave_type',[userId])).rows),snapshot);
  assert.equal(Number((await db.query('SELECT qualifying_leave_days FROM leave_opening_balance_setups WHERE user_id=$1',[userId])).rows[0].qualifying_leave_days),5);
 } finally {await db.query('ROLLBACK');db.release();await pool.end();}
});
