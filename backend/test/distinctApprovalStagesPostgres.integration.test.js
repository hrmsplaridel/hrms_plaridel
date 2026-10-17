'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('pg');
const { loadDepartmentApprover, finalQueueVisibilitySql } = require('../src/services/approvalStageSeparation');
const { listNotifications, countUnread } = require('../src/services/notificationService');
const { validateEmployeeUpdateTransition } = require('../src/services/leaveWorkflowRules');
const { assertFinalLeaveReviewer, resolveEligibleFinalReviewers } = require('../src/services/leaveFinalReviewerService');

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
      await db.query(`CREATE TEMP TABLE leave_requests(id uuid,user_id uuid,employee_id uuid,status text,
          final_review_route text DEFAULT 'hr',final_reviewer_user_id uuid);
        CREATE TEMP TABLE leave_request_history(id uuid,leave_request_id uuid,action text,acted_by uuid,acted_at timestamptz,
          from_status text,to_status text);
        CREATE TEMP TABLE locator_slips(id uuid,employee_id uuid,status text,dept_head_reviewer_id uuid);
        CREATE TEMP TABLE locator_slip_history(locator_slip_id uuid,from_status text,to_status text,created_at timestamptz);
        CREATE TEMP TABLE users(id uuid,full_name text,role text,is_active boolean);
        CREATE TEMP TABLE dtr_admin_access(admin_user_id uuid,leave_allowed boolean,locator_allowed boolean);
        CREATE TEMP TABLE primary_reviewer_designations(id uuid,employee_id uuid,scope_key text,
          position_title_snapshot text,is_active boolean,effective_from date,effective_to date);
        CREATE TEMP TABLE leave_final_reviewer_backups(employee_id uuid,is_active boolean,
          effective_from date,effective_to date,backup_rank integer);
        CREATE TEMP TABLE user_notifications(id uuid,user_id uuid,category text,type text,title text,body text,
          read_at timestamptz,reference_type text,reference_id uuid,metadata jsonb,created_at timestamptz);
      `);
      await db.query("INSERT INTO users VALUES($1,'Applicant','employee',true),($2,'Primary','admin',true),($3,'Backup','hr',true)",[applicant,earl,other]);
      await db.query("INSERT INTO primary_reviewer_designations VALUES(gen_random_uuid(),$1,'final_hr','HR Officer',true,'2000-01-01',null)",[earl]);
      await db.query("INSERT INTO leave_final_reviewer_backups VALUES($1,true,'2000-01-01',null,1)",[other]);
      await db.query("INSERT INTO leave_requests(id,user_id,employee_id,status) VALUES($1,$2,$2,'pending_hr')",[request,applicant]);
      await db.query("INSERT INTO locator_slips VALUES($1,$2,'pending_hr',$3)",[request,applicant,earl]);
      await db.query('ALTER TABLE pg_temp.leave_requests ADD COLUMN IF NOT EXISTS workflow_snapshot jsonb');
      await db.query('ALTER TABLE pg_temp.locator_slips ADD COLUMN IF NOT EXISTS workflow_snapshot jsonb');
      await db.query('ALTER TABLE pg_temp.leave_requests ADD COLUMN signature_revision integer');
      await db.query('ALTER TABLE pg_temp.locator_slips ADD COLUMN signature_revision integer');
      await db.query(`INSERT INTO leave_request_history(id,leave_request_id,action,acted_by,acted_at) VALUES
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
      const resubmission = validateEmployeeUpdateTransition({ currentStatus:'returned',desiredStatus:'pending' });
      assert.equal(resubmission.historyAction,'resubmitted');
      await db.query(`INSERT INTO leave_request_history(id,leave_request_id,action,acted_by,acted_at) VALUES(gen_random_uuid(),$1,$3,$2,'2026-10-09 10:00+08')`,[request,applicant,resubmission.historyAction]);
      await db.query('UPDATE locator_slips SET dept_head_reviewer_id=NULL');
      for (const kind of ['leave','locator']) assert.equal(await loadDepartmentApprover(db,kind,request),null);

      // Resubmitting does not itself change routing. This fixture represents a new
      // cycle already resolved to final HR by the normal submission handler.
      const queue=`SELECT id FROM leave_requests r WHERE ${finalQueueVisibilitySql('leave','r','$1::uuid')}`;
      assert.equal((await db.query(queue,[earl])).rows.length,1);
      await assertFinalLeaveReviewer(db,applicant,earl,'leave',request);
      assert.deepEqual((await resolveEligibleFinalReviewers(db,applicant,'leave',request)).map(r=>r.id),[earl,other]);
      assert.equal((await listNotifications(db,earl)).length,2);
      assert.equal(await countUnread(db,earl),2);
      await assert.rejects(assertFinalLeaveReviewer(db,applicant,applicant,'leave',request),{statusCode:403});

      // A new department decision restores separation for this cycle, using its
      // actual actor rather than carrying forward the old primary's decision.
      await db.query(`INSERT INTO leave_request_history(id,leave_request_id,action,acted_by,acted_at) VALUES(gen_random_uuid(),$1,'department_head_approved',$2,'2026-10-09 11:00+08')`,[request,other]);
      assert.equal(await loadDepartmentApprover(db,'leave',request),other);
      await assert.rejects(assertFinalLeaveReviewer(db,applicant,other,'leave',request),{statusCode:403});
      await assertFinalLeaveReviewer(db,applicant,earl,'leave',request);
      assert.deepEqual((await resolveEligibleFinalReviewers(db,applicant,'leave',request)).map(r=>r.id),[earl]);
      assert.equal((await db.query(queue,[other])).rows.length,0);
      assert.equal((await listNotifications(db,other)).filter(n=>n.reference_type==='leave_request').length,0);

      // Both supported rejection statuses use the same actual resubmission action.
      let hour=12;
      for (const currentStatus of ['rejected_by_department_head','rejected_by_hr']) {
        const transition=validateEmployeeUpdateTransition({currentStatus,desiredStatus:'pending'});
        assert.equal(transition.historyAction,'resubmitted');
        await db.query(`INSERT INTO leave_request_history(id,leave_request_id,action,acted_by,acted_at) VALUES(gen_random_uuid(),$1,$2,$3,$4::timestamptz)`,
          [request,transition.historyAction,applicant,`2026-10-09 ${hour++}:00+08`]);
        assert.equal(await loadDepartmentApprover(db,'leave',request),null,currentStatus);
        await assertFinalLeaveReviewer(db,applicant,other,'leave',request);
        assert.equal((await db.query(queue,[other])).rows.length,1);
        await db.query(`INSERT INTO leave_request_history(id,leave_request_id,action,acted_by,acted_at) VALUES(gen_random_uuid(),$1,'department_head_approved',$2,$3::timestamptz)`,
          [request,other,`2026-10-09 ${hour++}:00+08`]);
        await assert.rejects(assertFinalLeaveReviewer(db,applicant,other,'leave',request),{statusCode:403});
      }
      assert.equal((await db.query("SELECT count(*)::int AS n FROM leave_request_history WHERE action='department_head_approved'")).rows[0].n,4,
        'earlier department decisions remain in history');
      await db.query(`INSERT INTO leave_request_history(id,leave_request_id,action,acted_by,acted_at) VALUES
        (gen_random_uuid(),$1,'submitted',$2,'2026-10-09 16:00+08'),
        (gen_random_uuid(),$1,'signed',$3,'2026-10-09 17:00+08')`,[request,applicant,other]);
      assert.equal(await loadDepartmentApprover(db,'leave',request),null,'submitted remains a boundary; signing is not an endorsement');
      assert.equal((await db.query('SELECT status FROM leave_requests WHERE id=$1',[request])).rows[0].status,'pending_hr');
    } finally {await db.query('ROLLBACK');await db.end();}
  });
