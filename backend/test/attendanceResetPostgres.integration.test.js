const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const { createAttendanceResetService } = require('../src/services/attendanceReset');

test('PostgreSQL reset audits removed evidence and prevents stale processing from recreating it; all test data rolls back', {
  skip: process.env.ATTENDANCE_RESET_DB_TEST !== '1',
}, async () => {
  require('dotenv').config({ quiet: true });
  const { pool } = require('../src/config/db');
  const client = await pool.connect();
  const employee = randomUUID(), actor = randomUUID(), summary = randomUUID();
  const date = '2026-10-08';
  const punches = ['2026-10-08T18:56:53+08:00', '2026-10-08T19:27:10+08:00'];
  const snapshot = { startMinutes: 1140, endMinutes: 1200, punchMode: 'single_session',
    graceMinutes: 0, isWorkingDay: true, captureWindowMinutes: 120 };
  let restoreDb, restoreWs, restoreProcessing;
  try {
    await client.query('BEGIN');
    const migration = fs.readFileSync(path.join(__dirname, '../scripts/migrations/dtr/20261108_super_admin_attendance_reset.sql'), 'utf8');
    await client.query(migration.replace(/^BEGIN;|^COMMIT;/gm, ''));
    // The service receives an already-authorized actor; route tests enforce the
    // super-admin role. Use a disposable audit actor because only one real super
    // admin is allowed by the database, and never modify that existing account.
    for (const [id, role] of [[employee, 'employee'], [actor, 'hr']]) {
      await client.query(`INSERT INTO users(id, email, password_hash, full_name, role, biometric_user_id, employee_number, leave_credit_eligible)
        VALUES($1, $2, 'not-a-login-credential', 'Attendance reset rollback test', $3, $4, NULL, false)`,
      [id, `${id}@rollback.invalid`, role, role === 'employee' ? id : null]);
    }
    for (const timestamp of punches) await client.query(
      `INSERT INTO biometric_attendance_logs(user_id, biometric_user_id, logged_at, raw_line)
       VALUES($1,$2,$3,'rollback-only test punch')`, [employee, employee, timestamp]);
    await client.query(`INSERT INTO dtr_daily_summary(id,employee_id,attendance_date,time_in,total_hours,status,source,shift_snapshot)
      VALUES($1,$2,$3,$4,0,'incomplete','system',$5)`, [summary, employee, date, punches[0], JSON.stringify(snapshot)]);
    const transactionalClient = {
      release() {},
      async query(sql, params) {
        if (sql.startsWith('BEGIN')) return client.query('SAVEPOINT attendance_reset_test');
        if (sql === 'COMMIT') return client.query('RELEASE SAVEPOINT attendance_reset_test');
        if (sql === 'ROLLBACK') {
          await client.query('ROLLBACK TO SAVEPOINT attendance_reset_test');
          return client.query('RELEASE SAVEPOINT attendance_reset_test');
        }
        return client.query(sql, params);
      },
    };
    const service = createAttendanceResetService({ db: { connect: async () => transactionalClient }, broadcast() {},
      now: () => new Date('2026-11-08T12:00:00Z') });
    const input = { employee_id: employee, attendance_date: date };
    const preview = await service.preview(input, actor);
    assert.equal(preview.punches.length, 2);
    assert.equal(preview.punches[0].logged_at_local, '2026-10-08 18:56:53');
    let reset;
    restoreDb = withMockedModule('../src/config/db', { pool: { async query(sql, params) {
      if (/^SELECT id, source, time_in/.test(sql.trim()) && !reset) {
        reset = await service.apply({ ...input, preview_token: preview.preview_token,
          reason: 'Rollback-only integration test', confirmation: 'RESET' }, actor);
      }
      return client.query(sql, params);
    } } });
    restoreWs = withMockedModule('../src/websockets/biometricStream', { broadcastBiometricUpdate() {} });
    clearModule('../src/services/biometricProcessing');
    const result = await require('../src/services/biometricProcessing').processBiometricLogsToSummary([employee], date, date);
    assert.deepEqual(result, { inserted: 0, updated: 0 });
    assert.equal(reset.punches_deleted, 2);
    assert.equal((await client.query('SELECT count(*)::int AS n FROM dtr_daily_summary WHERE employee_id=$1', [employee])).rows[0].n, 0);
    assert.equal((await client.query('SELECT count(*)::int AS n FROM biometric_attendance_logs WHERE user_id=$1', [employee])).rows[0].n, 0);
    const audit = await client.query("SELECT details FROM audit_logs WHERE user_id=$1 AND action='attendance_reset'", [actor]);
    const details = typeof audit.rows[0].details === 'string' ? JSON.parse(audit.rows[0].details) : audit.rows[0].details;
    assert.equal(details.before.punches.length, 2);
    assert.equal(details.before.summary.id, summary);
    assert.deepEqual(reset.reconciliation_months, ['2026-10-01']);
    assert.equal((await client.query('SELECT count(*)::int AS n FROM attendance_reset_punches WHERE employee_id=$1', [employee])).rows[0].n, 2);
    restoreProcessing = withMockedModule('../src/services/biometricProcessing', {
      resolveBiometricPunchDate: async () => date,
      evaluateBiometricDayGate: async () => ({ allowed: false, reason: 'no_schedule' }),
      isPunchAfterShiftEnd: () => false,
      processBiometricLogsToSummary: async () => ({ inserted: 0, updated: 0 }),
    });
    clearModule('../src/routes/biometricAttendanceLogs');
    const router = require('../src/routes/biometricAttendanceLogs');
    const importRows = router.stack.find(layer => layer.route?.path === '/import').route.stack.at(-1).handle;
    for (const [timestamp, expected] of [[punches[0], 0], [punches[1], 0], ['2026-10-08T20:00:00+08:00', 1]]) {
      const res = { status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } };
      await importRows({ body: { rows: [{ biometric_user_id: employee, logged_at: timestamp, raw_line: 'replay test' }] } }, res);
      assert.equal(res.code, undefined);
      assert.equal(res.body.inserted, expected);
    }
  } finally {
    clearModule('../src/routes/biometricAttendanceLogs'); restoreProcessing?.();
    clearModule('../src/services/biometricProcessing'); restoreWs?.(); restoreDb?.();
    await client.query('ROLLBACK'); client.release(); await pool.end();
  }
});
