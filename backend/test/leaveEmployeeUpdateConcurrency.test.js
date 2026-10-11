const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const desired of ['draft','pending']) for(const changed of ['pending_hr','approved','discarded']) {
 test(`stale ${desired} update cannot change ${changed} request`,async()=>{
 const queries=[];let released=false;const original={id:'request',status:'draft',employee_official_snapshot:{}};
 const client={async query(sql){queries.push(sql);if(sql==='BEGIN'||sql==='ROLLBACK'||sql.includes('pg_advisory_xact_lock'))return{rows:[]};if(sql.includes('FROM leave_requests')&&sql.includes('FOR UPDATE'))return {rows:changed==='discarded'?[]:[{...original,status:changed}]};throw Error('Unexpected query before locked status check');},release(){released=true}};
 const db=withMockedModule('../src/config/db',{pool:{query:async()=>({rows:[original]}),connect:async()=>client}});
 const path='../src/routes/leaveRoutes';clearModule(path);
 try {const route=require(path).stack.find(l=>l.route?.path==='/:id'&&l.route.methods.put).route;
 const res={code:200,status(n){this.code=n;return this},json(v){this.body=v}};
 await route.stack.at(-1).handle({user:{id:'employee'},params:{id:'request'},body:{status:desired,leave_type:'vacationLeave',start_date:'2026-11-02',end_date:'2026-11-03'}},res);
 assert.equal(res.code,changed==='discarded'?404:409);
 assert.ok(queries.some(q=>q.includes('FOR UPDATE')));
 assert.ok(queries.includes('ROLLBACK'));assert.ok(released);
 assert.ok(!queries.some(q=>/UPDATE leave_requests|INSERT INTO leave_balances|UPDATE leave_balances/.test(q)));
 }finally{clearModule(path);db()}
 });
}

test('two simultaneous submissions of one draft create one reservation',async()=>{
 const row={id:'request',status:'draft',user_id:'employee',employee_id:'employee',employee_official_snapshot:{}};
 let owner=null;const waiters=[];let pending=0,updates=0;const history=[];
 const pool={async query(sql){return {rows:sql.includes('FROM leave_requests')?[{...row}]:[]}},async connect(){const client={release(){},async query(sql,p=[]){
  if(sql==='COMMIT'||sql==='ROLLBACK'){if(owner===client){owner=null;waiters.shift()?.()}return{rows:[]}}
  if(sql.includes('FROM leave_requests')&&sql.includes('FOR UPDATE')){if(owner)await new Promise(r=>waiters.push(r));owner=client;return{rows:[{...row}]}}
  if(sql.startsWith('SELECT id FROM leave_types'))return{rows:[{id:'type'}]};
  if(sql.includes('SELECT *')&&sql.includes('FROM leave_types'))return{rows:[{id:'type',name:'vacationLeave',display_name:'Vacation Leave',employee_can_file:true,is_active:true,minimum_advance_days:0,balance_ledger_type:'vacationLeave',entitlement_basis:'accrual'}]};
  if(sql.includes('FROM generate_series'))return{rows:[{attendance_date:'2026-11-02',working_days:[1,2,3,4,5],has_assignment:true,has_shift:true},{attendance_date:'2026-11-03',working_days:[1,2,3,4,5],has_assignment:true,has_shift:true}]};
  if(sql.startsWith('SELECT balance_ledger_type'))return{rows:[{balance_ledger_type:'vacationLeave'}]};
  if(sql.includes('FROM leave_balances'))return{rows:[{earned_days:10,used_days:0,pending_days:pending,adjusted_days:0}]};
  if(sql.startsWith('UPDATE leave_requests')&&sql.includes('leave_type_id =')){assert.equal(owner,client);row.status=p[8];row.start_date=p[1];row.end_date=p[2];row.number_of_days=p[3];updates++;return{rows:[{...row}]}}
  if(sql.startsWith('UPDATE leave_balances'))pending+=p[2];
  return {rows:[]};
 }};return client}};
 const mocks=[];
 const mock=(p,value)=>mocks.push(withMockedModule(p,value));
 mock('../src/config/db',{pool});
 const details=require('../src/services/leaveRequestDetailsPolicy');mock('../src/services/leaveRequestDetailsPolicy',{...details,loadEmployeeOfficialSnapshot:async()=>({})});
 mock('../src/services/leaveFinalReviewerService',{assertLeaveSubmissionReviewer:async()=>{}});
 mock('../src/services/departmentHeadService',{getDepartmentReviewSnapshot:async()=>null});
 mock('../src/services/departmentReviewerService',{replaceRequestReviewerSnapshot:async()=>{}});
 mock('../src/services/leaveRequestHistory',{initLeaveRequestHistory:async()=>{},insertLeaveRequestHistory:async(_,h)=>history.push(h)});
 mock('../src/services/leaveBalanceLedger',{...require('../src/services/leaveBalanceLedger'),initLeaveBalanceLedger:async()=>{},insertLeaveBalanceLedger:async()=>{}});
 mock('../src/services/leaveNotifications',{notifyAfterSubmit:async()=>{}});
 const path='../src/routes/leaveRoutes';clearModule(path);
 try{const route=require(path).stack.find(l=>l.route?.path==='/:id'&&l.route.methods.put).route;
 const response=()=>({code:200,status(n){this.code=n;return this},json(v){this.body=v}});const a=response(),b=response();
 const req=()=>({user:{id:'employee'},params:{id:'request'},body:{status:'pending',leave_type:'vacationLeave',start_date:'2026-11-02',end_date:'2026-11-03',details:{location_option:'withinPhilippines',location_details:'Test'}}});
 await Promise.all([route.stack.at(-1).handle(req(),a),route.stack.at(-1).handle(req(),b)]);
 assert.deepEqual([a.code,b.code].sort(),[200,409]);assert.equal(updates,1);assert.equal(history.length,1);assert.equal(pending,2);
 }finally{clearModule(path);mocks.reverse().forEach(r=>r())}
});

