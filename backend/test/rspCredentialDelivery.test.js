'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');

for(const scenario of ['success','mail_failure','concurrent_change','metadata_failure']) {
 test(`credential delivery preserves account security: ${scenario}`,async()=>{
  const calls=[];let mailed=0;
  const restores=[
   withMockedModule('../src/config/db',{pool:{query:async(sql,params)=>{
    calls.push({sql,params});
    if(/SELECT full_name, email, hired_user_id/.test(sql))return {rows:[{full_name:'Applicant',email:'applicant@test.invalid',hired_user_id:'user',hr_account_setup_done:true}]};
    if(/SELECT id, email, password_hash/.test(sql))return {rows:[{id:'user',email:'applicant@test.invalid',password_hash:'old-hash'}]};
    if(/UPDATE public\.users SET password_hash/.test(sql))return {rows:scenario==='concurrent_change'?[]:[{id:'user'}],rowCount:scenario==='concurrent_change'?0:1};
    if(/SET hire_credentials_email_sent_at/.test(sql)&&scenario==='metadata_failure')throw Error('Simulated metadata failure');
    return {rows:[],rowCount:0};
   }}}),
   withMockedModule('bcrypt',{hash:async()=> 'new-hash'}),
   withMockedModule('../src/utils/smtpMail',{isSmtpConfigured:()=>true,sendSmtpMail:async()=>{mailed++;if(scenario==='mail_failure')throw Error('Simulated mail failure');}}),
   withMockedModule('../src/utils/emailJsMail',{...require('../src/utils/emailJsMail'),isEmailJsConfiguredForHireEmail:()=>false}),
   withMockedModule('../src/services/rspIssuedForm',{assertIssuedFormSchema:async()=>{}}),
   withMockedModule('../src/services/rspPreDeliberation',{assertPreDeliberationSchema:async()=>{}}),
   withMockedModule('../src/services/rspFinalHiring',{assertFinalHiringSchema:async()=>{}}),
  ];
  const oldError=console.error;console.error=()=>{};
  clearModule('../src/routes/rspApplications');
  try{
   const router=require('../src/routes/rspApplications');
   const handler=router.stack.find(l=>l.route?.path==='/:applicationId/send-credentials').route.stack.at(-1).handle;
   const res={statusCode:200,status(n){this.statusCode=n;return this;},json(body){this.body=body;return this;}};
   await handler({params:{applicationId:'application'},user:{id:'hr',role:'hr'}},res);
   const writes=calls.filter(c=>/UPDATE public\.users SET password_hash/.test(c.sql));
   assert.ok(writes[0],`Expected a password update; response: ${JSON.stringify(res.body)}`);
   assert.match(writes[0].sql,/auth_version\s*=\s*auth_version\s*\+\s*1/,'Password rotation invalidates existing access and refresh tokens');
   assert.match(writes[0].sql,/AND password_hash = \$3/,'Do not overwrite an account changed since it was read');
   assert.equal(writes[0].params[2],'old-hash');
   if(scenario==='success'){assert.equal(res.statusCode,200);assert.equal(mailed,1);assert.equal(writes.length,1);}
   if(scenario==='concurrent_change'){assert.equal(res.statusCode,409);assert.equal(mailed,0);}
   if(scenario==='mail_failure'){
    assert.equal(res.statusCode,500);assert.equal(writes.length,2);
    assert.match(writes[1].sql,/AND password_hash = \$3/,'A failed send must not undo a later password reset');
    assert.deepEqual(writes[1].params,['old-hash','user','new-hash']);
   }
   if(scenario==='metadata_failure'){assert.equal(res.statusCode,500);assert.equal(mailed,1);assert.equal(writes.length,1,'Do not invalidate the password already delivered by email');}
   assert.equal(res.body.password,undefined);
  }finally{clearModule('../src/routes/rspApplications');console.error=oldError;restores.reverse().forEach(restore=>restore());}
 });
}
