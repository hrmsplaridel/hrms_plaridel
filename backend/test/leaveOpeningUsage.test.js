const test = require('node:test');
const assert = require('node:assert/strict');
const service = require('../src/services/leaveOpeningBalances');
const usage = () => require('../src/services/leaveOpeningUsage');
const ID = '11111111-1111-4111-8111-111111111111';
const actor = {id:'22222222-2222-4222-8222-222222222222',role:'hr'};

for (const [name, opening, expected, review] of [
  ['verified three days',{cutoff_date:'2026-10-31',qualifying_leave_days:3},5,false],
  ['verified zero',{cutoff_date:'2026-10-31',qualifying_leave_days:0},2,false],
  ['unverified legacy',{cutoff_date:'2026-10-31',qualifying_leave_days:null},2,true],
  ['previous year',{cutoff_date:'2025-12-31',qualifying_leave_days:5},7,false],
]) test(`qualifying usage: ${name}`, async () => {
  const requests = [
    {status:'approved',start_date:'2026-02-01',end_date:'2026-02-05'},
    {status:'approved',start_date:'2026-11-02',end_date:'2026-11-03'},
    {status:'rejected',start_date:'2026-11-04',end_date:'2026-11-04'},
  ];
  const result = await usage().qualifyingUsage({},ID,2026,opening,requests,
    async(_db,_id,from,to)=> (Date.parse(to)-Date.parse(from))/86400000+1);
  assert.equal(result.used,expected);assert.equal(result.needsReview,review);
});

test('qualifying usage clips overlapping cutoff/year dates before counting and ignores reversed ranges', async () => {
  const ranges=[];
  const result=await usage().qualifyingUsage({},ID,2026,{cutoff_date:'2026-10-31',qualifying_leave_days:3},[
    {status:'approved',start_date:'2026-10-30',end_date:'2026-11-02'},
    {status:'approved',start_date:'2026-12-31',end_date:'2027-01-04'},
    {status:'approved',start_date:'2025-12-30',end_date:'2026-01-02'},
  ],async(_db,_id,from,to)=>{ranges.push([from,to]);return 1;});
  assert.deepEqual(ranges,[['2026-11-01','2026-11-02'],['2026-12-31','2026-12-31']]);
  assert.equal(result.used,5);
});

function verificationDb({verified=false}={}) {
  const calls=[];
  return {calls,query:async(sql,params)=>{
    calls.push({sql,params});
    if(sql.includes('FROM leave_opening_balance_setups')) return {rows:[{user_id:ID,cutoff_date:'2026-10-31',qualifying_leave_days:verified?3:null}]};
    if(sql.includes('UPDATE leave_opening_balance_setups')) return {rows:[{user_id:ID,cutoff_date:'2026-10-31',qualifying_leave_days:params[1]}]};
    return {rows:[]};
  }};
}
test('legacy usage verification records reference and verifier without changing credit balances',async()=>{
  const db=verificationDb();
  const result=await service.verifyOpeningUsage(db,{userId:ID,actor,cutoff_date:'2026-10-31',qualifying_leave_days:3,reference:'HR leave card 2026',confirmed:true});
  assert.equal(Number(result.setup.qualifying_leave_days),3);
  assert.equal(db.calls.some(c=>/UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(c.sql)),false);
  const update=db.calls.find(c=>c.sql.includes('UPDATE leave_opening_balance_setups'));
  assert.ok(update.params.includes(actor.id));assert.ok(update.params.includes('HR leave card 2026'));
});
for(const change of [{qualifying_leave_days:-1},{qualifying_leave_days:367},{qualifying_leave_days:null},{confirmed:false},{reference:''},{cutoff_date:'2026-09-30'},{actor:{...actor,role:'employee'}}])
test(`invalid verification is rejected: ${JSON.stringify(change)}`,async()=>{
  const db=verificationDb();
  await assert.rejects(service.verifyOpeningUsage(db,{userId:ID,actor,cutoff_date:'2026-10-31',qualifying_leave_days:3,reference:'HR card',confirmed:true,...change}),e=>e.statusCode>=400);
  assert.equal(db.calls.some(c=>c.sql.startsWith('UPDATE')),false);
});
test('verified opening usage cannot be overwritten',async()=>{
  await assert.rejects(service.verifyOpeningUsage(verificationDb({verified:true}),{userId:ID,actor,cutoff_date:'2026-10-31',qualifying_leave_days:0,reference:'HR card',confirmed:true}),e=>e.statusCode===409);
});

test('year-end blocks deductions until historical usage is verified',async()=>{
  const {getYearEndForcedLeaveCompliance,applyYearEndForcedLeaveDeductions}=require('../src/services/leaveYearEndForcedLeave');
  const pool={query:async()=>({rows:[{user_id:ID,vl_accumulated:30,vl_available:30,opening_cutoff:'2025-10-31',opening_qualifying_days:null,qualifying_requests:[]}]}),connect:async()=>{throw new Error('Must not deduct');}};
  const result=await getYearEndForcedLeaveCompliance(pool,{year:2025});
  assert.equal(result.employees[0].status,'needs_history_review');
  assert.equal(result.employees[0].can_apply,false);
  assert.equal(result.employees[0].actual_deduction,0);
  const applied=await applyYearEndForcedLeaveDeductions(pool,{year:2025});
  assert.equal(applied.summary.history_review,1);
});
test('year-end adds verified historical usage to post-cutoff requests',async()=>{
  const {getYearEndForcedLeaveCompliance}=require('../src/services/leaveYearEndForcedLeave');
  const pool={query:async sql=>({rows:String(sql).includes('FROM users u')?[{user_id:ID,vl_accumulated:30,vl_available:30,opening_cutoff:'2025-10-31',opening_qualifying_days:3,
    qualifying_requests:[{status:'approved',start_date:'2025-11-03',end_date:'2025-11-04',number_of_days:2}]}]
      :String(sql).includes('generate_series')?[{attendance_date:'2025-11-03',working_days:[1,2,3,4,5]},{attendance_date:'2025-11-04',working_days:[1,2,3,4,5]}]:[]})};
  const result=await getYearEndForcedLeaveCompliance(pool,{year:2025});
  assert.equal(result.employees[0].qualifying_leave_days_used,5);
  assert.equal(result.employees[0].status,'compliant');
});

test('year-end rechecks usage under the employee lock before deducting',async()=>{
  const {applyYearEndForcedLeaveDeductions}=require('../src/services/leaveYearEndForcedLeave');
  const writes=[];
  const row=days=>({user_id:ID,vl_accumulated:30,vl_available:30,opening_cutoff:'2025-10-31',opening_qualifying_days:days,qualifying_requests:[]});
  const client={release(){},query:async sql=>{
    writes.push(sql);
    return {rows:String(sql).includes('FROM users u')?[row(5)]:[]};
  }};
  const result=await applyYearEndForcedLeaveDeductions({query:async()=>({rows:[row(3)]}),connect:async()=>client},{year:2025});
  assert.equal(result.results[0].apply_status,'compliant');
  assert.equal(writes.some(sql=>/UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(sql)),false);
});

test('manual year-end deduction also blocks unverified opening usage',async(t)=>{
  t.mock.method(console,'error',()=>{});
  const writes=[];
  const client={release(){},query:async sql=>{
    writes.push(sql);
    return {rows:sql.includes('FROM users')?[{id:ID}]:sql.includes('FROM leave_opening_balance_setups')
      ?[{user_id:ID,cutoff_date:'2025-10-31',qualifying_leave_days:null}]:[]};
  }};
  const controller=require('../src/modules/leave/controllers/administration.controller')({
    pool:{connect:async()=>client},yearEndManilaYearNow:()=>2026,
    upsertLeaveBalanceDeduction:async()=>{throw Error('Must not deduct');},
  });
  const response={status(code){this.code=code;return this;},json(body){this.body=body;}};
  await controller.deductForcedLeave({user:actor,body:{user_id:ID,days_to_deduct:5,year:2025}},response);
  assert.equal(response.code,409);assert.match(response.body.error,/historical.*usage/i);
  assert.equal(writes.some(sql=>/UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(sql)),false);
});
