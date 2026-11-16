'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const {randomUUID,randomBytes}=require('node:crypto');
test('PostgreSQL encrypts and verifies signatures across native, RSP, leave and locator workflows',{
 skip:process.env.SIGNATURE_SECURITY_DB_TEST!=='1',
},async()=>{
 require('dotenv').config({quiet:true});
 const previous=process.env.SIGNATURE_SECURITY_KEYS;
 process.env.SIGNATURE_SECURITY_KEYS=JSON.stringify({active:'integration',keys:{integration:randomBytes(32).toString('base64')}});
 const {pool}=require('../src/config/db');const db=await pool.connect();
 const {createSignatureAsset,signDocumentField,getDocumentBuilder}=require('../src/services/docutrackerDocumentBuilderService');
 const {signSourceSlot,getSourceSignatures}=require('../src/services/docutrackerRspSignatureService');
 const {signLeaveSourceApplicant,getLeaveSourceSignatures}=require('../src/services/docutrackerLeaveSignatureService');
 const {signLocatorSourceSlot,getLocatorSourceSignatures}=require('../src/services/locatorSignatureService');
 const {withSigningRequest,authorizeSigning}=require('../src/services/signatureAuthorization');
 const user={id:randomUUID(),role:'employee'};
 const password='Test-only-password-123!';
 const png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
 try{
  await db.query('BEGIN');
  await db.query('SELECT 1 FROM signature_integrity_receipts LIMIT 0');
  await db.query(`INSERT INTO users(id,email,password_hash,full_name,role,employment_type,date_hired)
   VALUES($1,$2,$3,'Signature Security Test','employee','permanent','2025-01-01')`,
   [user.id,`${user.id}@security-test.invalid`,await require('bcrypt').hash(password,10)]);
  const asset=await createSignatureAsset(db,user,{source_type:'drawn',mime_type:'image/png',image_base64:png,is_saved:true});
  const stored=(await db.query('SELECT image_bytes FROM docutracker_signature_assets WHERE id=$1',[asset.id])).rows[0];
  assert.notEqual(stored.image_bytes.toString('base64'),png);assert.equal(asset.image_base64,png);
  const proxy={query:async(sql,values)=>{
   if(sql==='BEGIN')return db.query('SAVEPOINT signing_action');
   if(sql==='COMMIT')return db.query('RELEASE SAVEPOINT signing_action');
   if(sql==='ROLLBACK')return db.query('ROLLBACK TO SAVEPOINT signing_action');
   return db.query(sql,values);
  },release(){}};
  const scoped={query:(sql,values)=>db.query(sql,values),connect:async()=>proxy};
  const input={signature_asset_id:asset.id};
  const native=randomUUID(),field=randomUUID(),rsp=randomUUID(),leave=randomUUID(),locator=randomUUID();
  await db.query(`INSERT INTO docutracker_documents(id,document_number,document_type,title,created_by,status)
   VALUES($1,$2,'purchaseRequest','Security test',$3,'pending')`,[native,`SEC-${native}`,user.id]);
  await db.query(`INSERT INTO docutracker_document_contents(document_id,pages) VALUES($1,'[[{"insert":"Original text\\n"}]]')`,[native]);
  await db.query(`INSERT INTO docutracker_signature_fields(id,document_id,page_number,position_x,position_y,width,height,assigned_signer_id)
   VALUES($1,$2,1,0.1,0.1,0.2,0.1,$3)`,[field,native,user.id]);
  await db.query("INSERT INTO selection_lineup_entries(id,created_by,vacant_position) VALUES($1,$2,'Test position')",[rsp,user.id]);
  await db.query(`INSERT INTO docutracker_rsp_source_signatures(source_table,source_record_id,slot_key,label,assigned_signer_id,assignment_source,created_by)
   VALUES('selection_lineup_entries',$1,'prepared_by','Prepared by',$2,'creator',$2)`,[rsp,user.id]);
  await db.query(`INSERT INTO leave_requests(id,employee_id,user_id,start_date,end_date,reason,status)
   VALUES($1,$2,$2,'2026-11-18','2026-11-18','Original reason','draft')`,[leave,user.id]);
  await db.query(`INSERT INTO locator_slips(id,employee_id,slip_date,office,reason,am_in,print_signatories)
   VALUES($1,$2,'2026-11-18','Test office','Original reason',true,$3::jsonb)`,[locator,user.id,JSON.stringify({
    applicant:{id:user.id,name:'Signature Security Test',position_title:'Employee'},department_head:{id:null,name:'',position_title:''},hr_approver:{id:null,name:'',position_title:''}})]);
  const cases=[
   {id:native,sign:()=>signDocumentField(scoped,user,native,field,input),read:()=>getDocumentBuilder(scoped,user,native),rows:r=>r.signature_fields,
    alter:()=>db.query(`UPDATE docutracker_document_contents SET pages='[[{"insert":"Changed text\\n"}]]',revision=revision+1 WHERE document_id=$1`,[native])},
   {id:rsp,sign:()=>signSourceSlot(scoped,user,'rsp','selection_lineup_entries',rsp,'prepared_by',input),read:()=>getSourceSignatures(scoped,user,'rsp','selection_lineup_entries',rsp),rows:r=>r.signatures,
    alter:()=>db.query("UPDATE selection_lineup_entries SET vacant_position='Changed' WHERE id=$1",[rsp])},
   {id:leave,sign:()=>signLeaveSourceApplicant(scoped,user,'dtr','leave_requests',leave,input),read:()=>getLeaveSourceSignatures(scoped,user,'dtr','leave_requests',leave),rows:r=>r.signatures,
    alter:()=>db.query("UPDATE leave_requests SET reason='Changed' WHERE id=$1",[leave])},
   {id:locator,sign:()=>signLocatorSourceSlot(scoped,user,'dtr','locator_slips',locator,'applicant',input),read:()=>getLocatorSourceSignatures(scoped,user,'dtr','locator_slips',locator),rows:r=>r.signatures,
    alter:()=>db.query("UPDATE locator_slips SET reason='Changed' WHERE id=$1",[locator])},
  ];
  for(const item of cases){
   const request={method:'POST',originalUrl:`/api/security-test/${item.id}/sign`,headers:{'x-signing-request-id':randomUUID()},body:input,user};
   let challenge;const response={setHeader(name,value){if(name==='X-Signature-Challenge')challenge=value;}};
   await assert.rejects(withSigningRequest(request,response,item.sign),error=>error.statusCode===428);
   assert.ok(challenge);
   const authorization=await authorizeSigning(scoped,user,{challenge,password});
   request.headers['x-signature-authorization']=authorization;
   const signed=await withSigningRequest(request,response,item.sign);
   const confirmed=item.rows(signed).find(row=>row.signature_asset_id===asset.id);
   assert.equal(confirmed?.signature_image_base64.replace(/\s/g,''),png);
   assert.equal(confirmed.integrity_status,'verified');
   await assert.rejects(withSigningRequest(request,response,item.sign),/used/);
   await item.alter();
   const changed=await item.read();
   assert.equal(item.rows(changed).some(row=>row.signature_image_base64),false);
  }
  const ojt=require('../src/services/ojtSignatureSecurity');
  const ojtId=randomUUID();
  await db.query('INSERT INTO ojt_work_immersion_evaluation_entries(id,school) VALUES($1,$2)',[ojtId,'Original school']);
  const signOjt=async()=>{
   await proxy.query('BEGIN');
   try{
    const before=(await proxy.query('SELECT * FROM ojt_work_immersion_evaluation_entries WHERE id=$1 FOR UPDATE',[ojtId])).rows[0];
    const row=(await proxy.query('UPDATE ojt_work_immersion_evaluation_entries SET interviewer_signature=$2 WHERE id=$1 RETURNING *',[ojtId,png])).rows[0];
    const result=await ojt.secureOjtSave(proxy,user,before,row);
    await proxy.query('COMMIT');return result;
   }catch(error){await proxy.query('ROLLBACK');throw error;}
  };
  const request={method:'PUT',originalUrl:`/api/rsp-ld/entries/${ojtId}`,headers:{'x-signing-request-id':randomUUID()},body:{interviewer_signature:png},user};
  let challenge;const response={setHeader(name,value){if(name==='X-Signature-Challenge')challenge=value;}};
  await assert.rejects(withSigningRequest(request,response,signOjt),error=>error.statusCode===428);
  request.headers['x-signature-authorization']=await authorizeSigning(scoped,user,{challenge,password});
  const signedOjt=await withSigningRequest(request,response,signOjt);
  assert.equal(signedOjt.interviewer_signature,png);assert.equal(signedOjt.signature_integrity_status,'verified');
  const storedOjt=(await db.query('SELECT * FROM ojt_work_immersion_evaluation_entries WHERE id=$1',[ojtId])).rows[0];
  assert.ok(storedOjt.interviewer_signature.startsWith(ojt.PREFIX));
  assert.equal(ojt.decodeOjtEntry({...storedOjt,school:'Changed school'}).interviewer_signature,null);
  await db.query('SAVEPOINT immutable_receipts');
  await assert.rejects(db.query(`DELETE FROM signature_integrity_receipts WHERE sealed_manifest->'payload'->>'signer_id'=$1`,[user.id]),/append-only/);
  await db.query('ROLLBACK TO SAVEPOINT immutable_receipts');
 }finally{
  await db.query('ROLLBACK');db.release();await pool.end();
  if(previous===undefined)delete process.env.SIGNATURE_SECURITY_KEYS;else process.env.SIGNATURE_SECURITY_KEYS=previous;
 }
});
