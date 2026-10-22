'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeWorkflow, workflowStatus, nextWorkflowStep, resolveWorkflowReviewers, prepareWorkflow,
  printOfficials,
} = require('../src/services/approvalWorkflows');

for (const kind of ['leave', 'locator']) {
  for (const source of ['submitter_department_reviewers', 'department_reviewers', 'final_hr_reviewers', 'active_mayor', 'specific_users']) {
    test(`${kind} single ${source} step prints the confirmed reviewer in the matching form block`, async () => {
      const departmentOnly = ['submitter_department_reviewers', 'department_reviewers'].includes(source);
      const row = { employee_id: 'applicant', status: 'approved', workflow_snapshot: {
        steps: [{ assignee_source: source }], current_step: 1,
        decisions: [{ step: 0, action: 'approve', actor_id: 'acting-backup',
          reviewer: { employee_id: 'acting-backup', name: 'Saved Acting Reviewer', position_title: 'Saved Title' } }],
      } };
      const before = structuredClone(row);
      const officials = await printOfficials({ query: async () => { throw Error('Use the saved reviewer snapshot'); } }, kind, row);
      const active = departmentOnly ? officials.department_head : officials.hr_approver;
      const blank = departmentOnly ? officials.hr_approver : officials.department_head;
      assert.equal(active.id, 'acting-backup');
      assert.equal(active.name, 'Saved Acting Reviewer');
      assert.equal(active.position_title, 'Saved Title');
      assert.equal(blank.id, null);
      assert.equal(blank.name, '');
      assert.deepEqual(row, before, 'Printing must not modify the filed workflow');
    });
  }
  test(`${kind} multiple review steps retain separate department and final printed officials`, async () => {
    const row = { workflow_snapshot: { steps: [
      { assignee_source: 'submitter_department_reviewers' },
      { assignee_source: 'final_hr_reviewers' },
      { assignee_source: 'active_mayor' },
    ], decisions: [
      { step: 0, action: 'approve', actor_id: 'head', reviewer: { name: 'Department Reviewer' } },
      { step: 2, action: 'approve', actor_id: 'mayor', reviewer: { name: 'Mayor' } },
    ] } };
    const officials = await printOfficials({}, kind, row);
    assert.equal(officials.department_head.id, 'head');
    assert.equal(officials.hr_approver.id, 'mayor');
  });
}

test('named workflows validate executable ordered steps and manual signing', () => {
  assert.deepEqual(normalizeWorkflow({name:' Full approval ', steps:['department','hr','mayor']}),
    {name:'Full approval', steps:['department','hr','mayor'], is_active:true,self_filing_signatory_policy:'mayor'});
  for (const steps of [[], ['unknown'], ['hr','hr'], ['mayor','hr'], ['hr','department'], ['manual_mayor']]) {
    assert.throws(() => normalizeWorkflow({name:'Invalid',steps}), {statusCode:400});
  }
  assert.doesNotThrow(() => normalizeWorkflow({name:'Paper',steps:['department','manual_mayor']}));
  assert.doesNotThrow(() => normalizeWorkflow({name:'Direct',steps:['mayor']}));
  assert.throws(() => normalizeWorkflow({name:'',steps:['hr']}), {statusCode:400});
});

test('a request advances through its saved workflow, not an edited template', () => {
  const snapshot = {id:'workflow',version:2,name:'Full',steps:['department','hr','mayor'],current_step:0,decisions:[]};
  const first = nextWorkflowStep(snapshot, {id:'head'}, 'approve');
  assert.equal(workflowStatus(first), 'pending_hr');
  assert.equal(snapshot.current_step,0);
  const second = nextWorkflowStep(first,{id:'hr'},'approve');
  assert.equal(workflowStatus(second),'pending_mayor');
  assert.equal(second.version,2);
  assert.throws(() => nextWorkflowStep(second,{id:'head'},'approve'), {statusCode:403});
  assert.equal(workflowStatus(nextWorkflowStep(second,{id:'mayor'},'approve')),'approved');
});

test('return starts a fresh decision cycle while preserving workflow version', () => {
  const returned = nextWorkflowStep({version:1,steps:['department','hr'],current_step:1,
    decisions:[{actor_id:'head',step:0}]},{id:'hr'},'return');
  assert.equal(returned.outcome,'returned');
  assert.equal(returned.current_step,1);
});

test('reviewers exclude applicant and earlier approving actors, including backups', async () => {
  const snapshot={steps:['hr'],current_step:0,decisions:[{actor_id:'head'}]};
  const reviewers=await resolveWorkflowReviewers({},'leave',{employee_id:'employee',workflow_snapshot:snapshot}, {
    final:async()=>({reviewers:[{id:'employee',role:'hr'},{id:'head',role:'hr'},
      {id:'disabled',role:'admin',leave_allowed:false},{id:'backup',role:'hr'}]}),
  });
  assert.deepEqual(reviewers.map(r=>r.id),['backup']);
});

test('manual Mayor signing completes the system decision without a Mayor inbox action', () => {
  const snapshot={steps:['department','manual_mayor'],current_step:0,decisions:[]};
  const next=nextWorkflowStep(snapshot,{id:'head'},'approve');
  assert.equal(workflowStatus(next),'approved');
  assert.equal(next.manual_signing_required,true);
});

test('resubmission uses the original workflow even when the template was edited or deactivated',async()=>{
  const saved={id:'original',name:'Original',version:1,steps:['department'],current_step:0,decisions:[],outcome:'returned'};
  const snapshot=await prepareWorkflow({query:async()=>{throw Error('Must not resolve the edited template');}},'leave',
    {approval_workflow_id:'original',approval_workflow_snapshot:saved},'applicant',
    {departmentHeadUserId:'head',reviewerUserIds:['head']});
  assert.equal(snapshot.version,1);assert.deepEqual(snapshot.steps,['department']);assert.equal(workflowStatus(snapshot),'pending_department_head');
});

for(const kind of ['leave','locator'])test(`${kind} always follows its selected workflow despite legacy employment restrictions`,async()=>{
  const {withMockedModule}=require('./helpers/moduleMocks');
  const restore=withMockedModule('../src/services/leaveFinalReviewerService',{
    resolveFinalLeaveReviewerConfiguration:async()=>({reviewers:[{id:'hr',role:'hr'}]}),
  });
  try{
    for(const employmentType of ['permanent','job_order']){
      const db={query:async(sql)=>{
        if(sql.includes('FROM approval_workflows'))return {rows:[{id:'selected',name:'Department only',version:1,
          is_active:true,steps:['department'],employment_types:['job_order']}]};
        if(sql.startsWith('SELECT employment_type'))return {rows:[{employment_type:employmentType}]};
        throw Error(`Unexpected query: ${sql}`);
      }};
      const snapshot=await prepareWorkflow(db,kind,{approval_workflow_id:'selected'},'applicant',
        {departmentHeadUserId:'head',reviewerUserIds:['head']});
      assert.deepEqual(snapshot.steps,['department']);
      assert.equal(snapshot.version,1);
    }
  }finally{restore();}
});

test('an endorsement cannot leave a later Mayor step assigned to the same approving actor',async()=>{
  const {withMockedModule}=require('./helpers/moduleMocks');
  const {workflowDecision}=require('../src/services/approvalWorkflows');
  const row={id:'request',employee_id:'employee',status:'pending_department_head',workflow_snapshot:{
    steps:['department','hr','mayor'],current_step:0,decisions:[]}};
  const restores=[
    withMockedModule('../src/services/leaveFinalReviewerService',{resolveFinalLeaveReviewerConfiguration:async()=>({reviewers:[{id:'hr',role:'hr'}]})}),
    withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:'mayor'})}),
  ];
  const db={query:async(sql)=>({rows:sql.startsWith('SELECT workflow_snapshot')?[{workflow_snapshot:row.workflow_snapshot}]:
    sql.includes('JOIN users u ON u.id=r.reviewer_id')?[{id:'mayor'},{id:'head-backup'}]:[row]})};
  try{
    await assert.rejects(workflowDecision(db,'leave','request','mayor','approve'),{statusCode:409});
    const decision=await workflowDecision(db,'leave','request','head-backup','approve');
    assert.equal(decision.status,'pending_hr');
  }finally{restores.reverse().forEach(r=>r());}
});

test('starting a prepared review cycle preserves old decisions without replacing the prepared version',async()=>{
  const {initialWorkflow}=require('../src/services/approvalWorkflows');
  const previous={id:'same',version:1,steps:['department','hr'],current_step:1,
    decisions:[{actor_id:'head',action:'approve',signature:{signature_asset_id:'ink'}}],outcome:'returned'};
  const prepared={id:'same',version:2,steps:['hr'],current_step:0,decisions:[]};
  let written;
  const db={query:async(sql,params)=>{
    if(sql.startsWith('SELECT'))return {rows:[{workflow_snapshot:previous}]};
    written=JSON.parse(params[1]);return {rows:[]};
  }};
  await initialWorkflow(db,'leave','request',prepared);
  assert.equal(written.version,2);assert.deepEqual(written.steps,['hr']);
  assert.equal(written.cycles[0].decisions[0].signature.signature_asset_id,'ink');
});

test('completed workflow retains final HR authority for idempotent decisions and allowed revocation',async()=>{
  const reviewers=await resolveWorkflowReviewers({},'leave',{employee_id:'applicant',workflow_snapshot:{
    steps:['department','hr'],current_step:2,decisions:[{step:0,actor_id:'head',action:'approve'},{step:1,actor_id:'hr',action:'approve'}],
  }},{final:async()=>({reviewers:[{id:'head',role:'hr'},{id:'hr',role:'hr'},{id:'backup',role:'hr'}]})});
  assert.deepEqual(reviewers.map(r=>r.id),['hr','backup']);
});
