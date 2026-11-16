'use strict';
const {randomUUID}=require('node:crypto');
const {digest,encryptSignature,decryptSignature,sealManifest,verifyManifest,securityError}=require('./signatureSecurity');
const PREFIX='UPSIG-OJT1:';
const TABLE='ojt_work_immersion_evaluation_entries';
function content(row){return Object.fromEntries(Object.entries(row).filter(([key])=>
 !['interviewer_signature','created_at','updated_at','deleted_at','signature_integrity_status','signature_signer_id'].includes(key)));}
function image(value){
 const raw=String(value||'').replace(/^data:image\/(png|jpeg);base64,/i,'').replace(/\s/g,'');
 if(raw.length>2800000||!/^[A-Za-z0-9+/]*={0,2}$/.test(raw))throw securityError('Invalid interviewer signature image.','VALIDATION',400);
 const bytes=Buffer.from(raw,'base64');
 const png=bytes.subarray(0,8).toString('hex')==='89504e470d0a1a0a';
 const jpeg=bytes.subarray(0,3).toString('hex')==='ffd8ff';
 if(!bytes.length||bytes.length>2097152||(!png&&!jpeg))throw securityError('Interviewer signature must be a PNG or JPEG under 2 MB.','VALIDATION',400);
 return {bytes,mimeType:png?'image/png':'image/jpeg'};
}
function seal(row,ownerId,assurance,authorizationId=null){
 const ink=image(row.interviewer_signature);
 const payload={scope:TABLE,record_id:String(row.id),owner_id:ownerId,signer_id:assurance==='confirmed'?ownerId:null,
  signer_name:row.interviewer||null,signed_at:new Date().toISOString(),nonce:randomUUID(),
  content_digest:digest(content(row)),image_digest:digest(ink.bytes),mime_type:ink.mimeType,assurance,authorization_id:authorizationId};
 const protectedValue={image:encryptSignature(ink.bytes,{assetId:row.id,ownerId,mimeType:ink.mimeType}).toString('base64'),receipt:sealManifest(payload)};
 return PREFIX+Buffer.from(JSON.stringify(protectedValue)).toString('base64url');
}
function sealOjtBaseline(row){return seal(row,'legacy-unknown','legacy_baseline');}
function decodeOjtEntry(row){
 if(!row?.interviewer_signature)return row;
 if(!row.interviewer_signature.startsWith(PREFIX))return {...row,signature_integrity_status:'legacy_unverified'};
 try{
  const protectedValue=JSON.parse(Buffer.from(row.interviewer_signature.slice(PREFIX.length),'base64url').toString());
  const m=verifyManifest(protectedValue.receipt);
  if(m.scope!==TABLE||m.record_id!==String(row.id)||m.content_digest!==digest(content(row)))throw securityError('OJT signature integrity verification failed.');
  const bytes=decryptSignature(Buffer.from(protectedValue.image,'base64'),{assetId:row.id,ownerId:m.owner_id,mimeType:m.mime_type});
  if(digest(bytes)!==m.image_digest)throw securityError('OJT signature integrity verification failed.');
  return {...row,interviewer_signature:bytes.toString('base64'),signature_integrity_status:m.assurance==='confirmed'?'verified':'legacy_baseline',signature_signer_id:m.signer_id};
 }catch(error){
  if(error.statusCode===503)throw error;
  return {...row,interviewer_signature:null,signature_integrity_status:'invalid'};
 }
}
async function storeReceipt(db,encoded){
 const secured=JSON.parse(Buffer.from(encoded.slice(PREFIX.length),'base64url').toString());
 await db.query(`INSERT INTO signature_integrity_receipts(subject_key,sealed_manifest) VALUES($1,$2::jsonb) ON CONFLICT DO NOTHING`,
  [digest(secured.receipt.payload),JSON.stringify({...secured.receipt,encrypted_image:secured.image})]);
}
async function secureOjtSave(db,user,previous,row){
 if(!row?.interviewer_signature)return row;
 const before=decodeOjtEntry(previous);
 let incoming=row.interviewer_signature;
 if(incoming.startsWith(PREFIX)){
  if(incoming!==previous?.interviewer_signature)throw securityError('Signature storage data cannot be submitted by a client.','VALIDATION',400);
  incoming=before?.interviewer_signature;
 }
 let encoded=null;
 if(incoming){
  const current=image(incoming).bytes.toString('base64');
  const prior=before?.interviewer_signature?image(before.interviewer_signature).bytes.toString('base64'):null;
  if(current===prior){
   if(digest(content(previous))===digest(content(row)))encoded=previous.interviewer_signature.startsWith(PREFIX)
    ?previous.interviewer_signature:sealOjtBaseline({...row,interviewer_signature:current});
   // Material edits clear old ink. A newly drawn signature must be confirmed.
  }else{
   const signing=require('./signatureAuthorization');
   const proof=await signing.requireSigningAuthorization(db,user.id,
    signing.signingDocumentBinding(TABLE,content(row),digest(image(current).bytes)));
   encoded=seal({...row,interviewer_signature:current},String(user.id),'confirmed',proof.id);
  }
 }
 await db.query('UPDATE ojt_work_immersion_evaluation_entries SET interviewer_signature=$2 WHERE id=$1',[row.id,encoded]);
 if(encoded)await storeReceipt(db,encoded);
 await db.query(`INSERT INTO audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES($1,$2,'ojt_form',$3,$4)`,[user.id,encoded?'ojt_signature_secured':'ojt_signature_invalidated',row.id,
  JSON.stringify({reason:encoded?'Signature stored with content integrity evidence':'Form content changed; signature must be added again'})]);
 return decodeOjtEntry({...row,interviewer_signature:encoded});
}
module.exports={PREFIX,TABLE,content,sealOjtBaseline,decodeOjtEntry,storeReceipt,secureOjtSave};
