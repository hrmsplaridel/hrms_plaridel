'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {Client}=require('pg');
const {randomUUID}=require('node:crypto');
const engine=require('../src/services/approvalWorkflows');
const {reconcileReviewNotifications}=require('../src/services/reviewNotificationCompletion');
test('same-status workflow transitions complete previous alerts and reconcile delayed alerts in isolated tables',
 {skip:!process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL},async()=>{
 const db=new Client({connectionString:process.env.WORKFLOW_AUDIT_TEST_DATABASE_URL});await db.connect();
 try{
  await db.query('BEGIN');
  await db.query(`CREATE TEMP TABLE user_notifications(id uuid,user_id uuid,type text,reference_type text,reference_id uuid,
    metadata jsonb,read_at timestamptz,created_at timestamptz DEFAULT now());
   CREATE TEMP TABLE leave_requests(id uuid,status text,workflow_snapshot jsonb,signature_revision integer);
   CREATE TEMP TABLE locator_slips(LIKE leave_requests);
   CREATE TEMP TABLE leave_request_history(leave_request_id uuid,from_status text,to_status text,acted_at timestamptz);
   CREATE TEMP TABLE locator_slip_history(locator_slip_id uuid,from_status text,to_status text,created_at timestamptz);`);
  for(const kind of ['leave','locator']){
   const request=randomUUID(),reviewer=randomUUID(),oldAlert=randomUUID(),currentAlert=randomUUID(),delayedAlert=randomUUID(),legacyAlert=randomUUID();
   const snapshot={version:1,current_step:1,steps:[{label:'Department'},{label:'HR'}],decisions:[
    {step:0,actor_id:reviewer,action:'approve',acted_at:new Date().toISOString(),signature:{revision:1}},
   ]};
   const ref=kind==='leave'?'leave_request':'locator_slip';
   await db.query(`INSERT INTO ${engine.tableFor(kind)} VALUES($1,'pending_hr',$2,1)`,[request,JSON.stringify({...snapshot,current_step:0,decisions:[]})]);
   await db.query(`INSERT INTO user_notifications(id,user_id,type,reference_type,reference_id,metadata,created_at)
    VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute')`,[oldAlert,reviewer,`${kind}_pending_hr`,ref,request,JSON.stringify({workflow_approval:true,workflow_step:0,workflow_version:1,signature_revision:1})]);
   await engine.saveWorkflow(db,kind,request,snapshot);
   assert.ok((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[oldAlert])).rows[0].read_at,'Prior step alerts close even though pending_hr did not change');
   for(const [alert,step] of [[currentAlert,1],[delayedAlert,0]])await db.query(`INSERT INTO user_notifications(id,user_id,type,reference_type,reference_id,metadata)
    VALUES($1,$2,$3,$4,$5,$6)`,[alert,reviewer,`${kind}_pending_hr`,ref,request,JSON.stringify({workflow_approval:true,workflow_step:step,workflow_version:1,signature_revision:1})]);
   await db.query(`INSERT INTO user_notifications(id,user_id,type,reference_type,reference_id,metadata,created_at)
    VALUES($1,$2,$3,$4,$5,'{"workflow_approval":true}',now()-interval '1 minute')`,[legacyAlert,reviewer,`${kind}_pending_hr`,ref,request]);
   await reconcileReviewNotifications(db,reviewer);
   assert.equal((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[currentAlert])).rows[0].read_at,null);
   assert.ok((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[delayedAlert])).rows[0].read_at,'A delayed earlier-stage alert must not stay actionable');
   assert.ok((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[legacyAlert])).rows[0].read_at,'Pre-fix alerts without step metadata reconcile against saved decisions');
  }
 }finally{await db.query('ROLLBACK');await db.end();}
});
