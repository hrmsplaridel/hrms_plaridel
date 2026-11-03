'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const create=require('../src/modules/leave/controllers/staffFiling.controller');
const id=n=>`77777777-7777-4777-8777-${String(n).padStart(12,'0')}`;
function response(){return {code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};}
test('approved paper endpoint preserves the encoder and trusted employee identity',async()=>{
 const user={id:id(1),role:'admin'};let call;
 const handlers=create({}, {submitWithAttachment:async(req,res,target)=>{call={user:req.user,target};res.status(201).json({id:id(9),status:'approved',user_id:target});}});
 const res=response();await handlers.fileForEmployees({user,file:{buffer:Buffer.from('proof')},body:{employee_ids:[id(2)]}},res);
 assert.equal(res.body.created,1);assert.equal(res.body.results[0].request.status,'approved');assert.deepEqual(call,{user,target:id(2)});
});
test('paper recording rejects missing evidence, batch reuse, own leave and digital signatures',async()=>{
 let calls=0;const handlers=create({}, {submitWithAttachment:async()=>calls++});
 for(const [change,code] of [
  [{file:null},400],[{body:{employee_ids:[id(2),id(3)]}},400],
  [{body:{employee_ids:[id(1)]}},400],[{user:{id:id(1),role:'employee'}},403],
  [{body:{employee_ids:[id(2)],signature:{signature_asset_id:id(8)}}},400],
  [{body:{employee_ids:[id(2)],applicant_signature_asset_id:id(8)}},400],
 ]){const res=response();await handlers.fileForEmployees({user:{id:id(1),role:'admin'},file:{buffer:Buffer.from('proof')},body:{employee_ids:[id(2)]},...change},res);assert.equal(res.code,code);}
 assert.equal(calls,0);
});

test('signatory suggestions are HR-only and malformed employee dates fail safely',async()=>{
 const handlers=create({},{});
 const blocked=response();await handlers.paperSignatorySuggestions({user:{id:id(1),role:'employee'},query:{}},blocked);
 assert.equal(blocked.code,403);
 const invalid=response();await handlers.paperSignatorySuggestions({user:{id:id(1),role:'hr'},query:{employee_id:'bad'}},invalid);
 assert.equal(invalid.code,400);
});
