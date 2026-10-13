const test = require('node:test');
const assert = require('node:assert/strict');
const { PDFDocument } = require('pdf-lib');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

async function pdf(width=841.89,height=595.28) {
  const doc=await PDFDocument.create();doc.addPage([width,height]).drawText('Locator');
  return Buffer.from(await doc.save());
}
test('locator backgrounds retain additional detail pages without shrinking their content',async()=>{
  const {mergeLocatorBackground}=require('../src/services/locatorPrintTemplates');
  const overlay=await PDFDocument.create();overlay.addPage([841.89,595.28]).drawText('Locator');
  overlay.addPage([595.28,841.89]).drawText('Additional answers');
  const output=await PDFDocument.load(await mergeLocatorBackground(await pdf(),await overlay.save()));
  assert.equal(output.getPageCount(),2);
  assert.ok(Math.abs(output.getPage(1).getWidth()-595.28)<1);
});
test('locator backgrounds accept both A4 orientations and preserve the background page size',async()=>{
  const {validateLocatorBackground,mergeLocatorBackground}=require('../src/services/locatorPrintTemplates');
  for(const [width,height] of [[595.28,841.89],[841.89,595.28]]) {
    const background=await validateLocatorBackground(await pdf(width,height),'application/pdf');
    const result=await PDFDocument.load(await mergeLocatorBackground(background,await pdf()));
    assert.equal(result.getPageCount(),1);
    assert.ok(Math.abs(result.getPage(0).getWidth()-width)<1);
    assert.ok(Math.abs(result.getPage(0).getHeight()-height)<1);
  }
  await assert.rejects(validateLocatorBackground(await pdf(300,300),'application/pdf'),/A4/);
  const original=await pdf();assert.deepEqual(await mergeLocatorBackground(null,original),original);
});
test('custom page layouts retain exact A4 coordinates instead of fitting the old slip',async()=>{
  const {mergeLocatorBackground}=require('../src/services/locatorPrintTemplates');
  const layout={version:1,orientation:'portrait',elements:[]};
  const bytes=await mergeLocatorBackground(await pdf(595.28,841.89),await pdf(595.28,841.89),layout);
  const output=await PDFDocument.load(bytes);assert.equal(output.getPageCount(),1);
  await assert.rejects(mergeLocatorBackground(await pdf(),await pdf(595.28,841.89),layout),/orientation/i);
});
test('saving layout creates a new version while keeping earlier request templates',async()=>{
  const calls=[];let values;
  const layout={version:1,orientation:'portrait',elements:[{id:'title',kind:'text',text:'TRAVEL ORDER',x:40,y:120,width:500,height:30,font_size:18}]};
  const res=await route('/types/:id','post',{params:{id:'type'},body:{print_layout:JSON.stringify(layout)},user:{id:'admin'}},async(sql,p)=>{
    calls.push(sql);if(sql.startsWith('SELECT t.'))return {rows:[{id:'old',print_layout:null}]};
    if(sql.startsWith('INSERT INTO')){values=p;return {rows:[{id:'new',print_layout:p[4]?JSON.parse(p[4]):null}]};}
    return {rows:[]};
  });
  assert.equal(res.code,200);assert.equal(res.body.print_layout.elements[0].text,'TRAVEL ORDER');
  assert.equal(JSON.parse(values[4]).elements[0].text,'TRAVEL ORDER');
  assert.ok(!calls.some(s=>s.startsWith('UPDATE locator_slips')));
});
test('new type layout preview uses unsaved background and does not write a template',async()=>{
  const layout={version:1,orientation:'portrait',elements:[{id:'title',kind:'text',text:'TRAVEL ORDER',x:40,y:120,width:500,height:30,font_size:18}]};
  const res=await route('/preview','post',{body:{print_layout:JSON.stringify(layout)},user:{id:'admin'},files:{
    file:[{buffer:await pdf(595.28,841.89)}],background:[{buffer:await pdf(595.28,841.89),mimetype:'application/pdf'}],
  }},async()=>{throw Error('Draft preview must not access the database for a new type');});
  assert.equal(res.code,200);assert.equal((await PDFDocument.load(res.body)).getPageCount(),1);
});
test('invalid layouts roll back before a template version is inserted',async()=>{
  const calls=[];const res=await route('/types/:id','post',{params:{id:'type'},body:{print_layout:'{"version":1,"orientation":"portrait","elements":[]}'},user:{id:'admin'}},async sql=>{
    calls.push(sql);return {rows:sql.startsWith('SELECT t.')?[{id:'old'}]:[]};
  });
  assert.equal(res.code,400);assert.ok(calls.includes('ROLLBACK'));assert.ok(!calls.some(s=>s.startsWith('INSERT INTO')));
});
test('active Mayor can render their direct-route form and inactive Mayor is denied',async()=>{
  const req={params:{id:'request'},body:{version_id:'saved'},file:{buffer:await pdf()},user:{id:'mayor',role:'mayor'}};
  const res=await route('/requests/:id/render','post',req,async(sql)=>{
    if(sql.includes("= 'mayor'"))return {rows:[{employee_id:'mayor',name:'Mayor'}]};
    assert.match(sql,/\$3='mayor' AND ls.final_review_route='mayor_direct'/);
    return {rows:[{version_id:'saved',background_pdf:null,print_layout:null}]};
  });
  assert.equal(res.code,200);
  const denied=await route('/requests/:id/render','post',req,async()=>({rows:[]}));assert.equal(denied.code,404);
});
async function route(path,method,req,query) {
  const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  clearModule('../src/routes/locatorPrintTemplates');
  try {
    const router=require('../src/routes/locatorPrintTemplates');
    const handler=router.stack.find(e=>e.route?.path===path&&e.route.methods[method]).route.stack.at(-1).handle;
    const res={code:200,status(n){this.code=n;return this;},json(b){this.body=b;return this;},set(){return this;},send(b){this.body=b;return this;}};
    await handler(req,res);return res;
  } finally {clearModule('../src/routes/locatorPrintTemplates');restore();}
}
test('locator background replacement appends a version without updating filed requests',async()=>{
  const calls=[];const buffer=await pdf();
  const res=await route('/types/:id','post',{params:{id:'type'},body:{},user:{id:'admin'},
    file:{buffer,mimetype:'application/pdf',originalname:'header.pdf'}},async(sql,p)=>{
      calls.push(sql);
      if(sql.startsWith('SELECT t.'))return {rows:[{id:'old'}]};
      if(sql.startsWith('INSERT INTO'))return {rows:[{id:'new',background_pdf:p[1],background_name:p[2]}]};
      return {rows:[]};
    });
  assert.equal(res.code,200);assert.equal(res.body.has_background,true);
  assert.equal(res.body.background_name,'header.pdf');assert.ok(calls.includes('COMMIT'));
  assert.ok(!calls.some(s=>s.startsWith('UPDATE locator_slips')));
});
test('unauthorized locator background access returns not found',async()=>{
  const res=await route('/requests/:id/render','post',{params:{id:'request'},body:{},user:{id:'other',role:'employee'}},async(sql)=>{
    assert.match(sql,/locator_allowed/);assert.match(sql,/locator_slip_department_reviewers/);return {rows:[]};
  });assert.equal(res.code,404);
});
test('render refuses a stale template version',async()=>{
  const res=await route('/requests/:id/render','post',{params:{id:'request'},body:{version_id:'old'},
    file:{buffer:await pdf()},user:{id:'owner',role:'employee'}},async()=>({rows:[{version_id:'new'}]}));
  assert.equal(res.code,409);
});
test('removing a background appends an empty version and retains earlier artwork',async()=>{
  const calls=[];let values;
  const res=await route('/types/:id','post',{params:{id:'type'},body:{remove_background:'true'},user:{id:'admin'}},async(sql,p)=>{
    calls.push(sql);
    if(sql.startsWith('SELECT t.'))return {rows:[{id:'old',background_pdf:Buffer.from('old artwork'),background_name:'old.pdf'}]};
    if(sql.startsWith('INSERT INTO')){values=p;return {rows:[{id:'new',background_pdf:p[1],background_name:p[2]}]};}
    return {rows:[]};
  });
  assert.equal(res.code,200);assert.equal(res.body.has_background,false);
  assert.equal(values[1],null);assert.equal(values[2],null);
  assert.ok(!calls.some(s=>s.startsWith('DELETE')||s.startsWith('UPDATE locator_print_template_versions')));
});
test('failed locator settings writes roll back',async()=>{
  const calls=[];
  const res=await route('/types/:id','post',{params:{id:'type'},body:{},user:{id:'admin'}},async(sql)=>{
    calls.push(sql);if(sql.startsWith('SELECT t.'))return {rows:[{id:'old'}]};
    if(sql.startsWith('INSERT INTO'))throw Error('write failed');return {rows:[]};
  });
  assert.equal(res.code,500);assert.ok(calls.includes('ROLLBACK'));assert.ok(!calls.includes('COMMIT'));
});
