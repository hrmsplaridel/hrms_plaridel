const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const jwt = require('jsonwebtoken');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

test('assisted recovery: privacy, concurrency, delivery failure, completion and session revocation', async () => {
  const { createPasswordResetAssistance } = require('../src/services/passwordResetAssistance');
  const admin = new Pool({ connectionString: process.env.DATABASE_URL });
  const schema = `reset_test_${randomUUID().replaceAll('-', '')}`;
  let db, restore, restoreSms;
  const actor = randomUUID(), user = randomUUID();
  const mail = [];
  const changes = [];
  let failMail = false;
  try {
    await admin.query(`CREATE SCHEMA ${schema}`);
    db = new Pool({ connectionString: process.env.DATABASE_URL, options: `-c search_path=${schema},public` });
    await db.query(`CREATE TABLE users (id uuid PRIMARY KEY, email text, full_name text, role text,
      is_active boolean DEFAULT true, employment_status text DEFAULT 'active', password_hash text, updated_at timestamptz, contact_number text);
      CREATE TABLE audit_logs (id uuid DEFAULT gen_random_uuid(), user_id uuid, action text, entity_type text, entity_id uuid, details text);
      CREATE TABLE auth_password_reset_otps (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES users(id),
        code_hash text, sent_to text, expires_at timestamptz, consumed_at timestamptz, failed_attempts int DEFAULT 0, ip_address inet, created_at timestamptz DEFAULT now());
      CREATE TABLE auth_refresh_tokens (id uuid DEFAULT gen_random_uuid(), user_id uuid, revoked_at timestamptz);`);
    await db.query(fs.readFileSync(path.join(__dirname, '../scripts/migrations/20261004_password_reset_assistance.sql'), 'utf8'));
    await db.query("INSERT INTO users (id,email,full_name,role) VALUES ($1,'root@test.local','Root','super_admin'),($2,'employee@test.local','Employee','employee')", [actor, user]);
    const service = createPasswordResetAssistance({ pool: db, notify: () => changes.push('changed'), isMailConfigured: () => true, sendMail: async message => {
      if (failMail) throw new Error('provider includes secret response');
      mail.push(message);
    } });
    const expected = await service.request('missing@test.local');
    assert.deepEqual(await service.request('root@test.local'), expected);
    await db.query('UPDATE users SET is_active = false WHERE id = $1', [user]);
    assert.deepEqual(await service.request('employee@test.local'), expected);
    await db.query('UPDATE users SET is_active = true WHERE id = $1', [user]);
    await Promise.all(Array.from({ length: 6 }, () => service.request('employee@test.local')));
    const rows = (await service.list({})).requests;
    assert.equal(rows.length, 1);
    assert.equal(changes.length, 1);
    assert.equal(rows[0].status, 'pending');
    const id = rows[0].id;
    failMail = true;
    await assert.rejects(service.send(id, actor, true), /could not be sent/i);
    assert.equal((await service.list({})).requests[0].status, 'pending');
    assert.equal((await db.query('SELECT * FROM auth_password_reset_otps')).rowCount, 0);
    assert.equal(changes.length, 1);
    failMail = false;
    await assert.rejects(service.send(id, actor, false), /verify/i);
    await service.send(id, actor, true);
    assert.equal(mail.length, 1);
    assert.equal(changes.length, 2);
    assert.equal(mail[0].to, 'employee@test.local');
    assert.equal((await service.list({})).requests[0].status, 'sent');
    await assert.rejects(service.send(id, actor, true), /wait/i);
    const code = mail[0].text.match(/\b\d{6}\b/)[0];
    const audit = JSON.stringify((await db.query('SELECT * FROM audit_logs')).rows);
    assert.ok(!audit.includes(code));
    assert.ok(!JSON.stringify(await service.list({})).includes(code));
    await db.query('INSERT INTO auth_refresh_tokens (user_id) VALUES ($1)', [user]);
    restore = withMockedModule('../src/config/db', { pool: db });
    const sms = [];
    restoreSms = withMockedModule('../src/utils/uniSmsSms', {
      normalizePhilippinesMobileNumber: () => '+639171234567',
      sendPasswordResetOtpSms: async value => { sms.push(value); },
    });
    clearModule('../src/routes/auth');
    const router = require('../src/routes/auth');
    const handler = router.stack.find(e => e.route?.path === '/reset-password').route.stack.at(-1).handle;
    async function reset(resetCode) {
      const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
      await handler({ body: { email: 'employee@test.local', code: resetCode, new_password: 'NewPassword123!' } }, res);
      return res;
    }
    assert.equal((await reset(code === '000000' ? '111111' : '000000')).statusCode, 400);
    assert.equal((await reset(code)).statusCode, 200);
    assert.equal((await reset(code)).statusCode, 400);
    const closed = (await service.list({ status: 'closed' })).requests[0];
    assert.ok(closed.completed_at);
    assert.equal((await db.query('SELECT * FROM auth_refresh_tokens WHERE revoked_at IS NULL')).rowCount, 0);
    const { createAuthMiddleware } = require('../src/middleware/auth');
    const middleware = createAuthMiddleware(db);
    for (const version of [0, 1]) {
      const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json() {} };
      let next = false;
      const token = jwt.sign({ id: user, auth_version: version }, process.env.JWT_SECRET);
      await middleware({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
      assert.equal(next, version === 1);
    }
    assert.equal((await db.query("SELECT * FROM audit_logs WHERE action = 'password_reset_completed'")).rowCount, 1);
    await service.request('employee@test.local');
    assert.equal((await service.list({})).requests.length, 1); // Closed request cooldown.
    await db.query("UPDATE password_reset_requests SET created_at = now() - interval '20 minutes'");
    await service.request('employee@test.local');
    const nextId = (await service.list({ status: 'pending' })).requests[0].id;
    const deliveries = await Promise.allSettled([service.send(nextId, actor, true), service.send(nextId, actor, true)]);
    assert.equal(deliveries.filter(r => r.status === 'fulfilled').length, 1);
    const newCode = mail.at(-1).text.match(/\b\d{6}\b/)[0];
    await db.query("UPDATE auth_password_reset_otps SET expires_at = now() - interval '1 minute' WHERE consumed_at IS NULL");
    assert.equal((await reset(newCode)).statusCode, 400);
    await db.query("UPDATE password_reset_requests SET sent_at = now() - interval '2 minutes'");
    await service.send(nextId, actor, true);
    const limitedCode = mail.at(-1).text.match(/\b\d{6}\b/)[0];
    const wrong = limitedCode === '000000' ? '111111' : '000000';
    for (let n = 0; n < 5; n++) assert.equal((await reset(wrong)).statusCode, 400);
    assert.equal((await reset(limitedCode)).statusCode, 400);
    await db.query("UPDATE password_reset_requests SET sent_at = now() - interval '2 minutes'");
    await service.send(nextId, actor, true);
    const closedCode = mail.at(-1).text.match(/\b\d{6}\b/)[0];
    await service.close(nextId, actor);
    assert.equal((await reset(closedCode)).statusCode, 400);
    await assert.rejects(service.send(nextId, actor, true), /closed/i);
    // Existing SMS recovery still works, including single issuance under concurrency.
    await db.query("UPDATE auth_password_reset_otps SET created_at = now() - interval '2 minutes'");
    const forgot = router.stack.find(e => e.route?.path === '/forgot-password').route.stack.at(-1).handle;
    const response = () => ({ statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } });
    await Promise.all([forgot({ body: { email: 'employee@test.local' } }, response()), forgot({ body: { email: 'employee@test.local' } }, response())]);
    assert.equal(sms.length, 1);
    const results = await Promise.all([reset(sms[0].code), reset(sms[0].code)]);
    assert.deepEqual(results.map(r => r.statusCode).sort(), [200, 400]);
  } finally {
    clearModule('../src/routes/auth');
    if (restore) restore();
    if (restoreSms) restoreSms();
    if (db) await db.end();
    await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await admin.end();
  }
});
