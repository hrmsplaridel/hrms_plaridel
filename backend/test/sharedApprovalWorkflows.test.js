'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const engine=require('../src/services/approvalWorkflows');
const {withMockedModule}=require('./helpers/moduleMocks');
const primary='11111111-1111-4111-8111-111111111111';
const backup='22222222-2222-4222-8222-222222222222';
const step=(label,ids=[primary,backup])=>({step_order:1,label,assignee_type:'user',assignee_source:'specific_users',user_ids:ids,requires_signature:true,allowed_actions:['approve','return','reject']});
test('shared workflows accept custom labels, ordered primary/backups and more than three steps',()=>{
 const steps=Array.from({length:4},(_,i)=>({...step(`Review ${i+1}`),step_order:i+1}));
 const workflow=engine.normalizeWorkflow({name:'Shared approval',steps});
 assert.equal(workflow.steps.length,4);assert.deepEqual(workflow.steps[0].user_ids,[primary,backup]);
 assert.throws(()=>engine.normalizeWorkflow({name:'Invalid',steps:[step('Review',[primary,primary])]}),{statusCode:400});
 assert.throws(()=>engine.normalizeWorkflow({name:'Invalid',steps:[step('Review',[])]}),{statusCode:400});
 assert.throws(()=>engine.normalizeWorkflow({name:'Invalid',steps:[{...step('Review'),allowed_actions:['forward']}]}),{statusCode:400});
});
test('custom steps only complete after the final decision and enforce configured actions',()=>{
 const snapshot={steps:[step('Initial'),{...step('Final'),step_order:2,allowed_actions:['approve','reject']}],current_step:0,decisions:[]};
 assert.equal(engine.workflowStatus(snapshot),'pending_hr');
 const next=engine.nextWorkflowStep(snapshot,{id:primary},'approve');
 assert.equal(engine.workflowStatus(next),'pending_hr');
 assert.throws(()=>engine.nextWorkflowStep(next,{id:backup},'return'),{statusCode:403});
 assert.equal(engine.workflowStatus(engine.nextWorkflowStep(next,{id:backup},'approve')),'approved');
});
test('Leave and Locator resolve primary/backups through the DocuTracker resolver and exclude earlier actors',async()=>{
 const calls=[];
 const restore=withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async(db,options)=>{calls.push(options);return [primary,backup];}});
 const db={query:async()=>({rows:[{id:primary,name:'Primary',role:'employee'},{id:backup,name:'Backup',role:'employee'}]})};
 try{for(const kind of ['leave','locator']) {
  const reviewers=await engine.resolveWorkflowReviewers(db,kind,{employee_id:'applicant',workflow_snapshot:{steps:[step('Initial'),step('Final')],current_step:1,decisions:[{step:0,actor_id:primary,action:'approve'}]}});
  assert.deepEqual(reviewers.map(r=>r.id),[backup]);
 }assert.equal(calls.length,2);assert.equal(calls[0].submitterUserId,'applicant');}
 finally{restore();}
});
test('an employee assigned as primary or backup can open and sign a shared Leave request',async()=>{
 const {clearModule}=require('./helpers/moduleMocks');
 const row={id:primary,employee_user_id:'applicant',status:'pending_hr',signature_revision:1,
  workflow_snapshot:{steps:[step('Custom reviewer')],current_step:0,decisions:[]}};
 const db={query:async(sql)=>({rows:sql.includes('FROM leave_requests lr')?[row]:sql.startsWith('SELECT workflow_snapshot')?[{workflow_snapshot:row.workflow_snapshot}]:sql.includes('FROM users WHERE id=ANY')?[{id:primary},{id:backup}]:[]})};
 const restore=withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async()=>[primary,backup]});
 clearModule('../src/services/docutrackerLeaveSignatureService');
 try {
  const service=require('../src/services/docutrackerLeaveSignatureService');
  const bundle=await service.getLeaveSourceSignatures(db,{id:backup,role:'employee'},'dtr','leave_requests',primary);
  assert.equal(bundle.signatures.find(s=>s.slot_key==='hr_approver').can_sign,true);
  await assert.rejects(service.getLeaveSourceSignatures(db,{id:'outsider',role:'employee'},'dtr','leave_requests',primary),{code:'FORBIDDEN'});
 }finally{clearModule('../src/services/docutrackerLeaveSignatureService');restore();}
});
test('a stale decision cannot act on a newly resubmitted approval cycle',async()=>{
 const snapshot={steps:[step('Review')],current_step:0,decisions:[]};
 const db={query:async(sql)=>({rows:sql.startsWith('SELECT workflow_snapshot')?[{workflow_snapshot:snapshot}]:
  [{id:primary,employee_id:'applicant',status:'pending_hr',signature_revision:3,workflow_snapshot:snapshot}]})};
 await assert.rejects(engine.workflowDecision(db,'leave',primary,backup,'return',{step:0,revision:2}),{statusCode:409});
});
test('shared printed signatures preserve each step and the acting backup name',async()=>{
 const row={status:'approved',employee_id:'applicant',signature_revision:2,workflow_snapshot:{steps:[step('Initial'),step('Final')],current_step:2,decisions:[
  {step:0,actor_id:backup,action:'approve',reviewer:{employee_id:backup,name:'Acting Backup',position_title:'Assistant'},signature:{revision:2,signature_asset_id:'ink-one',signer_name_snapshot:'Acting Backup'}},
  {step:1,actor_id:primary,action:'approve',reviewer:{employee_id:primary,name:'Final Reviewer',position_title:'Administrator'},signature:{revision:2,signature_asset_id:'ink-two',signer_name_snapshot:'Final Reviewer'}},
 ]}};
 const db={query:async()=>({rows:[{id:'ink-one',owner_user_id:backup,signature_image_base64:'backup-ink'},{id:'ink-two',owner_user_id:primary,signature_image_base64:'final-ink'}]})};
 const officials=await engine.printOfficials(db,'leave',row);
 assert.equal(officials.department_head.name,'Acting Backup');assert.equal(officials.hr_approver.name,'Final Reviewer');
 const signatures=await engine.decisionSignatures(db,row);
 assert.deepEqual(signatures.map(s=>s.slot_key),['workflow_step_1','workflow_step_2']);
 assert.equal(signatures[0].signature_image_base64,'backup-ink');
 row.status='returned';assert.deepEqual(await engine.decisionSignatures(db,row),[]);
 row.status='approved';
 row.signature_revision=3;assert.deepEqual(await engine.decisionSignatures(db,row),[]);
});
test('shared manual Mayor workflows print the system reviewer and leave the Mayor ink blank',async()=>{
 const restore=withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:'mayor',name:'Municipal Mayor',position_title:'Mayor'})});
 const row={status:'approved',workflow_snapshot:{steps:[step('Office approval'),{step_order:2,label:'Mayor signing',assignee_source:'manual_mayor'}],current_step:2,
   decisions:[{step:0,actor_id:primary,action:'approve',reviewer:{employee_id:primary,name:'Office Reviewer'}}]}};
 try {
  const officials=await engine.printOfficials({},'leave',row);
  assert.equal(officials.department_head.id,primary);assert.equal(officials.hr_approver.id,'mayor');
 }finally{restore();}
});
