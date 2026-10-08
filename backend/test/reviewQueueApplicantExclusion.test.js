const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const kind of ['leave','locator']) {
 test(`${kind} review rows, counts and filter options exclude the authenticated applicant`,async()=>{
  const seen=[];
  const query=async(sql,params=[])=>{if(sql.includes(kind==='leave'?'FROM leave_requests lr':'FROM locator_slips ls'))seen.push({sql,params});return{rows:sql.includes('COUNT(*)')?[{total:0}]:[]}};
  const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  const path=kind==='leave'?'../src/routes/leaveRoutes':'../src/routes/locatorSlips';clearModule(path);
  try{const router=require(path);for(const routePath of kind==='leave'?['/','/filter-options','/pending','/department-head','/department-head/filter-options']:['/admin','/department-head']) {
   seen.length=0;
   const res={code:200,status(n){this.code=n;return this},json(v){this.body=v}};
   await router.stack.find(l=>l.route?.path===routePath&&l.route.methods.get).route.stack.at(-1).handle({user:{id:'reviewer',role:'admin'},query:{paginated:'true'}},res);
   assert.equal(res.code,200);assert.ok(seen.length>0);
   for(const {sql,params} of seen){
    if(kind==='leave')assert.match(sql,/COALESCE\(lr.user_id, lr.employee_id\) <> \$\d+::uuid/);
    else assert.match(sql,/ls.employee_id <> \$\d+::uuid/);
    assert.ok(params.includes('reviewer'));
   }
  }}finally{clearModule(path);restore()}
 });
}
test('old leave self-review alerts are filtered from list and unread count',async()=>{
 const service=require('../src/services/notificationService');const db={query:async(sql)=>{
 assert.match(sql,/leave_pending_hr/);assert.match(sql,/leave_forwarded_to_hr/);assert.match(sql,/leave_pending_department_head/);
 assert.match(sql,/COALESCE\(lr.user_id, lr.employee_id\) = user_notifications.user_id/);return{rows:[]};
 }};await service.listNotifications(db,'reviewer');await service.countUnread(db,'reviewer');
});
