'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {listInbox}=require('../src/services/sharedWorkflowInbox');
const engine=require('../src/services/approvalWorkflows');
const {evaluateLocatorRevocation}=require('../src/services/locatorRevocationPolicy');

for(const sources of [
 ['submitter_department_reviewers'], ['final_hr_reviewers'], ['active_mayor'],
 ['submitter_department_reviewers','final_hr_reviewers','active_mayor'],
]) {
 test(`approved Locator queue preserves revocation time for ${sources.join(' -> ')}`,async()=>{
  const approvedAt=new Date('2026-10-22T13:19:05.668Z');
  const row={id:'locator',employee_id:'applicant',employee_name:'Applicant',status:'approved',
   created_at:'2026-10-22T13:15:00Z',hr_reviewed_at:approvedAt,
   workflow_snapshot:{name:'Route',version:1,current_step:sources.length,outcome:'approved',
    steps:sources.map(assignee_source=>({assignee_source,label:assignee_source,allowed_actions:['approve']})),
    decisions:[{step:sources.length-1,actor_id:'reviewer',action:'approve'}]}};
  const db={query:async sql=>({rows:sql.includes('FROM locator_slips')?[row]:[]})};
  const [entry]=await listInbox(db,{id:'reviewer'},{includeHistory:true});
  assert.equal(entry.can_review,false);
  const request=JSON.parse(JSON.stringify(entry.request_data));
  assert.equal(request.hr_reviewed_at,approvedAt.toISOString());
  const policyInput={status:request.status,approvedAt:request.hr_reviewed_at,reason:'The requested date was incorrect.'};
  assert.equal(evaluateLocatorRevocation({...policyInput,now:approvedAt}).ok,true);
  assert.equal(evaluateLocatorRevocation({...policyInput,now:new Date(approvedAt.getTime()+3*86400000)}).ok,true);
  assert.equal(evaluateLocatorRevocation({...policyInput,now:new Date(approvedAt.getTime()+3*86400000+1)}).code,'locator_revoke_window_expired');
 });
}
test('assigned queue includes module list fields without exposing storage paths or other modules',async()=>{
 const original=engine.resolveWorkflowReviewers;
 engine.resolveWorkflowReviewers=async()=>[{id:'backup'}];
 const snapshot={name:'Custom',version:1,current_step:0,steps:[{label:'Supervisor',allowed_actions:['approve']}],decisions:[]};
 const db={query:async sql=>({rows:sql.includes('FROM leave_requests')?[{
  id:'leave',employee_id:'applicant',employee_name:'Applicant',status:'pending_hr',
  start_date:'2026-10-20',end_date:'2026-10-21',number_of_days:'2',leave_type_name:'vacationLeave',
  employee_official_snapshot:{office_department:'HR'},workflow_snapshot:snapshot,
  attachment_path:'private/server/file',created_at:'2026-10-16',
 }]:[]})};
 try {
  const [entry]=await listInbox(db,{id:'backup'});
  assert.equal(entry.request_data.user_id,'applicant');
  assert.equal(entry.request_data.leave_type,'vacationLeave');
  assert.equal(entry.request_data.working_days_applied,2);
  assert.equal(entry.request_data.office_department,'HR');
  assert.equal(entry.request_data.attachment_path,undefined);
 }finally{engine.resolveWorkflowReviewers=original;}
});

for(const kind of ['leave','locator']) for(const status of ['pending_hr','approved','returned','rejected_by_hr']) {
 test(`reviewed ${kind} remains read-only in history after ${status}`,async()=>{
  const original=engine.resolveWorkflowReviewers;
  engine.resolveWorkflowReviewers=async()=>[{id:'next-reviewer'}];
  const snapshot={name:'Custom',version:1,current_step:status==='approved'?2:1,
   steps:[{label:'Department Review',allowed_actions:['approve']},{label:'HR Review',allowed_actions:['approve']}],
   decisions:[{step:0,action:'approve',actor_id:'previous-reviewer',signature:{signer_name_snapshot:'Previous Reviewer'}}],
   ...(status==='pending_hr'?{}:{outcome:status})};
  const db={query:async(sql)=>({rows:sql.includes(`FROM ${kind==='leave'?'leave_requests':'locator_slips'}`)&&sql.includes('jsonb_array_elements')?[{
   id:'reviewed',employee_id:'applicant',employee_name:'Applicant',status,
   workflow_snapshot:snapshot,created_at:'2026-10-16',
  }]:[]})};
  try{
   assert.equal((await listInbox(db,{id:'previous-reviewer'})).length,0);
   const rows=await listInbox(db,{id:'previous-reviewer'},{includeHistory:true});
   assert.equal(rows.length,1);
   assert.equal(rows[0].can_review,false);
   assert.deepEqual(rows[0].allowed_actions,[]);
   assert.equal(rows[0].request_data.status,status);
   assert.equal((await listInbox(db,{id:'unrelated'},{includeHistory:true})).length,0);
  }finally{engine.resolveWorkflowReviewers=original;}
 });
}

test('assigned leave details include safe filing fields and official snapshots for the shared details view',async()=>{
 const original=engine.resolveWorkflowReviewers;
 engine.resolveWorkflowReviewers=async()=>[{id:'reviewer'}];
 const snapshot={name:'Department to Mayor',version:1,current_step:0,steps:[{label:'Department Review',allowed_actions:['approve']}],decisions:[]};
 const schema=[{key:'destination',label:'Destination',type:'text',required:false}];
 const db={query:async sql=>({rows:sql.includes('FROM leave_requests')?[{
  id:'leave',employee_id:'applicant',employee_name:'Applicant',status:'pending_hr',
  start_date:'2026-10-20',end_date:'2026-10-21',number_of_days:'2',leave_type_name:'others',
  employee_official_snapshot:{employee_name:'Applicant',office_department:'Accounting',position_title:'Accountant',salary:25000,date_filed:'2026-10-16'},
  details:{custom_leave_type_text:'Earl leave',destination:'Cebu',salary:999999,attachment_path:'secret',unrecognized:'hidden'},
  employee_detail_schema_snapshot:schema,workflow_snapshot:snapshot,attachment_path:'private/file',created_at:'2026-10-16',
 }]:[]})};
 try{
  const [entry]=await listInbox(db,{id:'reviewer'});
  assert.equal(entry.request_data.position_title,'Accountant');
  assert.equal(entry.request_data.salary,25000);
  assert.equal(entry.request_data.date_filed,'2026-10-16');
  assert.equal(entry.request_data.custom_leave_type_text,'Earl leave');
  assert.deepEqual(entry.request_data.custom_details,{destination:'Cebu'});
  assert.equal(entry.request_data.employee_detail_schema_snapshot[0].label,'Destination');
  assert.equal(entry.request_data.attachment_path,undefined);
  assert.equal(entry.request_data.unrecognized,undefined);
  assert.equal(entry.additional_details.salary,undefined);
  assert.equal(entry.additional_details.attachment_path,undefined);
 }finally{engine.resolveWorkflowReviewers=original;}
});

test('Locator queue supplies saved type labels and custom fields to the existing details panel',async()=>{
 const original=engine.resolveWorkflowReviewers;
 engine.resolveWorkflowReviewers=async()=>[{id:'reviewer'}];
 const schema=[{key:'purpose',label:'Visit purpose',type:'text'}];
 const row={id:'locator',employee_id:'applicant',employee_name:'Applicant',status:'pending_hr',
  workflow_snapshot:{name:'Route',version:1,current_step:0,steps:[{label:'Department Review',allowed_actions:['approve']}],decisions:[]},
  slip_date:new Date('2026-10-19T16:00:00Z'),slip_date_text:'2026-10-20',request_type:'custom',request_type_label_snapshot:'Official visit',
  request_type_location_label_snapshot:'Visit destination',employee_detail_schema_snapshot:schema,
  additional_details:{purpose:'Inspection'},attachment_path:'private/file',created_at:'2026-10-17'};
 try{
  const [entry]=await listInbox({query:async sql=>({rows:sql.includes('FROM locator_slips')?[row]:[]})},{id:'reviewer'});
  assert.equal(entry.request_data.request_type_location_label,'Visit destination');
  assert.equal(entry.request_data.slip_date,'2026-10-20');
  assert.deepEqual(entry.request_data.employee_detail_schema_snapshot,schema);
  assert.deepEqual(entry.request_data.additional_details,{purpose:'Inspection'});
  assert.equal(entry.request_data.attachment_path,undefined);
 }finally{engine.resolveWorkflowReviewers=original;}
});
