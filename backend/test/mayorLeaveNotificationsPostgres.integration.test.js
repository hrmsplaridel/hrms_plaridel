'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {Client}=require('pg');
const {randomUUID}=require('node:crypto');
const {listNotifications,countUnread}=require('../src/services/notificationService');

test('electronic Mayor leave alerts remain visible and unread while obsolete manual alerts stay hidden',
 {skip:!process.env.MAYOR_LEAVE_NOTIFICATION_TEST_DATABASE_URL},async()=>{
 const db=new Client({connectionString:process.env.MAYOR_LEAVE_NOTIFICATION_TEST_DATABASE_URL});
 await db.connect();
 try{
  await db.query('BEGIN');
  await db.query(`CREATE TEMP TABLE user_notifications(id uuid,user_id uuid,category text,type text,title text,body text,
    read_at timestamptz,reference_type text,reference_id uuid,metadata jsonb,created_at timestamptz);
   CREATE TEMP TABLE leave_requests(id uuid,status text,user_id uuid,employee_id uuid,final_review_route text,workflow_snapshot jsonb,signature_revision integer);
   CREATE TEMP TABLE locator_slips(id uuid,status text,employee_id uuid,dept_head_reviewer_id uuid,workflow_snapshot jsonb,signature_revision integer);
   CREATE TEMP TABLE leave_request_history(id uuid,leave_request_id uuid,action text,acted_by uuid,acted_at timestamptz,from_status text,to_status text);
   CREATE TEMP TABLE locator_slip_history(locator_slip_id uuid,from_status text,to_status text,created_at timestamptz);`);
  const mayor=randomUUID(),applicant=randomUUID(),electronic=randomUUID(),manual=randomUUID();
  await db.query(`INSERT INTO leave_requests VALUES($1,'pending_mayor',$3,$3,'mayor_direct',$4),
    ($2,'approved',$3,$3,'mayor',NULL)`,[electronic,manual,applicant,JSON.stringify({steps:['department','hr','mayor'],current_step:2,decisions:[]})]);
  for(const request of [electronic,manual]){
   for(const type of ['leave_pending_mayor','leave_forwarded_to_mayor']){
    await db.query(`INSERT INTO user_notifications VALUES($1,$2,'leave',$3,'Mayor approval','Review needed',NULL,'leave_request',$4,NULL,now())`,
     [randomUUID(),mayor,type,request]);
   }
  }
  const rows=await listNotifications(db,mayor);
  assert.equal(rows.length,2,'electronic Mayor alerts must not be hidden');
  assert.ok(rows.every(n=>n.reference_id===electronic));
  assert.equal(await countUnread(db,mayor),2);
  assert.equal((await listNotifications(db,mayor,{unreadOnly:true})).length,2);
  // Self-review alerts remain suppressed for an applicant.
  await db.query(`INSERT INTO user_notifications VALUES($1,$2,'leave','leave_pending_mayor','Review',NULL,NULL,'leave_request',$3,NULL,now())`,[randomUUID(),applicant,electronic]);
  assert.equal(await countUnread(db,applicant),0);
  assert.equal((await listNotifications(db,applicant)).length,0);
 }finally{await db.query('ROLLBACK');await db.end();}
});
