const test = require('node:test');
const assert = require('node:assert/strict');
const {Client} = require('pg');
const {assertLeaveSubmissionReviewer,assertDepartmentApprovalFinalReviewer} = require('../src/services/leaveFinalReviewerService');

test('PostgreSQL readiness requires a distinct active reviewer with the relevant module access',
  {skip:!process.env.APPROVAL_STAGES_TEST_DATABASE_URL}, async () => {
    const db=new Client({connectionString:process.env.APPROVAL_STAGES_TEST_DATABASE_URL});
    await db.connect();
    const applicant='11111111-1111-4111-8111-111111111111';
    const head='22222222-2222-4222-8222-222222222222';
    const backup='33333333-3333-4333-8333-333333333333';
    const departmentBackup='44444444-4444-4444-8444-444444444444';
    const request='55555555-5555-4555-8555-555555555555';
    const snapshot={departmentHeadUserId:head,reviewerUserIds:[head]};
    try {
      await db.query('BEGIN');
      await db.query(`CREATE TEMP TABLE users(id uuid,full_name text,role text,is_active boolean);
        CREATE TEMP TABLE dtr_admin_access(admin_user_id uuid,leave_allowed boolean,locator_allowed boolean);
        CREATE TEMP TABLE primary_reviewer_designations(id uuid,employee_id uuid,scope_key text,
          position_title_snapshot text,is_active boolean,effective_from date,effective_to date);
        CREATE TEMP TABLE leave_final_reviewer_backups(employee_id uuid,is_active boolean,
          effective_from date,effective_to date,backup_rank int);
        CREATE TEMP TABLE leave_requests(id uuid,user_id uuid,employee_id uuid,status text,
          final_review_route text,final_reviewer_user_id uuid);
        CREATE TEMP TABLE locator_slips(id uuid,employee_id uuid,status text,final_review_route text,dept_head_reviewer_id uuid);
        CREATE TEMP TABLE leave_request_history(id uuid,leave_request_id uuid,action text,acted_by uuid,acted_at timestamptz);`);
      await db.query('ALTER TABLE pg_temp.leave_requests ADD COLUMN IF NOT EXISTS workflow_snapshot jsonb');
      await db.query('ALTER TABLE pg_temp.locator_slips ADD COLUMN IF NOT EXISTS workflow_snapshot jsonb');
      await db.query("INSERT INTO users VALUES($1,'Applicant','employee',true),($2,'Head','admin',true),($3,'Backup','hr',false)",
        [applicant,head,backup]);
      await db.query('INSERT INTO dtr_admin_access VALUES($1,true,true)',[head]);
      await db.query("INSERT INTO primary_reviewer_designations VALUES(gen_random_uuid(),$1,'final_hr','HR',true,'2000-01-01',null)",[head]);
      await db.query("INSERT INTO leave_final_reviewer_backups VALUES($1,true,'2000-01-01',null,1)",[backup]);
      await db.query("INSERT INTO leave_requests VALUES($1,$2,$2,'pending_department_head','hr',null)",[request,applicant]);
      await db.query("INSERT INTO locator_slips VALUES($1,$2,'pending_department_head','hr',null)",[request,applicant]);
      for (const kind of ['leave','locator']) {
        await assert.rejects(assertLeaveSubmissionReviewer(db,applicant,kind,null,snapshot),{statusCode:409});
        await assert.rejects(assertDepartmentApprovalFinalReviewer(db,applicant,head,kind,request),{statusCode:409});
      }
      await db.query('UPDATE users SET is_active=true WHERE id=$1',[backup]);
      for (const kind of ['leave','locator']) {
        await assertLeaveSubmissionReviewer(db,applicant,kind,null,snapshot);
        await assertDepartmentApprovalFinalReviewer(db,applicant,head,kind,request);
      }
      await db.query("UPDATE leave_final_reviewer_backups SET effective_to='2000-01-02'");
      for (const kind of ['leave','locator']) {
        await assert.rejects(assertDepartmentApprovalFinalReviewer(db,applicant,head,kind,request),{statusCode:409});
        // A department backup may endorse, leaving the configured primary for HR.
        await assertLeaveSubmissionReviewer(db,applicant,kind,null,{...snapshot,reviewerUserIds:[head,departmentBackup]});
        await assertDepartmentApprovalFinalReviewer(db,applicant,departmentBackup,kind,request);
      }
      await db.query('UPDATE leave_final_reviewer_backups SET effective_to=null');
      await db.query("UPDATE users SET role='admin' WHERE id=$1",[backup]);
      await db.query('INSERT INTO dtr_admin_access VALUES($1,false,true)',[backup]);
      await assert.rejects(assertDepartmentApprovalFinalReviewer(db,applicant,head,'leave',request),{statusCode:409});
      await assertDepartmentApprovalFinalReviewer(db,applicant,head,'locator',request);
      await db.query('UPDATE dtr_admin_access SET locator_allowed=false WHERE admin_user_id=$1',[backup]);
      await assert.rejects(assertDepartmentApprovalFinalReviewer(db,applicant,head,'locator',request),{statusCode:409});
      await db.query("UPDATE users SET role='employee' WHERE id=$1",[backup]);
      for (const kind of ['leave','locator']) {
        await assert.rejects(assertDepartmentApprovalFinalReviewer(db,applicant,head,kind,request),{statusCode:409});
      }
      assert.equal((await db.query('SELECT status FROM leave_requests')).rows[0].status,'pending_department_head');
      assert.equal((await db.query('SELECT status FROM locator_slips')).rows[0].status,'pending_department_head');
      assert.equal((await db.query('SELECT count(*)::int AS n FROM leave_request_history')).rows[0].n,0);
    } finally {await db.query('ROLLBACK');await db.end();}
  });
