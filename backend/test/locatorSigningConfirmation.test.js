'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const create=require('../src/modules/locator/controllers/submit.controller');
test('locator submission preserves signing confirmation responses and cleans rolled-back uploads',async()=>{
 const removed=[];
 const controllers=create({LOCATOR_ATTACHMENT_SUBDIR:'locator',boolField:v=>v===true,
  normalizeRequestType:v=>v,removeLocatorAttachmentFile:v=>removed.push(v),
  locatorSubmissionService:{submit:async()=>{throw Object.assign(new Error('Confirm your password.'),{statusCode:428,code:'SIGNATURE_AUTHORIZATION_REQUIRED'});}}});
 for(const method of ['submitRequest','submitWithAttachment']){
  const res={statusCode:200,status(v){this.statusCode=v;return this;},json(v){this.body=v;return this;}};
  await controllers[method]({user:{id:'employee'},body:{},file:{filename:'rolled-back.pdf'}},res);
  assert.equal(res.statusCode,428);assert.equal(res.body.code,'SIGNATURE_AUTHORIZATION_REQUIRED');
 }
 assert.deepEqual(removed,['locator/rolled-back.pdf']);
});
