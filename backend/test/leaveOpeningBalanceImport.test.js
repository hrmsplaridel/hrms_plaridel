'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const {parseOpeningBalanceCsv,runOpeningBalanceImport}=require('../src/services/leaveOpeningBalanceImport');
const header='employee_number,cutoff_date,sick_leave_days,vacation_leave_days,qualifying_leave_days,reason';
const csv=`${header}\r\n001,2026-10-31,12.125,9,3,"Verified card, October"\r\n`;
test('CSV handles BOM, quotes and CRLF while retaining decimal precision',()=>{
 const rows=parseOpeningBalanceCsv('\ufeff'+csv);
 assert.equal(rows.length,1);assert.equal(rows[0].employee_number,'001');
 assert.equal(rows[0].sick_leave_days,'12.125');assert.equal(rows[0].reason,'Verified card, October');
});
test('CSV rejects malformed, oversized, missing/duplicate/unknown columns and empty imports',()=>{
 for(const value of ['',header,header+'\n"broken',header+'\n1,2',header.replace('reason','employee_number')+'\n1,2,3,4,5,6',
 header+',extra\n1,2,3,4,5,6,7', 'x'.repeat(262145),header+'\n'+Array(201).fill('1,2026-10-31,0,0,0,Source').join('\n')]){
  assert.throws(()=>parseOpeningBalanceCsv(value),e=>e.statusCode===400);
 }
});
test('employee numbers are exact, duplicate normalized IDs flag both rows, and nonstaff cannot import',async()=>{
 const db={connect:async()=>({query:async(sql)=>({rows:[]}),release(){}})};
 const result=await runOpeningBalanceImport(db,{actor:{id:'hr',role:'hr'},csv:csv+'1,2026-10-31,0,0,0,Source\n'});
 assert.equal(result.valid,false);assert.ok(result.rows.every(r=>r.error.includes('Duplicate')));
 const unknown=await runOpeningBalanceImport(db,{actor:{id:'hr',role:'hr'},csv});
 assert.match(unknown.rows[0].error,/not found/i);
 await assert.rejects(runOpeningBalanceImport(db,{actor:{id:'employee',role:'employee'},csv}),e=>e.statusCode===403);
 await assert.rejects(runOpeningBalanceImport(db,{actor:{id:'hr',role:'hr'},csv,commit:true}),/Confirm/);
});
