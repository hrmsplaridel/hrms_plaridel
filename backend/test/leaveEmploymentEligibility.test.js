const test=require('node:test');
const assert=require('node:assert/strict');
const {normalizeEligibleEmploymentTypes,assertLeaveEmploymentEligibility}=require('../src/services/leaveEmploymentEligibility');
test('unconfigured eligibility preserves existing behavior and performs no employee query',async()=>{
  await assertLeaveEmploymentEligibility({query(){throw Error('Unexpected query');}},{eligible_employment_types:null},'employee');
});
test('configured eligibility uses the database employment type, not client input',async()=>{
  const rule={display_name:'Vacation Leave',eligible_employment_types:['permanent','contractual']};
  await assertLeaveEmploymentEligibility({query:async()=>({rows:[{employment_type:'contractual'}]})},rule,'employee');
  for(const type of ['job_order','regular',null]) {
    await assert.rejects(assertLeaveEmploymentEligibility({query:async()=>({rows:[{employment_type:type}]})},rule,'employee'),e=>e.statusCode===403);
  }
});
test('configuration accepts explicit reset, removes duplicates, rejects unknown and empty selections',()=>{
  assert.equal(normalizeEligibleEmploymentTypes(null),null);
  assert.deepEqual(normalizeEligibleEmploymentTypes(['permanent','permanent']),['permanent']);
  for(const value of [[],['unknown'],'permanent',[null]]) assert.throws(()=>normalizeEligibleEmploymentTypes(value),e=>e.statusCode===400);
});

const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const [path,method,omittedType,resubmit] of [['/draft','post',false],['/submit','post',false],['/submit-with-attachment','post',false],['/:id','put',false],['/:id','put',true],['/:id','put',false,true]]) {
  test(`${method} ${path} rejects ineligible employment before request writes (omittedType=${omittedType}, resubmit=${!!resubmit})`,async()=>{
    const statements=[];
    const query=async(sql)=>{
      statements.push(sql);
      if(sql.includes('FROM leave_requests')&&sql.includes('SELECT id, status')) return {rows:[{id:'request',status:resubmit?'returned':'draft',leave_type_id:'type'}]};
      if(sql.startsWith('SELECT id FROM leave_types')) return {rows:[{id:'type'}]};
      if(sql.includes('SELECT *')&&sql.includes('FROM leave_types')) return {rows:[{id:'type',name:'vacationLeave',eligible_employment_types:['permanent']}]};
      if(sql.includes('SELECT employment_type FROM users')) return {rows:[{employment_type:'job_order'}]};
      if(sql.includes('FROM generate_series')) return {rows:[{attendance_date:'2026-12-01',working_days:[1,2,3,4,5],has_assignment:true,has_shift:true}]};
      return {rows:[]};
    };
    const restores=[withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}}),
      withMockedModule('../src/services/leaveFinalReviewerService',{
        ...require('../src/services/leaveFinalReviewerService'),assertLeaveSubmissionReviewer:async()=>{},
      })];
    const modulePath='../src/routes/leaveRoutes';clearModule(modulePath);
    const error=console.error;console.error=()=>{};
    try{
      const router=require(modulePath);
      const route=router.stack.find(r=>r.route?.path===path&&r.route.methods[method]);
      const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;}};
      await route.route.stack.at(-1).handle({user:{id:'employee'},params:{id:'request'},
        body:{...(omittedType?{}:{leave_type:'vacationLeave'}),...(resubmit?{status:'pending'}:{}),start_date:'2026-12-01',end_date:'2026-12-01'},file:{buffer:Buffer.from('test'),originalname:'test.pdf'}},res);
      assert.equal(res.code,403);
      assert.match(res.body.error,/employment type/i);
      assert.equal(statements.some(s=>/^\s*(INSERT INTO|UPDATE) leave_requests/.test(s)),false);
    }finally{console.error=error;clearModule(modulePath);restores.reverse().forEach(r=>r());}
  });
}
