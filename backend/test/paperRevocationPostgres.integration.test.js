'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {Pool}=require('pg');
const id=n=>`77777777-7777-4777-8777-${String(n).padStart(12,'0')}`;
const response=()=>({code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}});
test('paper Leave and Locator revoke atomically, preserve evidence, reverse actual credits once, and queue historical reconciliation',
 {skip:!process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL},async()=>{
  const url=new URL(process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL);assert.match(url.pathname,/^\/hrms_workflow_audit_[a-f0-9]{16}$/);
  process.env.DATABASE_URL=url.toString();
  const db=new Pool({connectionString:url.toString(),max:4});
  try{
   await db.query(fs.readFileSync(path.join(__dirname,'../scripts/init-schema.sql'),'utf8'));
   for(const [n,role] of [[1,'hr'],[2,'employee'],[3,'admin']])await db.query("INSERT INTO users(id,email,password_hash,full_name,role) VALUES($1,$2,'test-only',$3,$4)",[id(n),`revoke${n}@test.local`,`Revoke Person ${n}`,role]);
   await db.query("INSERT INTO leave_types(id,name,balance_ledger_type) VALUES($1,'recordedPaidLeave','none')",[id(10)]);
   await db.query("INSERT INTO leave_balances(user_id,leave_type,earned_days,used_days) VALUES($1,'vacationLeave',20,2.5)",[id(2)]);
   const paper={source:'approved_paper',original_filing_date:'2020-01-01',approval_date:'2020-01-02',encoded_at:new Date().toISOString(),encoded_by:id(1),
    final_approver:{name:'Original Paper Mayor',position_title:'Mayor'},applicant:{user_id:id(2),name:'Employee',signature:{signature_asset_id:id(90),source:'saved_signature_copy',signature_image_base64:'frozen-original-ink'}}};
   const createLeave=async(n,record=paper)=>db.query(`INSERT INTO leave_requests(id,user_id,employee_id,leave_type_id,status,start_date,end_date,number_of_days,
     approved_days_with_pay,approved_at,attachment_path,paper_approval_record) VALUES($1,$2,$2,$3,'approved',$5::date,$5::date,1,1,'2020-01-02','signed-original.pdf',$4)`,[id(n),id(2),id(10),JSON.stringify(record),`2020-01-${String(n-18).padStart(2,'0')}`]);
   for(const n of [20,21,22,23])await createLeave(n,n===23?{...paper,encoded_at:'2020-01-01T00:00:00Z'}:paper);
   await db.query("INSERT INTO leave_balance_ledger(user_id,leave_type,action,affected_bucket,days_changed,related_leave_request_id) VALUES($1,'vacationLeave','leave_approved','used',0.5,$2)",[id(2),id(20)]);
   await db.query("INSERT INTO dtr_leave_coverage(leave_request_id,employee_id,attendance_date) VALUES($1,$2,'2020-01-02')",[id(20),id(2)]);
   await db.query("INSERT INTO dtr_daily_summary(employee_id,attendance_date,status,time_in) VALUES($1,'2020-01-02','present','2020-01-02T08:00:00+08')",[id(2)]);
   await db.query("INSERT INTO leave_attendance_deductions(user_id,service_month,posted_at) VALUES($1,'2020-01-01',now())",[id(2)]);
   const notices=[],refreshes=[];
   const deps={pool:db,LEAVE_REVOKE_WINDOW_MS:3*86400000,assertFinalLeaveReviewer:async()=>{throw Error('A paper reversal must not depend on current digital routing');},
    insertLeaveBalanceLedger:require('../src/services/leaveBalanceLedger').insertLeaveBalanceLedger,
    insertLeaveRequestHistory:require('../src/services/leaveRequestHistory').insertLeaveRequestHistory,
    removeApprovedLeaveCoverage:require('../src/services/leaveDtrCoverage').removeApprovedLeaveCoverage,
    toIsoDateStr:d=>typeof d==='string'?d.slice(0,10):`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`,
    mapLeaveRowToApi:row=>({...row,paper_approval_record:require('../src/modules/leave/services/paperSignatures').publicPaperRecord(row.paper_approval_record)}),
    notifySafe:f=>f(),leaveNotifications:{notifyEmployee:async(_db,event)=>notices.push(event)},
    broadcastDtrLeaveRefresh:(...a)=>refreshes.push(a),broadcastLeaveUpdated(){}
   };
   const revoke=require('../src/modules/leave/controllers/revoke.controller')(deps).revokeLeave;
   const invoke=async(n,user={id:id(1),role:'hr'},reason='The approved paper was recorded twice.')=>{
    const res=response();await revoke({user,params:{id:id(n)},body:{reason}},res);return res;
   };
   assert.equal((await invoke(20,{id:id(2),role:'employee'})).code,403);
   assert.equal((await invoke(20,{id:id(3),role:'admin'})).code,403,'Admin without leave permission cannot reverse a paper record');
   assert.equal((await invoke(20,undefined,'short')).code,400);
   assert.equal((await invoke(23)).code,409,'Original encoding time controls expiration');
   const results=await Promise.all([invoke(20),invoke(20)]);
   assert.deepEqual(results.map(r=>r.code).sort(),[200,409],'Concurrent revocation restores accounting only once');
   const saved=(await db.query('SELECT * FROM leave_requests WHERE id=$1',[id(20)])).rows[0];
   assert.equal(saved.status,'cancelled');assert.equal(saved.attachment_path,'signed-original.pdf');
   assert.deepEqual({...saved.paper_approval_record,revocation:undefined},{...paper,revocation:undefined});
   assert.equal(saved.paper_approval_record.revocation.restored_credit_days,0.5);
   assert.equal(saved.paper_approval_record.revocation.reconciliation_required,true);
   assert.equal((await db.query("SELECT used_days FROM leave_balances WHERE user_id=$1 AND leave_type='vacationLeave'",[id(2)])).rows[0].used_days,'2.000');
   assert.equal((await db.query("SELECT count(*)::int AS n FROM leave_balance_ledger WHERE related_leave_request_id=$1 AND action='leave_revoked'",[id(20)])).rows[0].n,1);
   assert.equal((await db.query('SELECT count(*)::int AS n FROM dtr_leave_coverage WHERE leave_request_id=$1',[id(20)])).rows[0].n,0);
   assert.equal((await db.query('SELECT count(*)::int AS n FROM dtr_daily_summary WHERE employee_id=$1 AND time_in IS NOT NULL',[id(2)])).rows[0].n,1);
   const free=await invoke(21);assert.equal(free.code,200);assert.equal(free.body.paper_approval_record.revocation.restored_credit_days,0);
   assert.equal((await db.query("SELECT used_days FROM leave_balances WHERE user_id=$1 AND leave_type='vacationLeave'",[id(2)])).rows[0].used_days,'2.000');
   assert.equal(notices.length,2);assert.equal(refreshes.length,2);
   // Fail at the end of the transaction: status, credit and coverage must all survive.
   await db.query("INSERT INTO leave_balance_ledger(user_id,leave_type,action,affected_bucket,days_changed,related_leave_request_id) VALUES($1,'vacationLeave','leave_approved','used',0.5,$2)",[id(2),id(22)]);
   const failing=require('../src/modules/leave/controllers/revoke.controller')({...deps,insertLeaveRequestHistory:async()=>{throw Error('Audit write failed');}}).revokeLeave;
   const failed=response();await failing({user:{id:id(1),role:'hr'},params:{id:id(22)},body:{reason:'The employee dates were incorrect.'}},failed);
   assert.equal(failed.code,500);assert.equal((await db.query('SELECT status FROM leave_requests WHERE id=$1',[id(22)])).rows[0].status,'approved');
   assert.equal((await db.query("SELECT used_days FROM leave_balances WHERE user_id=$1 AND leave_type='vacationLeave'",[id(2)])).rows[0].used_days,'2.000');
   // Locator uses its existing revoked status and keeps the signed original unchanged.
   await db.query("INSERT INTO locator_slips(id,employee_id,slip_date,office,reason,request_type,status,am_in,hr_reviewed_at,paper_approval_record,attachment_path) VALUES($1,$2,'2020-01-03','Office','Visit','locator','approved',true,'2020-01-02',$3,'locator-original.pdf')",[id(30),id(2),JSON.stringify(paper)]);
   const locator=require('../src/modules/locator/controllers/revoke.controller')({pool:db,
    evaluateLocatorRevocation(){throw Error('Paper uses recording time');},
    recordLocatorWorkflowEvent:require('../src/services/locatorWorkflowHistory').recordLocatorWorkflowEvent,
    fetchLocatorSlipDetails:async(pool,recordId)=>(await pool.query('SELECT * FROM locator_slips WHERE id=$1',[recordId])).rows[0],
    locatorNotifications:{notifyEmployee:async()=>{}},notifySafe:f=>f(),broadcastLocatorUpdated(){}
   }).revokeRequest;
   const callLocator=async(reason='The signed locator was recorded twice.')=>{const res=response();await locator({user:{id:id(1),role:'hr'},params:{id:id(30)},body:{revocation_reason:reason}},res);return res;};
   assert.equal((await callLocator('')).code,400);
   const loc=await callLocator();assert.equal(loc.code,200);assert.equal(loc.body.status,'revoked');assert.deepEqual(loc.body.paper_approval_record,paper);
   assert.equal(loc.body.attachment_path,'locator-original.pdf');assert.equal(loc.body.month_end_reconciliation_required,true);
   assert.equal((await callLocator()).code,409);
   assert.equal((await db.query("SELECT count(*)::int AS n FROM locator_slip_history WHERE locator_slip_id=$1 AND action='approval_revoked'",[id(30)])).rows[0].n,1);
   assert.ok((await db.query("SELECT 1 FROM dtr_month_end_reconciliation_queue WHERE employee_id=$1 AND service_month='2020-01-01' AND status='pending'",[id(2)])).rowCount);
  }finally{await db.end();}
});
