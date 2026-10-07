const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const root=path.join(__dirname,'..');
test('fresh schema omits retired request tables and permission',()=>{
 const sql=fs.readFileSync(path.join(root,'scripts/init-schema.sql'),'utf8');
 assert.doesNotMatch(sql,/dtr_corrections|dtr_correction_attachments|dtr_correction_reviewer_configs|corrections_allowed/);
 assert.match(sql,/CREATE TABLE IF NOT EXISTS dtr_daily_summary/);
 assert.match(sql,/CREATE TABLE IF NOT EXISTS biometric_attendance_logs/);
});
test('access queries work without the retired permission column',async()=>{
 const {withMockedModule}=require('./helpers/moduleMocks');
 const restore=withMockedModule('../src/config/db',{pool:{}});
 const p=require.resolve('../src/middleware/dtrAccess');delete require.cache[p];
 try {const m=require(p);await m.loadDtrAccess('user',{query:async sql=>{assert.doesNotMatch(sql,/corrections_allowed/);return {rows:[{manage_allowed:true}]}}});assert.throws(()=>m.requireDtrFeatureIfAdmin('corrections_allowed'),/Unknown DTR feature/)}finally{delete require.cache[p];restore()}
});
