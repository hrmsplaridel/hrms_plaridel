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

for (const kind of ['leave', 'locator']) {
  test(`${kind} correction keeps its saved workflow when the type no longer links a workflow`, async () => {
    const saved = { id: 'original', name: 'Original Department Route', version: 2,
      steps: ['department'], current_step: 0, outcome: kind === 'leave' ? 'returned' : 'returned_for_correction',
      self_filing_signatory_policy: 'blank', decisions: [{ step: 0, actor_id: 'head', action: 'return' }] };
    const rule = { approval_workflow_id: null, approval_workflow_snapshot: saved, approval_route: 'mayor' };
    const review = { departmentHeadUserId: 'head', reviewerUserIds: ['head'] };
    const db = { query: async () => { throw Error('Do not fall back to current type routing or HR configuration'); } };
    const snapshot = await prepareWorkflow(db, kind, rule, 'applicant', review);
    assert.ok(snapshot, 'The saved workflow must not be dropped');
    assert.equal(snapshot.id, 'original');
    assert.equal(snapshot.version, 2);
    assert.equal(snapshot.self_filing_signatory_policy, 'blank');
    assert.deepEqual(snapshot.steps, ['department']);
    assert.deepEqual(snapshot.decisions, []);
    assert.equal(workflowStatus(snapshot), 'pending_department_head');
    assert.equal(saved.decisions.length, 1, 'The previous cycle remains unchanged');
    await require('../src/services/leaveFinalReviewerService').assertLeaveSubmissionReviewer(db, 'applicant', kind, rule, review);
  });
}

test('new requests without a selected or saved workflow retain legacy routing', async () => {
  assert.equal(await prepareWorkflow({}, 'leave', { approval_workflow_id: null }, 'applicant'), null);
});

for (const format of ['legacy', 'shared']) for (const route of [
  ['department'], ['hr'], ['mayor'], ['department', 'hr'], ['department', 'mayor'],
  ['department', 'hr', 'mayor'], ['department', 'manual_mayor'], ['hr', 'manual_mayor'],
]) {
  test(`${format} route audit: ${route.join(' -> ')} advances in order and stops on return or rejection`, () => {
    const steps = format === 'shared'
      ? route.map((kind, index) => require('../src/services/approvalWorkflows').legacyStep(kind, index))
      : route;
    const workflow = normalizeWorkflow({ name: 'Audited route', steps });
    let snapshot = { ...workflow, current_step: 0, decisions: [] };
    const manual = route.at(-1) === 'manual_mayor';
    const electronic = route.length - (manual ? 1 : 0);
    for (let index = 0; index < electronic; index++) {
      assert.notEqual(workflowStatus(snapshot), 'approved');
      for (const action of ['return', 'reject']) {
        const ended = nextWorkflowStep(snapshot, { id: `reviewer-${index}` }, action);
        assert.ok(ended.outcome);
        assert.throws(() => nextWorkflowStep(ended, { id: 'other' }, 'approve'), { statusCode: 409 });
      }
      const before = structuredClone(snapshot);
      snapshot = nextWorkflowStep(snapshot, { id: `reviewer-${index}` }, 'approve');
      assert.deepEqual(before.decisions.map(d => d.actor_id), Array.from({ length: index }, (_, i) => `reviewer-${i}`));
      if (index + 1 < electronic) {
        assert.notEqual(workflowStatus(snapshot), 'approved');
        assert.throws(() => nextWorkflowStep(snapshot, { id: `reviewer-${index}` }, 'approve'), { statusCode: 403 });
      }
    }
    assert.equal(workflowStatus(snapshot), 'approved');
    assert.equal(snapshot.decisions.length, electronic);
    assert.equal(snapshot.manual_signing_required === true, manual);
  });
}

test('Leave correction does not apply a new legacy Mayor rule over its saved HR workflow', async () => {
  const { withMockedModule } = require('./helpers/moduleMocks');
  const original = { id: 'request', status: 'returned', leave_type_id: 'type', employee_official_snapshot: {},
    workflow_snapshot: { id: 'original', version: 1, steps: ['hr'], current_step: 0, decisions: [], outcome: 'returned' } };
  const rule = { name: 'vacationLeave', approval_workflow_id: null, approval_route: 'mayor' };
  const calls = []; let prepared;
  const query = async (sql, params = []) => {
    calls.push(sql);
    if (sql.startsWith('SELECT employment_type')) return { rows: [{ employment_type: 'permanent' }] };
    if (sql.includes('SELECT attachment_path')) return { rows: [{ attachment_path: null }] };
    if (sql.startsWith('SELECT full_name')) return { rows: [{ full_name: 'Applicant' }] };
    if (sql.includes('FROM leave_requests')) return { rows: [structuredClone(original)] };
    if (sql.includes('UPDATE leave_requests')) return { rows: [{ ...original, status: params[8], signature_revision: 2 }] };
    return { rows: [] };
  };
  const noop = async () => {};
  const restore = withMockedModule('../src/services/docutrackerLeaveSignatureService', { confirmSubmittedApplicantSignature: noop });
  const oldError = console.error; console.error = () => {};
  try {
    const controller = require('../src/modules/leave/controllers/update.controller')({
      pool: { query, connect: async () => ({ query, release() {} }) },
      validateEmployeeUpdateTransition: () => ({ nextStatus: 'pending', historyAction: 'resubmitted' }),
      toIsoDateStr: value => value || null, invalidProvidedDate: () => false,
      computeNumberOfDaysSync: () => 1, lockEmployeeLeaveFiling: noop,
      ensureLeaveTypeIdByName: async () => 'type', getLeaveTypeDefinition: async () => ({ ...rule }),
      assertLeaveEmploymentEligibility: noop, assertLeaveServiceEligibility: noop, getDepartmentReviewSnapshot: async () => null,
      workflowEngine: {
        prepareWorkflow: async (_, kind, received) => {
          assert.equal(received.approval_workflow_snapshot.id, 'original');
          return { ...received.approval_workflow_snapshot, outcome: undefined, decisions: [] };
        }, workflowStatus,
        initialWorkflow: async (_, kind, id, snapshot) => { prepared = snapshot; },
      },
      assertLeaveSubmissionReviewer: noop, normalizeEmployeeDetailSchema: () => [], employeeLeaveDetailsFromPayload: () => ({}),
      loadEmployeeOfficialSnapshot: async () => ({}), normalizeEmployeeOfficialSnapshot: value => value,
      readMaternityDeliveryType: () => null, readAdoptionParentRole: () => null, readLeaveEventDates: () => ({}),
      computeEmployeeLeaveWorkingDays: async () => ({ days: 1 }), getUserSexForLeaveValidation: async () => null,
      validateEmployeeLeaveRequestWithRule: () => ({ valid: true }), mustBlockMissingAttachment: () => false,
      hasOverlappingLeaveRequest: async () => false, assertAnnualQuotaLeaveLimit: noop,
      serializeEmployeeDetailSchema: () => '[]', replaceRequestReviewerSnapshot: noop, insertLeaveRequestHistory: noop,
      reservePendingLeaveBalance: async () => ({ reservedDays: 0 }), notifySafe: () => {}, mapLeaveRowToApi: value => value,
      broadcastLeaveUpdated: () => {},
    });
    const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
    await controller.updateLeave({ user: { id: 'applicant' }, params: { id: 'request' },
      body: { leave_type: 'vacationLeave', status: 'pending', start_date: '2099-01-05', end_date: '2099-01-05' } }, res);
    assert.equal(res.code, 200, JSON.stringify(res.body));
    assert.equal(res.body.status, 'pending_hr');
    assert.equal(prepared.id, 'original');
    assert.equal(calls.some(sql => sql.startsWith('SELECT employment_type')), false);
  } finally { console.error = oldError; restore(); }
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

test('print bindings can load legacy middle-step ink with revision and asset-owner checks',async()=>{
  const {decisionSignatures}=require('../src/services/approvalWorkflows');
  const db={query:async()=>({rows:[{id:'ink',owner_user_id:'hr',signature_image_base64:'aW5r'}]})};
  const row={status:'approved',signature_revision:2,workflow_snapshot:{steps:['department','hr','mayor'],decisions:[
    {step:1,action:'approve',actor_id:'hr',signature:{signature_asset_id:'ink',revision:2}},
  ]}};
  assert.deepEqual(await decisionSignatures(db,row),[]);
  assert.equal((await decisionSignatures(db,row,{includeLegacy:true}))[0].slot_key,'workflow_step_2');
  assert.deepEqual(await decisionSignatures(db,{...row,status:'revoked'},{includeLegacy:true}),[]);
  assert.deepEqual(await decisionSignatures(db,{...row,signature_revision:3},{includeLegacy:true}),[]);
  assert.deepEqual(await decisionSignatures({query:async()=>({rows:[{id:'ink',owner_user_id:'other'}]})},row,{includeLegacy:true}),[]);
});
