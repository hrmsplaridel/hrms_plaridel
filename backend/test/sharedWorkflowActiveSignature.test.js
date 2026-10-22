'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const engine=require('../src/services/approvalWorkflows');
const id=n=>`11111111-1111-4111-8111-${String(n).padStart(12,'0')}`;

test('signature selection preserves finalized, legacy, and current-stage ink',()=>{
 const signature={signed_by:id(2),signature_asset_id:id(20)};
 assert.equal(engine.currentStepSignature({status:'pending_hr'},signature),signature);
 const workflow_snapshot={steps:[{label:'Review'}],current_step:1,
  decisions:[{step:0,action:'approve',actor_id:id(2)}]};
 assert.equal(engine.currentStepSignature({status:'approved',workflow_snapshot},signature),signature);
 assert.equal(engine.currentStepSignature({status:'pending_hr',workflow_snapshot:{...workflow_snapshot,current_step:0}},signature),signature);
});

for(const kind of ['leave','locator']) {
 for(const stage of [1,2]) {
  for(const currentSigned of [false,true]) {
   test(`${kind}: step ${stage+1} shows only its active signature, current signed=${currentSigned}`,async()=>{
    const reviewer={id:id(stage+2),role:stage===2?'mayor':'hr'};
    const previousActor=id(stage+1);
    const previousAsset=id(20+stage);
    const steps=['Department Review','HR Review','Mayor Approval'].map(label=>({label,assignee_source:'specific_users',allowed_actions:['approve']}));
    const row={id:id(10),employee_user_id:id(1),employee_id:id(1),employee_name:'Applicant',viewer_name:'Current Reviewer',
     status:stage===2?'pending_mayor':'pending_hr',signature_revision:1,final_review_route:'hr',
     print_signatories:{applicant:{id:id(1),name:'Applicant',position_title:''},department_head:{id:id(2),name:'Department Reviewer',position_title:''},hr_approver:{id:id(4),name:'Mayor',position_title:''}},
     workflow_snapshot:{steps,current_step:stage,decisions:[{step:stage-1,actor_id:previousActor,action:'approve',
      signature:{signature_asset_id:previousAsset,signed_by:previousActor,signer_name_snapshot:'Previous Reviewer',signed_at:'2026-10-16',revision:1}}]}};
    const stored={id:id(30),slot_key:'hr_approver',assigned_signer_id:currentSigned?reviewer.id:previousActor,
     signed_by:currentSigned?reviewer.id:previousActor,signature_asset_id:currentSigned?id(40):previousAsset,
     signer_name_snapshot:currentSigned?'Current Reviewer':'Previous Reviewer',signed_at:'2026-10-16',revision:1,signature_image_base64:'ink'};
    const db={query:async sql=>{
     if(sql.includes('FROM leave_requests lr')||sql.includes('FROM locator_slips ls'))return {rows:[row]};
     if(sql.includes('FROM docutracker_leave_signatures')||sql.includes('FROM docutracker_locator_signatures'))return {rows:[stored]};
     if(sql.includes('FROM docutracker_signature_assets'))return {rows:[{id:previousAsset,owner_user_id:previousActor,mime_type:'image/png',signature_image_base64:'previous-ink'}]};
     throw Error('Unexpected query '+sql);
    }};
    const restores=[
     withMockedModule('../src/services/leaveFinalReviewerService',{
      resolveEligibleFinalReviewers:async()=>[reviewer],
      resolveFinalLeaveReviewerConfiguration:async()=>({primary:null}),
     }),
     withMockedModule('../src/services/sharedWorkflowInbox',{canRead:async()=>true}),
     withMockedModule('../src/services/approvalWorkflows',{...engine,printOfficials:async()=>row.print_signatories}),
    ];
    const module=kind==='leave'?'../src/services/docutrackerLeaveSignatureService':'../src/services/locatorSignatureService';
    clearModule(module);
    try{
     const service=require(module);
     const result=await (kind==='leave'?service.getLeaveSourceSignatures:service.getLocatorSourceSignatures)(db,reviewer,'dtr',kind==='leave'?'leave_requests':'locator_slips',row.id);
     const active=result.signatures.find(s=>s.slot_key==='hr_approver');
     assert.equal(active.signed_by||null,currentSigned?reviewer.id:null);
     assert.equal(active.signature_image_base64||null,currentSigned?'ink':null);
     assert.equal(active.assigned_signer_id,reviewer.id);
     assert.equal(active.can_sign,true);
     const previous=result.signatures.find(s=>s.slot_key===`workflow_step_${stage}`);
     assert.equal(previous.signed_by,previousActor);
     assert.equal(previous.signature_image_base64,'previous-ink');
     assert.equal(previous.can_sign,false);
    }finally{clearModule(module);restores.reverse().forEach(restore=>restore());}
   });
  }
 }
}
