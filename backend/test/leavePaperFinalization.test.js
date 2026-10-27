'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const create=require('../src/modules/leave/use-cases/finalizeApproval');
test('paper finalization records actual paper approval and encoder without fabricating digital approval',async()=>{
 const calls=[];const paper={source:'approved_paper',approval_date:'2026-09-02',original_filing_date:'2026-09-01',encoded_by:'encoder',final_approver:{name:'Paper Mayor',position_title:'Mayor'}};
 const db={query:async(sql,params)=>{calls.push({sql,params});return {rows:[{id:'leave',paper_approval_record:paper,signature_revision:1}]};}};
 const runtime={computeEmployeeLeaveWorkingDays:async()=>({countedDates:['2026-09-10'],days:1}),
  assertCoverageMatchesRequestedDays:()=>({dates:['2026-09-10'],days:1}),getLeaveTypeDefinition:async()=>({}),assertLeaveServiceEligibility:async()=>{},assertRequiredLeaveAttachment:()=>{},
  resolveApprovalAllocation:()=>({requestedDays:1,approvedDaysWithPay:1,approvedDaysWithoutPay:0,usedDaysToDeduct:1}),
  validateAdminTransition:()=>({historyAction:'approved'}),requireHrApprovalSignature:async()=>{throw Error('Paper evidence does not create a digital signature');},
  workflowEngine:{loadRequestWorkflow:async()=>{throw Error('Paper approvals are already complete');},isShared:()=>false},resolveActiveMayor:async()=>{throw Error('Do not substitute today\'s Mayor');},
  toIsoDateStr:s=>s,storedLeaveAttachmentExists:()=>true,hasOverlappingLeaveRequest:async()=>false,assertAnnualQuotaLeaveLimit:async()=>{},
  replaceApprovedLeaveCoverage:async(db,input)=>calls.push({coverage:input}),reservedCreditDaysFromRequest:()=>1,
  upsertLeaveBalanceDeduction:async(...args)=>calls.push({deduction:args}),insertLeaveRequestHistory:async(db,input)=>calls.push({history:input})};
 await create(runtime).finalizeLeaveApproval(db,{id:'leave',user_id:'employee',start_date:'2026-09-10',end_date:'2026-09-10',days:1,status:'pending_hr',leave_type_name:'test'},
  {id:'leave',reviewerId:'encoder',paperRecord:paper});
 const update=calls.find(c=>c.sql);
 assert.equal(update.params[1],null,'Encoder is not approved_by/reviewer_id');
 assert.equal(JSON.parse(update.params[7]).name,'Paper Mayor');
 assert.equal(update.params[8],'2026-09-02T00:00:00+08:00');
 assert.equal(calls.find(c=>c.history).history.action,'paper_approved_recorded');
 assert.equal(calls.find(c=>c.history).history.actedBy,'encoder');
 assert.equal(calls.find(c=>c.coverage).coverage.actorUserId,'encoder');
 assert.equal(calls.filter(c=>c.deduction).length,1);
});

test('digital revocation does not reopen an approved paper record for employee editing',async()=>{
 const controller=require('../src/modules/leave/controllers/revoke.controller')({assertFinalLeaveReviewer:async()=>{},pool:{connect:async()=>({query:async(sql)=>({rows:sql.includes('FROM leave_requests')?[{id:'paper',status:'approved',paper_approval_record:{source:'approved_paper'}}]:[]}),release(){}})}}).revokeLeave;
 const res={status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
 await controller({user:{id:'reviewer'},params:{id:'paper'},body:{}},res);
 assert.equal(res.code,409);assert.match(res.body.error,/paper/i);
});
