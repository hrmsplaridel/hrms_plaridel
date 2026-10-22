'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const {listInbox}=require('../src/services/sharedWorkflowInbox');
const id=n=>`11111111-1111-4111-8111-${String(n).padStart(12,'0')}`;
for(const kind of ['leave','locator']) for(const stage of [0,1,2,3,4]) {
 test(`${kind} stage ${stage}: notification details and recipients match the saved workflow inbox`,async()=>{
  const owner=id(1),request=id(2);
  const steps=[
   {label:'Department Review',assignee_source:'submitter_department_reviewers',user_ids:[]},
   {label:'Custom Finance Review',assignee_source:'specific_users',user_ids:[id(12),id(13),owner]},
   {label:'Final HR Review',assignee_source:'final_hr_reviewers',user_ids:[]},
   {label:'Mayor Approval',assignee_source:'active_mayor',user_ids:[]},
  ].map((s,i)=>({...s,step_order:i+1,allowed_actions:['approve','return','reject']}));
  const groups=[[id(10),id(11)],[id(12),id(13)],[id(14),id(15)],[id(16)]];
  const snapshot={id:id(3),name:'Custom route',version:7,current_step:stage,steps,
   decisions:Array.from({length:Math.min(stage,4)},(_,i)=>({step:i,action:'approve',actor_id:groups[i][0]}))};
  const status=stage===4?'approved':stage===3?'pending_mayor':'pending_hr';
  const row={id:request,employee_id:owner,user_id:owner,status,workflow_snapshot:snapshot,
   signature_revision:3,employee_name:'Workflow Applicant',created_at:'2026-10-17',
   start_date:'2026-10-20',end_date:'2026-10-21',slip_date:'2026-10-20',slip_date_text:'2026-10-20',
   start_date_text:'2026-10-20',end_date_text:'2026-10-21',leave_type_name:'Special Leave',
   request_type:'custom_visit',request_type_label_snapshot:'Official Visit',am_in:true,pm_out:true};
  const sent=[];
  const db={query:async(sql,params=[])=>{
   if(sql.startsWith('SELECT workflow_snapshot'))return{rows:[{workflow_snapshot:snapshot}]};
   if(sql.includes(`FROM ${kind==='leave'?'leave_requests':'locator_slips'} r`))return{rows:[row]};
   if(sql.includes('FROM users WHERE id=ANY'))return{rows:params[0].filter(v=>v!==owner).map(id=>({id,name:id,role:'employee'}))};
   if(sql.includes('FROM primary_reviewer_designations'))return{rows:[{id:id(14),role:'hr'}]};
   if(sql.includes('FROM leave_final_reviewer_backups'))return{rows:[{id:id(15),role:'hr'}]};
   return{rows:[]};
  }};
  const restores=[withMockedModule('../src/services/notificationService',{
   insertNotificationForUsers:async(_,ids,payload)=>sent.push({ids,...payload}),insertNotification:async()=>{},
  }),withMockedModule('../src/services/docutrackerWorkflowService',{
   resolveStepAssignees:async(_,opts)=>opts.stepConfig.assignee_source==='submitter_department_reviewers'?groups[0]:opts.stepConfig.user_ids,
  }),withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:id(16),name:'Mayor'})})];
  const modules=[`../src/services/${kind}Notifications`,'../src/services/workflowReviewNotifications'];
  clearModule(modules[0]);
  try{
   await require(modules[0]).notifyAfterSubmit(db,{
    slipId:request,leaveRequestId:request,status:stage===3?'pending_mayor':'pending_hr',employeeUserId:owner,
   });
   if(stage===4){assert.equal(sent.length,0,'A delayed task must not send a new approval alert for a completed request');return;}
   assert.equal(sent.length,1);
   assert.deepEqual(sent[0].ids,groups[stage]);
   assert.match(sent[0].body,/Workflow Applicant/);
   assert.match(sent[0].body,kind==='leave'?/Special Leave/:/Official Visit/);
   assert.match(sent[0].body,/2026-10-20/);
   assert.ok(sent[0].body.includes(steps[stage].label));
   assert.equal(sent[0].referenceId,request);
   assert.equal(sent[0].metadata.workflow_approval,true);
   assert.equal(sent[0].metadata.workflow_step,stage);
   assert.equal(sent[0].metadata.workflow_version,7);
   assert.equal(sent[0].metadata.signature_revision,3);
   for(const reviewer of [...groups.flat(),id(30),owner]){
    const inbox=await listInbox(db,{id:reviewer});
    assert.equal(inbox.some(entry=>entry.id===request),groups[stage].includes(reviewer),`Queue recipient ${reviewer}`);
   }
  }finally{for(const path of modules){try{clearModule(path);}catch{}}restores.reverse().forEach(restore=>restore());}
 });
}
