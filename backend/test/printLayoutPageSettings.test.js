const test=require('node:test');const assert=require('node:assert/strict');const {PDFDocument}=require('pdf-lib');
const {normalizeLocatorPrintLayout}=require('../src/services/locatorPrintLayout');const {mergeLocatorBackground,validateLocatorBackground}=require('../src/services/locatorPrintTemplates');
const layout=(paper='long')=>({version:1,orientation:'portrait',paper_size:paper,margins:{top:36,right:36,bottom:36,left:36},font_family:'serif',default_font_size:14,elements:[{id:'title',kind:'text',text:'TRAVEL ORDER',x:40,y:40,width:400,height:90,font_size:48,font_family:'mono'}]});
test('paper, margins and typography persist with legacy layouts left unchanged',()=>{
 const result=normalizeLocatorPrintLayout(layout());assert.equal(result.paper_size,'long');assert.deepEqual(result.margins,layout().margins);assert.equal(result.font_family,'serif');assert.equal(result.elements[0].font_size,48);assert.equal(result.elements[0].font_family,'mono');
 const old=layout('a4');delete old.paper_size;delete old.margins;delete old.font_family;delete old.default_font_size;old.elements[0].font_size=20;delete old.elements[0].font_family;
 const legacy=normalizeLocatorPrintLayout(old);assert.equal(legacy.paper_size,undefined);assert.equal(legacy.font_family,undefined);
});
test('invalid paper, margins and fonts are rejected',()=>{
 for(const change of [v=>v.paper_size='unknown',v=>v.paper_size='',v=>v.paper_size=null,v=>v.paper_size='toString',v=>v.paper_size='constructor',v=>v.margins.left=-1,v=>v.margins.right=600,v=>v.elements[0].x=0,v=>v.font_family='remote-url',v=>v.elements[0].font_family='unknown',v=>v.default_font_size=0,v=>v.elements[0].font_size=73]){
 const value=layout();change(value);assert.throws(()=>normalizeLocatorPrintLayout(value),{status:400});
 }
});
test('custom backgrounds and overlays support A4, Letter, Long Bond and Legal',async()=>{
 for(const [paper,width,height] of [['a4',595.28,841.89],['letter',612,792],['long',612,936],['legal',612,1008]])for(const orientation of ['portrait','landscape']){
 const size=orientation==='portrait'?[width,height]:[height,width];const bg=await PDFDocument.create();bg.addPage(size).drawText('Header');const fg=await PDFDocument.create();fg.addPage(size).drawText('Content');
 const bytes=await validateLocatorBackground(await bg.save(),'application/pdf');const output=await PDFDocument.load(await mergeLocatorBackground(bytes,await fg.save(),{...layout(paper),orientation}));
 assert.deepEqual(output.getPage(0).getSize(),{width:size[0],height:size[1]});
 }
 const doc=await PDFDocument.create();doc.addPage([612,936]).drawText('Long');const bytes=await doc.save();await assert.rejects(()=>mergeLocatorBackground(null,bytes,layout('letter')),/paper size/);
});

test('large signature fonts need enough space for the name and position',()=>{const value=layout();value.elements=[{id:'sig',kind:'signature',source:'applicant',x:40,y:40,width:300,height:80,font_size:48}];assert.throws(()=>normalizeLocatorPrintLayout(value),{status:400});});
