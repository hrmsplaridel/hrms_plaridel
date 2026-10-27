'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const create=require('../src/modules/leave/use-cases/staffFiling');
const id=n=>`77777777-7777-4777-8777-${String(n).padStart(12,'0')}`;
const actor={id:id(1),role:'hr'};
const paper=()=>({original_filing_date:'2026-09-01',approval_date:'2026-09-02',
 final_approver:{name:'Original Mayor',position_title:'Municipal Mayor'},
 confirmed_complete:true,confirmed_not_recorded:true});
function harness(){const calls=[];const db={query:async(sql,params)=>{calls.push(sql);return {rows:sql.includes('docutracker_signature_assets')?[]:[{id:params[0],full_name:'Employee',employment_type:'permanent'}]};}};
 return {db,calls,service:create({todayInHrmsTimezone:()=> '2026-10-26',assertFinalLeaveReviewer:async()=>{throw Error('Paper encoder must not be treated as an approver');},workflowEngine:{prepareWorkflow:async()=>{throw Error('Do not reroute completed paper approval');}}})};}
const input=()=>({actor,employeeId:id(2),rule:{admin_can_file:true,allow_approved_paper_filing:true},paperApproval:paper(),hasAttachment:true,start:'2026-09-10',end:'2026-09-11'});
test('paper recording requires authority, another employee, configured permission and the approved document',async()=>{
 const {db,service}=harness();
 for(const change of [{actor:{...actor,role:'employee'}},{employeeId:actor.id},{hasAttachment:false},
  {rule:{admin_can_file:true}},{rule:{admin_can_file:false,allow_approved_paper_filing:true}}]) {
  await assert.rejects(service.prepareStaffLeave(db,{...input(),...change}),e=>[400,403].includes(e.statusCode));
 }
});
test('every paper route including Mayor and custom records approval without resolving digital reviewers',async()=>{
 for(const route of ['hr','mayor','custom']){
  const {db,service,calls}=harness();const result=await service.prepareStaffLeave(db,{...input(),rule:{...input().rule,approval_route:route,approval_workflow_id:id(30)}});
  assert.equal(result.paperRecord.source,'approved_paper');assert.equal(result.paperRecord.approval_date,'2026-09-02');
  assert.equal(result.paperRecord.encoded_by,actor.id);assert.equal(result.autoApprove,undefined);
  assert.equal(calls.some(sql=>sql.includes('approval_workflows')),false);
 }
});
test('paper approval metadata must be complete, dated correctly and explicitly confirmed',async()=>{
 const {db,service}=harness();
 for(const data of [null,{}, {...paper(),approval_date:'2026-02-30'}, {...paper(),approval_date:'2026-10-27'},
  {...paper(),original_filing_date:'2026-09-03'}, {...paper(),final_approver:{name:'',position_title:'Mayor'}},
  {...paper(),confirmed_complete:false},{...paper(),confirmed_not_recorded:false}]) {
  await assert.rejects(service.prepareStaffLeave(db,{...input(),paperApproval:data}),{statusCode:400});
 }
});

test('paper applicant identity comes from the selected employee, never the submitted applicant or encoder',async()=>{
 const {db,service,calls}=harness();
 const result=await service.prepareStaffLeave(db,{...input(),paperApproval:{...paper(),applicant:{user_id:actor.id,name:'Forged',signature:{signature_image_base64:'forged'}}}});
 assert.equal(result.paperRecord.applicant?.user_id,id(2));
 assert.equal(result.paperRecord.applicant?.name,'Employee');
 assert.equal(result.paperRecord.applicant?.signature,null);
 assert.equal(calls.filter(sql=>sql.includes('docutracker_signature_assets')).length,1);
});
