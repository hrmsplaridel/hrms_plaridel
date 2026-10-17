const test=require('node:test');const assert=require('node:assert/strict');const {Client}=require('pg');const {randomUUID}=require('node:crypto');
const {completeReviewNotifications,reconcileReviewNotifications}=require('../src/services/reviewNotificationCompletion');
test('review alerts close by stage, rollback atomically, and repair older rounds without reading applicant outcomes',
 {skip:!process.env.REVIEW_NOTIFICATION_TEST_DATABASE_URL},async()=>{
 const db=new Client({connectionString:process.env.REVIEW_NOTIFICATION_TEST_DATABASE_URL});await db.connect();
 const schema='review_notification_test_'+randomUUID().replaceAll('-','');
 try{
  await db.query(`CREATE SCHEMA ${schema}`);await db.query(`SET search_path TO ${schema},public`);
  await db.query(`CREATE TABLE user_notifications(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),user_id UUID,type TEXT,reference_type TEXT,reference_id UUID,read_at TIMESTAMPTZ,created_at TIMESTAMPTZ DEFAULT now(),metadata JSONB);
   CREATE TABLE leave_requests(id UUID PRIMARY KEY,status TEXT,workflow_snapshot JSONB,signature_revision integer);
   CREATE TABLE locator_slips(id UUID PRIMARY KEY,status TEXT,workflow_snapshot JSONB,signature_revision integer);
   CREATE TABLE leave_request_history(leave_request_id UUID,from_status TEXT,to_status TEXT,acted_at TIMESTAMPTZ);
   CREATE TABLE locator_slip_history(locator_slip_id UUID,from_status TEXT,to_status TEXT,created_at TIMESTAMPTZ);`);
  const request=randomUUID(), user=randomUUID(), backup=randomUUID();
  await db.query("INSERT INTO leave_requests VALUES($1,'pending_department_head')",[request]);
  const insert=async(type,owner=user,date='2026-01-01')=>(await db.query(`INSERT INTO user_notifications(user_id,type,reference_type,reference_id,created_at)VALUES($1,$2,'leave_request',$3,$4)RETURNING id`,[owner,type,request,date])).rows[0].id;
  const head=await insert('leave_pending_department_head'), back=await insert('leave_pending_department_head',backup);
  const applicant=await insert('leave_approved');
  await db.query('BEGIN');await db.query("UPDATE leave_requests SET status='pending_hr' WHERE id=$1",[request]);
  await completeReviewNotifications(db,'leave_request',request,'pending_department_head','pending_hr');await db.query('COMMIT');
  const hr=await insert('leave_forwarded_to_hr',user,new Date());
  let rows=(await db.query('SELECT * FROM user_notifications')).rows;
  assert.ok(rows.find(n=>n.id===head).read_at);assert.ok(rows.find(n=>n.id===back).read_at);
  assert.equal(rows.find(n=>n.id===hr).read_at,null);assert.equal(rows.find(n=>n.id===applicant).read_at,null);
  await db.query('BEGIN');await completeReviewNotifications(db,'leave_request',request,'pending_hr','approved');await db.query('ROLLBACK');
  assert.equal((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[hr])).rows[0].read_at,null);
  await db.query("UPDATE leave_requests SET status='approved' WHERE id=$1",[request]);
  await reconcileReviewNotifications(db,user);
  assert.ok((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[hr])).rows[0].read_at);
  assert.equal((await db.query('SELECT read_at FROM user_notifications WHERE id=$1',[applicant])).rows[0].read_at,null);
  await db.query("UPDATE leave_requests SET status='pending_department_head' WHERE id=$1",[request]);
  await db.query("INSERT INTO leave_request_history VALUES($1,'pending_department_head','returned','2026-01-02')",[request]);
  const old=await insert('leave_pending_department_head'), fresh=await insert('leave_pending_department_head',user,new Date());
  const untouched=await insert('leave_pending_department_head',backup);
  await reconcileReviewNotifications(db,user);
  rows=(await db.query('SELECT * FROM user_notifications')).rows;
  assert.ok(rows.find(n=>n.id===old).read_at);assert.equal(rows.find(n=>n.id===fresh).read_at,null);
  assert.equal(rows.find(n=>n.id===untouched).read_at,null);
 }finally{await db.query('ROLLBACK');await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);await db.end();}
});
