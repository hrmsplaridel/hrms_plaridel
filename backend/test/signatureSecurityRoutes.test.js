'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const {randomBytes}=require('node:crypto');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('signing authorization requires a valid session and password and limits failed attempts',async()=>{
 const oldKeys=process.env.SIGNATURE_SECURITY_KEYS,oldJwt=process.env.JWT_SECRET;
 process.env.SIGNATURE_SECURITY_KEYS=JSON.stringify({active:'route-test',keys:{'route-test':randomBytes(32).toString('base64')}});
 process.env.JWT_SECRET=randomBytes(32).toString('hex');
 const userId='11111111-1111-4111-8111-111111111111';
 const passwordHash=await require('bcrypt').hash('correct-password',10);
 const restore=withMockedModule('../src/config/db',{pool:{query:async(sql)=>sql.includes('FROM users')
  ? {rows:[{id:userId,role:'employee',is_active:true,employment_status:'active',auth_version:1,password_hash:passwordHash}]}
  : {rowCount:0,rows:[]}}});
 clearModule('../src/middleware/auth');clearModule('../src/routes/signatureSecurity');
 const app=require('express')();app.use(require('express').json());
 app.use('/api/signature-security',require('../src/routes/signatureSecurity'));
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
 try{
  const url=`http://127.0.0.1:${server.address().port}/api/signature-security/authorize`;
  const bearer=require('jsonwebtoken').sign({id:userId,typ:'access',auth_version:1},process.env.JWT_SECRET);
  const challenge=Buffer.from(JSON.stringify(require('../src/services/signatureSecurity').sealManifest({
   user_id:userId,auth_version:1,request_digest:'request',expires_at:Date.now()+60000},'challenge'))).toString('base64url');
  const post=(password,authorized=true)=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json',
   ...(authorized?{Authorization:`Bearer ${bearer}`}:{})},body:JSON.stringify({challenge,password})});
  assert.equal((await post('correct-password',false)).status,401);
  const success=await post('correct-password');assert.equal(success.status,200);
  assert.equal(success.headers.get('cache-control'),'no-store');
  assert.equal(typeof (await success.json()).authorization,'string');
  for(let attempt=0;attempt<5;attempt++)assert.equal((await post('incorrect')).status,403);
  const limited=await post('incorrect');assert.equal(limited.status,429);assert.ok(limited.headers.get('retry-after'));
 }finally{
  server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
  clearModule('../src/routes/signatureSecurity');clearModule('../src/middleware/auth');restore();
  if(oldKeys===undefined)delete process.env.SIGNATURE_SECURITY_KEYS;else process.env.SIGNATURE_SECURITY_KEYS=oldKeys;
  if(oldJwt===undefined)delete process.env.JWT_SECRET;else process.env.JWT_SECRET=oldJwt;
 }
});
