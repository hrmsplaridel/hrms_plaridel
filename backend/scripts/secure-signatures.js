'use strict';
// Dry-run by default. Never prints key material or signature images.
const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');
require('dotenv').config({path:path.resolve(__dirname,'../.env'),quiet:true});
const args=process.argv.slice(2);
const createIndex=args.indexOf('--create-key-file');
if(createIndex>=0){
 const target=args[createIndex+1];
 if(!target)throw Error('Provide the key file path.');
 fs.writeFileSync(path.resolve(target),JSON.stringify({active:'v1',keys:{v1:crypto.randomBytes(32).toString('base64')}},null,2)+'\n',{flag:'wx',mode:0o600});
 console.log('Created signature key file. Store a secure backup separately from database backups.');
}else{
 const {pool}=require('../src/config/db');
 const {keyring,isEncryptedSignature,encryptSignature,decryptSignature}=require('../src/services/signatureSecurity');
 const {recordSignatureEvidence}=require('../src/services/signatureIntegrity');
 const ojt=require('../src/services/ojtSignatureSecurity');
 (async()=>{
  const db=await pool.connect();let transaction=false;
  try{
   const target=(await db.query('SELECT current_database() AS database,host(inet_server_addr()) AS server,inet_server_port() AS port')).rows[0];
   const inventory=(await db.query('SELECT count(*)::int AS assets FROM docutracker_signature_assets')).rows[0];
   console.log(JSON.stringify({target,...inventory,mode:args.includes('--apply')?'apply':'dry-run'}));
   if(!args.includes('--apply'))return;
   if(args[args.indexOf('--confirm-db')+1]!==target.database || !args.includes('--confirm-db'))throw Error('Provide --confirm-db with the exact database name.');
   keyring();
   await db.query('BEGIN');transaction=true;
   await db.query(`LOCK TABLE docutracker_signature_assets,docutracker_signature_fields,
     docutracker_leave_signatures,docutracker_locator_signatures,docutracker_rsp_source_signatures,
     ojt_work_immersion_evaluation_entries IN EXCLUSIVE MODE`);
   const assets=(await db.query('SELECT id,owner_user_id,mime_type,image_bytes FROM docutracker_signature_assets ORDER BY id FOR UPDATE')).rows;
   let encrypted=0,snapshots=0,receipts=0,ojtEncrypted=0;
   for(const asset of assets){
    const identity={assetId:asset.id,ownerId:asset.owner_user_id,mimeType:asset.mime_type};
    const plain=decryptSignature(asset.image_bytes,identity,{allowLegacy:true});
    if(!isEncryptedSignature(asset.image_bytes)||args.includes('--reencrypt')){
     await db.query('UPDATE docutracker_signature_assets SET image_bytes=$2 WHERE id=$1',[asset.id,encryptSignature(plain,identity)]);encrypted++;
    }
   }
   for(const table of ['leave_requests','locator_slips']){
    const records=(await db.query(`SELECT id,paper_approval_record FROM ${table} WHERE paper_approval_record IS NOT NULL FOR UPDATE`)).rows;
    for(const row of records){
     const paper=row.paper_approval_record;let changed=false;
     for(const group of ['applicant','department_reviewer','certification_officer','final_approver']){
      const signature=paper[group]?.signature;if(!signature?.signature_image_base64)continue;
      const raw=Buffer.from(signature.signature_image_base64.replace(/\s+/g,''),'base64');
      const identity={assetId:signature.signature_asset_id,ownerId:signature.owner_user_id,mimeType:signature.mime_type};
      const plain=decryptSignature(raw,identity,{allowLegacy:true});
      if(!isEncryptedSignature(raw)||args.includes('--reencrypt')){
       signature.signature_image_base64=encryptSignature(plain,identity).toString('base64');changed=true;snapshots++;
      }
     }
     if(changed)await db.query(`UPDATE ${table} SET paper_approval_record=$2::jsonb WHERE id=$1`,[row.id,JSON.stringify(paper)]);
    }
   }
   const specs=[['docutracker_signature_fields','native_document','document_id'],
     ['docutracker_leave_signatures','leave_requests','leave_request_id'],
     ['docutracker_locator_signatures','locator_slips','locator_slip_id'],
     ['docutracker_rsp_source_signatures',null,'source_record_id']];
   for(const [table,scope,foreignKey] of specs){
    const rows=(await db.query(`SELECT * FROM ${table} WHERE signature_asset_id IS NOT NULL AND signed_at IS NOT NULL ORDER BY id`)).rows;
    for(const row of rows){
     await recordSignatureEvidence(db,{scope:scope||row.source_table,recordId:row[foreignKey],
      slot:scope==='native_document'?row.id:row.slot_key,revision:row.revision||0,row,baseline:true});receipts++;
    }
   }
   for(const table of ['leave_requests','locator_slips']){
    const records=(await db.query(`SELECT id,workflow_snapshot FROM ${table} WHERE workflow_snapshot IS NOT NULL`)).rows;
    for(const row of records)for(const decision of row.workflow_snapshot.decisions||[]){
     if(decision.action!=='approve'||!decision.signature?.signature_asset_id||!decision.signature.signed_at)continue;
     await recordSignatureEvidence(db,{scope:table,recordId:row.id,slot:`workflow_step_${decision.step+1}`,
       revision:decision.signature.revision||0,row:{...decision.signature,signed_by:decision.actor_id},baseline:true});receipts++;
    }
   }
   const ojtRows=(await db.query('SELECT * FROM ojt_work_immersion_evaluation_entries WHERE interviewer_signature IS NOT NULL FOR UPDATE')).rows;
   for(const row of ojtRows){
    if(!row.interviewer_signature)continue;
    if(row.interviewer_signature.startsWith(ojt.PREFIX)){
     if(ojt.decodeOjtEntry(row).signature_integrity_status==='invalid')throw Error('An OJT signature failed verification. Resolve it before conversion.');
     if(args.includes('--reencrypt')){
      const secured=JSON.parse(Buffer.from(row.interviewer_signature.slice(ojt.PREFIX.length),'base64url').toString());
      const m=secured.receipt.payload;
      const identity={assetId:row.id,ownerId:m.owner_id,mimeType:m.mime_type};
      secured.image=encryptSignature(decryptSignature(Buffer.from(secured.image,'base64'),identity),identity).toString('base64');
      await db.query('UPDATE ojt_work_immersion_evaluation_entries SET interviewer_signature=$2 WHERE id=$1',
       [row.id,ojt.PREFIX+Buffer.from(JSON.stringify(secured)).toString('base64url')]);ojtEncrypted++;
     }
     continue;
    }
    const encoded=ojt.sealOjtBaseline(row);
    await db.query('UPDATE ojt_work_immersion_evaluation_entries SET interviewer_signature=$2 WHERE id=$1',[row.id,encoded]);
    await ojt.storeReceipt(db,encoded);ojtEncrypted++;
   }
   await db.query('COMMIT');transaction=false;
   console.log(JSON.stringify({encrypted_assets:encrypted,encrypted_paper_snapshots:snapshots,baseline_receipts_checked:receipts,encrypted_ojt_signatures:ojtEncrypted}));
  }catch(error){if(transaction)await db.query('ROLLBACK');throw error;}
  finally{db.release();await pool.end();}
 })().catch(error=>{console.error(error.message);process.exitCode=1;});
}
