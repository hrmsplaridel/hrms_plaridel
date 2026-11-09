'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { Pool } = require('pg');
const path = require('node:path');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
require('dotenv').config({ path: path.join(__dirname, '../.env'), quiet: true });

test('manual import preview and confirmation enforce actual approved coverage in PostgreSQL', async () => {
  const admin = new Pool({ connectionString: process.env.DATABASE_URL });
  const schema = `import_test_${randomUUID().replaceAll('-', '')}`;
  const employee = randomUUID();
  let db;
  const restores = [];
  try {
    await admin.query(`CREATE SCHEMA ${schema}`);
    // One connection proves importing releases it before pooled summary lookups.
    db = new Pool({ connectionString: process.env.DATABASE_URL, max: 1,
      options: `-c search_path=${schema},public`, connectionTimeoutMillis: 5000 });
    await db.query(`CREATE TABLE users (id uuid, biometric_user_id text, is_active boolean,
      employment_status text, date_hired date, separation_date date);
      CREATE TABLE holidays (id uuid DEFAULT gen_random_uuid(), name text, holiday_type text,
        date_from date, date_to date, recurring boolean DEFAULT false, is_active boolean DEFAULT true, coverage text);
      CREATE TABLE leave_types (id uuid PRIMARY KEY, affects_dtr_normally boolean);
      CREATE TABLE leave_requests (id uuid PRIMARY KEY, employee_id uuid, leave_type_id uuid,
        start_date date, end_date date, number_of_days numeric, total_days numeric, status text);
      CREATE TABLE dtr_leave_coverage (leave_request_id uuid, attendance_date date);
      CREATE TABLE locator_slips (employee_id uuid, slip_date date, status text,
        am_in boolean, am_out boolean, pm_in boolean, pm_out boolean);
      CREATE TABLE attendance_reset_punches (employee_id uuid, logged_at timestamptz);
      CREATE TABLE biometric_attendance_logs (id uuid DEFAULT gen_random_uuid(), user_id uuid,
        biometric_user_id text, logged_at timestamptz, verify_code text, punch_code text,
        work_code text, raw_line text, source_file_name text, UNIQUE(biometric_user_id, logged_at));`);
    await db.query("INSERT INTO users VALUES ($1, '1001', true, 'active', '2025-01-01', NULL)", [employee]);
    await db.query("INSERT INTO holidays(name, date_from, date_to, coverage) VALUES ('Morning holiday','2026-09-02','2026-09-02','am_only')");
    const leaveType = randomUUID(), fullLeave = randomUUID();
    await db.query('INSERT INTO leave_types VALUES ($1,true)', [leaveType]);
    await db.query("INSERT INTO leave_requests VALUES ($1,$2,$3,'2026-09-03','2026-09-03',1,1,'approved')", [fullLeave, employee, leaveType]);
    await db.query("INSERT INTO dtr_leave_coverage VALUES ($1,'2026-09-03')", [fullLeave]);
    await db.query("INSERT INTO locator_slips VALUES ($1,'2026-09-04','approved',true,true,false,false)", [employee]);

    restores.push(withMockedModule('../src/config/db', { pool: db }));
    restores.push(withMockedModule('../src/services/biometricProcessing', {
      resolveBiometricPunchDate: async (_user, value) => value.slice(0, 10),
      evaluateBiometricDayGate: async () => {
        await db.query('SELECT 1');
        return { allowed: true, shiftInfo: {} };
      },
      isPunchAfterShiftEnd: () => false,
      processBiometricLogsToSummary: async () => {
        await db.query('SELECT 1');
        return { inserted: 0, updated: 0 };
      },
    }));
    clearModule('../src/routes/biometricAttendanceLogs');
    const router = require('../src/routes/biometricAttendanceLogs');
    const row = (date, time = '08:00:00') => ({ biometric_user_id: '1001',
      logged_at: `${date}T${time}+08:00`, raw_line: `1001,${date} ${time}` });
    async function request(route, rows, reviewed = false) {
      const handler = router.stack.find(item => item.route?.path === route).route.stack.at(-1).handle;
      const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
      await handler({ body: { rows, warnings_reviewed: reviewed } }, res);
      return res;
    }
    const rows = [row('2026-09-01'), row('2026-09-02'), row('2026-09-02', '13:00:00'),
      row('2026-09-03'), row('2026-09-04')];
    const preview = await request('/import/preview', rows);
    assert.equal(preview.code, 200);
    assert.equal(preview.body.rows_ready, 3);
    assert.equal(preview.body.rows_excluded, 2);
    assert.equal(preview.body.warning_count, 1);
    assert.equal((await db.query('SELECT * FROM biometric_attendance_logs')).rowCount, 0);
    assert.equal((await request('/import', rows)).code, 409);
    assert.equal((await db.query('SELECT * FROM biometric_attendance_logs')).rowCount, 0);
    const imported = await request('/import', rows, true);
    assert.equal(imported.code, 200);
    assert.equal(imported.body.inserted, 3);
    assert.equal(imported.body.skipped_holiday, 1);
    assert.equal(imported.body.skipped_leave, 1);
    assert.equal((await db.query('SELECT * FROM biometric_attendance_logs')).rowCount, 3);

    const fresh = [row('2026-09-09')];
    assert.equal((await request('/import/preview', fresh)).body.rows_ready, 1);
    await db.query("INSERT INTO leave_requests VALUES ($1,$2,$3,'2026-09-09','2026-09-09',1,1,'approved')",
      [randomUUID(), employee, leaveType]);
    const changed = await request('/import', fresh, true);
    assert.equal(changed.body.inserted, 0);
    assert.equal(changed.body.skipped_leave, 1);

    await db.query("INSERT INTO leave_requests VALUES ($1,$2,$3,'2026-09-10','2026-09-10',1,1,'pending')",
      [randomUUID(), employee, leaveType]);
    assert.equal((await request('/import/preview', [row('2026-09-10')])).body.rows_ready, 1);
    const coveredOnlyOneDay = randomUUID();
    await db.query("INSERT INTO leave_requests VALUES ($1,$2,$3,'2026-09-11','2026-09-14',2,2,'approved')",
      [coveredOnlyOneDay, employee, leaveType]);
    await db.query("INSERT INTO dtr_leave_coverage VALUES ($1,'2026-09-11')", [coveredOnlyOneDay]);
    assert.equal((await request('/import/preview', [row('2026-09-11')])).body.rows_excluded, 1);
    assert.equal((await request('/import/preview', [row('2026-09-14')])).body.rows_ready, 1);
  } finally {
    clearModule('../src/routes/biometricAttendanceLogs');
    restores.reverse().forEach(restore => restore());
    if (db) await db.end();
    await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await admin.end();
  }
});
