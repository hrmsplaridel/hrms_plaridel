'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('pg');
const { loadDepartmentApprover, finalQueueVisibilitySql } = require('../src/services/approvalStageSeparation');
const { listNotifications, countUnread } = require('../src/services/notificationService');

// Uses only temporary tables in a rollback transaction, never application rows.
test('PostgreSQL queues and old alerts respect the actual approver and resubmission cycle',
  {skip: !process.env.APPROVAL_STAGES_TEST_DATABASE_URL}, async () => {
    const db = new Client({connectionString:process.env.APPROVAL_STAGES_TEST_DATABASE_URL});
    await db.connect();
    const request='11111111-1111-4111-8111-111111111111';
    const applicant='22222222-2222-4222-8222-222222222222';
    const earl='33333333-3333-4333-8333-333333333333';
    const other='44444444-4444-4444-8444-444444444444';
    try {
      await db.query('BEGIN');
      await db.query(`CREATE TEMP TABLE leave_requests(id uuid,user_id uuid,employee_id uuid,status text);
        CREATE TEMP TABLE leave_request_history(id uuid,leave_request_id uuid,action text,acted_by uuid,acted_at timestamptz);
        CREATE TEMP TABLE locator_slips(id uuid,employee_id uuid,status text,dept_head_reviewer_id uuid);
        CREATE TEMP TABLE user_notifications(id uuid,user_id uuid,category text,type text,title text,body text,
          read_at timestamptz,reference_type text,reference_id uuid,metadata jsonb,created_at timestamptz);
      `);
      await db.query("INSERT INTO leave_requests VALUES($1,$2,$2,'pending_hr')",[request,applicant]);
      await db.query("INSERT INTO locator_slips VALUES($1,$2,'pending_hr',$3)",[request,applicant,earl]);
      await db.query(`INSERT INTO leave_request_history VALUES
        (gen_random_uuid(),$1,'submitted',$2,'2026-10-09 08:00+08'),
        (gen_random_uuid(),$1,'department_head_approved',$3,'2026-10-09 09:00+08')`,[request,applicant,earl]);
      for (const kind of ['leave','locator']) {
        assert.equal(await loadDepartmentApprover(db,kind,request),earl);
        const table=kind==='leave'?'leave_requests':'locator_slips';
        const query=`SELECT id FROM ${table} r WHERE ${finalQueueVisibilitySql(kind,'r','$1::uuid')}`;
        assert.equal((await db.query(query,[earl])).rows.length,0);
        assert.equal((await db.query(query,[other])).rows.length,1);
        for (const user of [earl,other,applicant]) {
          await db.query(`INSERT INTO user_notifications VALUES(gen_random_uuid(),$1,$2,$3,'Review',NULL,NULL,$4,$5,NULL,now())`,
            [user,kind,`${kind}_forwarded_to_hr`,kind==='leave'?'leave_request':'locator_slip',request]);
        }
      }
      assert.equal((await listNotifications(db,earl)).length,0);
      assert.equal(await countUnread(db,earl),0);
      assert.equal(await countUnread(db,applicant),0);
      assert.equal(await countUnread(db,other),2);
      await db.query(`INSERT INTO user_notifications VALUES(gen_random_uuid(),$1,'leave','leave_approved','Status',NULL,NULL,'leave_request',$2,NULL,now())`,[applicant,request]);
      assert.equal(await countUnread(db,applicant),1);
      await db.query(`INSERT INTO leave_request_history VALUES(gen_random_uuid(),$1,'submitted',$2,'2026-10-09 10:00+08')`,[request,applicant]);
      await db.query('UPDATE locator_slips SET dept_head_reviewer_id=NULL');
      for (const kind of ['leave','locator']) assert.equal(await loadDepartmentApprover(db,kind,request),null);
    } finally {await db.query('ROLLBACK');await db.end();}
  });
