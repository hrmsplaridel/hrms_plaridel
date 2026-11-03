'use strict';
const OFFICIAL_GROUPS=['final_approver','certification_officer','department_reviewer'];
const GROUPS=[...OFFICIAL_GROUPS,'applicant'];
function conflict(message){throw Object.assign(new Error(message),{statusCode:409});}
function publicPaperRecord(record){
 if(!record)return null;
 const result={...record};
 for(const group of GROUPS){
  const person=record[group];if(!person)continue;
  result[group]={...person};
  if(person.signature){const {signature_image_base64,...metadata}=person.signature;result[group].signature=metadata;}
 }
 return result;
}
function paperSignaturePayload(record){
 const signatures={};
 const slots={final_approver:'hr_approver',certification_officer:'certification_officer',department_reviewer:'department_head',applicant:'applicant'};
 for(const group of GROUPS){
  const person=record[group];const signature=person?.signature;
  if(!person?.user_id||!signature?.signature_asset_id||!signature.signature_image_base64||signature.source!=='saved_signature_copy'||String(signature.owner_user_id)!==String(person.user_id))continue;
  signatures[group]={slot_key:slots[group],label:'Stored signature copied from approved paper recording',
   assigned_signer_id:person.user_id,assigned_signer_name:person.name,can_sign:false,
   assignment_source:'approved_paper_copy',signature_asset_id:signature.signature_asset_id,
   signature_image_base64:signature.signature_image_base64,mime_type:signature.mime_type,
   signed_by:person.user_id,signer_name_snapshot:person.name,signed_at:record.encoded_at,
   applied_by:signature.applied_by};
 }
 return signatures;
}
function createPaperSignatures(dependencies){
 const suggest=dependencies.suggestPaperSignatories||require('./paperSignatories')(dependencies).suggestPaperSignatories;
 async function snapshotPaperSignatures(db,{actor,employeeId,leaveType,paperRecord}){
  const selected=GROUPS.filter(group=>paperRecord[group]?.user_id);
  if(!selected.length)return paperRecord;
  if(paperRecord.applicant && String(paperRecord.applicant.user_id).toLowerCase()!==String(employeeId).toLowerCase())conflict('The applicant signature must belong to the selected employee.');
  const choices=selected.some(group=>OFFICIAL_GROUPS.includes(group))
   ? await suggest(db,{employeeId,leaveType,filingDate:paperRecord.original_filing_date,approvalDate:paperRecord.approval_date}) : {};
  const record={...paperRecord};const assets=new Map();
  for(const group of selected){
   const person=paperRecord[group];
   // Applicant identity is built from the validated employee row by prepareStaffLeave.
   const allowed=group==='applicant'?person:(choices[group]||[]).find(choice=>String(choice.user_id).toLowerCase()===person.user_id.toLowerCase());
   if(!allowed)conflict('The selected paper signatory is no longer in the configured list. Refresh the suggestions or choose Other signatory.');
   if(!assets.has(allowed.user_id)){
    const asset=(await db.query(`SELECT id,owner_user_id,mime_type,encode(image_bytes,'base64') AS signature_image_base64
      FROM docutracker_signature_assets WHERE owner_user_id=$1::uuid AND is_saved = true
      ORDER BY created_at DESC,id DESC LIMIT 1`,[allowed.user_id])).rows[0]||null;
    if(asset&&String(asset.owner_user_id).toLowerCase()!==String(allowed.user_id).toLowerCase())conflict('The stored signature does not belong to the selected signatory.');
    assets.set(allowed.user_id,asset);
   }
   const asset=assets.get(allowed.user_id);
   record[group]={name:allowed.name,position_title:allowed.position_title||person.position_title,user_id:allowed.user_id,
    signature:asset?{source:'saved_signature_copy',signature_asset_id:asset.id,owner_user_id:allowed.user_id,
     mime_type:asset.mime_type,signature_image_base64:asset.signature_image_base64.replace(/\s+/g,''),applied_by:actor.id}:null};
  }
  return record;
 }
 return {snapshotPaperSignatures};
}
module.exports=createPaperSignatures;
module.exports.publicPaperRecord=publicPaperRecord;
module.exports.paperSignaturePayload=paperSignaturePayload;
