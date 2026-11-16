'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const crypto=require('node:crypto');
let previous;
test.beforeEach(()=>{previous=process.env.SIGNATURE_SECURITY_KEYS;process.env.SIGNATURE_SECURITY_KEYS=JSON.stringify({active:'v1',keys:{v1:crypto.randomBytes(32).toString('base64')}});});
test.afterEach(()=>{if(previous===undefined)delete process.env.SIGNATURE_SECURITY_KEYS;else process.env.SIGNATURE_SECURITY_KEYS=previous;});
test('signing requires password confirmation bound to the exact request and cannot replay',async()=>{
 const {withSigningRequest,requireSigningAuthorization,authorizeSigning}=require('../src/services/signatureAuthorization');
 let challenge;let consumed=false;
 const req={method:'POST',originalUrl:'/api/example/sign',headers:{'x-signing-request-id':crypto.randomUUID()},body:{reason:'Meeting'},user:{id:'signer'}};
 const res={setHeader(name,value){if(name==='X-Signature-Challenge')challenge=value;}};
 const db={query:async sql=>sql.includes('INSERT INTO signature_authorization_uses')
  ? {rowCount:consumed?0:1,rows:consumed?[]:[{authorization_id:'used'}],...(consumed=true,{})}
  : {rows:[{id:'signer',is_active:true,employment_status:'active',auth_version:3,password_hash:'hash'}]}};
 await assert.rejects(withSigningRequest(req,res,()=>requireSigningAuthorization(db,'signer','contents-one')),error=>error.statusCode===428);
 assert.ok(challenge);
 await assert.rejects(authorizeSigning(db,{id:'signer'},{challenge,password:'wrong'},async()=>false),/password/i);
 const proof=await authorizeSigning(db,{id:'signer'},{challenge,password:'correct'},async()=>true);
 req.headers['x-signature-authorization']=proof;
 const changed={...req,body:{reason:'Different'}};
 await assert.rejects(withSigningRequest(changed,res,()=>requireSigningAuthorization(db,'signer','contents-one')),/authorization/i);
 await assert.rejects(withSigningRequest(req,res,()=>requireSigningAuthorization(db,'signer','contents-changed')),/authorization/i);
 await withSigningRequest(req,res,async()=>{await requireSigningAuthorization(db,'signer','contents-one');await requireSigningAuthorization(db,'signer','contents-one');});
 await assert.rejects(withSigningRequest(req,res,()=>requireSigningAuthorization(db,'signer','contents-one')),/used|authorization/i);
});
test('signing outside a protected request fails closed',async()=>{
 const {requireSigningAuthorization}=require('../src/services/signatureAuthorization');
 await assert.rejects(requireSigningAuthorization({},'signer'),/confirmation/i);
});

test('new file upload confirmation survives regenerated storage names but detects content changes',()=>{
 const {withSigningRequest,signingDocumentBinding}=require('../src/services/signatureAuthorization');
 const one={id:'first-request',reason:'Meeting',attachment_path:'first.pdf',attachment_uploaded_at:'first'};
 const two={...one,id:'retry-request',attachment_path:'retry.pdf',attachment_uploaded_at:'retry'};
 const req={file:{buffer:Buffer.from('same upload')}};
 withSigningRequest(req,{},()=>{
  assert.equal(signingDocumentBinding('leave_requests',one,'image'),signingDocumentBinding('leave_requests',two,'image'));
  assert.notEqual(signingDocumentBinding('leave_requests',one,'image'),signingDocumentBinding('leave_requests',{...two,reason:'Changed'},'image'));
 });
 withSigningRequest({}, {},()=>assert.notEqual(signingDocumentBinding('leave_requests',one,'image'),signingDocumentBinding('leave_requests',two,'image')));
});

test('expired challenges and another account cannot obtain signing authorization',async()=>{
 const {authorizeSigning}=require('../src/services/signatureAuthorization');
 const {sealManifest}=require('../src/services/signatureSecurity');
 const db={query:async()=>({rows:[{id:'signer',is_active:true,employment_status:'active',auth_version:2,password_hash:'hash'}]})};
 for(const payload of [
  {user_id:'signer',auth_version:2,expires_at:Date.now()-1},
  {user_id:'another',auth_version:2,expires_at:Date.now()+60000},
  {user_id:'signer',auth_version:1,expires_at:Date.now()+60000},
 ]){
  const challenge=Buffer.from(JSON.stringify(sealManifest(payload,'challenge'))).toString('base64url');
  await assert.rejects(authorizeSigning(db,{id:'signer'},{challenge,password:'correct'},async()=>true),/expired/i);
 }
});
