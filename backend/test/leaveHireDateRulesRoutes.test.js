const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
async function withRoutes(rule, hireDate, run, usage=[]) {
 const query=async(sql,params=[])=>{
  if(sql.startsWith('SELECT id FROM leave_types'))return {rows:[{id:'type'}]};
  if(sql.includes('FROM leave_types'))return {rows:[{id:'type',name:'wellnessLeave',display_name:'Wellness Leave',entitlement_basis:'annual',max_days:5,balance_ledger_type:'none',...rule}]};
  if(sql.includes('FROM leave_requests') && (sql.includes('FOR UPDATE') || !sql.includes('JOIN'))) return {rows:[{id:'draft',employee_id:'employee',user_id:'employee',status:'draft',leave_type_id:'type',start_date:'2026-10-19',end_date:'2026-10-19'}]};
  if(sql.includes('FROM users') && sql.includes('date_hired'))return {rows:[{date_hired:hireDate,employment_type:'job_order'}]};
  if(sql.includes('FROM generate_series')) {
   const rows=[];for(let d=new Date(params[1]+'T12:00:00Z');d.toISOString().slice(0,10)<=params[2];d.setUTCDate(d.getUTCDate()+1))rows.push({attendance_date:d.toISOString().slice(0,10),working_days:[1,2,3,4,5],has_shift:true});
   return {rows};
  }
  if(sql.includes('SELECT lr.id, lr.start_date, lr.end_date, lr.status'))return {rows:usage};
  if(sql.includes('JOIN leave_types') && sql.includes('FROM leave_requests'))return {rows:usage.map(r=>({...r,leave_type:'wellnessLeave'}))};
  return {rows:[]};
 };
 const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
 const path='../src/routes/leaveRoutes';clearModule(path);
 try {
  const router=require(path);
  await run(async(routePath,req)=>{
   const route=router.stack.find(l=>l.route?.path===routePath && l.route.methods[req.method || 'get']).route;
   const res={code:200,status(c){this.code=c;return this;},json(body){this.body=body;return this;}};
   await route.stack.at(-1).handle({user:{id:'employee',role:'employee'},query:{},params:{userId:'employee',id:'draft'},...req},res);
   return res;
  });
 } finally {clearModule(path);restore();}
}
test('working-days preview uses the hire-year limit and January renewal',async()=>{
 await withRoutes({first_year_allowance:'prorated'},'2026-10-01',async get=>{
  for(const [year,limit] of [[2026,1],[2027,5]]) {
   const res=await get('/working-days',{query:{start_date:`${year}-11-02`,end_date:`${year}-11-03`,leave_type:'wellnessLeave'}});
   assert.equal(res.code,200);
   assert.equal(res.body.annual_entitlement.years[0].limit_days,limit);
   assert.equal(res.body.annual_entitlement.years[0].allowed,year===2027);
  }
 });
});
test('cross-year preview assigns a separate prorated and full-year allowance',async()=>{
 await withRoutes({first_year_allowance:'prorated'},'2026-10-01',async get=>{
  const res=await get('/working-days',{query:{start_date:'2026-12-31',end_date:'2027-01-04',leave_type:'wellnessLeave'}});
  assert.equal(res.code,200);
  assert.deepEqual(res.body.annual_entitlement.years.map(y=>[y.year,y.limit_days,y.requested_days]),[[2026,1,1],[2027,5,2]]);
 });
});
test('preview reports missing hire date for proration instead of granting five days',async()=>{
 await withRoutes({first_year_allowance:'prorated'},null,async get=>{
  const res=await get('/working-days',{query:{start_date:'2026-10-19',end_date:'2026-10-19',leave_type:'wellnessLeave'}});
  assert.equal(res.body.annual_entitlement.allowed,false);
  assert.match(res.body.annual_entitlement.years[0].error_message,/hire date.*HR/);
 });
});
test('preview reports eligibility date before and at the service anniversary',async()=>{
 await withRoutes({minimum_service_months:6},'2026-04-20',async get=>{
  for(const [day,eligible] of [['2026-10-19',false],['2026-10-20',true]]){
   const res=await get('/working-days',{query:{start_date:day,end_date:day,leave_type:'wellnessLeave'}});
   assert.equal(res.body.service_eligibility.eligible,eligible);
   assert.equal(res.body.service_eligibility.eligible_from,'2026-10-20');
  }
 });
});
test('balance summary applies the same rounded hire-year allowance as filing',async()=>{
 const year=Number(new Intl.DateTimeFormat('en',{year:'numeric',timeZone:'Asia/Manila'}).format(new Date()));
 await withRoutes({first_year_allowance:'prorated'},`${year}-10-01`,async get=>{
  const res=await get('/balances/:userId',{});
  assert.equal(res.code,200);
  assert.equal(res.body[0].earned_days,1);
  assert.equal(res.body[0].calculated_days,1.25);
 });
});

for (const routePath of ['/submit','/submit-with-attachment','/:id']) {
 test(`${routePath} cannot bypass minimum service`, async()=>{
  await withRoutes({minimum_service_months:6},'2026-10-01',async request=>{
   const res=await request(routePath,{method:routePath==='/:id'?'put':'post',
    body:{leave_type:'wellnessLeave',start_date:'2026-10-19',end_date:'2026-10-19',status:'pending',details:{}},
    file:{originalname:'test.pdf',mimetype:'application/pdf',buffer:Buffer.from('%PDF-1.4 test')}});
   assert.equal(res.code,400);
   assert.match(res.body.error,/eligible on 2027-04-01/);
  });
 });
}
