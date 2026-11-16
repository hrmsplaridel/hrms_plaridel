'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const png = Buffer.from('89504e470d0a1a0a01', 'hex');
let old;
test.beforeEach(() => { old=process.env.SIGNATURE_SECURITY_KEYS; process.env.SIGNATURE_SECURITY_KEYS=JSON.stringify({active:'v1',keys:{v1:crypto.randomBytes(32).toString('base64')}}); });
test.afterEach(() => { if(old===undefined)delete process.env.SIGNATURE_SECURITY_KEYS;else process.env.SIGNATURE_SECURITY_KEYS=old; });
test('receipt verifies the signed contents and rejects changed text, signer, image or revision', async () => {
  const { recordSignatureEvidence, verifySignatureEvidence } = require('../src/services/signatureIntegrity');
  let content={id:'request',reason:'Attend meeting',employee_id:'employee',signature_revision:1}, receipt;
  const db={query:async(sql,params)=>{
    if(sql.includes('signature-integrity-content'))return {rows:[{content}]};
    if(sql.includes('FROM docutracker_signature_assets'))return {rows:[{id:'asset',owner_user_id:'signer',mime_type:'image/png',image_bytes:png}]};
    if(sql.includes('INSERT INTO signature_integrity_receipts')) {receipt=JSON.parse(params[1]);return {rows:[]};}
    if(sql.includes('FROM signature_integrity_receipts'))return {rows:receipt?[{sealed_manifest:receipt}]:[]};
    throw Error('Unexpected integrity query');
  }};
  const context={scope:'leave_requests',recordId:'request',slot:'applicant',revision:1};
  const row={signature_asset_id:'asset',signed_by:'signer',signed_at:'2026-11-16T12:00:00.000Z',signature_image_base64:png.toString('base64')};
  await recordSignatureEvidence(db,{...context,row,baseline:true});
  assert.equal(await verifySignatureEvidence(db,context,row),'legacy_baseline');
  content={...content,reason:'Changed purpose'};
  await assert.rejects(verifySignatureEvidence(db,context,row),/integrity/i);
  content={...content,reason:'Attend meeting'};
  for(const changed of [{signed_by:'other'},{signature_asset_id:'other'},{signature_image_base64:Buffer.from('different').toString('base64')}]) {
    await assert.rejects(verifySignatureEvidence(db,context,{...row,...changed}),/integrity/i);
  }
  await assert.rejects(verifySignatureEvidence(db,{...context,revision:2},row),/integrity/i);
  receipt=null;
  await assert.rejects(verifySignatureEvidence(db,context,row),/integrity/i);
});
test('review progress can change without changing the applicant-signed content', () => {
  const { projectContent } = require('../src/services/signatureIntegrity');
  const source={id:'request',reason:'Meeting',start_date:'2026-11-17',status:'pending_hr',updated_at:'before',approved_days_with_pay:0};
  assert.deepEqual(projectContent('leave_requests',source),projectContent('leave_requests',{...source,status:'approved',updated_at:'after',approved_days_with_pay:1}));
  assert.notDeepEqual(projectContent('leave_requests',source),projectContent('leave_requests',{...source,start_date:'2026-11-18'}));
});
