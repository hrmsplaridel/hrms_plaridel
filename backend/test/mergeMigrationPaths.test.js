'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');

for(const service of ['rspIssuedForm','rspPreDeliberation','rspFinalHiring']) {
 test(`${service} points administrators to an existing upgrade script`,()=>{
  const source=fs.readFileSync(path.join(root,`backend/src/services/${service}.js`),'utf8');
  const migration=source.match(/const (?:ISSUED_FORM_MIGRATION|MIGRATION) = '([^']+)'/)[1];
  assert.ok(fs.existsSync(path.join(root,migration)),`Missing migration: ${migration}`);
 });
}
