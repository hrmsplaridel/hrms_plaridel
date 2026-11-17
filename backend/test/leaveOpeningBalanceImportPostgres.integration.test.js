'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
test('PostgreSQL import previews without writes, validates accounting rules, imports atomically, and rejects replays',{
 skip:process.env.LEAVE_OPENING_BALANCE_DB_TEST!=='1',
},async()=>{
 require('dotenv').config({quiet:true});const {pool}=require('../src/config/db');const db=await pool.connect();
 const {runOpeningBalanceImport,COLUMNS}=require('../src/services/leaveOpeningBalanceImport');
 const actor={id:randomUUID(),role:'hr'};const ids=[randomUUID(),randomUUID()];
 try{
  await db.query('BEGIN');
  // Negative isolated numbers are not accepted by imports; use large unused
  // positive numbers selected under the same test transaction instead.
  const maximum=(await db.query('SELECT COALESCE(max(employee_number),0)::bigint AS n FROM users')).rows[0].n;
  const base=Math.max(1000000000,Number(maximum)+1);
  for(const [i,id] of [actor.id,...ids].entries())await db.query(`INSERT INTO users(id,employee_number,email,password_hash,full_name,role,employment_type,date_hired)
    VALUES($1,$2,$3,'not-a-login-credential',$4,$5,'permanent','2020-01-01')`,[id,base+i,`${id}@import-test.invalid`,`Import test ${i}`,i===0?'hr':'employee']);
  let failDuringCommit=false,updates=0;
  const proxy={query:(sql,args)=>{
    if(failDuringCommit&&sql.startsWith('UPDATE leave_balances')&&++updates===7){
      throw Object.assign(new Error('Simulated concurrent accounting change'),{statusCode:409});
    }
    return sql==='BEGIN'?db.query('SAVEPOINT import_transaction'):
    sql==='COMMIT'?db.query('RELEASE SAVEPOINT import_transaction'):
    sql==='ROLLBACK'?db.query('ROLLBACK TO SAVEPOINT import_transaction'):db.query(sql,args);
  },release(){}};
  const scoped={connect:async()=>proxy};const options={today:'2026-11-01'};
  const line=(i,changes={})=>[base+i,'2026-10-31','12.125','9','3','Verified HR card'].map((v,j)=>changes[j]??v).join(',');
  const csv=(...lines)=>COLUMNS.join(',')+'\n'+lines.join('\n');
  const count=async()=>Number((await db.query('SELECT count(*) AS n FROM leave_opening_balance_setups WHERE user_id=ANY($1::uuid[])',[ids])).rows[0].n);
  const valid=csv(line(1),line(2));
  const preview=await runOpeningBalanceImport(scoped,{actor,csv:valid},options);
  assert.equal(preview.valid,true);assert.equal(await count(),0);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM leave_balance_ledger WHERE user_id=ANY($1::uuid[])',[ids])).rows[0].n,0);
  for(const changes of [{2:'-1'},{2:'1.1234'},{2:'NaN'},{2:'10000000'},{1:'2026-10-30'},{1:'2026-11-30'},{4:'366'},{5:''}]){
   const result=await runOpeningBalanceImport(scoped,{actor,csv:csv(line(1),line(2,changes))},options);
   assert.equal(result.valid,false);assert.ok(result.rows[1].error);assert.equal(await count(),0);
  }
  await db.query('UPDATE users SET employment_type=$2 WHERE id=$1',[ids[1],'job_order']);
  await assert.rejects(runOpeningBalanceImport(scoped,{actor,csv:valid,commit:true,confirmed:true},options),e=>e.statusCode===422);
  assert.equal(await count(),0);
  await db.query('UPDATE users SET employment_type=$2,leave_credit_eligible=true WHERE id=$1',[ids[1],'permanent']);
  failDuringCommit=true;
  await assert.rejects(runOpeningBalanceImport(scoped,{actor,csv:valid,commit:true,confirmed:true},options),e=>e.statusCode===409);
  failDuringCommit=false;
  assert.equal(await count(),0,'A late failure rolls back the earlier employee in the same batch');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM leave_balance_ledger WHERE user_id=ANY($1::uuid[])',[ids])).rows[0].n,0);
  const saved=await runOpeningBalanceImport(scoped,{actor,csv:valid,commit:true,confirmed:true},options);
  assert.equal(saved.imported,2);assert.equal(await count(),2);
  const balances=(await db.query('SELECT adjusted_days FROM leave_balances WHERE user_id=ANY($1::uuid[]) ORDER BY user_id,leave_type',[ids])).rows;
  assert.deepEqual(balances.map(r=>r.adjusted_days),['12.125','9.000','12.125','9.000']);
  await assert.rejects(runOpeningBalanceImport(scoped,{actor,csv:valid,commit:true,confirmed:true},options),e=>e.statusCode===422&&e.rows.every(r=>/already recorded/.test(r.error)));
  assert.equal((await db.query('SELECT count(*)::int AS n FROM leave_balance_ledger WHERE user_id=ANY($1::uuid[])',[ids])).rows[0].n,4);
 }finally{await db.query('ROLLBACK');db.release();await pool.end();}
});
