const test = require('node:test');
const assert = require('node:assert/strict');
const { PDFDocument } = require('pdf-lib');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

async function pdf(width=841.89,height=595.28) {
  const doc=await PDFDocument.create();doc.addPage([width,height]).drawText('Locator');
  return Buffer.from(await doc.save());
}
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
