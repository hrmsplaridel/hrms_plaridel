const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('locator coverage is scoped to the authenticated employee and selected date',async()=>{
 let params;
 const restore=withMockedModule('../src/config/db',{pool:{async connect(){throw Error('Unexpected transaction');},async query(sql,p){
  if(!sql.includes('FROM assignments a')) return {rows:[]};
  params=p;return {rows:[{shift_id:'s',shift_name:'Single',working_days:[1,2,3,4,5],punch_mode:'single_session'}]};
 }}});
 clearModule('../src/routes/locatorSlips');
 try {
  const router=require('../src/routes/locatorSlips');
  const handler=router.stack.find(e=>e.route?.path==='/shift-coverage').route.stack.at(-1).handle;
  const res={code:200,status(n){this.code=n;return this;},json(b){this.body=b;return this;}};
  await handler({user:{id:'owner'},query:{slip_date:'2026-10-12',employee_id:'someone-else'}},res);
  assert.deepEqual(params,['owner','2026-10-12']);assert.equal(res.body.single_session,true);
  assert.deepEqual(res.body.allowed_slots,['am_in','pm_out']);
  await handler({user:{id:'owner'},query:{slip_date:'bad'}},res);assert.equal(res.code,400);
 }finally{clearModule('../src/routes/locatorSlips');restore();}
});
