const test=require('node:test');const assert=require('node:assert/strict');
const {normalizeLeavePrintLayout}=require('../src/services/leavePrintLayout');
const {validateLayout,mergeBackground}=require('../src/services/leavePrintTemplates');
const {PDFDocument}=require('pdf-lib');
const layout=(source='working_days',kind='field')=>({version:1,orientation:'landscape',elements:[{id:'days',kind,source,x:50,y:180,width:180,height:75,font_size:10}]});
test('leave layout accepts leave fields, custom answers and certification signer',()=>{
 assert.equal(validateLayout('custom'),'custom');
 for(const source of ['working_days','inclusive_dates','custom:destination'])assert.equal(normalizeLeavePrintLayout(layout(source)).elements[0].source,source);
 assert.equal(normalizeLeavePrintLayout(layout('certification_officer','signature')).elements[0].source,'certification_officer');
});
test('leave layout rejects unknown sources, off-page geometry and duplicate ids',()=>{
 assert.throws(()=>normalizeLeavePrintLayout(layout('time_segments')),/source/);
 const bad=layout();bad.elements[0].x=800;assert.throws(()=>normalizeLeavePrintLayout(bad),/within/);
 const dup=layout();dup.elements.push({...dup.elements[0]});assert.throws(()=>normalizeLeavePrintLayout(dup),/unique/);
});
test('custom leave merge preserves landscape coordinates and continuation size',async()=>{
 const bg=await PDFDocument.create();bg.addPage([841.89,595.28]).drawText('Header');
 const fg=await PDFDocument.create();fg.addPage([841.89,595.28]).drawText('Employee',{x:52,y:300});fg.addPage([595.28,841.89]).drawText('Continuation');
 const bytes=await mergeBackground(await bg.save(),await fg.save(),{layout:'custom',printLayout:layout()});
 const out=await PDFDocument.load(bytes);assert.equal(out.getPageCount(),2);
 assert.equal(out.getPage(0).getWidth(),841.89);assert.equal(out.getPage(1).getHeight(),841.89);
 await assert.rejects(async()=>mergeBackground(await bg.save(),await fg.save(),{layout:'custom',printLayout:{...layout(),orientation:'portrait'}}),/orientation/);
});

