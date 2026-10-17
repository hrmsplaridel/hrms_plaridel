'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('DocuTracker resolves current Mayor and HR primary/backups from shared authority sources',async()=>{
 const restores=[withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:'mayor'})}),
  withMockedModule('../src/services/leaveFinalReviewerService',{resolveFinalLeaveReviewerConfiguration:async()=>({reviewers:[{id:'primary'},{id:'backup'}]})})];
 clearModule('../src/services/docutrackerWorkflowService');
 try {
  const {resolveStepAssignees}=require('../src/services/docutrackerWorkflowService');
  assert.deepEqual(await resolveStepAssignees({}, {stepConfig:{assignee_source:'active_mayor'},submitterUserId:'applicant'}),['mayor']);
  assert.deepEqual(await resolveStepAssignees({}, {stepConfig:{assignee_source:'final_hr_reviewers'},submitterUserId:'primary'}),['backup']);
  await assert.rejects(resolveStepAssignees({}, {stepConfig:{assignee_source:'active_mayor'},submitterUserId:'mayor'}),{code:'VALIDATION'});
 }finally{clearModule('../src/services/docutrackerWorkflowService');restores.reverse().forEach(r=>r());}
});
test('shared document workflows support the same current Mayor and configured HR authorities',()=>{
 assert.doesNotThrow(()=>require('../src/services/sharedDocumentWorkflows').validateForDocuments({is_active:true,
  steps:[{assignee_source:'final_hr_reviewers'},{assignee_source:'active_mayor'}]}));
});
test('publishing a shared workflow creates a new pinned DocuTracker version with ordered backups',async()=>{
 const calls=[];
 const db={query:async(sql,params=[])=>{
  calls.push({sql,params});
  if(sql.startsWith('SELECT workflow_id'))return {rows:[{workflow_id:'shared',workflow_version:1}]};
  if(sql.includes('FROM approval_workflow_document_types'))return {rows:[{document_type:'memo',workflow_version:1}]};
  if(sql.startsWith('SELECT id FROM users'))return {rows:params[0].map(id=>({id}))};
  if(sql.includes('MAX(version)'))return {rows:[{next_version:8}]};
  if(sql.includes('INSERT INTO docutracker_workflow_steps'))return {rows:[{id:'step-id'}]};
  return {rows:[]};
 }};
 await require('../src/services/sharedDocumentWorkflows').syncLinkedDocumentWorkflows(db,{id:'shared',version:2,is_active:true,
  steps:[{step_order:1,label:'Custom final approval',assignee_type:'user',assignee_source:'specific_users',user_ids:['primary','backup'],requires_signature:true,allowed_actions:['approve','reject']}]},'admin');
 const version=calls.find(c=>c.sql.includes('INSERT INTO docutracker_routing_config_versions'));
 assert.equal(version.params[1],8);
 assert.equal(JSON.parse(version.params[2])[0].label,'Custom final approval');
 const assignees=calls.filter(c=>c.sql.includes('INSERT INTO docutracker_workflow_step_assignees'));
 assert.equal(assignees[0].params[2],true);assert.equal(assignees[1].params[3],1);
 assert.ok(!calls.some(c=>/UPDATE docutracker_documents|DELETE FROM docutracker_routing_config_versions/.test(c.sql)));
});
test('publishing cannot reclaim a document type concurrently linked to a different workflow',async()=>{
 const calls=[];
 const db={query:async(sql)=>{calls.push(sql);return {rows:sql.startsWith('SELECT workflow_id')?[{workflow_id:'replacement',workflow_version:1}]:
   sql.includes('FROM approval_workflow_document_types')?[{document_type:'memo',workflow_version:1}]:
   sql.includes('MAX(version)')?[{next_version:2}]:sql.includes('INSERT INTO docutracker_workflow_steps')?[{id:'step'}]:[]};}};
 await require('../src/services/sharedDocumentWorkflows').syncLinkedDocumentWorkflows(db,{id:'original',version:2,is_active:true,
  steps:[{step_order:1,label:'Department',assignee_type:'user',assignee_source:'submitter_department_reviewers',allowed_actions:['approve']}]},'admin');
 assert.ok(!calls.some(sql=>sql.includes('INSERT INTO docutracker_routing_config_versions')));
});
for(const route of ['config','assignees'])test(`DocuTracker ${route} cannot independently overwrite a shared published workflow`,async()=>{
 const calls=[];
 const db={query:async(sql)=>{calls.push(sql);return {rows:sql.includes('SELECT workflow_id')?[{workflow_id:'shared'}]:sql.includes('AS shared_version')?[{id:'step',shared_version:true}]:[],rowCount:sql.includes('AS shared_version')?1:0};},release(){}};
 const restore=withMockedModule('../src/config/db',{pool:{...db,connect:async()=>db}});
 clearModule('../src/routes/docutracker');
 try {
  const router=require('../src/routes/docutracker');
  const path=route==='config'?'/routing-configs':'/workflow-steps/:stepId/assignees';
  const handler=router.stack.find(s=>s.route?.path===path && s.route.methods[route==='config'?'post':'put']).route.stack.at(-1).handle;
  const response={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
  await handler({user:{id:'admin',role:'admin'},params:{stepId:'11111111-1111-4111-8111-111111111111'},body:route==='config'?{document_type:'memo',steps:[{step_order:1,label:'Changed',assignee_type:'user',assignee_source:'specific_users',user_ids:['primary'],allowed_actions:['approve']}]}:{assignees:[]}},response);
  assert.equal(response.code,409);assert.ok(!calls.some(s=>/DELETE FROM|INSERT INTO/.test(s)));
 }finally{clearModule('../src/routes/docutracker');restore();}
});
