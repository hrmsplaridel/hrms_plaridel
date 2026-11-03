const test = require('node:test');
const assert = require('node:assert/strict');
const EMPLOYEE='11111111-1111-4111-8111-111111111111';
const ACTOR='22222222-2222-4222-8222-222222222222';
const input=()=>({userId:EMPLOYEE,actor:{id:ACTOR,role:'hr'},cutoff_date:'2026-10-31',sick_leave_days:25,vacation_leave_days:30,qualifying_leave_days:3,reason:'Verified opening balances from the HR leave card.',confirmed:true});
function harness(options={}) {
 const calls=[],ledger=[];
 const balances=['sickLeave','vacationLeave'].map((leave_type,i)=>({leave_type,earned_days:i?10:5,used_days:0,pending_days:options.pending||0,adjusted_days:0,last_accrual_date:options.lastAccrual||null}));
 const db={async query(sql,params=[]){calls.push({sql,params});
  if(sql.includes('FROM users'))return {rows:[{id:EMPLOYEE,employment_type:options.employment||'permanent',leave_credit_eligible:true,is_active:true,employment_status:'active'}]};
  if(sql.includes('FROM leave_opening_balance_setups'))return {rows:options.existing?[{user_id:EMPLOYEE,cutoff_date:'2026-09-30'}]:[]};
  if(sql.includes('FROM leave_requests'))return {rows:options.requests?[{id:'request'}]:[]};
  if(sql.includes('FROM leave_attendance_deductions')||sql.includes('FROM leave_monthly_accrual_postings'))return {rows:[]};
  if(sql.includes('FROM leave_balances'))return {rows:balances};
  if(sql.includes('UPDATE leave_balances')){
   const row=balances.find(b=>b.leave_type===params[1]);row.adjusted_days=params[2];row.last_accrual_date=params[3];return {rows:[{...row}]};
  }
  if(sql.includes('INSERT INTO leave_balance_ledger')){ledger.push(params);return {rows:[]};}
  if(sql.includes('INSERT INTO leave_opening_balance_setups'))return {rows:[{user_id:EMPLOYEE,cutoff_date:params[1],sick_leave_days:params[2],vacation_leave_days:params[3]}]};
  return {rows:[]};
 },release(){calls.push({sql:'release',params:[]});}};
 return {db,calls,ledger,balances};
}
test('opening balances set final SL/VL totals atomically without adding the full amount twice',async()=>{
 const h=harness();const {applyOpeningBalances}=require('../src/services/leaveOpeningBalances');
 await applyOpeningBalances(h.db,input(),{today:'2026-11-01'});
 assert.equal(h.balances[0].adjusted_days,20);assert.equal(h.balances[1].adjusted_days,20);
 assert.deepEqual(h.balances.map(b=>b.last_accrual_date),['2026-10-01','2026-10-01']);
 assert.equal(h.ledger.length,2);
 assert.ok(h.calls.some(c=>c.sql.includes('pg_advisory_xact_lock(743022, 0)')));
 assert.ok(h.calls.some(c=>c.sql.includes('INSERT INTO leave_opening_balance_setups')));
 const setup=h.calls.find(c=>c.sql.includes('INSERT INTO leave_opening_balance_setups'));
 assert.match(setup.sql,/qualifying_leave_days/);assert.ok(setup.params.includes(3));
});
for(const [name,change,options] of [
 ['duplicate',{}, {existing:true}],['pending reservations',{}, {pending:1}],
 ['pending/approved post-cutoff requests',{}, {requests:true}],['later accrual',{}, {lastAccrual:'2026-11-01'}],
 ['JO account',{}, {employment:'job_order'}],['unconfirmed',{confirmed:false},{}],
 ['negative',{sick_leave_days:-1},{}],['non-number',{vacation_leave_days:'invalid'},{}],
 ['array amount',{sick_leave_days:[25]},{}],['missing amount',{vacation_leave_days:null},{}],
 ['partial month',{cutoff_date:'2026-10-15'},{}],['future month',{cutoff_date:'2026-11-30'},{}],
 ['missing usage',{qualifying_leave_days:null},{}],['invalid usage',{qualifying_leave_days:367},{}],
 ['unauthorized employee',{actor:{id:ACTOR,role:'employee'}},{}],
])test(`opening setup rejects ${name} before updating balances`,async()=>{
 const h=harness(options);const {applyOpeningBalances}=require('../src/services/leaveOpeningBalances');
 await assert.rejects(applyOpeningBalances(h.db,{...input(),...change},{today:'2026-11-01'}),e=>e.statusCode>=400&&e.statusCode<500);
 assert.equal(h.calls.some(c=>c.sql.includes('UPDATE leave_balances')),false);
});
test('opening cutoff rejects a new historical deduction, but permits the next period',async()=>{
 const {assertAfterOpeningBalanceCutoff}=require('../src/services/leaveOpeningBalances');
 const db={query:async()=>({rows:[{user_id:EMPLOYEE,cutoff_date:'2026-10-31'}]})};
 await assert.rejects(assertAfterOpeningBalanceCutoff(db,EMPLOYEE,'2026-10-30'),/opening balance/i);
 await assertAfterOpeningBalanceCutoff(db,EMPLOYEE,'2026-11-01');
});

for(const duplicate of [false,true])test(`opening API commits both balances or rolls back a rejected setup: duplicate=${duplicate}`,async()=>{
 const h=harness({existing:duplicate});let broadcasts=0;
 const controllers=require('../src/modules/leave/controllers/openingBalances.controller')({pool:{connect:async()=>h.db},broadcastLeaveUpdated:()=>broadcasts++});
 const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
 await controllers.saveOpeningBalances({user:input().actor,params:{userId:EMPLOYEE},body:input()},res);
 assert.equal(res.code,duplicate?409:201);
 assert.equal(h.calls.some(c=>c.sql==='COMMIT'),!duplicate);
 assert.equal(h.calls.some(c=>c.sql==='ROLLBACK'),duplicate);
 assert.equal(broadcasts,duplicate?0:1);
 assert.equal(h.calls.at(-1).sql,'release');
});

test('old year-end deductions also respect the opening cutoff',async()=>{
 const calls=[];
 const db={query:async(sql)=>{calls.push(sql);return {rows:sql.includes('FROM leave_opening_balance_setups')?[{user_id:EMPLOYEE,cutoff_date:'2025-12-31'}]:sql.includes('SELECT id FROM users')?[{id:EMPLOYEE}]:[]};},release(){}};
 const controller=require('../src/modules/leave/controllers/administration.controller')({pool:{connect:async()=>db},yearEndManilaYearNow:()=>2026});
 const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
 await controller.deductForcedLeave({user:{id:ACTOR,role:'hr'},body:{user_id:EMPLOYEE,days_to_deduct:5,year:2025}},res);
 assert.equal(res.code,409);assert.match(res.body.error,/opening balance/i);
 assert.equal(calls.some(sql=>/UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(sql)),false);
});

test('year-end scheduler excludes years already covered by opening balances',async()=>{
 const {getYearEndForcedLeaveCompliance}=require('../src/services/leaveYearEndForcedLeave');
 await getYearEndForcedLeaveCompliance({query:async sql=>{
  assert.match(sql,/leave_opening_balance_setups/);assert.match(sql,/cutoff_date\s*>=\s*make_date/);return {rows:[]};
 }},{year:2025});
});

test('opening setup list returns only recording status, without balances or audit details', async () => {
 const controllers = require('../src/modules/leave/controllers/openingBalances.controller')({
  pool: {query: async sql => {
   assert.match(sql, /SELECT user_id,\s*to_char\(cutoff_date/);
   assert.doesNotMatch(sql, /sick_leave_days|vacation_leave_days|reason|created_by/);
   return {rows: [{user_id: EMPLOYEE, cutoff_date: '2026-10-31'}]};
  }},
 });
 const res = {json(body) {this.body = body;}};
 await controllers.listOpeningBalances({}, res);
 assert.deepEqual(res.body, {setups: [{user_id: EMPLOYEE, cutoff_date: '2026-10-31'}]});
});

test('opening setup list reports failure instead of implying employees are unrecorded', async () => {
 const controllers = require('../src/modules/leave/controllers/openingBalances.controller')({
  pool: {query: async () => {throw new Error('database unavailable');}},
 });
 const res = {status(code) {this.code = code; return this;}, json(body) {this.body = body;}};
 await controllers.listOpeningBalances({}, res);
 assert.equal(res.code, 500);
 assert.equal(res.body.error, 'Unable to load opening balance recording status.');
 assert.equal(res.body.setups, undefined);
});
