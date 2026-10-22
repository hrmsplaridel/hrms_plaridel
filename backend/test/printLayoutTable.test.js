const test=require('node:test');const assert=require('node:assert/strict');
const {normalizeLocatorPrintLayout}=require('../src/services/locatorPrintLayout');
const {normalizeLeavePrintLayout}=require('../src/services/leavePrintLayout');
const table=()=>({version:1,orientation:'portrait',elements:[{id:'summary',kind:'table',x:40,y:180,width:400,height:120,font_size:11,header_row:true,borders:true,column_widths:[1,2],cells:[[{kind:'text',text:'Employee'},{kind:'text',text:'Destination'}],[{kind:'field',source:'employee_name'},{kind:'field',source:'custom:destination'}]]}]});
test('table layout stores editable cells, column widths, headers and borders',()=>{
 const value=normalizeLocatorPrintLayout(JSON.stringify(table()));assert.equal(value.elements[0].kind,'table');assert.deepEqual(value.elements[0].column_widths,[1,2]);assert.equal(value.elements[0].cells[1][1].source,'custom:destination');
 const leave=table();leave.elements[0].cells[1][1].source='working_days';assert.equal(normalizeLeavePrintLayout(leave).elements[0].cells[1][1].source,'working_days');
});
test('table rejects ragged, oversized, unsafe and unreadable cells before save',()=>{
 for(const change of [v=>v.cells[1].pop(),v=>v.cells=Array(13).fill(v.cells[0]),v=>v.cells[1][1].source='password_hash',v=>v.cells[0][0].text='x'.repeat(501),v=>v.column_widths=[0,1],v=>v.column_widths=[1],v=>v.height=20,v=>v.column_widths=[.1,10],v=>v.cells[0][0]={kind:'signature',source:'applicant'}]){
 const value=table();change(value.elements[0]);assert.throws(()=>normalizeLocatorPrintLayout(value),{status:400});
 }
});
test('layout payload size is validated before the database constraint',()=>{
 const value=table();value.elements=Array.from({length:60},(_,i)=>({...value.elements[0],id:`table_${i}`,cells:Array.from({length:12},()=>[{kind:'text',text:'x'.repeat(500)},{kind:'text',text:'x'.repeat(500)}]),height:360}));
 assert.throws(()=>normalizeLocatorPrintLayout(value),/100 KB/);
});
