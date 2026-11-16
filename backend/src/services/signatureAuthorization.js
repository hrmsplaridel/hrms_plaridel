'use strict';
const { AsyncLocalStorage }=require('node:async_hooks');
const crypto=require('node:crypto');
const fs=require('node:fs');
const bcrypt=require('bcrypt');
const {digest,sealManifest,verifyManifest,securityError}=require('./signatureSecurity');
const requests=new AsyncLocalStorage();
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
function withSigningRequest(req,res,work){return requests.run({req,res},work);}
function signingRequestContext(req,res,next){return withSigningRequest(req,res,next);}
function requestDigest(req){
 const files=[req.file,...(Array.isArray(req.files)?req.files:Object.values(req.files||{}).flat())].filter(Boolean)
  .map(file=>({field:file.fieldname,name:file.originalname,type:file.mimetype,
    digest:digest(file.buffer || fs.readFileSync(file.path))}));
 return digest({method:req.method,path:req.originalUrl,request_id:req.headers['x-signing-request-id'],body:req.body,files});
}
function encode(value){return Buffer.from(JSON.stringify(value)).toString('base64url');}
function decode(value,purpose){
 try{if(typeof value!=='string'||value.length>4096)throw Error();return verifyManifest(JSON.parse(Buffer.from(value,'base64url').toString()),purpose);}
 catch(error){if(error.statusCode===503)throw error;throw securityError('Invalid signing authorization.','FORBIDDEN',403);}
}
async function currentAccount(db,id){
 const user=(await db.query(`SELECT id,is_active,employment_status,auth_version,password_hash FROM users WHERE id=$1::uuid`,[id])).rows[0];
 if(!user || user.is_active!==true || user.employment_status!=='active')throw securityError('An active account is required to confirm signing.','FORBIDDEN',403);
 return user;
}
function signingDocumentBinding(scope,content,imageDigest){
 const stable={...content};delete stable.id;
 const req=requests.getStore()?.req;
 if(req?.file || Object.keys(req?.files||{}).length){
  // File contents and original names are already part of requestDigest. Storage
  // names and upload timestamps are regenerated if the first transaction rolls back.
  delete stable.attachment_path;delete stable.attachment_uploaded_at;
 }
 return digest({scope,content:stable,image_digest:imageDigest});
}
async function requireSigningAuthorization(db,signerId,documentBinding=null){
 const state=requests.getStore();
 if(!state)throw securityError('Signing confirmation requires a protected application request.','UNAVAILABLE',503);
 if(String(state.req.user?.id)!==String(signerId))throw securityError('Signing authorization does not belong to this account.','FORBIDDEN',403);
 if(state.authorizedClient===db)return state.authorization;
 const account=await currentAccount(db,signerId);
 const fingerprint=requestDigest(state.req);
 const proof=state.req.headers['x-signature-authorization'];
 if(!proof){
  const challenge=sealManifest({user_id:String(signerId),auth_version:account.auth_version||0,
    request_digest:fingerprint,document_binding:documentBinding,expires_at:Date.now()+5*60*1000},'challenge');
  state.res.setHeader('X-Signature-Challenge',encode(challenge));
  throw securityError('Confirm your password to apply this signature.','SIGNATURE_AUTHORIZATION_REQUIRED',428);
 }
 const authorization=decode(proof,'authorization');
 if(!UUID.test(state.req.headers['x-signing-request-id']||'') ||
    authorization.user_id!==String(signerId) || authorization.auth_version!==(account.auth_version||0) ||
    authorization.request_digest!==fingerprint || authorization.expires_at<=Date.now() ||
    authorization.document_binding!==documentBinding ||
    !UUID.test(authorization.id||''))throw securityError('Signing authorization does not match this request.','FORBIDDEN',403);
 const used=await db.query(`INSERT INTO signature_authorization_uses(authorization_id,user_id,expires_at)
   VALUES($1::uuid,$2::uuid,to_timestamp($3 / 1000.0)) ON CONFLICT DO NOTHING RETURNING authorization_id`,
 [authorization.id,signerId,authorization.expires_at]);
 if(!used.rowCount)throw securityError('Signing authorization has already been used.','CONFLICT',409);
 state.authorizedClient=db;state.authorization=authorization;
 return authorization;
}
async function authorizeSigning(db,user,{challenge,password}={},compare=bcrypt.compare){
 const payload=decode(challenge,'challenge');
 const account=await currentAccount(db,user.id);
 if(payload.user_id!==String(user.id)||payload.auth_version!==(account.auth_version||0)||payload.expires_at<=Date.now()) {
  throw securityError('Signing confirmation expired. Please retry the original action.','FORBIDDEN',403);
 }
 if(typeof password!=='string'||!password.length||password.length>256||!await compare(password,account.password_hash)) {
  throw securityError('Password is incorrect.','FORBIDDEN',403);
 }
 await db.query('DELETE FROM signature_authorization_uses WHERE expires_at < now()');
 return encode(sealManifest({...payload,id:crypto.randomUUID(),authorized_at:Date.now()},'authorization'));
}
module.exports={signingRequestContext,withSigningRequest,requireSigningAuthorization,authorizeSigning,signingDocumentBinding};
