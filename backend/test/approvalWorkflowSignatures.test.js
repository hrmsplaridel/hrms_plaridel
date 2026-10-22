'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getLeaveSourceSignatures}=require('../src/services/docutrackerLeaveSignatureService');
test('HR certification ink remains available after the Mayor signs the final step',async()=>{
  const id='11111111-1111-4111-8111-111111111111';
  const snapshot={steps:['hr','mayor'],current_step:2,decisions:[{step:0,actor_id:'hr',action:'approve',
    signature:{signature_asset_id:'hr-asset',signed_by:'hr',signer_name_snapshot:'HR Officer',signed_at:'2026-10-15',revision:1}}]};
  const db={query:async(sql)=>{
    if(sql.includes('FROM leave_requests lr'))return {rows:[{id,status:'approved',employee_user_id:'employee',signature_revision:1,
      final_review_route:'mayor_direct',workflow_snapshot:snapshot}]};
    if(sql.includes('FROM docutracker_leave_signatures'))return {rows:[{slot_key:'hr_approver',signed_by:'mayor',signature_asset_id:'mayor-asset',signature_image_base64:'mayor-ink'}]};
    if(sql.includes('FROM docutracker_signature_assets'))return {rows:[{mime_type:'image/png',signature_image_base64:'hr-ink'}]};
    throw Error('Unexpected query '+sql);
  }};
  const result=await getLeaveSourceSignatures(db,{id:'employee',role:'employee'},'dtr','leave_requests',id);
  assert.equal(result.signatures.find(s=>s.slot_key==='certification_officer')?.signed_by,'hr');
  assert.equal(result.signatures.find(s=>s.slot_key==='hr_approver')?.signed_by,'mayor');
});
