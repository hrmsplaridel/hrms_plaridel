const test = require('node:test');
const assert = require('node:assert/strict');
const {listDocuments, mapSourceStatusToDocuTracker, sourceActionForRow} = require('../src/services/docutrackerWorkflowService');
const owner = '11111111-1111-4111-8111-111111111111';
const reviewer = '22222222-2222-4222-8222-222222222222';
const id = '33333333-3333-4333-8333-333333333333';

test('Locator is listed once as a source-backed document and participates in status/search filters', async () => {
  const row = {id, employee_id:owner, employee_name:'Ana Employee', status:'approved',
    slip_date_text:'2026-11-04', request_type:'locator', request_type_label_snapshot:'Official Business',
    reason:'Municipal transaction', office:'Municipal Hall', created_at:'2026-11-04T00:00:00Z', updated_at:'2026-11-04T01:00:00Z'};
  const db = {query: async sql => ({rows: sql.includes('FROM locator_slips') ? [row] : [], rowCount:sql.includes('FROM locator_slips') ? 1 : 0})};
  const user = {id:reviewer,role:'admin'};
  const result = await listDocuments(db,user,{type:'dtr',q:'Municipal',status:'approved'});
  assert.equal(result.documents.length,1);
  const document = result.documents[0];
  assert.equal(document.source_table,'locator_slips');
  assert.equal(document.source_record_id,id);
  assert.equal(document.source_only,true);
  assert.equal(document.status,'approved');
  assert.equal(document.created_by,owner);
  assert.equal(document.source_action,null);
  assert.equal((await listDocuments(db,user,{type:'dtr',status:'rejected'})).documents.length,0);
  assert.equal((await listDocuments(db,user,{type:'memo'})).documents.length,0);
});

test('Locator lifecycle is mapped without changing Leave status semantics', () => {
  for (const [raw, mapped] of Object.entries({pending_mayor:'in_review',pending_hr:'in_review',
    pending_department_head:'in_review',returned_for_correction:'returned',revoked:'cancelled',
    rejected_by_hr:'rejected',rejected_by_department_head:'rejected',approved:'approved',cancelled:'cancelled'})) {
    assert.equal(mapSourceStatusToDocuTracker('dtr',raw,'locator_slips'),mapped,raw);
  }
  assert.equal(mapSourceStatusToDocuTracker('dtr','approved','leave_requests'),'approved');
});

test('DocuTracker DTR permission and Locator ownership both limit employee source listings', async () => {
  let grant=true,locatorQueries=0;
  const own={id,employee_id:owner,employee_name:'Ana',status:'approved',slip_date_text:'2026-11-04',created_at:'2026-11-04T00:00:00Z'};
  const db={query:async(sql)=>{
    if(sql.includes('FROM docutracker_permissions'))return {rows:grant?[{user_id:owner,document_type:'dtr',granted:true}]:[]};
    if(sql.includes('FROM locator_slips')){locatorQueries++;return {rows:[own,{...own,id:'unrelated',employee_id:reviewer}]};}
    return {rows:[],rowCount:0};
  }};
  const user={id:owner,role:'employee'};
  assert.deepEqual((await listDocuments(db,user,{type:'dtr'})).documents.map(d=>d.source_record_id),[id]);
  const before=locatorQueries;grant=false;
  assert.equal((await listDocuments(db,user,{type:'dtr'})).documents.length,0);
  assert.equal(locatorQueries,before);
});

test('Locator required actions belong only to its current reviewer or returned-request owner', () => {
  const row={source_module:'dtr',source_table:'locator_slips',source_owner_id:owner,source_status:'pending_hr',viewer_can_review:true};
  assert.equal(sourceActionForRow(row,{id:reviewer,role:'employee'}).action,'review_locator_in_dtr');
  assert.equal(sourceActionForRow({...row,viewer_can_review:false},{id:reviewer,role:'hr'}),null);
  assert.equal(sourceActionForRow({...row,source_status:'approved'},{id:reviewer,role:'admin'}),null);
  assert.equal(sourceActionForRow({...row,source_status:'returned_for_correction',viewer_can_review:false},{id:owner,role:'employee'}).action,'update_locator_in_dtr');
});

const {locatorSourceAccess,getLocatorSourceWorkflow} = require('../src/services/docutrackerLocatorSourceWorkflowService');
const snapshot={name:'Specific people',version:2,current_step:0,steps:[{step_order:1,label:'Custom reviewer',assignee_source:'specific_users',user_ids:[reviewer]}],decisions:[]};
const noMayor={mayorRead:async()=>false};

test('Locator source access keeps ownership, current assignments and completed history separate', async () => {
  const row={id,employee_id:owner,status:'pending_hr',workflow_snapshot:snapshot};
  const db={query:async()=>({rows:[]})};
  assert.deepEqual(await locatorSourceAccess(db,row,{id:owner,role:'employee'},
    {...noMayor,sharedRead:async()=>false}),{read:true,review:false});
  assert.deepEqual(await locatorSourceAccess(db,row,{id:reviewer,role:'employee'},
    {...noMayor,sharedRead:async()=>true,reviewers:async()=>[{id:reviewer}]}),{read:true,review:true});
  assert.deepEqual(await locatorSourceAccess(db,row,{id:'outsider',role:'admin'},
    {...noMayor,sharedRead:async()=>false}),{read:false,review:false});
  assert.deepEqual(await locatorSourceAccess(db,{...row,status:'approved'},{id:reviewer,role:'employee'},
    {...noMayor,sharedRead:async()=>true}),{read:true,review:false});
  assert.deepEqual(await locatorSourceAccess(db,{...row,workflow_snapshot:null},{id:'outsider',role:'employee'},noMayor),{read:false,review:false});
  assert.deepEqual(await locatorSourceAccess(db,{...row,workflow_snapshot:null,status:'approved',hr_reviewer_id:reviewer},
    {id:reviewer,role:'mayor'},noMayor),{read:false,review:false});
});

test('Locator workflow and audit trail use the saved steps and actual deciding reviewer', async () => {
  const row={id,employee_id:owner,status:'approved',employee_name:'Ana',workflow_snapshot:{...snapshot,current_step:1,
    decisions:[{step:0,actor_id:reviewer,action:'approve',signature:{signer_name_snapshot:'Actual Backup'}}]}};
  const db={query:async()=>({rows:[row],rowCount:1})};
  const history=[{id:'event',action:'hr_approved',title:'Custom reviewer · Approved',actor_id:reviewer,actor_name:'Ben',from_status:'pending_hr',to_status:'approved',created_at:'2026-11-04T00:00:00Z'}];
  const result=await getLocatorSourceWorkflow(db,{id:reviewer,role:'employee'},id,
    {...noMayor,sharedRead:async()=>true,history:async()=>history});
  assert.equal(result.steps.length,1);
  assert.equal(result.steps[0].label,'Custom reviewer');
  assert.equal(result.steps[0].reviewers[0].name,'Actual Backup');
  assert.equal(result.steps[0].indicator.kind,'approved');
  assert.equal(result.history[0].action,'Custom reviewer · Approved');
  assert.equal(result.current_step,null);
  assert.equal(result.request_data.employee_name,'Ana');
  assert.equal('attachment_bytes' in result.request_data,false);
  assert.equal(await getLocatorSourceWorkflow(db,{id:'stranger',role:'employee'},id,
    {...noMayor,sharedRead:async()=>false}),null);
});

test('paper Locator and manual-Mayor workflows retain their distinct approval evidence', async () => {
  const db={query:async()=>({rows:[{id,employee_id:owner,status:'approved',paper_approval_record:{final_approver:{name:'Paper Mayor'}},workflow_snapshot:snapshot}]})};
  const paper=await getLocatorSourceWorkflow(db,{id:owner,role:'employee'},id,{...noMayor,sharedRead:async()=>true,history:async()=>[]});
  assert.equal(paper.steps[0].label,'Original paper approval');
  assert.equal(paper.steps[0].reviewers[0].name,'Paper Mayor');
  const manualDb={query:async()=>({rows:[{id,employee_id:owner,status:'approved',workflow_snapshot:{...snapshot,current_step:2,steps:[...snapshot.steps,{label:'Mayor on paper',assignee_source:'manual_mayor'}]}}]})};
  const manual=await getLocatorSourceWorkflow(manualDb,{id:owner,role:'employee'},id,{...noMayor,sharedRead:async()=>true,history:async()=>[]});
  assert.equal(manual.steps[1].indicator.kind,'unrecorded');
  assert.equal(manual.steps[1].indicator.label,'MANUAL SIGNING');
});

test('Locator workflow endpoint validates identifiers and hides inaccessible requests', async () => {
  const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
  let calls=0;
  const restoreDb=withMockedModule('../src/config/db',{pool:{query:async()=>({rows:[]})}});
  const restoreService=withMockedModule('../src/services/docutrackerLocatorSourceWorkflowService',{
    getLocatorSourceWorkflow:async(_db,user)=>{calls++;return user.id===owner?{steps:[],history:[]}:null;},
  });
  clearModule('../src/routes/docutracker');
  try {
    const router=require('../src/routes/docutracker');
    const layer=router.stack.find(l=>l.route?.path==='/sources/dtr/locator_slips/:sourceRecordId/workflow');
    assert.ok(layer);
    const run=async(sourceRecordId,user)=>{
      const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
      await layer.route.stack.at(-1).handle({params:{sourceRecordId},user},res);return res;
    };
    assert.equal((await run('invalid',{id:owner})).code,404);
    assert.equal(calls,0);
    assert.equal((await run(id,{id:'outsider'})).code,404);
    assert.deepEqual((await run(id,{id:owner})).body,{steps:[],history:[]});
  } finally {clearModule('../src/routes/docutracker');restoreService();restoreDb();}
});
