'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('pg');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('Locator print SQL restricts Mayor privilege to current authority and preserves independent access',
  { skip: !process.env.LOCATOR_MAYOR_ACCESS_TEST_DATABASE_URL }, async () => {
    const db = new Client({ connectionString: process.env.LOCATOR_MAYOR_ACCESS_TEST_DATABASE_URL });
    await db.connect();
    let restore;
    try {
      await db.query('BEGIN');
      await db.query(`
        CREATE TEMP TABLE users(id uuid PRIMARY KEY, full_name text, role text, is_active boolean,
          employment_status text, date_hired date, separation_date date, created_at timestamptz);
        CREATE TEMP TABLE assignments(id uuid, employee_id uuid, position_id uuid, department_id uuid,
          is_active boolean, effective_from date, effective_to date, created_at timestamptz);
        CREATE TEMP TABLE positions(id uuid, name text);
        CREATE TEMP TABLE departments(id uuid, name text);
        CREATE TEMP TABLE locator_slips(id uuid PRIMARY KEY, employee_id uuid, final_review_route text,
          print_template_version_id uuid, assigned_department_head_id uuid, dept_head_reviewer_id uuid);
        CREATE TEMP TABLE locator_print_template_versions(id uuid, background_pdf bytea, print_layout jsonb);
        CREATE TEMP TABLE dtr_admin_access(admin_user_id uuid, locator_allowed boolean);
        CREATE TEMP TABLE locator_slip_department_reviewers(locator_slip_id uuid, reviewer_id uuid);
      `);
      const current = '11111111-1111-4111-8111-111111111111';
      const former = '22222222-2222-4222-8222-222222222222';
      const employee = '33333333-3333-4333-8333-333333333333';
      const requestId = '44444444-4444-4444-8444-444444444444';
      await db.query(`INSERT INTO users(id, full_name, role, is_active, employment_status, created_at)
        VALUES ($1,'Current Mayor','mayor',true,'active','2026-01-02'),
               ($2,'Former Mayor','mayor',true,'active','2026-01-01')`, [current, former]);
      await db.query(`INSERT INTO locator_slips(id,employee_id,final_review_route) VALUES($1,$2,'mayor_direct')`, [requestId, employee]);
      restore = withMockedModule('../src/config/db', { pool: db });
      clearModule('../src/routes/locatorPrintTemplates');
      const router = require('../src/routes/locatorPrintTemplates');
      const handler = router.stack.find(e => e.route?.path === '/requests/:id/render').route.stack.at(-1).handle;
      const read = async (id, role = 'mayor') => {
        const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } };
        await handler({ params: { id: requestId }, user: { id, role }, body: {} }, res);
        // Authorized requests reach PDF-input validation; denied requests expose no metadata.
        return res;
      };
      assert.equal((await read(current)).code, 400);
      assert.equal((await read(former)).code, 404);
      for (const route of ['hr', 'mayor']) {
        await db.query('UPDATE locator_slips SET final_review_route=$1', [route]);
        assert.equal((await read(current)).code, 404);
      }
      await db.query("UPDATE locator_slips SET final_review_route='mayor_direct',employee_id=$1", [former]);
      assert.equal((await read(former)).code, 400);
      await db.query('UPDATE locator_slips SET employee_id=$1,dept_head_reviewer_id=$2', [employee, former]);
      assert.equal((await read(former)).code, 400);
      await db.query('UPDATE locator_slips SET dept_head_reviewer_id=NULL');
      await db.query('INSERT INTO locator_slip_department_reviewers VALUES($1,$2)', [requestId, former]);
      assert.equal((await read(former)).code, 400);
      assert.equal((await read(employee, 'employee')).code, 400);
      assert.equal((await read(employee, 'hr')).code, 400);
      await db.query('DELETE FROM locator_slip_department_reviewers');
      await db.query("UPDATE users SET employment_status='inactive' WHERE id=$1", [current]);
      assert.equal((await read(current)).code, 404);
      assert.equal((await read(former)).code, 400);
      await db.query('UPDATE users SET is_active=false');
      assert.equal((await read(former)).code, 404);
    } finally {
      clearModule('../src/routes/locatorPrintTemplates');
      restore?.();
      await db.query('ROLLBACK');
      await db.end();
    }
  });
