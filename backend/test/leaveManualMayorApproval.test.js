const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
for (const route of ['mayor', 'hr', 'ineligible']) {
 test(`department approval ${route === 'ineligible' ? 'rejects an unmet service requirement before accounting' : route === 'mayor' ? 'finalizes manual Mayor accounting once' : 'retains the final HR stage'}`, async () => {
  const employee = '11111111-1111-4111-8111-111111111111';
  const actor = '22222222-2222-4222-8222-222222222222';
  const requestId = '33333333-3333-4333-8333-333333333333';
  const row = {id:requestId,user_id:employee,employee_id:employee,final_review_route:route === 'ineligible' ? 'mayor' : route,
   status:'pending_department_head',start_date:'2026-10-12',end_date:'2026-10-12',days:1,
   leave_type_name:'Wellness',reserved_credit_days:1,signature_revision:3};
  let balance = {earned_days:5,used_days:0,pending_days:1,adjusted_days:0};
  const statements=[], coverage=[], notices=[], history=[];
  const query = async (sql,params=[]) => {
   const s=String(sql).replace(/\s+/g,' ').trim();statements.push(s);
   if (s.includes('FOR UPDATE OF lr')) return {rows:[{...row}]};
   if (s.includes('FROM primary_reviewer_designations')) return {rows:[{id:'55555555-5555-4555-8555-555555555555'}]};
   if (s.includes('FROM generate_series')) return {rows:[{attendance_date:'2026-10-12',working_days:[1,2,3,4,5],has_shift:true}]};
   if (s.startsWith('SELECT * FROM leave_types')) return {rows:[{name:'Wellness',requires_attachment:false,credit_policy:'own',balance_ledger_type:'Wellness',affects_dtr_normally:true,minimum_service_months:route==='ineligible'?6:0}]};
   if (s.includes('date_hired') && s.includes('FROM users')) return {rows:[{date_hired:'2026-10-01'}]};
   if (s.startsWith('SELECT balance_ledger_type')) return {rows:[{balance_ledger_type:'Wellness'}]};
   if (s.includes('FROM leave_balances')) return {rows:[{...balance}]};
   if (s.startsWith('INSERT INTO leave_balances')) balance.used_days+=params[2];
   if (s.startsWith('UPDATE leave_balances')) balance.pending_days-=params[2];
   if (s.startsWith('UPDATE leave_requests')) {
    row.status=s.includes("status = 'approved'")?'approved':params[1];
    if (row.status==='approved') {row.approved_by=actor;row.reserved_credit_days=0;}
    return {rows:[{...row}]};
   }
   if (s.startsWith('SELECT lr.*')) return {rows:[{...row}]};
   if (s.startsWith('INSERT INTO leave_request_history')) history.push(params[6]);
   return {rows:[]};
  };
  const realCoverage=require('../src/services/leaveDtrCoverage');
  const restores=[
   withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}}),
   withMockedModule('../src/services/docutrackerLeaveSignatureService',{
    requireDepartmentHeadApprovalSignature:async()=>{},requireHrApprovalSignature:async()=>{throw Error('Must not require HR signature');}}),
   withMockedModule('../src/services/leaveDtrCoverage',{...realCoverage,replaceApprovedLeaveCoverage:async(_,input)=>coverage.push(input)}),
   withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({name:'Local Mayor'})}),
   withMockedModule('../src/services/leaveNotifications',{notifyEmployee:async(_,n)=>notices.push(n),notifyDepartmentHeadApprovedForHr:async()=>notices.push({type:'forwarded_hr'})}),
  ];
  clearModule('../src/routes/leaveRoutes');
  const originalError=console.error;console.error=()=>{};
  try {
   const router=require('../src/routes/leaveRoutes');
   const handle=router.stack.find(s=>s.route?.path==='/:id/department-head-approve').route.stack.at(-1).handle;
   const req={user:{id:actor,role:'employee'},params:{id:requestId},body:{}};
   const res={code:200,status(c){this.code=c;return this;},json(b){this.body=b;}};
   await handle(req,res);
   if (route === 'ineligible') {
    assert.equal(res.code,400);
    assert.match(res.body.error,/eligible on 2027-04-01/);
    assert.equal(row.status,'pending_department_head');
    assert.equal(balance.used_days,0);assert.equal(balance.pending_days,1);
    assert.equal(coverage.length,0);assert.ok(statements.includes('ROLLBACK'));
    return;
   }
   assert.equal(res.code,200,JSON.stringify(res.body));
   assert.equal(row.status,route==='mayor'?'approved':'pending_hr');
   assert.equal(balance.used_days,route==='mayor'?1:0);
   assert.equal(balance.pending_days,route==='mayor'?0:1);
   assert.equal(coverage.length,route==='mayor'?1:0);
   assert.equal(notices.some(n=>n.type==='forwarded_hr'),route==='hr');
   assert.equal(history[0].revision,3,'approval history identifies the confirmed request version');
   if(route==='mayor') {
    assert.equal(row.approved_by,actor);
    assert.equal(coverage[0].actorUserId,actor);
    assert.ok(notices.some(n=>n.type==='leave_approved'));
    await handle(req,res);
    assert.equal(res.code,400);
    assert.equal(balance.used_days,1);
    assert.equal(coverage.length,1);
    assert.ok(statements.includes('ROLLBACK'));
   }
  } finally {console.error=originalError;clearModule('../src/routes/leaveRoutes');restores.reverse().forEach(r=>r());}
 });
}
