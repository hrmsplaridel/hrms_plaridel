const test=require('node:test');const assert=require('node:assert/strict');
const {chooseLeaveRoute,normalizeRouting}=require('../src/services/leaveRouting');
const {assertFinalLeaveReviewer,resolveEligibleFinalReviewers}=require('../src/services/leaveFinalReviewerService');
test('routing is independent of print layout and applies by employment type',()=>{
 const rule={approval_route:'mayor',mayor_employment_types:['job_order','contract_of_service']};
 assert.equal(chooseLeaveRoute(rule,'job_order'),'mayor');
 assert.equal(chooseLeaveRoute(rule,'contract_of_service'),'mayor');
 assert.equal(chooseLeaveRoute(rule,'permanent'),'hr');
 assert.equal(chooseLeaveRoute({print_layout:'wellness'},'job_order'),'hr');
 assert.deepEqual(normalizeRouting({approval_route:'hr'}),{approval_route:'hr',mayor_employment_types:null});
 assert.throws(()=>normalizeRouting({approval_route:'bad'}),/routing/i);
});
function db(){return {query:async(sql)=>{
 const s=String(sql);
 if(s.includes('SELECT final_review_route'))return {rows:[{final_review_route:'mayor',final_reviewer_user_id:'mayor'}]};
 if(s.includes("u.role = 'mayor'"))return {rows:[{id:'mayor',name:'Mayor'}]};
 return {rows:[]};
}};}
test('manual Mayor route has no electronic final reviewer',async()=>{
 const pool=db();assert.deepEqual(await resolveEligibleFinalReviewers(pool,'employee','leave','request'),[]);
 await assert.rejects(assertFinalLeaveReviewer(pool,'employee','mayor','leave','request'),/No final/);
 await assert.rejects(assertFinalLeaveReviewer(pool,'employee','hr','leave','request'),/No final/);
});

test('manual Mayor route does not send a final approval notification',async()=>{
 const {withMockedModule,clearModule}=require('./helpers/moduleMocks');const sent=[];
 const restore=withMockedModule('../src/services/notificationService',{insertNotificationForUsers:async(_,ids,body)=>sent.push({ids,...body})});
 clearModule('../src/services/leaveNotifications');
 try{const service=require('../src/services/leaveNotifications');const pool=db();
 const input={employeeUserId:'employee',leaveRequestId:'request',status:'pending_mayor'};
 await service.notifyAfterSubmit(pool,input);await service.notifyDepartmentHeadApprovedForHr(pool,input);
 assert.deepEqual(sent,[]);
 }finally{restore();clearModule('../src/services/leaveNotifications');}
});
test('manual Mayor signature stays unavailable electronically',async()=>{
 const service=require('../src/services/docutrackerLeaveSignatureService');const base=db();
 const pool={query:async(sql,params)=>{
  if(String(sql).includes('FROM leave_requests lr')&&!String(sql).includes('department_approver_id'))return {rows:[{id:'request',status:'pending_mayor',employee_user_id:'employee',final_review_route:'mayor',final_reviewer_user_id:'mayor'}]};
  if(String(sql).includes('FROM docutracker_leave_signatures'))return {rows:[]};
  return base.query(sql,params);
 }};
 const form=await service.getLeaveSourceSignatures(pool,{id:'mayor',role:'mayor'},'dtr','leave_requests','11111111-1111-4111-8111-111111111111');
 assert.equal(form.signatures.find(s=>s.slot_key==='hr_approver').can_sign,false);
 assert.equal(form.signatures.find(s=>s.slot_key==='hr_approver').label,'Mayor Signature');
 const hr=await service.getLeaveSourceSignatures(pool,{id:'hr',role:'hr'},'dtr','leave_requests','11111111-1111-4111-8111-111111111111');
 assert.equal(hr.signatures.find(s=>s.slot_key==='hr_approver').can_sign,false);
});

test('department approval completes only the manual Mayor route',()=>{
 const {validateDepartmentHeadTransition}=require('../src/services/leaveWorkflowRules');
 assert.deepEqual(validateDepartmentHeadTransition({currentStatus:'pending_department_head',desiredStatus:'pending_hr',finalReviewRoute:'mayor'}),{nextStatus:'approved',historyAction:'department_head_approved'});
 assert.equal(validateDepartmentHeadTransition({currentStatus:'pending_department_head',desiredStatus:'pending_hr',finalReviewRoute:'hr'}).nextStatus,'pending_hr');
 assert.throws(()=>validateDepartmentHeadTransition({currentStatus:'approved',desiredStatus:'pending_hr',finalReviewRoute:'mayor'}));
});

test('Mayor cannot access the electronic final approval API',()=>{
 const {requireLeaveFinalRole}=require('../src/services/leaveRouting');
 const res={status(code){this.code=code;return this;},json(body){this.body=body;}};
 requireLeaveFinalRole({user:{role:'mayor'}},res,()=>assert.fail('Mayor reached final approval'));
 assert.equal(res.code,403);
});
