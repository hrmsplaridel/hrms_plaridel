const test = require('node:test');
const assert = require('node:assert/strict');
const {PDFDocument, StandardFonts} = require('pdf-lib');
const {validateBackground, mergeBackground, validateLayout} = require('../src/services/leavePrintTemplates');
async function pdf(width=595.28,height=841.89,pages=1) {
 const doc=await PDFDocument.create(); for(let i=0;i<pages;i++) doc.addPage([width,height]).drawText(" ");
 return Buffer.from(await doc.save());
}
test('only supported layouts are accepted',()=>{
 assert.equal(validateLayout('wellness'),'wellness');
 assert.equal(validateLayout('csc'),'csc');
 assert.throws(()=>validateLayout('arbitrary'),/layout/i);
});
test('templates must be readable single-page portrait A4',async()=>{
 assert.ok(await validateBackground(await pdf(),'application/pdf'));
 await assert.rejects(validateBackground(await pdf(600,400),'application/pdf'),/A4/);
 await assert.rejects(validateBackground(await pdf(595,842,2),'application/pdf'),/single/);
 await assert.rejects(validateBackground(Buffer.from('fake'),'application/pdf'),/PDF/);
});
test('merge preserves letterhead and overlays content on one A4 page',async()=>{
 const background=await pdf(); const doc=await PDFDocument.create();
 const font=await doc.embedFont(StandardFonts.Helvetica);
 doc.addPage([595.28,841.89]).drawText('Employee Example',{x:50,y:500,font});
 const result=await mergeBackground(background,await doc.save());
 assert.equal((await PDFDocument.load(result)).getPageCount(),1);
 assert.equal((await PDFDocument.load(await mergeBackground(background,await pdf(595,842,2)))).getPageCount(),2);
});
