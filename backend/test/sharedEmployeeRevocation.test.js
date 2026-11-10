'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const engine=require('../src/services/approvalWorkflows');
const snapshot={current_step:2,steps:[
  {label:'First',assignee_source:'specific_users',user_ids:['first']},
  {label:'Final',assignee_source:'specific_users',user_ids:['final','backup']},
],decisions:[{step:0,actor_id:'first',action:'approve'},{step:1,actor_id:'final',action:'approve'}]};
const row={id:'request',employee_id:'applicant',status:'approved',workflow_snapshot:snapshot};

test('employee Leave revocation restores deducted credits once and records the actor',async()=>{
 let used=3;
 const audit=[],ledger=[];
 const target={...row,user_id:'applicant',days:1,leave_type_name:'Sick Leave',approved_days_with_pay:1,
  start_date:'2026-11-02',end_date:'2026-11-02',approved_at:new Date().toISOString()};
 const client={async query(sql){
  if(sql.includes('FROM leave_requests lr'))return {rows:[target]};
  if(sql.startsWith('UPDATE leave_requests'))target.status='returned';
  if(sql.includes('UPDATE leave_balances'))used--;
  return {rows:[]};
 },release(){}};
 const restore=withMockedModule('../src/services/approvalWorkflows',{...engine,resolveWorkflowReviewers:async()=>[{id:'final'}]});
 try {
  const controller=require('../src/modules/leave/controllers/revoke.controller')({
   pool:{connect:async()=>client,query:async()=>({rows:[target]})},
   LEAVE_REVOKE_WINDOW_DAYS:3,LEAVE_REVOKE_WINDOW_MS:3*86400000,
   approvedPaidDaysForRevoke:()=>1,resolveBalanceLedgerLeaveType:async()=>'sickLeave',
   fetchBalanceSnapshot:async()=>({used_days:used}),
   insertLeaveBalanceLedger:async(db,event)=>ledger.push(event),
   insertLeaveRequestHistory:async(db,event)=>audit.push(event),
   removeApprovedLeaveCoverage:async()=>1,toIsoDateStr:x=>x,
   mapLeaveRowToApi:r=>r,notifySafe:()=>{},broadcastDtrLeaveRefresh:()=>{},broadcastLeaveUpdated:()=>{},
  });
  const request={params:{id:'request'},user:{id:'final',role:'employee'},body:{reason:'Recorded against the wrong date.'}};
  const response=()=>({code:200,status(code){this.code=code;return this;},json(body){this.body=body;}});
  const first=response();await controller.revokeLeave(request,first);
  assert.equal(first.code,200);assert.equal(used,2);
  assert.equal(ledger[0].daysChanged,-1);assert.equal(ledger[0].actorUserId,'final');
  assert.equal(audit[0].actedBy,'final');
  const again=response();await controller.revokeLeave(request,again);
  assert.equal(again.code,403);assert.equal(used,2);assert.equal(ledger.length,1);
 }finally{restore();}
});

for(const kind of ['leave','locator']) {
 test(`${kind}: approved revocation always resolves the final electronic step`,async()=>{
  const restore=withMockedModule('../src/services/approvalWorkflows',{...engine,resolveWorkflowReviewers:async(db,module,target)=>{
   assert.equal(target.workflow_snapshot.current_step,snapshot.steps.length);
   return [{id:'final'}];
  }});
  try {
   const access=require('../src/services/leaveRevocationAccess');
   const check=kind==='leave'?access.canRevokeSharedLeave:access.canRevokeSharedLocator;
   assert.equal(await check({}, {...row,workflow_snapshot:{...snapshot,current_step:0}},{id:'final',role:'employee'}),true);
  }finally{restore();}
 });
 for(const scenario of ['valid','first','owner','expired','permission-changed','already-revoked']) {
  test(`${kind}: locked revoke transaction preserves authority and deadline: ${scenario}`,async()=>{
   const calls=[],audit=[];
   let coverage=0, rebuilt=0, released=false;
   const actor=scenario==='first'?'first':scenario==='owner'?'applicant':'final';
   const target={...row,status:scenario==='already-revoked'?'returned':'approved',
    user_id:'applicant',days:1,leave_type_name:'Wellness Leave',approved_days_with_pay:1,
    start_date:'2026-11-02',end_date:'2026-11-02',slip_date:'2026-11-02',
    approved_at:new Date(Date.now()-(scenario==='expired'?4:0)*86400000).toISOString(),
    hr_reviewed_at:new Date(Date.now()-(scenario==='expired'?4:0)*86400000).toISOString()};
   const client={async query(sql){calls.push(sql);return {rows:sql.includes('FROM leave_requests lr')||sql.includes('FROM locator_slips')?[target]:[],rowCount:0};},release(){released=true;}};
   const restores=[withMockedModule('../src/services/approvalWorkflows',{...engine,
    resolveWorkflowReviewers:async()=>scenario==='permission-changed'?[]:[{id:'final'}],
   })];
   try {
    const deps={pool:{connect:async()=>client,query:async()=>({rows:[target]})},
     LEAVE_REVOKE_WINDOW_DAYS:3,LEAVE_REVOKE_WINDOW_MS:3*86400000,
     approvedPaidDaysForRevoke:()=>1,resolveBalanceLedgerLeaveType:async()=>null,
     removeApprovedLeaveCoverage:async()=>{coverage++;return 1;},
     rebuildCoverageAttendance:async(scope)=>{assert.ok(calls.includes('COMMIT'));assert.equal(released,true);
       assert.equal(scope.employeeId,'applicant');rebuilt++;},
     insertLeaveRequestHistory:async(db,event)=>audit.push(event),
     recordLocatorWorkflowEvent:async(db,event)=>audit.push(event),
     evaluateLocatorRevocation:require('../src/services/locatorRevocationPolicy').evaluateLocatorRevocation,
     fetchLocatorSlipDetails:async()=>({...target,status:'revoked'}),
     mapLeaveRowToApi:r=>r,toIsoDateStr:x=>x,notifySafe:()=>{},
     broadcastDtrLeaveRefresh:()=>{},broadcastLeaveUpdated:()=>{},broadcastLocatorUpdated:()=>{},
    };
    const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
    const controller=require(`../src/modules/${kind}/controllers/revoke.controller`)(deps);
    await controller[kind==='leave'?'revokeLeave':'revokeRequest']({params:{id:'request'},user:{id:actor,role:'employee'},body:{reason:'Recorded against the wrong date.'}},res);
    if(scenario==='valid') {
     assert.equal(res.code,200);
     assert.equal(audit.length,1);
     assert.equal(audit[0].actedBy||audit[0].actorId,'final');
     assert.equal(coverage,kind==='leave'?1:0);
     assert.ok(calls.includes('COMMIT'));
     assert.equal(rebuilt,kind==='leave'?1:0);
    } else {
     assert.equal(res.code,scenario==='expired'?(kind==='leave'?400:409):403);
     assert.equal(audit.length,0);
     assert.equal(coverage,0);
     assert.equal(rebuilt,0);
     assert.equal(calls.some(sql=>/^(UPDATE|DELETE|INSERT)/.test(sql)),false);
     assert.ok(calls.includes('ROLLBACK'));
    }
   }finally{restores.reverse().forEach(r=>r());}
  });
 }
 test(`${kind}: employee revoke capability is limited to final-step reviewers`,async()=>{
  const restores=[withMockedModule('../src/services/approvalWorkflows',{...engine,
   resolveWorkflowReviewers:async()=>[{id:'final'},{id:'backup'}],
  })];
  try {
   const access=require('../src/services/leaveRevocationAccess');
   const canRevoke=kind==='leave'?access.canRevokeSharedLeave:access.canRevokeSharedLocator;
   for(const [id,allowed] of [['final',true],['backup',true],['first',false],['applicant',false],['stranger',false]]) {
    assert.equal(await canRevoke({},row,{id,role:'employee'}),allowed,id);
   }
   assert.equal(await canRevoke({}, {...row,status:'returned'}, {id:'final',role:'employee'}),false);
   assert.equal(await canRevoke({}, {...row,paper_approval_record:{}}, {id:'final',role:'employee'}),false);
  } finally {restores.reverse().forEach(r=>r());}
 });

 for(const [actor,allowed] of [['final',true],['first',false],['stranger',false],['applicant',false]]) {
  test(`${kind}: revoke route guard employee=${actor}`,async()=>{
   const restores=[
    withMockedModule('../src/config/db',{pool:{query:async()=>({rows:[row]})}}),
    withMockedModule('../src/services/approvalWorkflows',{...engine,resolveWorkflowReviewers:async()=>[{id:'final'}]}),
   ];
   const path=`../src/services/${kind}Routing`; clearModule(path);
   try {
    const guard=require(path)[kind==='leave'?'requireLeaveFinalRole':'requireLocatorFinalRole'];
    let next=false;
    const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
    await guard({method:'PATCH',route:{path:'/:id/revoke'},params:{id:'request'},user:{id:actor,role:'employee'}},res,()=>{next=true;});
    assert.equal(next,allowed);
    assert.equal(res.code,allowed?200:403);
   } finally {clearModule(path);restores.reverse().forEach(r=>r());}
  });
 }
 test(`${kind}: shared inbox includes employee final-step revoke capability`,async()=>{
  const restores=[withMockedModule('../src/services/approvalWorkflows',{...engine,resolveWorkflowReviewers:async()=>[{id:'final'}]})];
  clearModule('../src/services/sharedWorkflowInbox');
  try {
   const db={query:async sql=>({rows:sql.includes(`FROM ${kind==='leave'?'leave_requests':'locator_slips'} r`)?[{...row,created_at:'2026-10-31T01:00:00Z'}]:[]})};
   const result=await require('../src/services/sharedWorkflowInbox').listInbox(db,{id:'final',role:'employee'},{includeHistory:true});
   assert.equal(result[0].request_data.can_revoke_approval,true);
  } finally {clearModule('../src/services/sharedWorkflowInbox');restores.reverse().forEach(r=>r());}
 });
}
