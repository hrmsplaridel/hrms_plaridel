'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
const engine = require('../src/services/approvalWorkflows');
const {workflowPrimaryApplicant, selfFilingOfficial} = require('../src/services/workflowPrintPolicy');
const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const applicant = id(1), reviewer = id(2), backup = id(3), mayor = id(4), department = id(5);
const person = (id, name) => ({id, employee_id:id, name, position_title:'Official'});

test('fixed-department steps check their selected department rather than the applicant department', async()=>{
  const seen=[];
  const resolvers={resolveDepartmentReviewers:async(db,options)=>{
    seen.push(options.departmentId);
    return {primary:{reviewerId:options.departmentId===department?reviewer:applicant}};
  }};
  const row={employee_id:applicant,department_id:department,slip_date_text:'2026-11-02'};
  assert.equal(await workflowPrimaryApplicant({},row,{assignee_source:'department_reviewers',department_id:id(99)},resolvers),true);
  assert.equal(await workflowPrimaryApplicant({},row,{assignee_source:'submitter_department_reviewers'},resolvers),false);
  assert.deepEqual(seen,[id(99),department]);
});

test('a backup is not a specific step primary and Mayor steps do not trigger replacement', async()=>{
  const row={employee_id:applicant};
  assert.equal(await workflowPrimaryApplicant({},row,{assignee_source:'specific_users',user_ids:[reviewer,applicant]}),false);
  for(const source of ['active_mayor','manual_mayor']) {
    assert.equal(await workflowPrimaryApplicant({},row,{assignee_source:source}),false);
  }
});

test('actual reviewer replacement follows the printed step in a mixed workflow', async()=>{
  const result=await selfFilingOfficial({}, {employee_id:applicant,workflow_snapshot:{
    self_filing_signatory_policy:'actual_reviewer',
    steps:[{assignee_source:'specific_users'},{assignee_source:'department_reviewers'}],
    decisions:[{step:0,action:'approve',actor_id:reviewer,reviewer:person(reviewer,'Records Reviewer')},
      {step:1,action:'approve',actor_id:backup,reviewer:person(backup,'Other Office')}],
  }},'department',null,0);
  assert.equal(result.name,'Records Reviewer');
});

for (const policy of ['mayor', 'blank', 'actual_reviewer']) {
  for (const ownsStep of [false, true]) {
    for (const approved of [false, true]) {
      test(`Locator specific step: ${policy}, applicant primary=${ownsStep}, approved=${approved}`, async () => {
        const actor = ownsStep ? backup : reviewer;
        const row = {
          id:id(10), employee_id:applicant, employee_name:'Applicant', department_id:department,
          slip_date_text:'2026-11-02', status:approved?'approved':'pending_hr', signature_revision:1,
          hr_reviewer_id:approved?actor:null, final_review_route:'hr',
          // Simulate both old bad snapshots and a fresh request before snapshotting.
          ...(approved ? {print_signatories:{applicant:person(applicant,'Applicant'), hr_approver:person(mayor,'Wrong Mayor')}} : {}),
          workflow_snapshot:{
            self_filing_signatory_policy:policy, current_step:approved?1:0,
            steps:[{label:'First Step',assignee_source:'specific_users',user_ids:[ownsStep?applicant:reviewer,backup]}],
            decisions:approved?[{step:0,action:'approve',actor_id:actor,reviewer:person(actor,'Actual Reviewer'),
              signature:{revision:1,signature_asset_id:id(20)}}]:[],
          },
        };
        const calls = [];
        let stored;
        const db = {async query(sql, params) {
          calls.push(sql);
          if(sql.includes('FROM locator_slips ls'))return {rows:[row]};
          if(sql.includes('FROM docutracker_locator_signatures'))return {rows:[]};
          if(sql.includes('FROM docutracker_signature_assets'))return {rows:[{id:id(20),owner_user_id:actor,signature_image_base64:'confirmed-ink'}]};
          if(sql.includes('SELECT id,full_name AS name,role FROM users'))return {rows:[{id:actor,name:'Actual Reviewer',role:'employee'}]};
          if(sql.includes('SELECT u.id AS employee_id'))return {rows:[person(actor,'Actual Reviewer')]};
          if(sql.includes('FROM assignments a JOIN positions p'))return {rows:[{position_title:'Employee'}]};
          if(sql.includes('SET print_signatories')){stored=JSON.parse(params[1]);return {rows:[]};}
          throw Error('Unexpected query '+sql);
        }};
        const restores = [
          withMockedModule('../src/services/departmentReviewerService',{
            resolveDepartmentReviewers:async()=>({primary:{reviewerId:applicant}}),
            replaceRequestReviewerSnapshot:async()=>{},
          }),
          withMockedModule('../src/services/leaveFinalReviewerService',{
            resolveFinalLeaveReviewerConfiguration:async()=>({primary:person(applicant,'Global HR')}),
          }),
          withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>person(mayor,'Mayor')}),
          withMockedModule('../src/services/sharedWorkflowInbox',{canRead:async()=>true}),
          withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async()=>[actor]}),
        ];
        const path='../src/services/locatorSignatureService'; clearModule(path);
        try {
          const service=require(path);
          const result=await service.getLocatorSourceSignatures(db,{id:applicant,role:'admin'},'dtr','locator_slips',row.id);
          const official=result.print_signatories.hr_approver;
          const expected=ownsStep ? policy==='mayor'?mayor:policy==='actual_reviewer'&&approved?backup:null : reviewer;
          assert.equal(official.name,expected===mayor?'Mayor':expected?'Actual Reviewer':'');
          assert.equal(official.signature_image_base64,approved&&(!ownsStep||policy==='actual_reviewer')?'confirmed-ink':null);
          assert.equal(result.print_signatories.department_head.name,'','One specific step has no department block');
          assert.equal(calls.some(sql=>/^(UPDATE|INSERT|DELETE)/.test(sql)),false,'Preview must not rewrite historical records');
          if(!approved){
            await service.snapshotLocatorReviewers(db,{requestId:row.id,requestType:'locator',departmentId:department,reviewers:[]});
            assert.equal(stored.hr_approver.id??stored.hr_approver.employee_id??null,expected);
          }
        } finally {clearModule(path);restores.reverse().forEach(restore=>restore());}
      });
    }
  }
}

for (const ownsStep of [false,true]) {
  test(`Leave recommendation uses the specific step primary, applicant primary=${ownsStep}`, async()=>{
    const row={id:id(10),employee_id:applicant,status:'approved',submitted_on:'2026-10-31',
      review_department_id:department,assigned_department_head_id:reviewer,
      workflow_snapshot:{self_filing_signatory_policy:'mayor',current_step:2,
        steps:[{label:'Records',assignee_source:'specific_users',user_ids:[ownsStep?applicant:reviewer,backup]},
          {label:'Final HR',assignee_source:'final_hr_reviewers'}],decisions:[]}};
    const restores=[withMockedModule('../src/services/sharedWorkflowInbox',{pendingReadAccess:async()=>true,canRead:async()=>true})];
    try {
      const controller=require('../src/modules/leave/controllers/signatories.controller')({
        pool:{query:async()=>({rows:[row]})},
        ...require('../src/modules/leave/services/signatories')({}),
        resolveDepartmentReviewers:async()=>({primary:{reviewerId:applicant}}),
        resolveFinalLeaveReviewerConfiguration:async()=>({primary:person(backup,'Certifier')}),
        resolveActiveMayor:async()=>person(mayor,'Mayor'),
        findAssignmentProfileByUserIdAtDate:async()=>person(reviewer,'Reviewer'),
        todayInHrmsTimezone:()=> '2026-10-31',
        workflowEngine:{...engine,printOfficials:async()=>({department_head:person(ownsStep?backup:reviewer,'Actual Reviewer'),hr_approver:person(backup,'Final HR')})},
      });
      const res={status(code){this.code=code;return this;},json(body){this.body=body;}};
      await controller.getSignatories({user:{id:applicant,role:'admin'},query:{employee_id:applicant,leave_request_id:row.id}},res);
      assert.equal(res.body.recommendation_officer.user_id,ownsStep?mayor:reviewer);
      assert.equal(res.body.hr_certification_officer.user_id,backup,'Credit certifier remains a separate configured official');
    }finally{restores.reverse().forEach(restore=>restore());}
  });
}
