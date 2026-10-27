'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const create=require('../src/modules/leave/services/paperSignatories');
const id=n=>`77777777-7777-4777-8777-${String(n).padStart(12,'0')}`;
const official=n=>({user_id:id(n),full_name:`Official ${n}`,position_title:`Position ${n}`,department_id:id(20)});
function setup(steps=null,extra={}) {
 const calls=[];
 const db={query:async(sql,params)=>{
  calls.push({sql,params});assert.match(sql.trim(),/^SELECT/i,'Suggestions must be read-only');
  if(sql.includes('ANY($1::uuid[])'))return {rows:params[0].map(value=>({id:value,name:'Specific '+value.slice(-1)}))};
  if(sql.includes('FROM users'))return {rows:[{id:id(1),employment_type:'permanent'}]};
  if(sql.includes('FROM approval_workflows'))return {rows:[{id:id(30),name:'Paper route',steps,is_active:true}]};
  return {rows:[]};
 }};
 const config={primary:{id:id(4),name:'HR Primary',position_title:'HR Director'},backups:[{id:id(5),name:'HR Backup'}]};
 const deps={
  getLeaveTypeDefinition:async()=>({name:'sickLeave',admin_can_file:true,allow_approved_paper_filing:true,...(steps?{approval_workflow_id:id(30)}:{})}),
  findAssignmentProfileByUserIdAtDate:async(db,user,date)=>{calls.push({profile:user,date});return official(Number(user.slice(-12)));},
  resolveDepartmentReviewers:async(db,args)=>{calls.push({department:args});return {primary:{reviewerId:id(2)},reviewers:[{reviewerId:id(2),reviewerName:'Head',reviewerRole:'primary',position_title:'Department Head'},{reviewerId:id(3),reviewerName:'Head Backup',reviewerRole:'backup'}]};},
  resolveFinalLeaveReviewerConfiguration:async(db,date)=>{calls.push({hrDate:date});return config;},
  resolveActiveMayor:async(db,date)=>{calls.push({mayorDate:date});return {employee_id:id(6),name:'Original Mayor',position_title:'Mayor'};},
  resolveOfficialSignatory:async(db,role,date)=>{calls.push({certifier:role,date});return {employee_id:id(7),name:'Credit Certifier',position_title:'Credit Officer'};},
  todayInHrmsTimezone:()=> '2026-10-26',...extra,
 };
 return {db,calls,service:create(deps)};
}
const input={employeeId:id(1),leaveType:'sickLeave',filingDate:'2026-09-01',approvalDate:'2026-09-02'};
const step=(source,other={})=>({label:source,assignee_source:source,...other});
test('paper suggestions use dated department, primary and backup HR reviewers and the separate certifier',async()=>{
 const {db,service,calls}=setup();const result=await service.suggestPaperSignatories(db,input);
 assert.deepEqual(result.final_approver.map(p=>p.user_id),[id(4),id(5)]);
 assert.deepEqual(result.department_reviewer.map(p=>p.user_id),[id(2),id(3)]);
 assert.equal(result.final_approver[1].reviewer_role,'backup');
 assert.equal(result.final_approver[1].position_title,'Position 5');
 assert.equal(result.certification_officer[0].user_id,id(7));
 assert.ok(calls.some(c=>c.profile===id(1)&&c.date==='2026-09-01'));
 assert.ok(calls.some(c=>c.department?.effectiveDate==='2026-09-02'));
 assert.ok(calls.some(c=>c.hrDate==='2026-09-02'));
});
test('each workflow source resolves the final paper signer without preparing digital approvals',async()=>{
 for(const [steps,expected] of [
  [[step('submitter_department_reviewers')],[id(2),id(3)]],
  [[step('department_reviewers',{department_id:id(21)})],[id(2),id(3)]],
  [[step('specific_users',{user_ids:[id(8),id(9),id(1)]})],[id(8),id(9)]],
  [[step('final_hr_reviewers')],[id(4),id(5)]],
  [[step('submitter_department_reviewers'),step('active_mayor')],[id(6)]],
  [[step('submitter_department_reviewers'),step('manual_mayor')],[id(6)]],
  [['department','hr'],[id(4),id(5)]],
 ]){
  const {db,service}=setup(steps);const result=await service.suggestPaperSignatories(db,input);
  assert.deepEqual(result.final_approver.map(p=>p.user_id),expected,JSON.stringify(steps));
  for(const group of ['final_approver','department_reviewer','certification_officer'])assert.ok(result[group].every(p=>p.user_id!==id(1)));
 }
});
test('manual Mayor legacy routing respects employment applicability',async()=>{
 for(const [types,expected] of [[null,id(6)],[['job_order'],id(4)]]){
  const {db,service}=setup(null,{getLeaveTypeDefinition:async()=>({approval_route:'mayor',mayor_employment_types:types,admin_can_file:true,allow_approved_paper_filing:true})});
  assert.equal((await service.suggestPaperSignatories(db,input)).final_approver[0].user_id,expected);
 }
});
test('invalid requests fail before lookup and disabled paper types cannot enumerate reviewers',async()=>{
 const {db,service,calls}=setup();
 for(const data of [{employeeId:'bad'},{filingDate:'2026-02-30'},{approvalDate:'2026-09-00'},{approvalDate:'2026-10-27'},{approvalDate:'2026-08-31'}]){
  await assert.rejects(service.suggestPaperSignatories(db,{...input,...data}),{statusCode:400});
 }
 assert.equal(calls.length,0);
 const disabled=setup(null,{getLeaveTypeDefinition:async()=>({allow_approved_paper_filing:false})});
 await assert.rejects(disabled.service.suggestPaperSignatories(disabled.db,input),{statusCode:403});
});
test('missing configuration gives empty choices so manual paper entry is still available',async()=>{
 const {db,service}=setup(null,{resolveDepartmentReviewers:async()=>({reviewers:[]}),resolveFinalLeaveReviewerConfiguration:async()=>({backups:[]}),resolveActiveMayor:async()=>null,resolveOfficialSignatory:async()=>null});
 const result=await service.suggestPaperSignatories(db,input);
 assert.deepEqual(result.final_approver,[]);assert.deepEqual(result.department_reviewer,[]);assert.deepEqual(result.certification_officer,[]);
});
