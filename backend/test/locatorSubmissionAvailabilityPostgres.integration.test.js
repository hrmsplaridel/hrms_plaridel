'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('pg');
const { getLocatorSubmissionAvailability } = require('../src/services/locatorSubmissionAvailability');

// All setup and configuration changes are pg_temp fixtures, rolled back at completion.
test('Locator availability resolves employee-fileable routes and dated reviewer readiness in PostgreSQL',
  { skip: !process.env.LOCATOR_AVAILABILITY_TEST_DATABASE_URL }, async () => {
    const db = new Client({ connectionString: process.env.LOCATOR_AVAILABILITY_TEST_DATABASE_URL });
    await db.connect();
    const employee = '11111111-1111-4111-8111-111111111111';
    const head = '22222222-2222-4222-8222-222222222222';
    const backup = '33333333-3333-4333-8333-333333333333';
    const mayor = '44444444-4444-4444-8444-444444444444';
    const department = '55555555-5555-4555-8555-555555555555';
    const nextDepartment = '66666666-6666-4666-8666-666666666666';
    try {
      await db.query('BEGIN');
      await db.query('CREATE TEMP TABLE fixture_anchor(id int); SET LOCAL search_path = pg_temp');
      await db.query(`CREATE TEMP TABLE users(id uuid PRIMARY KEY,email text,full_name text,role text,is_active boolean,
          employment_type text,employment_status text,date_hired date,separation_date date,created_at timestamptz DEFAULT now());
        CREATE UNIQUE INDEX fixture_single_active_mayor ON users(role) WHERE role='mayor' AND is_active=true;
        CREATE TEMP TABLE positions(id uuid,name text);
        CREATE TEMP TABLE departments(id uuid,name text);
        CREATE TEMP TABLE assignments(id uuid DEFAULT gen_random_uuid(),employee_id uuid,department_id uuid,position_id uuid,
          is_active boolean DEFAULT true,effective_from date,effective_to date,created_at timestamptz DEFAULT now());
        CREATE TEMP TABLE primary_reviewer_designations(id uuid DEFAULT gen_random_uuid(),employee_id uuid,department_id uuid,
          scope_key text,position_title_snapshot text,is_active boolean,effective_from date,effective_to date);
        CREATE TEMP TABLE department_reviewer_backups(id uuid DEFAULT gen_random_uuid(),department_id uuid,employee_id uuid,
          is_active boolean,effective_from date,effective_to date,backup_rank int,created_at timestamptz DEFAULT now());
        CREATE TEMP TABLE leave_final_reviewer_backups(employee_id uuid,is_active boolean,effective_from date,effective_to date,backup_rank int);
        CREATE TEMP TABLE dtr_admin_access(admin_user_id uuid,leave_allowed boolean,locator_allowed boolean);
        CREATE TEMP TABLE locator_request_types(code text,label text,filing_access text,approval_route text,
          mayor_employment_types text[],is_active boolean,sort_order int);
      `);
      await db.query('ALTER TABLE pg_temp.locator_request_types ADD COLUMN IF NOT EXISTS approval_workflow_id uuid');
      await db.query(`INSERT INTO users(id,full_name,role,is_active,employment_type,employment_status) VALUES
        ($1,'Employee','employee',true,'regular','active'),($2,'Head','hr',true,'permanent','active'),
        ($3,'Backup','admin',true,'permanent','active'),($4,'Mayor','mayor',true,'permanent','active')`, [employee, head, backup, mayor]);
      await db.query("INSERT INTO departments VALUES($1,'Current department'),($2,'Future department')", [department, nextDepartment]);
      await db.query(`INSERT INTO assignments(employee_id,department_id,effective_from,effective_to)
        VALUES($1,$2,'2026-10-01','2026-10-19'),($1,$3,'2026-10-20',null)`, [employee, department, nextDepartment]);
      await db.query(`INSERT INTO primary_reviewer_designations(employee_id,department_id,scope_key,position_title_snapshot,is_active,effective_from)
        VALUES($1,$2::uuid,'department:'||$2::uuid::text,'Department Head',true,'2000-01-01')`, [head, department]);
      await db.query("INSERT INTO locator_request_types VALUES('travel','Travel Order','employee','mayor_direct',ARRAY['job_order'],true,1)");
      const readOnly = { query: (sql, params) => {
        assert.match(sql.trim(), /^SELECT\b/, 'availability must not mutate requests/configuration');
        return db.query(sql, params);
      } };
      const check = (date = '2026-10-15') => getLocatorSubmissionAvailability(readOnly, employee, date);
      let result = await check();
      assert.equal(result.can_submit, false);
      assert.equal(result.types[0].route, 'hr');
      assert.match(result.reason, /final locator reviewer/i);
      await db.query("UPDATE users SET employment_type='job_order' WHERE id=$1", [employee]);
      result = await check();
      assert.equal(result.can_submit, true);
      assert.equal(result.types[0].route, 'mayor_direct');

      await db.query("UPDATE locator_request_types SET approval_route='mayor'");
      assert.equal((await check()).can_submit, true);
      assert.equal((await check('2026-10-20')).can_submit, false, 'future assignment has no department reviewer');
      await db.query('UPDATE primary_reviewer_designations SET employee_id=$1', [employee]);
      assert.equal((await check()).can_submit, false, 'an applicant cannot be their own department reviewer');
      await db.query("INSERT INTO department_reviewer_backups(department_id,employee_id,is_active,effective_from,backup_rank) VALUES($1,$2,true,'2000-01-01',1)", [department, head]);
      assert.equal((await check()).can_submit, true, 'an effective department backup supports manual Mayor signing');
      await db.query("UPDATE department_reviewer_backups SET effective_to='2000-01-02'");
      assert.equal((await check()).can_submit, false);
      await db.query('DELETE FROM department_reviewer_backups');
      await db.query('UPDATE primary_reviewer_designations SET employee_id=$1', [head]);

      await db.query("UPDATE locator_request_types SET filing_access='admin'");
      assert.deepEqual((await check()).types, []);
      assert.equal((await check()).can_submit, false);
      await db.query("UPDATE locator_request_types SET filing_access='both',is_active=false");
      assert.equal((await check()).can_submit, false);
      await db.query("UPDATE locator_request_types SET is_active=true,approval_route='hr'");
      await db.query(`INSERT INTO primary_reviewer_designations(employee_id,scope_key,position_title_snapshot,is_active,effective_from)
        VALUES($1,'final_hr','HR Officer',true,'2000-01-01')`, [head]);
      result = await check();
      assert.equal(result.can_submit, false, 'the sole reviewer cannot perform both stages');
      assert.match(result.reason, /different final HR reviewer/i);
      await db.query("INSERT INTO leave_final_reviewer_backups VALUES($1,true,'2000-01-01',null,1)", [backup]);
      assert.equal((await check()).can_submit, false, 'an admin backup needs Locator module access');
      await db.query('INSERT INTO dtr_admin_access VALUES($1,false,true)', [backup]);
      assert.equal((await check()).can_submit, true);
      await db.query("UPDATE leave_final_reviewer_backups SET effective_to='2000-01-02'");
      assert.equal((await check()).can_submit, false);
      await db.query("INSERT INTO department_reviewer_backups(department_id,employee_id,is_active,effective_from,backup_rank) VALUES($1,$2,true,'2000-01-01',1)", [department, backup]);
      assert.equal((await check()).can_submit, true, 'a department backup leaves the primary available for HR');

      await db.query("UPDATE locator_request_types SET approval_route='mayor_direct'");
      await db.query('UPDATE users SET is_active=false WHERE id=$1', [mayor]);
      assert.equal((await check()).can_submit, false, 'the eligible direct route cannot silently fall back to HR');
      await db.query("UPDATE users SET role='mayor' WHERE id=$1", [employee]);
      assert.equal((await check()).can_submit, false, 'self Mayor approval is unavailable');
    } finally {
      await db.query('ROLLBACK');
      await db.end();
    }
  });
