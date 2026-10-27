const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const EMPLOYEE='11111111-1111-4111-8111-111111111111',ACTOR='22222222-2222-4222-8222-222222222222';
test('staff route adapts full coverage, records the server actor and reports failures',async()=>{
  const submissions=[];
  const restoreDb=withMockedModule('../src/config/db',{pool:{connect:async()=>{},query:async sql=>({rows:String(sql).includes('FROM assignments')
    ? [{shift_id:'shift',shift_name:'Single',punch_mode:'single_session',working_days:[1,2,3,4,5]}] : [{id:EMPLOYEE}]})}});
  const restoreService=withMockedModule('../src/services/locatorSubmissionService',{createLocatorSubmissionService:()=>({submit:async input=>{submissions.push(input);return {id:'saved',status:'pending_hr'};}})});
  clearModule('../src/routes/locatorSlips');
  try{
    const router=require('../src/routes/locatorSlips');
    const route=router.stack.find(e=>e.route?.path==='/admin/file').route;
    const res={statusCode:200,status(code){this.statusCode=code;return this},json(data){this.body=data;return this}};
    // Role middleware executes before multipart handling and submission.
    route.stack[1].handle({user:{id:EMPLOYEE,role:'employee'}},res,()=>assert.fail('Employee bypassed staff guard'));
    assert.equal(res.statusCode,403);assert.equal(submissions.length,0);
    res.statusCode=200;
    await route.stack.at(-1).handle({user:{id:ACTOR,role:'hr'},body:{employee_ids:[EMPLOYEE],slip_date:'2026-10-12',request_type:'locator',office:'Office',reason:'Power outage',full_shift:true,filedBy:{id:EMPLOYEE}}},res);
    assert.equal(res.body.created,1);assert.equal(submissions[0].filedBy.id,ACTOR);
    assert.equal(submissions[0].amIn,true);assert.equal(submissions[0].pmOut,true);
    assert.equal(submissions[0].amOut,false);assert.equal(submissions[0].pmIn,false);
    await route.stack.at(-1).handle({user:{id:ACTOR,role:'hr'},body:{employee_ids:[ACTOR]}},res);
    assert.equal(res.statusCode,400);assert.equal(submissions.length,1);
  }finally{clearModule('../src/routes/locatorSlips');restoreService();restoreDb();}
});

test('staff employee picker can revalidate selected IDs for a changed date without search or page limits hiding them',async()=>{
  const {parseLocatorDateOnly}=require('../src/services/locatorFilingRules');
  const {validateStaffBatch}=require('../src/services/locatorStaffFiling');
  const calls=[];
  const controller=require('../src/modules/locator/controllers/staffFiling.controller')({
    parseLocatorDateOnly,validateStaffBatch,
    pool:{query:async(sql,params)=>{calls.push({sql,params});return {rows:[{id:EMPLOYEE,full_name:'Alice',total:1}]};}},
  });
  const response=()=>({statusCode:200,status(code){this.statusCode=code;return this;},json(body){this.body=body;return this;}});
  const res=response();
  await controller.listFilingEmployees({user:{id:ACTOR},query:{slip_date:'2026-10-29',employee_ids:JSON.stringify([EMPLOYEE]),search:'unrelated search',offset:'200'}},res);
  assert.equal(res.statusCode,200);
  assert.match(calls[0].sql,/u\.id\s*=\s*ANY\(\$5::uuid\[\]\)/);
  assert.deepEqual(calls[0].params,['2026-10-29',ACTOR,'',0,[EMPLOYEE]]);
  assert.equal(res.body.employees[0].id,EMPLOYEE);
  for(const employee_ids of ['invalid json','[]','["not-a-uuid"]']){
    const invalid=response();
    await controller.listFilingEmployees({user:{id:ACTOR},query:{slip_date:'2026-10-29',employee_ids}},invalid);
    assert.equal(invalid.statusCode,400);
  }
  assert.equal(calls.length,1,'Invalid selected IDs never reach the database');
  const normal=response();
  await controller.listFilingEmployees({user:{id:ACTOR},query:{slip_date:'2026-10-29',search:'HR',offset:'100'}},normal);
  assert.deepEqual(calls[1].params,['2026-10-29',ACTOR,'HR',100,null]);
});
