const test=require('node:test'); const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
function res(){return {code:200,status(n){this.code=n;return this;},json(b){this.body=b;return this;}};}
async function runRoute(path,method,req,query){
 const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
 clearModule('../src/routes/leavePrintTemplates');
 try {const router=require('../src/routes/leavePrintTemplates');
 const handler=router.stack.find(e=>e.route?.path===path&&e.route.methods[method]).route.stack.at(-1).handle;
 const response=res();await handler(req,response);return response;
 } finally {clearModule('../src/routes/leavePrintTemplates');restore();}
}
test('unauthorized employee cannot read another request template',async()=>{
 const response=await runRoute('/requests/:id','get',{params:{id:'req'},user:{id:'other',role:'employee'}},async()=>({rows:[]}));
 assert.equal(response.code,404);
});
test('print settings append a version and replace current pointer transactionally',async()=>{
 const statements=[];const query=async(sql,params)=>{
  statements.push(String(sql));
  if(String(sql).startsWith('SELECT lt.')) return {rows:[{id:'type',layout:'csc',background_pdf:null}]};
  if(String(sql).startsWith('INSERT INTO leave_print'))return {rows:[{id:'v2',layout:params[1],background_name:null}]};
  return {rows:[]};
 };
 const response=await runRoute('/types/:id','post',{params:{id:'type'},body:{layout:'wellness'},user:{id:'admin',role:'admin'}},query);
 assert.equal(response.code,200);assert.equal(response.body.layout,'wellness');
 assert.ok(statements.includes('COMMIT'));
 assert.ok(statements.some(s=>s.startsWith('UPDATE leave_types SET print_template_version_id')));
 assert.ok(!statements.some(s=>s.startsWith('UPDATE leave_print_template_versions')));
});
test('failed settings write rolls back without changing old versions',async()=>{
 const statements=[];
 const response=await runRoute('/types/:id','post',{params:{id:'type'},body:{layout:'bad'},user:{id:'admin',role:'admin'}},async(sql)=>{statements.push(String(sql));return {rows:[]};});
 assert.equal(response.code,400);assert.ok(!statements.some(s=>s.startsWith('INSERT')));
});

test('template upload stores normalized PDF in a new immutable version',async()=>{
 const {PDFDocument}=require('pdf-lib');const doc=await PDFDocument.create();doc.addPage([595.28,841.89]).drawText('Letterhead');
 const bytes=Buffer.from(await doc.save());let values;
 const response=await runRoute('/types/:id','post',{params:{id:'type'},body:{layout:'wellness'},user:{id:'admin'},
 file:{buffer:bytes,mimetype:'application/pdf',originalname:'letterhead.pdf'}},async(sql,params)=>{
 if(String(sql).startsWith('SELECT lt.'))return {rows:[{id:'type',layout:'csc'}]};
 if(String(sql).startsWith('INSERT INTO')){values=params;return {rows:[{id:'new',layout:'wellness',background_pdf:params[2],background_name:params[3]}]};}
 return {rows:[]};});
 assert.equal(response.code,200);assert.ok(Buffer.isBuffer(values[2]));assert.equal(values[3],'letterhead.pdf');
 assert.equal(response.body.has_background,true);
});

for (const employmentType of ['job_order','contract_of_service','permanent','temporary','casual','contractual','coterminous','regular',null]) {
 test(`Wellness form selection for ${employmentType}`,async()=>{
  const isJoCos=['job_order','contract_of_service'].includes(employmentType);
  const response=await runRoute('/requests/:id','get',{params:{id:'request'},user:{id:'owner',role:'employee'}},async(sql)=>{
   if(String(sql).startsWith('SELECT lr.'))return {rows:[{version_id:'version',layout:'wellness',
    employment_type:employmentType,background_pdf:Buffer.from('letterhead'),background_name:'HR_A4.pdf'}]};
   return {rows:[]};
  });
  assert.equal(response.code,200);
  assert.equal(response.body.layout,isJoCos?'wellness':'csc');
  assert.equal(response.body.has_background,isJoCos);
 });
}
