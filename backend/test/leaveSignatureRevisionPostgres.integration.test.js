'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');
const signatures = require('../src/services/docutrackerLeaveSignatureService');

const request = '11111111-1111-4111-8111-111111111111';
const employee = '22222222-2222-4222-8222-222222222222';
const reviewer = '44444444-4444-4444-8444-444444444444';
const asset = '33333333-3333-4333-8333-333333333333';
const hrReviewer = '55555555-5555-4555-8555-555555555555';
const hrAsset = '66666666-6666-4666-8666-666666666666';
const migrationPath = path.join(__dirname, '../scripts/migrations/dtr/20261015_leave_signature_revisions.sql');

// All fixtures and the trigger function live in pg_temp and are rolled back.
test('changed leave requires current-version signatures while preserving saved ink and history',
  { skip: !process.env.LEAVE_SIGNATURE_TEST_DATABASE_URL }, async () => {
    const db = new Client({ connectionString: process.env.LEAVE_SIGNATURE_TEST_DATABASE_URL });
    await db.connect();
    try {
      await db.query('BEGIN');
      await db.query('CREATE TEMP TABLE fixture_anchor(id int); SET LOCAL search_path = pg_temp');
      await db.query(`CREATE TEMP TABLE users(id uuid PRIMARY KEY, full_name text, is_active boolean, role text DEFAULT 'employee');
        CREATE TEMP TABLE dtr_admin_access(admin_user_id uuid,leave_allowed boolean,locator_allowed boolean);
        CREATE TEMP TABLE docutracker_signature_assets(id uuid PRIMARY KEY,owner_user_id uuid,mime_type text,image_bytes bytea);
        CREATE TEMP TABLE leave_requests(id uuid PRIMARY KEY,user_id uuid,employee_id uuid,status text,
          leave_type_id uuid,start_date date,end_date date,number_of_days numeric,total_days numeric,
          reason text,details jsonb,employee_official_snapshot jsonb,employee_detail_schema_snapshot jsonb,
          attachment_name text,attachment_path text,attachment_mime_type text,attachment_uploaded_at timestamptz,
          review_department_id uuid,assigned_department_head_id uuid,final_review_route text,
          final_reviewer_user_id uuid,print_template_version_id uuid,reviewer_id uuid,reviewer_remarks text,
          approved_at timestamptz,updated_at timestamptz);
        CREATE TEMP TABLE primary_reviewer_designations(id uuid,employee_id uuid,scope_key text,
          position_title_snapshot text,effective_from date,effective_to date,is_active boolean);
        CREATE TEMP TABLE leave_final_reviewer_backups(employee_id uuid,is_active boolean,
          effective_from date,effective_to date,backup_rank int);
        CREATE TEMP TABLE leave_request_department_reviewers(leave_request_id uuid,reviewer_id uuid);
        CREATE TEMP TABLE leave_request_history(id uuid DEFAULT gen_random_uuid(),leave_request_id uuid,
          action text,from_status text,to_status text,acted_by uuid,remarks text,metadata_json jsonb,acted_at timestamptz);
        CREATE TEMP TABLE docutracker_leave_signatures(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          leave_request_id uuid,slot_key text,assigned_signer_id uuid,signature_asset_id uuid,signed_by uuid,
          signer_name_snapshot text,signed_at timestamptz DEFAULT now(),created_by uuid,
          created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),
          CONSTRAINT docutracker_leave_signatures_request_slot_unique UNIQUE(leave_request_id,slot_key));`);
      if (fs.existsSync(migrationPath)) {
        const migration = fs.readFileSync(migrationPath, 'utf8')
          .replace(/^BEGIN;\s*|COMMIT;\s*$/gm, '')
          .replaceAll('invalidate_leave_signatures()', 'pg_temp.invalidate_leave_signatures()');
        await db.query(migration);
        await db.query(migration); // Upgrade is safe to repeat without losing archived rows.
      }
      await db.query('INSERT INTO users(id,full_name,is_active) VALUES($1,\'Employee One\',true),($2,\'Reviewer One\',true)', [employee, reviewer]);
      await db.query("INSERT INTO users VALUES($1,'HR Reviewer',true,'hr')", [hrReviewer]);
      await db.query("INSERT INTO primary_reviewer_designations VALUES(gen_random_uuid(),$1,'final_hr','HR Officer','2000-01-01',null,true)", [hrReviewer]);
      await db.query("INSERT INTO docutracker_signature_assets VALUES($1,$2,'image/png',decode('aW1hZ2U=','base64'))", [asset, reviewer]);
      await db.query("INSERT INTO docutracker_signature_assets VALUES($1,$2,'image/png',decode('aW1hZ2U=','base64'))", [hrAsset, hrReviewer]);
      await db.query('ALTER TABLE pg_temp.leave_requests ADD COLUMN IF NOT EXISTS workflow_snapshot jsonb');
      await db.query(`INSERT INTO leave_requests(id,user_id,employee_id,status,start_date,end_date,
        assigned_department_head_id,signature_revision) VALUES($1,$2,$2,'pending_department_head','2026-10-20','2026-10-20',$3,2)`,
      [request, employee, reviewer]);
      for (const slot of ['applicant', 'department_head', 'hr_approver']) {
        await db.query(`INSERT INTO docutracker_leave_signatures(leave_request_id,slot_key,assigned_signer_id,
          signature_asset_id,signed_by,signer_name_snapshot,revision) VALUES($1,$2,$3,$4,$3,'Reviewer One',1)`,
        [request, slot, reviewer, asset]);
      }

      // A previous version must not satisfy either review gate or show as ink in a preview.
      for (const gate of [signatures.requireDepartmentHeadApprovalSignature, signatures.requireHrApprovalSignature]) {
        await assert.rejects(gate(db, request, reviewer), e => e.code === 'CONFLICT' && e.statusCode === 409);
      }
      const bundle = await signatures.getLeaveSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'leave_requests', request);
      assert.ok(bundle.signatures.every(s => s.signed_by === null));

      // The same saved image may be explicitly selected again for this version.
      const pool = { query: db.query.bind(db), connect: async () => ({
        query: (sql, params) => ['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)
          ? Promise.resolve({ rows: [], rowCount: 0 }) : db.query(sql, params), release() {},
      }) };
      const signed = await signatures.signLeaveSourceDepartmentHead(pool, { id: reviewer, role: 'employee' },
        'dtr', 'leave_requests', request, { signature_asset_id: asset });
      assert.equal(signed.signatures.find(s => s.slot_key === 'department_head').signature_asset_id, asset);
      await signatures.requireDepartmentHeadApprovalSignature(db, request, reviewer);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM docutracker_leave_signatures')).rows[0].n, 4);
      const history = (await db.query('SELECT metadata_json FROM leave_request_history')).rows[0].metadata_json;
      assert.equal(history.revision, 2);
      assert.equal(history.signature_asset_id, asset);

      const revision = async () => (await db.query('SELECT signature_revision FROM leave_requests')).rows[0].signature_revision;
      await db.query("UPDATE leave_requests SET status='pending_hr',reviewer_id=$1,reviewer_remarks='Endorsed',updated_at=now()", [reviewer]);
      assert.equal(await revision(), 2, 'department endorsement does not invalidate its own signature');
      await signatures.requireDepartmentHeadApprovalSignature(db, request, reviewer);
      await db.query("UPDATE leave_requests SET status='returned'");
      assert.equal(await revision(), 3);
      await db.query("UPDATE leave_requests SET start_date='2026-10-22',end_date='2026-10-22'");
      assert.equal(await revision(), 4);
      await db.query("UPDATE leave_requests SET status='pending_department_head'");
      assert.equal(await revision(), 5, 'resubmission starts a new approval version');
      await assert.rejects(signatures.requireDepartmentHeadApprovalSignature(db, request, reviewer), { code: 'CONFLICT' });
      for (const update of ["details='{}'::jsonb", "reason='Changed purpose'", "attachment_path='new.pdf',attachment_uploaded_at=now()",
        "employee_official_snapshot='{}'::jsonb", "employee_detail_schema_snapshot='[]'::jsonb"]) {
        const before = await revision();
        await db.query(`UPDATE leave_requests SET ${update}`);
        assert.equal(await revision(), before + 1, update);
      }
      const beforeNoop = await revision();
      await db.query('UPDATE leave_requests SET reason=reason,details=details,updated_at=now()');
      assert.equal(await revision(), beforeNoop);

      await signatures.signLeaveSourceDepartmentHead(pool, { id: reviewer, role: 'employee' },
        'dtr', 'leave_requests', request, { signature_asset_id: asset });
      await signatures.requireDepartmentHeadApprovalSignature(db, request, reviewer);
      // Final HR must also reconfirm their own saved image, not another reviewer's ink.
      await db.query("UPDATE leave_requests SET status='pending_hr'");
      await assert.rejects(signatures.requireHrApprovalSignature(db, request, hrReviewer), { code: 'CONFLICT' });
      await assert.rejects(signatures.signLeaveSourceHrApprover(pool, { id: hrReviewer, role: 'hr' },
        'dtr', 'leave_requests', request, { signature_asset_id: asset }), { code: 'FORBIDDEN' });
      await signatures.signLeaveSourceHrApprover(pool, { id: hrReviewer, role: 'hr' },
        'dtr', 'leave_requests', request, { signature_asset_id: hrAsset });
      await signatures.requireHrApprovalSignature(db, request, hrReviewer);
      await assert.rejects(signatures.requireHrApprovalSignature(db, request, reviewer), { code: 'CONFLICT' });
      const beforeApprove = await revision();
      await db.query("UPDATE leave_requests SET status='approved',approved_at=now()");
      assert.equal(await revision(), beforeApprove, 'final approval preserves confirmed ink');
      const print = await signatures.getLeaveSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'leave_requests', request);
      assert.equal(print.signatures.find(s => s.slot_key === 'department_head').signed_by, reviewer);
      assert.equal(print.signatures.find(s => s.slot_key === 'hr_approver').signed_by, hrReviewer);
      assert.equal(print.signatures.find(s => s.slot_key === 'applicant').signed_by, null);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM docutracker_signature_assets')).rows[0].n, 2);
    } finally {
      await db.query('ROLLBACK');
      await db.end();
    }
  });
