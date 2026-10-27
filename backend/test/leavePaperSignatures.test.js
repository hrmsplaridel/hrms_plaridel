'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const create=require('../src/modules/leave/services/paperSignatures');
const id=n=>`77777777-7777-4777-8777-${String(n).padStart(12,'0')}`;
const actor={id:id(9),role:'hr'};
const paper={source:'approved_paper',original_filing_date:'2026-09-01',approval_date:'2026-09-02',final_approver:{user_id:id(1),name:'Client label',position_title:'Mayor'},certification_officer:{user_id:id(2),name:'HR',position_title:'HR Director'},department_reviewer:{name:'Former Head',position_title:'Director'}};
const allowed={final_approver:[{user_id:id(1),name:'Original Mayor',position_title:'Municipal Mayor'}],certification_officer:[{user_id:id(2),name:'Primary HR',position_title:'HR Director'}],department_reviewer:[]};
test('selected paper officials copy only their own saved signatures and freeze trusted names',async()=>{
 const queries=[];const service=create({suggestPaperSignatories:async()=>allowed});
 const db={query:async(sql,args)=>{queries.push({sql,args});assert.match(sql,/is_saved\s*=\s*true/);return {rows:args[0]===id(1)?[{id:id(11),owner_user_id:id(1),mime_type:'image/png',signature_image_base64:'c2F2ZWQ='}]:[]};}};
 const saved=await service.snapshotPaperSignatures(db,{actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:paper});
 assert.equal(saved.final_approver.name,'Original Mayor');assert.equal(saved.final_approver.signature.signature_asset_id,id(11));
 assert.equal(saved.final_approver.signature.signature_image_base64,'c2F2ZWQ=');assert.equal(saved.final_approver.signature.applied_by,actor.id);
 assert.equal(saved.certification_officer.signature,null,'Missing saved signatures do not borrow another official’s ink');
 assert.equal(saved.department_reviewer.signature,undefined,'Other signatory remains name-only');
 assert.equal(queries.length,2);assert.equal(paper.final_approver.name,'Client label','Input is not mutated');
});
test('unconfigured selected accounts and mismatched asset owners cannot apply a signature',async()=>{
 const service=create({suggestPaperSignatories:async()=>allowed});
 await assert.rejects(service.snapshotPaperSignatures({query:async()=>{throw Error('Must not load an arbitrary signature');}}, {actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:{...paper,final_approver:{...paper.final_approver,user_id:id(8)}}}),{statusCode:409});
 const wrongOwner={query:async()=>({rows:[{id:id(11),owner_user_id:id(8),signature_image_base64:'wrong'}]})};
 await assert.rejects(service.snapshotPaperSignatures(wrongOwner,{actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:paper}),{statusCode:409});
});
test('legacy named paper officials do not acquire signatures by matching a name',async()=>{
 const service=create({suggestPaperSignatories:async()=>{throw Error('No selected account');}});
 const legacy={...paper,final_approver:{name:'Original Mayor',position_title:'Mayor'},certification_officer:null};
 const saved=await service.snapshotPaperSignatures({query:async()=>{throw Error('No asset read expected');}}, {actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:legacy});
 assert.deepEqual(saved,legacy);
});

test('paper signature images are exposed only through the protected form endpoint payload',()=>{
 const {publicPaperRecord,paperSignaturePayload}=require('../src/modules/leave/services/paperSignatures');
 const record={...paper,encoded_at:'2026-10-26T10:00:00Z',final_approver:{...paper.final_approver,signature:{source:'saved_signature_copy',signature_asset_id:id(11),owner_user_id:id(1),signature_image_base64:'c2F2ZWQ=',mime_type:'image/png',applied_by:actor.id}}};
 const listed=publicPaperRecord(record);
 assert.equal(listed.final_approver.signature.signature_image_base64,undefined);
 assert.equal(listed.final_approver.signature.signature_asset_id,id(11));
 const payload=paperSignaturePayload(record);
 assert.equal(payload.final_approver.signature_image_base64,'c2F2ZWQ=');
 assert.equal(payload.final_approver.can_sign,false);assert.equal(payload.final_approver.assignment_source,'approved_paper_copy');
 assert.equal(payload.final_approver.signed_by,id(1));assert.equal(payload.final_approver.applied_by,actor.id);
 assert.equal(record.final_approver.signature.signature_image_base64,'c2F2ZWQ=');
});

test('paper applicants copy their own saved signature even when all officials are manual',async()=>{
 const service=create({suggestPaperSignatories:async()=>{throw Error('Manual officials need no lookup');}});
 const applicant={user_id:id(5),name:'Employee'};
 const record={...paper,applicant,final_approver:{name:'Manual official',position_title:'Mayor'},certification_officer:null};
 const db={query:async(sql,args)=>{
  assert.match(sql,/is_saved\s*=\s*true/);assert.deepEqual(args,[id(5)]);
  return {rows:[{id:id(15),owner_user_id:id(5),mime_type:'image/png',signature_image_base64:'ZW1wbG95ZWU='}]};
 }};
 const saved=await service.snapshotPaperSignatures(db,{actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:record});
 assert.equal(saved.applicant.signature?.owner_user_id,id(5));
 assert.equal(saved.applicant.signature?.applied_by,actor.id);
 assert.equal(create.publicPaperRecord(saved).applicant.signature.signature_image_base64,undefined);
 const payload=create.paperSignaturePayload({...saved,encoded_at:'2026-10-27T01:00:00Z'});
 assert.equal(payload.applicant.slot_key,'applicant');
 assert.equal(payload.applicant.signed_by,id(5));
 assert.equal(payload.applicant.signature_image_base64,'ZW1wbG95ZWU=');
 const missing=await service.snapshotPaperSignatures({query:async()=>({rows:[]})},{actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:record});
 assert.equal(missing.applicant.signature,null);
 await assert.rejects(service.snapshotPaperSignatures({query:async()=>({rows:[{id:id(15),owner_user_id:actor.id}]})},{actor,employeeId:id(5),leaveType:'sickLeave',paperRecord:record}),{statusCode:409});
 await assert.rejects(service.snapshotPaperSignatures(db,{actor,employeeId:id(6),leaveType:'sickLeave',paperRecord:record}),{statusCode:409});
});
