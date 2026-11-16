'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const {randomBytes}=require('node:crypto');
const png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
test('OJT legacy image is encrypted and bound to its form without inventing a verified signer',()=>{
 process.env.SIGNATURE_SECURITY_KEYS=JSON.stringify({active:'ojt-test',keys:{'ojt-test':randomBytes(32).toString('base64')}});
 const {sealOjtBaseline,decodeOjtEntry}=require('../src/services/ojtSignatureSecurity');
 const source={id:'test-form',school:'School',interviewer:'Historical name',interviewer_signature:png};
 const encrypted=sealOjtBaseline(source);
 assert.notEqual(encrypted, png);
 const decoded=decodeOjtEntry({...source,interviewer_signature:encrypted});
 assert.equal(decoded.interviewer_signature,png);assert.equal(decoded.signature_integrity_status,'legacy_baseline');
 assert.equal(decoded.signature_signer_id,null);
 const changed=decodeOjtEntry({...source,school:'Changed',interviewer_signature:encrypted});
 assert.equal(changed.interviewer_signature,null);assert.equal(changed.signature_integrity_status,'invalid');
});
test('material OJT edits invalidate an unchanged old signature instead of silently reapplying it',async()=>{
 const {sealOjtBaseline,secureOjtSave}=require('../src/services/ojtSignatureSecurity');
 const before={id:'test-form',school:'School',interviewer_signature:png};
 before.interviewer_signature=sealOjtBaseline(before);
 const calls=[];const db={query:async(sql,params)=>{calls.push({sql,params});return {rows:[]};}};
 const after=await secureOjtSave(db,{id:'admin'},before,{id:'test-form',school:'Changed',interviewer_signature:png});
 assert.equal(after.interviewer_signature,null);
 assert.ok(calls.some(call=>call.sql.includes('UPDATE ojt_work_immersion_evaluation_entries')&&call.params[1]===null));
});
