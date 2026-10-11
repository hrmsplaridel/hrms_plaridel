const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('manual credit adjustments exclude JO/COS and disabled credits, including historical balances',()=>{
 const {canAdjustLeaveCredits}=require('../src/services/leaveCreditAdjustmentEligibility');
 for(const employment_type of ['job_order','contract_of_service']) {
  assert.equal(canAdjustLeaveCredits({employment_type,leave_credit_eligible:true}),false);
 }
 assert.equal(canAdjustLeaveCredits({employment_type:'permanent',leave_credit_eligible:false}),false);
 assert.equal(canAdjustLeaveCredits({employment_type:'permanent',leave_credit_eligible:true}),true);
});
for(const filtered of [true,false])test(`adjustment employee filtering applies only when requested: ${filtered}`,async()=>{
 const queries=[];
 const restore=withMockedModule('../src/config/db',{pool:{async query(sql){queries.push(sql);return {rows:sql.includes('COUNT(*)')?[{c:0}]:[]};}}});
 clearModule('../src/routes/employees');
 try {
  const handler=require('../src/routes/employees').stack.find(l=>l.route?.path==='/'&&l.route.methods.get).route.stack.at(-1).handle;
  const res={status(){return this;},json(){}};
  await handler({user:{id:'admin',role:'admin'},query:{status:'Active',limit:'100',...(filtered?{credit_adjustment:'true'}:{})}},res);
  assert.equal(queries.length,2);
  for(const sql of queries)assert.equal(sql.includes("'job_order', 'contract_of_service'"),filtered);
 }finally{clearModule('../src/routes/employees');restore();}
});
for(const employee of [{employment_type:'job_order',leave_credit_eligible:true},{employment_type:'contract_of_service',leave_credit_eligible:false},{employment_type:'permanent',leave_credit_eligible:false}]) {
 test(`adjustment API rejects ineligible employee ${employee.employment_type} without balance writes`,async()=>{
  const calls=[];const query=async(sql)=>{calls.push(sql);return {rows:sql.includes('FROM users')?[employee]:[]};};
  const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  clearModule('../src/routes/leaveRoutes');
  try {
   const router=require('../src/routes/leaveRoutes');
   const handler=router.stack.find(l=>l.route?.path==='/balances/:userId/adjustments'&&l.route.methods.post).route.stack.at(-1).handle;
   const res={code:200,status(n){this.code=n;return this;},json(b){this.body=b;return this;}};
   await handler({params:{userId:'employee'},user:{id:'hr',role:'hr'},body:{leave_type:'vacationLeave',adjustment_days:1,remarks:'Correction'}},res);
   assert.equal(res.code,400);assert.match(res.body.error,/not eligible/i);
   assert.ok(calls.includes('ROLLBACK'));assert.ok(!calls.some(s=>/INSERT INTO leave_balances|UPDATE leave_balances|INSERT INTO leave_balance_ledger/.test(s)));
  }finally{clearModule('../src/routes/leaveRoutes');restore();}
 });
}

test('credit-eligible employees retain the audited adjustment endpoint',async()=>{
 const calls=[];let adjustment;
 const query=async(sql)=>{calls.push(sql);return {rows:sql.includes('FROM users')?[{employment_type:'permanent',leave_credit_eligible:true,full_name:'Eligible Employee'}]:[]};};
 const restoreDb=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
 const restoreLedger=withMockedModule('../src/services/leaveBalanceLedger',{
  ...require('../src/services/leaveBalanceLedger'),
  async applyAdminLeaveBalanceAdjustment(_db,input){adjustment=input;return {row:{user_id:input.userId,leave_type:input.leaveType,adjusted_days:1}};},
 });
 clearModule('../src/routes/leaveRoutes');
 try {
  const router=require('../src/routes/leaveRoutes');
  const handler=router.stack.find(l=>l.route?.path==='/balances/:userId/adjustments'&&l.route.methods.post).route.stack.at(-1).handle;
  const res={code:200,status(n){this.code=n;return this;},json(b){this.body=b;return this;}};
  await handler({params:{userId:'employee'},user:{id:'hr',role:'hr'},body:{leave_type:'vacationLeave',adjustment_days:1,remarks:'Correction'}},res);
  assert.equal(res.code,201);assert.equal(adjustment.userId,'employee');assert.ok(calls.includes('COMMIT'));
 }finally{clearModule('../src/routes/leaveRoutes');restoreLedger();restoreDb();}
});
